// Internal Bribes represent pool fee
module suiDouBashiVest::internal_bribe{
    use std::type_name::{Self, TypeName};
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::dynamic_field as df;
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use std::string::{Self, String};
    use sui::table_vec::{Self, TableVec};
    use sui::clock::{Self, Clock};
    use sui::math;

    use suiDouBashi::amm_v1::{Self, Pool};
    use suiDouBashiVest::vsdb::{Self, VSDB};
    use suiDouBashiVest::event;
    use suiDouBashiVest::err;

    use sui::table::{ Self, Table};

    const DURATION: u64 = { 7 * 86400 };
    const PRECISION: u64 = 1_000_000_000_000_000_000;
    const MAX_REWARD_TOKENS: u64 = 16;
    const MAX_U64: u64 = 18446744073709551615_u64;

    /// Rough illustration of the dynamic field architecture for reg:
    /// ```
    ///            type_name /--->Brbe--->Balance
    /// (Reg)-     type_name  -->Brbe--->Balance
    ///            type_name \--->Brbe--->Balance
    /// ```


    // per token_ads
    struct InternalBribe<phantom X, phantom Y> has key, store{
        id: UID,

        // LP_TOKEN
        total_supply: u64, // voting
        balace_of: Table<ID, u64>,
        supply_checkpoints: TableVec<SupplyCheckpoint>,

        // should this be shared object, or this will be too overkill
        reward_x: Reward<X>,
        reward_y: Reward<Y>,

        /// TODO: move down to VSDB

        // Question: will vector be too gas consuming ?
        checkpoints: Table<ID, TableVec<Checkpoint>>, // VSDB -> balance checkpoint

        // TODO: Balance<LP_TOKEN<X,Y>>
    }

    struct Reward<phantom T> has store{
        balance: Balance<T>,
        reward_rate: u64, // pair
        period_finish: u64,// pair
        last_update_time: u64, // pair
        reward_per_token_stored: u64, // pair
        reward_per_token_checkpoints: Table<ID, TableVec<RewardPerTokenCheckpoint>>, // pair
        user_reward_per_token_stored: Table<ID, u64>, // player -> token_value
        last_earn: Table<ID, u64>, // VSDB -> ts
        is_reward: bool,// pair
    }


    ///checkpoint for marking balance
    struct Checkpoint has store {
        timestamp: u64,
        balance: u64
    }
    ///checkpoint for marking supply
    struct SupplyCheckpoint has store {
        timestamp: u64,
        supply: u64
    }
    ///checkpoint for marking reward rate
    struct RewardPerTokenCheckpoint has store {
        timestamp: u64,
        reward_per_token: u64
    }

    public fun assert_generic_type<X,Y,T>():bool{
        let type_t = type_name::get<T>();
        let type_x = type_name::get<X>();
        let type_y = type_name::get<Y>();

        assert!( type_t == type_x || type_t == type_y, err::invalid_type_argument());

        return (type_t == type_x) // true ? type_x : type_y
    }


    // being calling by voter
    public fun create_bribe<X,Y>(
        _: &mut Pool<X,Y>,
        ctx: &mut TxContext
    ) {
        let reward_x = Reward<X>{
            balance: balance::zero<X>(),
            reward_rate: 0,
            period_finish: 0,
            last_update_time: 0,
            reward_per_token_stored: 0,
            reward_per_token_checkpoints: table::new<ID, TableVec<RewardPerTokenCheckpoint>>(ctx),
            user_reward_per_token_stored: table::new<ID, u64>(ctx),
            last_earn: table::new<ID, u64>(ctx),
            is_reward: false,
        };
        let reward_y = Reward<Y>{
            balance: balance::zero<Y>(),
            reward_rate: 0,
            period_finish: 0,
            last_update_time: 0,
            reward_per_token_stored: 0,
            reward_per_token_checkpoints: table::new<ID, TableVec<RewardPerTokenCheckpoint>>(ctx),
            user_reward_per_token_stored: table::new<ID, u64>(ctx),
            last_earn: table::new<ID, u64>(ctx),
            is_reward: false,
        };

        let bribe = InternalBribe<X,Y>{
            id: object::new(ctx),
            total_supply:0,
            balace_of: table::new<ID, u64>(ctx),
            supply_checkpoints: table_vec::empty<SupplyCheckpoint>(ctx),

            reward_x,
            reward_y,

            checkpoints: table::new<ID, TableVec<Checkpoint>>(ctx),

        };

        transfer::share_object(bribe);
    }

    //public entry fun deposit(self: )

    // ===== Getter =====
    // TODO: move to VSDB
    ///  Determine the prior balance for an account as of a block number
    public fun get_prior_balance_index<X,Y>(
        self: & InternalBribe<X,Y>,
        vsdb: &VSDB,
        ts:u64
    ):u64 {
        if(!table::contains(&self.checkpoints, object::id(vsdb))){
            return 0
        };
        let checkpoints = table::borrow(&self.checkpoints, object::id(vsdb));
        let len = table_vec::length(checkpoints);

        if( len == 0){
            return 0
        };

        if( table_vec::borrow(checkpoints, len - 1).timestamp <= ts ){
            return len - 1
        };

        if( table_vec::borrow(checkpoints, 0).timestamp > ts){
            return 0
        };

        let lower = 0;
        let upper = len - 1;
        while ( lower < upper){
            let center = upper - (upper - lower) / 2;
            let checkpoint = table_vec::borrow(checkpoints, center);
            if(checkpoint.timestamp == ts ){
                return center
            }else if (checkpoint.timestamp < ts){
                lower = center;
            }else{
                upper = center -1 ;
            }
        };
        return lower
    }

    // TODO: move to VSDB
    public fun get_prior_supply_index<X,Y>(
        self: & InternalBribe<X,Y>,
        ts:u64
    ):u64 {
        let len = table_vec::length(&self.supply_checkpoints);

        if( len == 0){
            return 0
        };

        if( table_vec::borrow(&self.supply_checkpoints, len - 1).timestamp <= ts ){
            return len - 1
        };

        if( table_vec::borrow(&self.supply_checkpoints, 0).timestamp > ts){
            return 0
        };

        let lower = 0;
        let upper = len - 1;
        while ( lower < upper){
            let center = upper - (upper - lower) / 2;
            let checkpoint = table_vec::borrow(&self.supply_checkpoints, center);
            if(checkpoint.timestamp == ts ){
                return center
            }else if (checkpoint.timestamp < ts){
                lower = center;
            }else{
                upper = center -1 ;
            }
        };

        return lower
    }

    // move to VSDB
    public fun get_prior_reward_per_token<T>(
        reward: & Reward<T>,
        vsdb: &VSDB,
        ts:u64
    ):(u64, u64) // ( ts, reward_per_token )
    {
        if(!table::contains(&reward.reward_per_token_checkpoints, object::id(vsdb))){
            return ( 0, 0 )
        };
        let checkpoints = table::borrow(&reward.reward_per_token_checkpoints, object::id(vsdb));
        let len = table_vec::length(checkpoints);

        if( len == 0){
            return ( 0, 0 )
        };

        if( table_vec::borrow(checkpoints, len - 1).timestamp <= ts ){
            let last_checkpoint = table_vec::borrow(checkpoints, len - 1);
            return ( last_checkpoint.timestamp, last_checkpoint.reward_per_token)
        };

        if( table_vec::borrow(checkpoints, 0).timestamp > ts){
            return ( 0, 0 )
        };

        let lower = 0;
        let upper = len - 1;
        while ( lower < upper){
            let center = upper - (upper - lower) / 2;
            let checkpoint = table_vec::borrow(checkpoints, center);
            if(checkpoint.timestamp == ts ){
                return (checkpoint.timestamp, checkpoint.reward_per_token )
            }else if (checkpoint.timestamp < ts){
                lower = center;
            }else{
                upper = center -1 ;
            }
        };

        let checkpoint = table_vec::borrow(checkpoints, lower);
        return ( checkpoint.timestamp, checkpoint.reward_per_token)
    }

    public fun get_reward_per_token<T>(total_supply:u64, reward: &Reward<T>, clock: &Clock): u64{
        if(total_supply == 0){
            return reward.reward_per_token_stored
        };

        return  reward.reward_per_token_stored + (last_time_reward_applicable(reward, clock) - math::min(reward.last_update_time, reward.period_finish)) * reward.reward_rate * PRECISION / total_supply
    }

    public fun left_x<X,Y>(self: &InternalBribe<X,Y>, clock: &Clock):u64{
        let ts = clock::timestamp_ms(clock);
        if(ts >= self.reward_x.period_finish) return 0;

        let _remaining = self.reward_x.period_finish - ts;
        return _remaining * self.reward_x.reward_rate
    }

    /// used to notify a gauge/bribe of a given reward, this can create griefing attacks by extending rewards
    public fun notify_reward_amount_x<X,Y>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &VSDB,
        coin_x: Coin<X>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        let value = coin::value(&coin_x);
        assert!(value > 0, 0);
        assert!(self.reward_x.is_reward, 0);

        let ts = clock::timestamp_ms(clock);
        if(self.reward_x.reward_rate == 0){
            write_reward_per_token_checkpoint(&mut self.reward_x, vsdb, 0, ts, ctx);
        };

        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token_x(self, vsdb, MAX_U64, true, clock, ctx);
        self.reward_x.reward_per_token_stored = reward_per_token_stored;
        self.reward_x.last_update_time = last_update_time;

        if(ts >= self.reward_x.period_finish){
            coin::put(&mut self.reward_x.balance, coin_x);
            self.reward_x.reward_rate = value / DURATION;
        }else{
            let _remaining = self.reward_x.period_finish - ts;
            let _left = _remaining + self.reward_x.reward_rate;
            assert!(value > _left, 1);
            coin::put(&mut self.reward_x.balance, coin_x);
            self.reward_x.reward_rate = ( value + _left ) / DURATION;
        };

        assert!(self.reward_x.reward_rate > 0, 1);
        let bal_total = balance::value(&self.reward_x.balance);
        assert!( self.reward_x.reward_rate <= bal_total / DURATION, 1);

        self.reward_x.period_finish = ts + DURATION;

        event::notify_reward<X>(tx_context::sender(ctx), value);
    }

    ///  returns the last time the reward was modified or periodFinish if the reward has ended
    public fun last_time_reward_applicable<T>(reward: &Reward<T>, clock: &Clock):u64{
        math::min(clock::timestamp_ms(clock), reward.period_finish)
    }

    public fun bribe_start(ts: u64):u64{
        ts - (ts % vsdb::week())
    }

    public fun get_epoch_start( ts: u64):u64{
        let bribe_start = bribe_start(ts);
        let bribe_end = bribe_start + DURATION;
        if( ts < bribe_end){
            return bribe_start
        }else{
            return bribe_end
        }
    }

    // refactor through assigning third generic type argument
    fun earned_x<X,Y>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &VSDB,
        clock: &Clock
    ):u64{
        let id = object::id(vsdb);
        // checking contains is sufficient
        if(!table::contains(&self.reward_x.last_earn, id) || !table::contains(&self.checkpoints, id) || !table::contains(&self.reward_x.reward_per_token_checkpoints, id)){
            return 0
        };

        let last_earn = *table::borrow(&self.reward_x.last_earn, id);
        let start_timestamp =  math::max(last_earn, table_vec::borrow(table::borrow(&self.reward_x.reward_per_token_checkpoints, id), 0).timestamp);

        let player_checkpoint = table::borrow(&self.checkpoints, id);

        let start_idx = get_prior_balance_index(self, vsdb, start_timestamp);
        let end_idx = table_vec::length(player_checkpoint) - 1;
        let earned_reward = 0;

        if(end_idx > 0){
            let i = start_idx;
            while( i <= end_idx - 1){
                let cp_0 = table_vec::borrow(player_checkpoint, i);
                let cp_1 = table_vec::borrow(player_checkpoint, i + 1);
                let ( _, reward_per_token_0) = get_prior_reward_per_token<X>(&self.reward_x, vsdb, cp_0.timestamp);
                let ( _, reward_per_token_1 ) = get_prior_reward_per_token<X>(&self.reward_x, vsdb, cp_1.timestamp);
                earned_reward =  earned_reward +  cp_0.balance *  ( reward_per_token_1 - reward_per_token_0) / PRECISION;
                i = i + 1;
            }
        };

        let checkpoint = table_vec::borrow(player_checkpoint, end_idx);
        let ( _, reward_per_token ) = get_prior_reward_per_token<X>(&self.reward_x, vsdb, checkpoint.timestamp);
        earned_reward = earned_reward + checkpoint.balance * (get_reward_per_token<X>(self.total_supply, &self.reward_x, clock) - math::max(reward_per_token, *table::borrow(&self.reward_x.user_reward_per_token_stored, id))) / PRECISION;

        return earned_reward
    }

    // calculate reward between each supply checkpoints
    fun calc_reward_per_token<T>(
        reward: &Reward<T>,
        timestamp_1: u64,
        timestamp_0: u64,
        supply: u64,
        start_timestamp: u64 // last update time
    ):(u64, u64){
        let end_time = math::max(timestamp_1, start_timestamp);
        let reward =  (math::min(end_time, reward.period_finish) - math::min(math::max(timestamp_0, start_timestamp), reward.period_finish)) * reward.reward_rate * PRECISION / supply ;

        return ( reward, end_time )
    }

    // ===== Setter =====
    fun write_checkpoint<X,Y>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &VSDB,
        balance: u64, // record down balance
        clock: &Clock,
        ctx: &mut TxContext
    ){
        let vsdb = object::id(vsdb);
        let timestamp = clock::timestamp_ms(clock);

        // create table_vec for new registry
        if( !table::contains(&self.checkpoints, vsdb)){
            let checkpoints = table_vec::empty(ctx);
            table::add(&mut self.checkpoints, vsdb, checkpoints);
        };

        let player_checkpoint = table::borrow_mut(&mut self.checkpoints, vsdb);
        let len = table_vec::length(player_checkpoint);

        if( len > 0 && table_vec::borrow(player_checkpoint, len - 1).timestamp == timestamp){
            let cp_mut = table_vec::borrow_mut(player_checkpoint, len - 1 );
            cp_mut.balance = balance;
        }else{
            let checkpoint = Checkpoint{
                timestamp,
                balance
            };
            table_vec::push_back(player_checkpoint, checkpoint);
        };
    }

    fun write_reward_per_token_checkpoint<T>(
        reward: &mut Reward<T>,
        vsdb: &VSDB,
        reward_per_token: u64, // record down balance
        timestamp: u64,
        ctx: &mut TxContext
    ){
        let vsdb = object::id(vsdb);

        if( !table::contains(&reward.reward_per_token_checkpoints, vsdb)){
            let checkpoints = table_vec::empty(ctx);
            table::add(&mut reward.reward_per_token_checkpoints, vsdb, checkpoints);
        };

        let player_checkpoint = table::borrow_mut(&mut reward.reward_per_token_checkpoints, vsdb);
        let len = table_vec::length(player_checkpoint);

        if( len > 0 && table_vec::borrow(player_checkpoint, len - 1).timestamp == timestamp){
            let cp_mut = table_vec::borrow_mut(player_checkpoint, len - 1 );
            cp_mut.reward_per_token = reward_per_token ;
        }else{
            let checkpoint = RewardPerTokenCheckpoint{
                timestamp,
                reward_per_token
            };
            table_vec::push_back(player_checkpoint, checkpoint);
        };
    }

    fun write_supply_checkpoint<X,Y>(
        self: &mut InternalBribe<X,Y>,
        clock: &Clock,
        //ctx: &mut TxContext
    ){
        let timestamp = clock::timestamp_ms(clock);
        let supply = self.total_supply;

        let len = table_vec::length(&self.supply_checkpoints);

        if( len > 0 && table_vec::borrow(&self.supply_checkpoints, len - 1).timestamp == timestamp){
            let cp_mut = table_vec::borrow_mut(&mut self.supply_checkpoints, len - 1 );
            cp_mut.supply = supply;
        }else{
            let checkpoint = SupplyCheckpoint{
                timestamp,
                supply
            };
            table_vec::push_back(&mut self.supply_checkpoints, checkpoint);
        };
    }


    /// require when
    /// 1. reward claims,
    /// 2. deposit ( votes )
    /// 3. withdraw ( revoke )
    /// 4. distribute
    /// update both global & plyaer state repsecitvley
    fun update_reward_per_token_x<X,Y>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &VSDB,
        max_run:u64,
        actual_last: bool,
        clock: &Clock,
        ctx: &mut TxContext
    ):(u64, u64) // ( reward_per_token_sttored, last_update_time)
    {
        let reward = &self.reward_x;
        let start_timestamp = reward.last_update_time;
        let reward_ = reward.reward_per_token_stored;

        if(table_vec::length(&self.supply_checkpoints) == 0){
            return ( reward_, start_timestamp )
        };

        if(reward.reward_rate == 0){
            return ( reward_, clock::timestamp_ms(clock))
        };

        let start_idx = get_prior_supply_index(self, start_timestamp);
        let end_idx = math::min(table_vec::length(&self.supply_checkpoints) - 1, max_run);

        let reward = &mut self.reward_x;

        // update reward_per_token_checkpoints
        if(end_idx > 0){
            let i = start_idx;
            while( i <= end_idx - 1){
                let sp_0 = table_vec::borrow(&self.supply_checkpoints, i);
                if(sp_0.supply > 0){
                    let sp_1 = table_vec::borrow(&self.supply_checkpoints, i + 1);
                    let ( reward_per_token , end_time) = calc_reward_per_token(reward, sp_1.timestamp, sp_0.timestamp, sp_0.supply, start_timestamp);
                    reward_ = reward_ + reward_per_token;
                    write_reward_per_token_checkpoint<X>(reward, vsdb, reward_, end_time, ctx);
                    start_timestamp = end_time;
                };
                i = i + 1;
            }
        };

        if(actual_last){
            let sp = table_vec::borrow(&self.supply_checkpoints, end_idx);
            if(sp.supply > 0){
                let last_time_reward = last_time_reward_applicable(reward, clock);
                let ( reward_per_token, _ ) = calc_reward_per_token(reward, last_time_reward, math::max(sp.timestamp, start_timestamp), sp.supply, start_timestamp);
                reward_ = reward_ + reward_per_token;
                write_reward_per_token_checkpoint(reward, vsdb, reward_, clock::timestamp_ms(clock), ctx);
                start_timestamp = clock::timestamp_ms(clock);
            };
        };

        return ( reward_, start_timestamp )
    }

    /// allows a player to claim reward for a given bribe
    fun get_reward_x<X, Y>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &VSDB,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        let id = object::id(vsdb);
        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token_x(self, vsdb, MAX_U64, true, clock, ctx);
        self.reward_x.reward_per_token_stored = reward_per_token_stored;
        self.reward_x.last_update_time = last_update_time;

        let _reward = earned_x(self, vsdb, clock);
        *table::borrow_mut(&mut self.reward_x.last_earn, id) = clock::timestamp_ms(clock);
        *table::borrow_mut(&mut self.reward_x.user_reward_per_token_stored, id) = reward_per_token_stored;

        if(_reward > 0){
            let coin_x = coin::take(&mut self.reward_x.balance, _reward, ctx);
            let value_x = coin::value(&coin_x);
            transfer::public_transfer(
                coin_x,
                tx_context::sender(ctx)
            );

            event::claim_reward(tx_context::sender(ctx), value_x);
        }
    }

    // called by voter
    fun deposit_x<X,Y>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &VSDB,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token_x(self, vsdb, MAX_U64, true, clock, ctx);
        self.reward_x.reward_per_token_stored = reward_per_token_stored;
        self.reward_x.last_update_time = last_update_time;

        self.total_supply = self.total_supply + amount;
        *table::borrow_mut(&mut self.balace_of, object::id(vsdb)) = *table::borrow(& self.balace_of, object::id(vsdb)) + amount;

        write_checkpoint(self, vsdb, amount, clock, ctx);
        write_supply_checkpoint(self, clock);
    }

    fun withdraw_x<X,Y>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &VSDB,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token_x(self, vsdb, MAX_U64, true, clock, ctx);
        self.reward_x.reward_per_token_stored = reward_per_token_stored;
        self.reward_x.last_update_time = last_update_time;

        self.total_supply = self.total_supply - amount;
        *table::borrow_mut(&mut self.balace_of, object::id(vsdb)) = *table::borrow(& self.balace_of, object::id(vsdb)) - amount;

        write_checkpoint(self, vsdb, amount, clock, ctx);
        write_supply_checkpoint(self, clock);
    }



    // ===== getter =====
    // #[test_only]public fun mock_init(ctx: &mut TxContext){
    //     init(ctx);
    // }

}