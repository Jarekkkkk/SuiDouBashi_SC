// Internal Bribes represent pool fee distributed to LP holders
module suiDouBashiVest::internal_bribe{
    use std::type_name::{Self, TypeName};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::clock::{Self, Clock};
    use sui::balance::{Self, Balance};
    use sui::math;
    use sui::table::{Self, Table};
    use sui::table_vec::{Self, TableVec};
    use sui::object_bag::{Self as ob, ObjectBag};

    use suiDouBashi::pool::Pool;
    use suiDouBashiVest::vsdb::VSDB;
    use suiDouBashiVest::event;
    use suiDouBashiVest::err;
    use suiDouBashiVest::checkpoints::{Self, SupplyCheckpoint, Checkpoint, RewardPerTokenCheckpoint};

    friend suiDouBashiVest::gauge;
    friend suiDouBashiVest::voter;

    const DURATION: u64 = { 7 * 86400 };
    const PRECISION: u256 = 1_000_000_000_000_000_000;
    const MAX_REWARD_TOKENS: u64 = 16;
    const MAX_U64: u64 = 18446744073709551615_u64;

    struct InternalBribe<phantom X, phantom Y> has key, store{
        id: UID,
        pool:ID,
        governor: address,

        /// Voting weight
        total_supply: u64, // is u64 enough ?
        balace_of: Table<ID, u64>,
        supply_checkpoints: TableVec<SupplyCheckpoint>,

        checkpoints: Table<ID, TableVec<Checkpoint>>, // VSDB -> balance checkpoint

        rewards: ObjectBag //TypeName<T> -> Reward<T>,
    }

    // - Reward
    struct Reward<phantom X, phantom Y, phantom T> has key, store{
        id: UID,

        balance: Balance<T>,

        //update when bribe is deposited
        reward_rate: u64, // bribe_amount/ 7 days
        period_finish: u64, // update when bribe is deposited, (internal_bribe -> fee ), (external_bribe -> doverse coins)

        last_update_time: u64, // update when someone 1.voting/ 2.reset/ 3.withdraw bribe/ 4. deposite bribe
        reward_per_token_stored: u64,

        user_reward_per_token_stored: Table<ID, u64>, // udpate when user deposit

        reward_per_token_checkpoints: TableVec<RewardPerTokenCheckpoint>,
        last_earn: Table<ID, u64>, // update when claim fees
    }
    fun create_reward<X,Y,T>(self: &mut InternalBribe<X,Y>, ctx: &mut TxContext){
        let type_name = type_name::get<T>();
        let reward =  Reward<X,Y,T>{
            id: object::new(ctx),
            balance: balance::zero<T>(),
            reward_rate: 0,
            period_finish: 0,
            last_update_time: 0,
            reward_per_token_stored: 0,
            reward_per_token_checkpoints: table_vec::empty<RewardPerTokenCheckpoint>(ctx),

            user_reward_per_token_stored: table::new<ID, u64>(ctx),
            last_earn: table::new<ID, u64>(ctx),
        };
        ob::add(&mut self.rewards, type_name, reward);
    }
    public fun borrow_reward<X,Y,T>(self: &InternalBribe<X,Y>):&Reward<X, Y, T>{
        let type_name = type_name::get<T>();
        assert_reward_created<X,Y,T>(self, type_name);
        ob::borrow(&self.rewards, type_name)
    }
    fun borrow_reward_mut<X,Y,T>(self: &mut InternalBribe<X,Y>):&mut Reward<X, Y, T>{
        let type_name = type_name::get<T>();
        assert_reward_created<X,Y,T>(self, type_name);
        ob::borrow_mut(&mut self.rewards, type_name)
    }

    // ===== Assertion =====
    public fun assert_generic_type<X,Y,T>(){
        let type_t = type_name::get<T>();
        let type_x = type_name::get<X>();
        let type_y = type_name::get<Y>();
        assert!( type_t == type_x || type_t == type_y, err::invalid_type_argument());
    }
    public fun assert_governor<X,Y>(self: &InternalBribe<X,Y>, ctx: &mut TxContext){
        assert!(self.governor == tx_context::sender(ctx), err::invalid_governor());
    }
    public fun assert_reward_created<X,Y,T>(self: &InternalBribe<X,Y>, type_name: TypeName){
        assert!(ob::contains(&self.rewards, type_name), err::reward_not_exist());
    }
    // being called by voter, when creating guage
    public (friend )fun create_bribe<X,Y>(
        pool: & Pool<X,Y>,
        ctx: &mut TxContext
    ):ID {
        let bribe = InternalBribe<X,Y>{
            id: object::new(ctx),
            governor: tx_context::sender(ctx),
            pool: object::id(pool),
            total_supply:0,
            balace_of: table::new<ID, u64>(ctx),
            supply_checkpoints: table_vec::empty<SupplyCheckpoint>(ctx),

            checkpoints: table::new<ID, TableVec<Checkpoint>>(ctx), // voting weights for each voter,
            rewards: ob::new(ctx)
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
        ts:u64
    ):(u64, u64) // ( ts, reward_per_token )
    {
        let checkpoints = &reward.reward_per_token_checkpoints;
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
    fun reward_per_token<X, Y, T>(
        self: &InternalBribe<X,Y>,
        clock: &Clock
    ): u64{
        let reward = borrow_reward<X,Y,T>(self);
        let reward_stored = reward.reward_per_token_stored;

        // no accumualated voting
        if(self.total_supply == 0){
            return reward_stored
        };

        let elapsed = ((last_time_reward_applicable(reward, clock) - math::min(reward.last_update_time, reward.period_finish)) as u256);
        return reward_stored + (elapsed * (reward.reward_rate as u256) * PRECISION / (self.total_supply as u256) as u64)
    }

    public fun left<X, Y, T>(reward: &Reward<X, Y, T>, clock: &Clock):u64{
        let ts = clock::timestamp_ms(clock);

        // no one bribing
        if(ts >= reward.period_finish) return 0;

        let _remaining = reward.period_finish - ts;
        return _remaining * reward.reward_rate
    }

    ///  returns the last time the reward was modified or periodFinish if the reward has ended
    public fun last_time_reward_applicable<X, Y, T>(reward: &Reward<X, Y, T>, clock: &Clock):u64{
        // Two scenarios
        // 1. return current time if latest bribe is deposited in 7 days
        // 2  return period_finish bribe has been abandoned over 7 days
        math::min(clock::timestamp_ms(clock), reward.period_finish)
    }

    // get accumulated coins for individual players
    fun earned<X,Y,T>(
        self: &InternalBribe<X,Y>,
        vsdb: &VSDB,
        clock: &Clock
    ):u64{
        assert_generic_type<X,Y,T>();

        let reward = borrow_reward<X,Y,T>(self);
        let rps_borrow = &reward.reward_per_token_checkpoints;
        let id = object::id(vsdb);
        // checking balance checkpoint for individual checkpoint is enough, since we empty table_vec is not allowed to exist
        if( !table::contains(&reward.last_earn, id) || !table::contains(&self.checkpoints, id) || table_vec::length(rps_borrow) == 0 ){
            return 0
        };

        let start_timestamp = math::max(*table::borrow(&reward.last_earn, id), checkpoints::reward_ts(table_vec::borrow(rps_borrow, 0)));

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
                let (_, reward_per_token_0) = get_prior_reward_per_token(reward, checkpoints::balance_ts(cp_0));
                let (_, reward_per_token_1) = get_prior_reward_per_token(reward, checkpoints::balance_ts(cp_1));
                // Is this always positive ?
                let acc = (checkpoints::balance(cp_0) as u256) * ((reward_per_token_1 - reward_per_token_0) as u256) / PRECISION;
                earned_reward = earned_reward +  (acc as u64);
                i = i + 1;
            }
        };

        let cp = table_vec::borrow(bps_borrow, end_idx);
        let ( _, perior_reward ) = get_prior_reward_per_token(reward, checkpoints::balance_ts(cp));
        let user_stored = if(table::contains(&reward.user_reward_per_token_stored, id)){
            *table::borrow(&reward.user_reward_per_token_stored, id)
        }else{
            0
        };
        let acc = (checkpoints::balance(cp) as u256) * ((reward_per_token<X,Y,T>(self, clock) - math::max(perior_reward, user_stored)) as u256) / PRECISION;
        earned_reward = earned_reward + (acc as u64);

        return earned_reward
    }

    // calculate reward between 2 supply checkpoints
    fun calc_reward_per_token<X, Y, T>(
        reward: &Reward<X, Y, T>,
        timestamp_1: u64,
        timestamp_0: u64,
        supply: u64,
        start_timestamp: u64 // last update time
    ):(u64, u64){
        let end_time = math::max(timestamp_1, start_timestamp);
        let start_time = math::max(timestamp_0, start_timestamp);
        let reward =  ((math::min(end_time, reward.period_finish) - math::min(start_time, reward.period_finish)) as u256) * (reward.reward_rate as u256) * PRECISION / (supply as u256) ;

        ((reward as u64), end_time)
    }

    // ===== Setter =====
    fun write_checkpoint_<X,Y>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &VSDB,
        balance: u64, // record down balance
        clock: &Clock,
        ctx: &mut TxContext
    ){
        let vsdb = object::id(vsdb);
        let ts = clock::timestamp_ms(clock);

        if( !table::contains(&self.checkpoints, vsdb)){
            let checkpoints = table_vec::empty(ctx);
            table::add(&mut self.checkpoints, vsdb, checkpoints);
        };

        let player_checkpoint = table::borrow_mut(&mut self.checkpoints, vsdb);
        let len = table_vec::length(player_checkpoint);

        if( len > 0 && checkpoints::balance_ts(table_vec::borrow(player_checkpoint, len - 1)) == ts){
            let cp_mut = table_vec::borrow_mut(player_checkpoint, len - 1 );
            checkpoints::update_balance(cp_mut, balance);
        }else{
            let checkpoint = checkpoints::new_cp(ts, balance);
            table_vec::push_back(player_checkpoint, checkpoint);
        };
    }

    fun write_reward_per_token_checkpoint_<X, Y, T>(
        reward: &mut Reward<X, Y, T>,
        reward_per_token: u64,
        timestamp: u64,
    ){
        let rp_s = &mut reward.reward_per_token_checkpoints;
        let len = table_vec::length(rp_s);
        if(len > 0 && checkpoints::reward_ts(table_vec::borrow(rp_s, len - 1)) == timestamp){
            let rp = table_vec::borrow_mut(rp_s, len - 1);
            checkpoints::update_reward(rp, reward_per_token);
        }else{
            table_vec::push_back(rp_s, checkpoints::new_rp(timestamp, reward_per_token));
        };
    }

    fun write_supply_checkpoint_<X,Y>(
        self: &mut InternalBribe<X,Y>,
        clock: &Clock,
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
    fun update_reward_per_token_<X,Y,T>(
        self: &mut InternalBribe<X,Y>,
        max_run:u64, // useful when tx might be out of gas
        actual_last: bool,
        clock: &Clock,
    ):(u64, u64) // ( reward_per_token_stored, last_update_time)
    {
        // only check internal bribe
        assert_generic_type<X,Y,T>();

        let ts = clock::timestamp_ms(clock);
        let reward = borrow_reward<X,Y,T>(self);
        let start_timestamp = reward.last_update_time;
        let reward_token_stored = reward.reward_per_token_stored;

        // no voting received
        if(table_vec::length(&self.supply_checkpoints) == 0){
            return ( reward_token_stored, start_timestamp )
        };

        // no bribing
        if(reward.reward_rate == 0){
            return ( reward_token_stored, ts )
        };

        let start_idx = get_prior_supply_index(self, start_timestamp);
        let end_idx = math::min(table_vec::length(&self.supply_checkpoints) - 1, max_run);

        if(end_idx > 0){
            let i = start_idx;
            while(i <= end_idx - 1){
                let sp_0_ts = checkpoints::supply_ts(table_vec::borrow(&self.supply_checkpoints, i));
                let sp_0_supply = checkpoints::supply(table_vec::borrow(&self.supply_checkpoints, i));
                if(sp_0_supply > 0){
                    let sp_1_ts = checkpoints::supply_ts(table_vec::borrow(&self.supply_checkpoints, i + 1));
                    let reward = borrow_reward_mut<X,Y,T>(self);
                    let (reward_per_token ,end_time) = calc_reward_per_token(reward, sp_1_ts, sp_0_ts, sp_0_supply, start_timestamp);
                    reward_token_stored = reward_token_stored + reward_per_token;
                    write_reward_per_token_checkpoint_(reward, reward_token_stored, end_time);
                    start_timestamp = end_time;
                };
                i = i + 1;
            }
        };

        if(actual_last){
            let sp_supply = checkpoints::supply(table_vec::borrow(&self.supply_checkpoints, end_idx));
            let sp_ts = checkpoints::supply_ts(table_vec::borrow(&self.supply_checkpoints, end_idx));
            if(sp_supply > 0){
                let reward = borrow_reward<X,Y,T>(self);
                let ( reward_per_token, _ ) = calc_reward_per_token(reward, last_time_reward_applicable(reward, clock), math::max(sp_ts, start_timestamp), sp_supply, start_timestamp);
                reward_token_stored = reward_token_stored + reward_per_token;
                let reward = borrow_reward_mut<X,Y,T>(self);
                write_reward_per_token_checkpoint_(reward, reward_token_stored, ts);
                start_timestamp = ts;
            };
        };

        return ( reward_token_stored, start_timestamp )
    }

    /// allows a voter to claim reward for a given bribe
    public (friend) fun get_reward<X, Y, T>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &VSDB,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert_generic_type<X,Y,T>();

        let id = object::id(vsdb);
        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token_<X,Y,T>(self, MAX_U64, true, clock);

        let _reward = earned<X,Y,T>(self, vsdb, clock);

        let reward = borrow_reward_mut<X,Y,T>(self);
        reward.reward_per_token_stored = reward_per_token_stored;
        reward.last_update_time = last_update_time;

        *table::borrow_mut(&mut reward.last_earn, id) = clock::timestamp_ms(clock);
        *table::borrow_mut(&mut reward.user_reward_per_token_stored, id) = reward_per_token_stored;

        if(_reward > 0){
            let coin_x = coin::take(&mut reward.balance, _reward, ctx);
            let value_x = coin::value(&coin_x);
            transfer::public_transfer(
                coin_x,
                tx_context::sender(ctx)
            );
            event::claim_reward(tx_context::sender(ctx), value_x);
        }
    }

    //// [voter]: receive votintg
    public (friend) fun deposit<X,Y>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &VSDB,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        // update all the rewards in bribes
        update_reward_per_token_<X,Y,X>(self, MAX_U64, true, clock);
        update_reward_per_token_<X,Y,Y>(self, MAX_U64, true, clock);

        self.total_supply = self.total_supply + amount;
        *table::borrow_mut(&mut self.balace_of, object::id(vsdb)) = *table::borrow(& self.balace_of, object::id(vsdb)) + amount;

        write_checkpoint_(self, vsdb, amount, clock, ctx);
        write_supply_checkpoint_(self, clock);
    }

    //// [voter]: abstain votintg
    public (friend) fun withdraw<X,Y>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &VSDB,
        amount: u64, // should be u256
        clock: &Clock,
        ctx: &mut TxContext
    ){
        update_reward_per_token_<X,Y,X>(self, MAX_U64, true, clock);
        update_reward_per_token_<X,Y,Y>(self, MAX_U64, true, clock);

        self.total_supply = self.total_supply - amount;
        *table::borrow_mut(&mut self.balace_of, object::id(vsdb)) = *table::borrow(& self.balace_of, object::id(vsdb)) - amount;

        write_checkpoint_(self, vsdb, amount, clock, ctx);
        write_supply_checkpoint_(self, clock);
    }

    /// collect fees from pool
    public fun notify_reward_amount<X,Y,T>(
        self: &mut InternalBribe<X,Y>,
        coin: Coin<T>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert_generic_type<X,Y,T>();

        let value = coin::value(&coin);
        let reward = borrow_reward<X,Y,T>(self);
        assert!(value > 0, err::empty_coin());

        let ts = clock::timestamp_ms(clock);
        if(reward.reward_rate == 0){
            write_reward_per_token_checkpoint_(borrow_reward_mut<X,Y,T>(self), 0, ts);
        };

        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token_<X,Y,T>(self, MAX_U64, true, clock);

        let reward = borrow_reward_mut<X,Y,T>(self);
        reward.reward_per_token_stored = reward_per_token_stored;
        reward.last_update_time = last_update_time;

        // initial bribe in each duration ( 7days )
        if(ts >= reward.period_finish){
            coin::put(&mut reward.balance, coin);
            reward.reward_rate = value / DURATION;
        }else{
        // accumulate bribes in each eopch
            let _remaining = reward.period_finish - ts;
            let _left = _remaining * reward.reward_rate;
            assert!(value > _left, err::insufficient_bribes());
            coin::put(&mut reward.balance, coin);
            reward.reward_rate = ( value + _left ) / DURATION;
        };

        assert!(reward.reward_rate > 0,  err::invalid_reward_rate());
        assert!(reward.reward_rate <= balance::value(& reward.balance) / DURATION, err::max_reward());

        reward.period_finish = ts + DURATION;

        event::notify_reward<X>(tx_context::sender(ctx), value);
    }
}