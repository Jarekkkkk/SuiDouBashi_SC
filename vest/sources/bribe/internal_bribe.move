// Internal Bribes represent pool fee distributed to LP holders
module suiDouBashiVest::internal_bribe{
    use std::type_name;
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::clock::{Self, Clock};
    use sui::math;
    use sui::table::{Self, Table};
    use sui::table_vec::{Self, TableVec};
    use sui::object_bag::{Self as ob, ObjectBag};
    use std::vector as vec;

    use suiDouBashi::pool::Pool;
    use suiDouBashiVest::vsdb::VSDB;
    use suiDouBashiVest::event;
    use suiDouBashiVest::err;
    use suiDouBashiVest::reward::{Self, Reward};
    use suiDouBashiVest::checkpoints::{Self, SupplyCheckpoint, Checkpoint};

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

        checkpoints: Table<ID, vector<Checkpoint>>, // VSDB -> balance checkpoint

        rewards: ObjectBag //TypeName<T> -> Reward<T>,
    }

    // - Reward
    fun create_reward<X,Y,T>(self: &mut InternalBribe<X,Y>, ctx: &mut TxContext){
        assert_generic_type<X,Y,T>();
        ob::add(&mut self.rewards, type_name::get<T>(), reward::new<X,Y,T>(ctx));
    }
    public fun borrow_reward<X,Y,T>(self: &InternalBribe<X,Y>):&Reward<X, Y, T>{
        let type_name = type_name::get<T>();
        assert!(ob::contains(&self.rewards, type_name), err::reward_not_exist());
        ob::borrow(&self.rewards, type_name)
    }
    fun borrow_reward_mut<X,Y,T>(self: &mut InternalBribe<X,Y>):&mut Reward<X, Y, T>{
        let type_name = type_name::get<T>();
        assert!(ob::contains(&self.rewards, type_name), err::reward_not_exist());
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
    // being calling by voter, when creating guage
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

            checkpoints: table::new<ID, vector<Checkpoint>>(ctx), // voting weights for each voter,
            rewards: ob::new(ctx)
        };
        let id = object::id(&bribe);

        // pair fees
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
        let id = object::id(vsdb);
        if( !table::contains(&self.checkpoints, id)) return 0;

        let checkpoints = table::borrow(&self.checkpoints, id);
        let len = vec::length(checkpoints);

        if( len == 0){
            return 0
        };

        if(!table::contains(&self.checkpoints, id)){
            return 0
        };

        if( checkpoints::balance_ts(vec::borrow(checkpoints, len - 1)) <= ts ){
            return len - 1
        };

        if( checkpoints::balance_ts(vec::borrow(checkpoints, 0)) > ts){
            return 0
        };

        let lower = 0;
        let upper = len - 1;
        while ( lower < upper){
            let center = upper - (upper - lower) / 2;
            let cp_ts = checkpoints::balance_ts(vec::borrow(checkpoints, center));
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

    public fun get_prior_reward_per_token<X, Y, T>(
        reward: &Reward<X, Y, T>,
        ts:u64
    ):(u64, u64) // ( ts, reward_per_token )
    {
        assert_generic_type<X,Y,T>();
        let checkpoints = reward::reward_per_token_checkpoints_borrow(reward);
        let len = table_vec::length(checkpoints);

        if( len == 0){
            return ( 0, 0 )
        };

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

     fun write_checkpoint_<X,Y>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &VSDB,
        balance: u64, // record down balance
        clock: &Clock,
    ){
        let vsdb = object::id(vsdb);
        let ts = clock::timestamp_ms(clock);

        if( !table::contains(&self.checkpoints, vsdb)){
            let checkpoints = vec::empty();
            table::add(&mut self.checkpoints, vsdb, checkpoints);
        };

        let player_checkpoint = table::borrow_mut(&mut self.checkpoints, vsdb);
        let len = vec::length(player_checkpoint);

        if( len > 0 && checkpoints::balance_ts(vec::borrow(player_checkpoint, len - 1)) == ts){
            let cp_mut = vec::borrow_mut(player_checkpoint, len - 1 );
            checkpoints::update_balance(cp_mut, balance);
        }else{
            let checkpoint = checkpoints::new_cp(ts, balance);
            vec::push_back(player_checkpoint, checkpoint);
        };
    }

    fun write_reward_per_token_checkpoint_<X, Y, T>(
        reward: &mut Reward<X, Y, T>,
        reward_per_token: u64, // record down balance
        timestamp: u64,
    ){
        let rp_s = reward::reward_per_token_checkpoints_borrow_mut(reward);
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
        let ts = clock::timestamp_ms(clock);
        let supply = self.total_supply;

        let len = table_vec::length(&self.supply_checkpoints);

        if( len > 0 && checkpoints::supply_ts(table_vec::borrow(&self.supply_checkpoints, len - 1)) == ts){
            let sp = table_vec::borrow_mut(&mut self.supply_checkpoints, len - 1 );
            checkpoints::update_supply(sp, supply)
        }else{
            let checkpoint = checkpoints::new_sp(ts, supply);
            table_vec::push_back(&mut self.supply_checkpoints, checkpoint);
        };
    }

    ///  returns the last time the reward was modified or periodFinish if the reward has ended
    public fun last_time_reward_applicable<X, Y, T>(reward: &Reward<X, Y, T>, clock: &Clock):u64{
        // Two scenarios
        // 1. return current time if latest fun  is deposited in 7 days
        // 2  return period_finish bribe has been abandoned over 7 days
        math::min(clock::timestamp_ms(clock), reward::period_finish(reward))
    }

    /// allows a voter to claim reward for a given bribe
    /// T as argument ( must be pair of coin types )
    public entry fun get_all_rewards<X,Y>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &VSDB,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        get_reward<X,Y,X>(self, vsdb, clock, ctx);
        get_reward<X,Y,Y>(self, vsdb, clock, ctx);
    }
    public entry fun get_reward<X, Y, T>(
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
        // global state
        reward::update_reward_per_token_stored(reward, reward_per_token_stored);
        reward::update_last_update_time(reward, last_update_time);

        // voter state
        reward::update_user_reward_per_token_stored(reward, id, reward_per_token_stored);
        reward::update_last_earn(reward, id, clock::timestamp_ms(clock));


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

    /// each pro rata coin distribution with total voting supply
    fun reward_per_token<X, Y, T>(
        self: &InternalBribe<X,Y>,
        clock: &Clock
    ): u64{
        let reward = borrow_reward<X,Y,T>(self);
        let reward_stored = reward::reward_per_token_stored(reward);

        // no accumualated voting
        if(self.total_supply == 0){
            return reward_stored
        };

        // TODO: merge all in function to save gas
        let last_update = reward::last_update_time(reward);
        let period_finish = reward::period_finish(reward);
        let reward_rate = reward::reward_rate(reward);
        let elapsed = ((last_time_reward_applicable(reward, clock) - math::min(last_update, period_finish)) as u256);
        return reward_stored + (elapsed * (reward_rate as u256) * PRECISION / (self.total_supply as u256) as u64)
    }

    fun batch_reward_per_token<X,Y,T>(
        self: &mut InternalBribe<X,Y>,
        max_run:u64, // useful when tx might be out of gas
        clock: &Clock,
    ):(u64, u64) // ( reward_per_token_stored, last_update_time)
    {
        assert_generic_type<X,Y,T>();

        let ts = clock::timestamp_ms(clock);
        let reward = borrow_reward<X,Y,T>(self);
        let start_timestamp = reward::last_update_time(reward);
        let reward_token_stored = reward::reward_per_token_stored(reward);

        // no voting received
        if(table_vec::length(&self.supply_checkpoints) == 0){
            return ( reward_token_stored, start_timestamp )
        };

        // no bribing
        if(reward::reward_rate(reward) == 0){
            return ( reward_token_stored, ts )
        };

        let start_idx = get_prior_supply_index(self, start_timestamp);
        let end_idx = math::min(table_vec::length(&self.supply_checkpoints) - 1, max_run);

        let i = start_idx;
        while(i < end_idx){
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
        };

        return ( reward_token_stored, start_timestamp )
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
        let reward =  ((math::min(end_time, reward::period_finish(reward)) - math::min(start_time, reward::period_finish(reward))) as u256) * (reward::reward_rate(reward) as u256) * PRECISION / (supply as u256) ;

        ((reward as u64), end_time)
    }

    public entry fun batch_update_reward_per_token<X,Y,T>(
        self: &mut InternalBribe<X,Y>,
        max_run:u64,
        clock: &Clock,
    ){
        update_reward_per_token_<X,Y,T>(self, max_run, false, clock);
    }

    fun update_reward_for_all_tokens_<X,Y>(
        self: &mut InternalBribe<X,Y>,
        clock: &Clock,
    ){
        update_reward_per_token_<X,Y,X>(self, MAX_U64, true, clock);
        update_reward_per_token_<X,Y,Y>(self, MAX_U64, true, clock);
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
        assert_generic_type<X,Y,T>();

        let ts = clock::timestamp_ms(clock);
        let reward = borrow_reward<X,Y,T>(self);
        let start_timestamp = reward::last_update_time(reward);
        let reward_token_stored = reward::reward_per_token_stored(reward);

        // no voting received
        if(table_vec::length(&self.supply_checkpoints) == 0){
            return ( reward_token_stored, start_timestamp )
        };

        // no bribing
        if(reward::reward_rate(reward) == 0){
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
                write_reward_per_token_checkpoint_(borrow_reward_mut<X,Y,T>(self), reward_token_stored, ts);
                start_timestamp = ts;
            };
        };

        return ( reward_token_stored, start_timestamp )
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
        // checking balance checkpoint for individual checkpoint is enough, since we empty table_vec is not allowed to exist
        if(!reward::last_earn_contain(reward, id) || !table::contains(&self.checkpoints, id) || table_vec::length(rps_borrow) == 0 ){
            return 0
        };

        let start_timestamp = math::max(reward::last_earn(reward, id), checkpoints::reward_ts(table_vec::borrow(rps_borrow, 0)));

        let bps_borrow = table::borrow(&self.checkpoints, id);

        let start_idx = get_prior_balance_index(self, vsdb, start_timestamp);
        let end_idx = vec::length(bps_borrow) - 1;
        let earned_reward = 0;

        // accumulate rewards in each reward checkpoints derived from balance checkpoints
        if(end_idx > 0){
            let i = start_idx;
            while( i <= end_idx - 1){ // leave last one
                let cp_0 = vec::borrow(bps_borrow, i);
                let cp_1 = vec::borrow(bps_borrow, i + 1);
                let (_, reward_per_token_0) = get_prior_reward_per_token(reward, checkpoints::balance_ts(cp_0));
                let (_, reward_per_token_1) = get_prior_reward_per_token(reward, checkpoints::balance_ts(cp_1));
                let acc = (checkpoints::balance(cp_0) as u256) * ((reward_per_token_1 - reward_per_token_0) as u256) / PRECISION;
                earned_reward = earned_reward + (acc as u64);
                i = i + 1;
            }
        };

        let cp = vec::borrow(bps_borrow, end_idx);
        let ( _, perior_reward ) = get_prior_reward_per_token(reward, checkpoints::balance_ts(cp));

        // current slope
        let acc = (checkpoints::balance(cp) as u256) * ((reward_per_token<X,Y,T>(self, clock) - math::max(perior_reward, reward::user_reward_per_token_stored(reward, id))) as u256) / PRECISION;
        earned_reward = earned_reward + (acc as u64);

        return earned_reward
    }

    //// [voter]: receive votintg
    public (friend) fun deposit<X,Y>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &VSDB,
        amount: u64,
        clock: &Clock,
        _ctx: &mut TxContext
    ){
        let id = object::id(vsdb);
        update_reward_for_all_tokens_(self, clock);

        self.total_supply = self.total_supply + amount;

        if(table::contains(&self.balace_of, id)){
            *table::borrow_mut(&mut self.balace_of, id) = *table::borrow(& self.balace_of, id) + amount;
        }else{
            table::add(&mut self.balace_of, id, amount);
        };

        write_checkpoint_(self, vsdb, amount, clock);
        write_supply_checkpoint_(self, clock);
    }

    //// [voter]: abstain votintg
    public (friend) fun withdraw<X,Y>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &VSDB,
        amount: u64, // should be u256
        clock: &Clock,
        _ctx: &mut TxContext
    ){
        update_reward_for_all_tokens_(self, clock);

        let id = object::id(vsdb);
        assert!(table::contains(&self.balace_of, id), err::invalid_voter());
        assert!(self.total_supply >= amount, err::insufficient_voting());
        self.total_supply = self.total_supply - amount;
        *table::borrow_mut(&mut self.balace_of, id) = *table::borrow(& self.balace_of, id) - amount;

        write_checkpoint_(self, vsdb, amount, clock);
        write_supply_checkpoint_(self, clock);
    }

    public fun left<X, Y, T>(reward: &Reward<X, Y, T>, clock: &Clock):u64{
        let ts = clock::timestamp_ms(clock);
        let period_finish = reward::period_finish(reward);
        let reward_rate = reward::reward_rate(reward);

        // no one bribing
        if(ts >= period_finish) return 0;

        let _remaining = period_finish - ts;
        return _remaining * reward_rate
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
        if(reward::reward_rate(reward) == 0){
            write_reward_per_token_checkpoint_(borrow_reward_mut<X,Y,T>(self), 0, ts);
        };

        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token_<X,Y,T>(self, MAX_U64, true, clock);
        let reward = borrow_reward_mut<X,Y,T>(self);
        reward::update_reward_per_token_stored(reward, reward_per_token_stored);
        reward::update_last_update_time(reward, last_update_time);

        // initial bribe in each duration ( 7 days )
        if(ts >= reward::period_finish(reward)){
            coin::put(reward::balance_mut(reward), coin);
            reward::update_reward_rate(reward, value / DURATION);
        }else{
        // accumulate bribes in each eopch
            let _remaining = reward::period_finish(reward) - ts;
            let _left = _remaining * reward::reward_rate(reward);
            assert!(value > _left, err::insufficient_bribes());
            coin::put(reward::balance_mut(reward), coin);
            reward::update_reward_rate(reward, ( value + _left ) / DURATION);
        };

        assert!(reward::reward_rate(reward) > 0,  err::invalid_reward_rate());
        assert!(reward::reward_rate(reward) <= reward::balance(reward) / DURATION, err::max_reward());

        reward::update_period_finish(reward, ts + DURATION);

        event::notify_reward<X>(tx_context::sender(ctx), value);
    }
}