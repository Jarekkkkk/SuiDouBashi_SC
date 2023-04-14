// Internal Bribes represent pool fee distributed to LP holders
module suiDouBashiVest::internal_bribe{
    use std::type_name::{Self, TypeName};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::dynamic_object_field as dof;
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::clock::{Self, Clock};
    use sui::math;
    use sui::table::{Self, Table};
    use sui::table_vec::{Self, TableVec};

    use suiDouBashi::pool::Pool;
    use suiDouBashiVest::vsdb::{Self, VSDB};
    use suiDouBashiVest::event;
    use suiDouBashiVest::err;
    use suiDouBashiVest::reward::{Self, Reward};
    use suiDouBashiVest::checkpoints::{Self, SupplyCheckpoint, Checkpoint};

    friend suiDouBashiVest::gauge;
    friend suiDouBashiVest::voter;

    const DURATION: u64 = { 7 * 86400 };
    const PRECISION: u64 = 1_000_000_000_000_000_000;
    const MAX_REWARD_TOKENS: u64 = 16;
    const MAX_U64: u64 = 18446744073709551615_u64;


    struct InternalBribe<phantom X, phantom Y> has key, store{
        id: UID,
        pool:ID,

        // TODO:
        //rewards: InternalBribe: 2, externalBribe: multiple

        /// Voting weight
        total_supply: u64,
        balace_of: Table<ID, u64>,

        supply_checkpoints: TableVec<SupplyCheckpoint>,

        // should this be shared object, or this will be too overkill
        // type_name -> Reward<T>

        checkpoints: Table<ID, TableVec<Checkpoint>>, // VSDB -> balance checkpoint
    }

    // - Reward
    /// TODO: whitelisted coin type, and type validatoin
    fun create_reward<X,Y,T>(self: &mut InternalBribe<X,Y>, ctx: &mut TxContext){
        assert_generic_type<X,Y,T>();
        let type_name = type_name::get<T>();
        let reward =  reward::new<X,Y,T>(ctx);
        dof::add(&mut self.id, type_name, reward);
    }
    public fun borrow_reward<X,Y,T>(self: &InternalBribe<X,Y>):&Reward<X, Y, T>{
        let type_name = type_name::get<T>();
        assert_reward_created<X,Y,T>(self, type_name);
        dof::borrow(&self.id, type_name)
    }
    fun borrow_reward_mut<X,Y,T>(self: &mut InternalBribe<X,Y>):&mut Reward<X, Y, T>{
        let type_name = type_name::get<T>();
        assert_reward_created<X,Y,T>(self, type_name);
        dof::borrow_mut(&mut self.id, type_name)
    }

    public fun assert_generic_type<X,Y,T>(){
        let type_t = type_name::get<T>();
        let type_x = type_name::get<X>();
        let type_y = type_name::get<Y>();
        assert!( type_t == type_x || type_t == type_y, err::invalid_type_argument());
    }

    public fun assert_reward_created<X,Y,T>(self: &InternalBribe<X,Y>, type_name: TypeName){
        assert!(dof::exists_(&self.id, type_name), err::reward_not_exist());
    }
    // being calling by voter, when creating guage
    public (friend )fun create_bribe<X,Y>(
        pool: & Pool<X,Y>,
        ctx: &mut TxContext
    ):ID {
        let bribe = InternalBribe<X,Y>{
            id: object::new(ctx),
            pool: object::id(pool),
            total_supply:0,
            balace_of: table::new<ID, u64>(ctx),
            supply_checkpoints: table_vec::empty<SupplyCheckpoint>(ctx),

            checkpoints: table::new<ID, TableVec<Checkpoint>>(ctx), // voting weights for each voter
        };
        let id = object::id(&bribe);
        create_reward<X,Y,X>(&mut bribe, ctx);
        create_reward<X,Y,Y>(&mut bribe, ctx);

        transfer::share_object(bribe);

        id
    }

    // ===== Getter =====
    ///  Determine the prior balance for an account as of a time_stmap
    public fun get_prior_balance_index<X,Y>(
        self: & InternalBribe<X,Y>,
        vsdb: &VSDB,
        ts:u64
    ):u64 {
        let checkpoints = table::borrow(&self.checkpoints, object::id(vsdb));
        let len = table_vec::length(checkpoints);

        if( len == 0){
            return 0
        };

        if(!table::contains(&self.checkpoints, object::id(vsdb))){
            return 0
        };

        if( checkpoints::balance_ts(table_vec::borrow(checkpoints, len - 1)) <= ts ){
            return len - 1
        };

        if( checkpoints::balance_ts(table_vec::borrow(checkpoints, 0)) > ts){
            return 0
        };

        let lower = 0;
        let upper = len - 1;
        while ( lower < upper){
            let center = upper - (upper - lower) / 2;
            let cp_ts = checkpoints::balance_ts(table_vec::borrow(checkpoints, center));
            if(cp_ts == ts ){
                return center
            }else if (cp_ts < ts){
                lower = center;
            }else{
                upper = center -1 ;
            }
        };
        return lower
    }

    public fun get_prior_supply_index<X,Y>(
        self: & InternalBribe<X,Y>,
        ts:u64
    ):u64 {
        let len = table_vec::length(&self.supply_checkpoints);

        if( len == 0){
            return 0
        };

        if( checkpoints::supply_ts(table_vec::borrow(&self.supply_checkpoints, len - 1)) <= ts ){
            return len - 1
        };

        if( checkpoints::supply_ts(table_vec::borrow(&self.supply_checkpoints, 0)) > ts){
            return 0
        };

        let lower = 0;
        let upper = len - 1;
        while ( lower < upper){
            let center = upper - (upper - lower) / 2;
            let sp_ts = checkpoints::supply_ts(table_vec::borrow(&self.supply_checkpoints, center));
            if( sp_ts == ts ){
                return center
            }else if ( sp_ts < ts){
                lower = center;
            }else{
                upper = center -1 ;
            }
        };

        return lower
    }

    // move to REWARD
    public fun get_prior_reward_per_token<X, Y, T>(
        reward: &Reward<X, Y, T>,
        vsdb: &VSDB,
        ts:u64
    ):(u64, u64) // ( ts, reward_per_token )
    {
        let id = object::id(vsdb);
        let checkpoints = reward::reward_per_token_checkpoints_borrow(reward);
        let len = table_vec::length(checkpoints);

        if( len == 0){
            return ( 0, 0 )
        };

        // return the latest reward as of specific time
        if( checkpoints::reward_ts(table_vec::borrow(checkpoints, len - 1)) <= ts ){
            let last_checkpoint = table_vec::borrow(checkpoints, len - 1);
            return ( checkpoints::reward_ts(last_checkpoint), checkpoints::reward(last_checkpoint))
        };

        if( checkpoints::reward_ts(table_vec::borrow(checkpoints, 0)) > ts){
            return ( 0, 0 )
        };

        let lower = 0;
        let upper = len - 1;
        while ( lower < upper){
            let center = upper - (upper - lower) / 2;
            let rp_ts = checkpoints::reward_ts(table_vec::borrow(checkpoints, center));
            let reward = checkpoints::reward(table_vec::borrow(checkpoints, center));
            if(rp_ts == ts ){
                return (rp_ts, reward )
            }else if (rp_ts < ts){
                lower = center;
            }else{
                upper = center -1 ;
            }
        };
        let rp = table_vec::borrow(checkpoints, lower);
        return ( checkpoints::reward_ts(rp), checkpoints::reward(rp))
    }

    /// each pro rata coin distribution with total voting supply
    fun get_reward_per_token<X, Y, T>(
        self: &InternalBribe<X,Y>,
        clock: &Clock
    ): u64{
        let reward = borrow_reward<X,Y,T>(self);
        let reward_stored = reward::reward_per_token_stored(reward);

        // no accumualated voting
        if(self.total_supply == 0){
            return reward_stored
        };

        let last_update = reward::last_update_time(reward);
        let period_finish = reward::period_finish(reward);
        let reward_rate = reward::reward_rate(reward);

        return  reward_stored + (last_time_reward_applicable(reward, clock) - math::min(last_update, period_finish)) * reward_rate * PRECISION / self.total_supply
    }

    public fun left<X, Y, T>(reward: &Reward<X, Y, T>, clock: &Clock):u64{
        let ts = clock::timestamp_ms(clock);
        let period_finish = reward::period_finish(reward);
        let reward_rate = reward::reward_rate(reward);

        // no on bribing
        if(ts >= period_finish) return 0;

        let _remaining = period_finish - ts;
        return _remaining * reward_rate
    }

    ///  returns the last time the reward was modified or periodFinish if the reward has ended
    public fun last_time_reward_applicable<X, Y, T>(reward: &Reward<X, Y, T>, clock: &Clock):u64{
        // Two scenarios
        // 1. return current time if we are still in epoch
        // 2  return period_finish if new bribes hasn't deposited in new epoch yet
        math::min(clock::timestamp_ms(clock), reward::period_finish(reward))
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

    // get accumulated coins for individual players
    fun earned<X,Y,T>(
        self: &InternalBribe<X,Y>,
        vsdb: &VSDB,
        clock: &Clock
    ):u64{
        assert_generic_type<X,Y,T>();

        let reward = borrow_reward<X,Y,T>(self);
        let rps_borrow = reward::reward_per_token_checkpoints_borrow(reward);
        let id = object::id(vsdb);
        // checking contains is sufficient, not allowing to exist any empty table
        if(!reward::last_earn_contain(reward, id) || !table::contains(&self.checkpoints, id) || table_vec::length(rps_borrow) == 0){
            return 0
        };

        let last_earn = reward::last_earn(reward, id);
        let start_timestamp =  math::max(last_earn, checkpoints::reward_ts(table_vec::borrow(rps_borrow, 0)));

        let bps_borrow = table::borrow(&self.checkpoints, id);

        let start_idx = get_prior_balance_index(self, vsdb, start_timestamp);
        let end_idx = table_vec::length(bps_borrow) - 1;
        let earned_reward = 0;

        // accumulate rewards in each reward checkpoints derived from balance checkpoints
        if(end_idx > 0){
            let i = start_idx;
            while( i <= end_idx - 1){ // leave last one
                let cp_0 = table_vec::borrow(bps_borrow, i);
                let cp_1 = table_vec::borrow(bps_borrow, i + 1);
                let ( _, reward_per_token_0) = get_prior_reward_per_token(reward, vsdb, checkpoints::balance_ts(cp_0));
                let ( _, reward_per_token_1 ) = get_prior_reward_per_token(reward, vsdb, checkpoints::balance_ts(cp_1));
                earned_reward =  earned_reward +  checkpoints::balance(cp_0) *  ( reward_per_token_1 - reward_per_token_0) / PRECISION;
                i = i + 1;
            }
        };

        let cp = table_vec::borrow(bps_borrow, end_idx);
        let ( _, reward_per_token ) = get_prior_reward_per_token(reward, vsdb, checkpoints::balance_ts(cp));

        // HOw ?
        earned_reward = earned_reward + checkpoints::balance(cp) * (get_reward_per_token<X,Y,T>(self, clock) - math::max(reward_per_token, reward::user_reward_per_token_stored(reward, id))) / PRECISION;

        return earned_reward
    }

    // calculate reward between supply checkpoints
    fun calc_reward_per_token<X, Y, T>(
        reward: &Reward<X, Y, T>,
        timestamp_1: u64,
        timestamp_0: u64,
        supply: u64,
        start_timestamp: u64 // last update time
    ):(u64, u64){
        let end_time = math::max(timestamp_1, start_timestamp);
        let start_time = math::max(timestamp_0, start_timestamp);
        let reward =  (math::min(end_time, reward::period_finish(reward)) - math::min(start_time, reward::period_finish(reward))) * reward::reward_rate(reward) * PRECISION / supply ;

        ( reward, end_time )
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

        if( !table::contains(&self.checkpoints, vsdb)){
            let checkpoints = table_vec::empty(ctx);
            table::add(&mut self.checkpoints, vsdb, checkpoints);
        };

        let player_checkpoint = table::borrow_mut(&mut self.checkpoints, vsdb);
        let len = table_vec::length(player_checkpoint);

        if( len > 0 && checkpoints::balance_ts(table_vec::borrow(player_checkpoint, len - 1)) == timestamp){
            let cp_mut = table_vec::borrow_mut(player_checkpoint, len - 1 );
            checkpoints::update_balance(cp_mut, balance);
        }else{
            let checkpoint = checkpoints::new_cp(timestamp, balance);
            table_vec::push_back(player_checkpoint, checkpoint);
        };
    }

    fun write_reward_per_token_checkpoint<X, Y, T>(
        reward: &mut Reward<X, Y, T>,
        reward_per_token: u64, // record down balance
        timestamp: u64,
    ){
        //register new one
        let rp_s = reward::reward_per_token_checkpoints_borrow_mut(reward);
        let len = table_vec::length(rp_s);
        if(len > 0 && checkpoints::reward_ts(table_vec::borrow(rp_s, len - 1)) == timestamp){
            let rp = table_vec::borrow_mut(rp_s, len - 1);
            checkpoints::update_reward(rp, reward_per_token);
        }else{
            table_vec::push_back(rp_s, checkpoints::new_rp(timestamp, reward_per_token));
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

        if( len > 0 && checkpoints::supply_ts(table_vec::borrow(&self.supply_checkpoints, len - 1)) == timestamp){
            let cp_mut = table_vec::borrow_mut(&mut self.supply_checkpoints, len - 1 );
            checkpoints::update_supply(cp_mut, supply)
        }else{
            let checkpoint = checkpoints::new_sp(timestamp, supply);
            table_vec::push_back(&mut self.supply_checkpoints, checkpoint);
        };
    }

    /// require when
    /// 1. reward claims,
    /// 2. deposit ( votes )
    /// 3. withdraw ( revoke )
    /// 4. distribute
    /// update both global & plyaer state repsecitvley
    fun update_reward_per_token<X,Y,T>(
        self: &mut InternalBribe<X,Y>,
        max_run:u64,
        actual_last: bool,
        clock: &Clock,
        ctx: &mut TxContext
    ):(u64, u64) // ( reward_per_token_stored, last_update_time)
    {
        // only check internal bribe
        assert_generic_type<X,Y,T>();

        let ts = clock::timestamp_ms(clock);
        let reward = borrow_reward<X,Y,T>(self);
        let start_timestamp = reward::last_update_time(reward);
        let reward_token_stored = reward::reward_per_token_stored(reward);

        if(table_vec::length(&self.supply_checkpoints) == 0){
            return ( reward_token_stored, start_timestamp )
        };

        if(reward::reward_rate(reward) == 0){
            return ( reward_token_stored, ts )
        };

        let start_idx = get_prior_supply_index(self, start_timestamp);
        let end_idx = math::min(table_vec::length(&self.supply_checkpoints) - 1, max_run);

        // update reward_per_token_checkpoints
        if(end_idx > 0){
            let i = start_idx;
            while( i <= end_idx - 1){
                let sp_0_ts = checkpoints::supply_ts(table_vec::borrow(&self.supply_checkpoints, i));
                let sp_0_supply = checkpoints::supply(table_vec::borrow(&self.supply_checkpoints, i));
                if(sp_0_supply > 0){
                    let sp_1_ts = checkpoints::supply_ts(table_vec::borrow(&self.supply_checkpoints, i + 1));
                    let reward = borrow_reward_mut<X,Y,T>(self);
                    let ( reward_per_token , end_time) = calc_reward_per_token(reward, sp_1_ts, sp_0_ts, sp_0_supply, start_timestamp);
                    reward_token_stored = reward_token_stored + reward_per_token;
                    write_reward_per_token_checkpoint(reward, reward_token_stored, end_time);
                    start_timestamp = end_time;
                };
                i = i + 1;
            }
        };

        if(actual_last){
            let sp_supply = checkpoints::supply(table_vec::borrow(&self.supply_checkpoints, end_idx));
            let sp_ts = checkpoints::supply_ts(table_vec::borrow(&self.supply_checkpoints, end_idx));
            if(sp_supply > 0){
                let reward = borrow_reward_mut<X,Y,T>(self);
                let last_time_reward = last_time_reward_applicable(reward, clock);
                let ( reward_per_token, _ ) = calc_reward_per_token(reward, last_time_reward, math::max(sp_ts, start_timestamp), sp_supply, start_timestamp);
                reward_token_stored = reward_token_stored + reward_per_token;
                let reward = borrow_reward_mut<X,Y,T>(self);
                write_reward_per_token_checkpoint(reward, reward_token_stored, ts);
                start_timestamp = ts;
            };
        };

        return ( reward_token_stored, start_timestamp )
    }

    /// allows a player to claim reward for a given bribe
    public (friend) fun get_reward<X, Y, T>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &VSDB,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert_generic_type<X,Y,T>();

        let id = object::id(vsdb);
        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token<X,Y,T>(self, MAX_U64, true, clock, ctx);

        let _reward = earned<X,Y,T>(self, vsdb, clock);

        let reward = borrow_reward_mut<X,Y,T>(self);
        reward::update_reward_per_token_stored(reward, reward_per_token_stored);
        reward::update_last_update_time(reward, last_update_time);

        reward::update_last_earn(reward, id, clock::timestamp_ms(clock));
        reward::update_user_reward_per_token_stored(reward, id, reward_per_token_stored);

        if(_reward > 0){
            let coin_x = coin::take(reward::balance_mut(reward), _reward, ctx);
            let value_x = coin::value(&coin_x);
            transfer::public_transfer(
                coin_x,
                tx_context::sender(ctx)
            );

            event::claim_reward(tx_context::sender(ctx), value_x);
        }
    }

    // Cna be public (?), and remove Voter from friend module
    public (friend) fun deposit<X,Y,T>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &VSDB,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert_generic_type<X,Y,T>();

        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token<X,Y,T>(self, MAX_U64, true, clock, ctx);

        let reward = borrow_reward_mut<X,Y,T>(self);
        reward::update_reward_per_token_stored(reward, reward_per_token_stored);
        reward::update_last_update_time(reward, last_update_time);

        self.total_supply = self.total_supply + amount;
        *table::borrow_mut(&mut self.balace_of, object::id(vsdb)) = *table::borrow(& self.balace_of, object::id(vsdb)) + amount;

        write_checkpoint(self, vsdb, amount, clock, ctx);
        write_supply_checkpoint(self, clock);
    }

    public (friend) fun withdraw<X,Y,T>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &VSDB,
        amount: u64, // should be u256
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert_generic_type<X,Y,T>();

        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token<X,Y,T>(self, MAX_U64, true, clock, ctx);

        let reward = borrow_reward_mut<X,Y,T>(self);
        reward::update_reward_per_token_stored(reward, reward_per_token_stored);
        reward::update_last_update_time(reward, last_update_time);

        self.total_supply = self.total_supply - amount;
        *table::borrow_mut(&mut self.balace_of, object::id(vsdb)) = *table::borrow(& self.balace_of, object::id(vsdb)) - amount;

        write_checkpoint(self, vsdb, amount, clock, ctx);
        write_supply_checkpoint(self, clock);
    }

    /// used to notify a gauge/bribe of a given reward, this can create griefing attacks by extending
    /// Bribe created !!!
    public fun notify_reward_amount<X,Y,T>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &VSDB,
        coin: Coin<T>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert_generic_type<X,Y,T>();

        let value = coin::value(&coin);
        let reward = borrow_reward<X,Y,T>(self);
        assert!(value > 0, 0);

        let ts = clock::timestamp_ms(clock);
        if(reward::reward_rate(reward) == 0){
            write_reward_per_token_checkpoint(borrow_reward_mut<X,Y,T>(self), 0, ts);
        };

        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token<X,Y,T>(self, MAX_U64, true, clock, ctx);

        let reward = borrow_reward_mut<X,Y,T>(self);
        reward::update_reward_per_token_stored(reward, reward_per_token_stored);
        reward::update_last_update_time(reward, last_update_time);

        // initial bribe in each epoch
        if(ts >= reward::period_finish(reward)){
            coin::put(reward::balance_mut(reward), coin);
            reward::update_reward_rate(reward, value / DURATION);
        }else{
        // accumulate bribes in each eopch
            let _remaining = reward::period_finish(reward) - ts;
            let _left = _remaining * reward::reward_rate(reward);
            assert!(value > _left, 1);
            coin::put(reward::balance_mut(reward), coin);
            reward::update_reward_rate(reward, ( value + _left ) / DURATION);
        };

        assert!(reward::reward_rate(reward) > 0,  err::invalid_reward_rate());
        let bal_total = reward::balance(reward);
        assert!( reward::reward_rate(reward) <= bal_total / DURATION,  err::max_reward());

        reward::update_period_finish(reward, ts + DURATION);

        event::notify_reward<X>(tx_context::sender(ctx), value);
    }
}