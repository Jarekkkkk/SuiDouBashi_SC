// Internal Bribes represent pool fee distributed to LP stakers
module suiDouBashi_vest::internal_bribe{
    use std::type_name;
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::clock::{Self, Clock};
    use sui::table::{Self, Table};
    use sui::table_vec::{Self, TableVec};
    use std::vector as vec;
    use sui::balance::{Self, Balance};

    use sui::dynamic_field as df;
    use sui::math;

    use suiDouBashi_amm::amm_math;
    use suiDouBashi_vsdb::vsdb::Vsdb;

    use suiDouBashi_vest::minter::package_version;
    use suiDouBashi_vest::event;
    use suiDouBashi_vest::checkpoints::{Self, SupplyCheckpoint, Checkpoint, RewardPerTokenCheckpoint};

    friend suiDouBashi_vest::gauge;
    friend suiDouBashi_vest::voter;

    const DURATION: u64 = { 7 * 86400 };
    const PRECISION: u256 = 1_000_000_000_000_000_000;
    const MAX_U64: u64 = 18446744073709551615_u64;

    const E_WRONG_VERSION: u64 = 001;
    const E_INVALID_TYPE: u64 = 100;
    const E_INVALID_VOTER: u64 = 100;
    const E_INSUFFICIENT_VOTES: u64 = 100;
    const E_EMPTY_VALUE: u64 = 100;
    const E_INSUFFICENT_BRIBES: u64 = 105;
    const E_INVALID_REWARD_RATE: u64 = 106;
    const E_MAX_REWARD: u64 = 107;

    struct InternalBribe<phantom X, phantom Y> has key, store{
        id: UID,
        version: u64,
        total_supply: u64,
        balance_of: Table<ID, u64>,
        supply_checkpoints: TableVec<SupplyCheckpoint>,
        checkpoints: Table<ID, vector<Checkpoint>>, // Vsdb -> voting balance checkpoint
    }

    public fun total_voting_weight<X,Y>(self: &InternalBribe<X,Y>):u64{ self.total_supply }
    public fun get_balance_of<X,Y>(self: &InternalBribe<X,Y>, vsdb: &Vsdb):u64 {
        *table::borrow(&self.balance_of, object::id(vsdb))
    }

    struct Reward<phantom X, phantom Y, phantom T> has store{
        balance: Balance<T>,
        reward_rate: u64, // bribe_amount/ 7 days
        period_finish: u64,
        last_update_time: u64, // update when someone 1.voting/ 2.reset/ 3.withdraw bribe/ 4. deposite bribe
        reward_per_token_stored: u256,

        user_reward_per_token_stored: Table<ID, u256>,

        reward_per_token_checkpoints: TableVec<RewardPerTokenCheckpoint>,
        last_earn: Table<ID, u64>,
    }

    public fun borrow_reward<X,Y,T>(self: &InternalBribe<X,Y>):&Reward<X, Y, T>{
        assert_generic_type<X,Y,T>();
        df::borrow(&self.id, type_name::get<T>())
    }
    fun borrow_reward_mut<X,Y, T>(self: &mut InternalBribe<X,Y>):&mut Reward<X, Y, T>{
        assert_generic_type<X,Y,T>();
        df::borrow_mut(&mut self.id, type_name::get<T>())
    }

    #[test_only]
    public fun get_reward_rate<X,Y,T>(reward: &Reward<X,Y,T>):u64 { reward.reward_rate }
    #[test_only]
    public fun get_period_finish<X,Y,T>(reward: &Reward<X,Y,T>): u64{ reward.period_finish }

    public fun get_reward_balance<X,Y,T>(self: &InternalBribe<X,Y>): u64 {
        let reward = borrow_reward<X,Y,T>(self);
        balance::value(&reward.balance)
    }

    // ===== Assertion =====
    public fun assert_generic_type<X,Y,T>(){
        let type_t = type_name::get<T>();
        assert!( type_t == type_name::get<X>() || type_t == type_name::get<Y>(), E_INVALID_TYPE);
    }

    public (friend )fun create_bribe<X,Y>(
        ctx: &mut TxContext
    ):ID {
        let bribe = InternalBribe<X,Y>{
            id: object::new(ctx),
            version: package_version(),
            total_supply:0,
            balance_of: table::new<ID, u64>(ctx),
            supply_checkpoints: table_vec::empty<SupplyCheckpoint>(ctx),
            checkpoints: table::new<ID, vector<Checkpoint>>(ctx),
        };
        let id = object::id(&bribe);

        let reward_x = Reward<X,Y,X>{
            balance: balance::zero<X>(),
            reward_rate: 0,
            period_finish: 0,
            last_update_time: 0,
            reward_per_token_stored: 0,
            reward_per_token_checkpoints: table_vec::empty<RewardPerTokenCheckpoint>(ctx),

            user_reward_per_token_stored: table::new<ID, u256>(ctx),
            last_earn: table::new<ID, u64>(ctx),
        };
        let reward_y = Reward<X,Y,Y>{
            balance: balance::zero<Y>(),
            reward_rate: 0,
            period_finish: 0,
            last_update_time: 0,
            reward_per_token_stored: 0,
            reward_per_token_checkpoints: table_vec::empty<RewardPerTokenCheckpoint>(ctx),

            user_reward_per_token_stored: table::new<ID, u256>(ctx),
            last_earn: table::new<ID, u64>(ctx),
        };

        df::add(&mut bribe.id, type_name::get<X>(), reward_x);
        df::add(&mut bribe.id, type_name::get<Y>(), reward_y);

        transfer::share_object(bribe);

        id
    }

    public fun get_prior_balance_index<X,Y>(
        self: & InternalBribe<X,Y>,
        vsdb: &Vsdb,
        ts:u64
    ):u64 {
        let id = object::id(vsdb);
        if( !table::contains(&self.checkpoints, id)) return 0;

        let checkpoints = table::borrow(&self.checkpoints, id);
        let len = vec::length(checkpoints);

        if( len == 0){
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
    ):(u64, u256) // ( ts, reward_per_token )
    {
        assert_generic_type<X,Y,T>();
        let checkpoints = &reward.reward_per_token_checkpoints;
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
        vsdb: &Vsdb,
        balance: u64,
        clock: &Clock,
    ){
        let vsdb = object::id(vsdb);
        let ts = clock::timestamp_ms(clock) / 1000;

        if(!table::contains(&self.checkpoints, vsdb)){
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
        reward_per_token: u256,
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
        let ts = clock::timestamp_ms(clock) / 1000;
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
        // 1. return current time if the latest deposited is in 7 days
        // 2  return period_finish when bribe has been abandoned over 7 days
        math::min(clock::timestamp_ms(clock) / 1000, reward.period_finish)
    }

    /// allows a voter to claim reward for a internal bribe ( pool_fees )
    public entry fun get_all_rewards<X,Y>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &Vsdb,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        get_reward<X,Y,X>(self, vsdb, clock, ctx);
        get_reward<X,Y,Y>(self, vsdb, clock, ctx);
    }
    public entry fun get_reward<X, Y, T>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &Vsdb,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        assert_generic_type<X,Y,T>();

        let id = object::id(vsdb);

        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token_<X,Y,T>(self, MAX_U64, true, clock);
        let _reward = earned<X,Y,T>(self, vsdb, clock);

        let reward = borrow_reward_mut<X,Y,T>(self);
        if(!table::contains(&reward.last_earn, id)){
            table::add(&mut reward.last_earn, id, 0);
        };
        if(!table::contains(&reward.user_reward_per_token_stored, id)){
            table::add(&mut reward.user_reward_per_token_stored, id, 0);
        };

        let reward = borrow_reward_mut<X,Y,T>(self);
        reward.reward_per_token_stored = reward_per_token_stored;
        reward.last_update_time = last_update_time;

        *table::borrow_mut(&mut reward.last_earn, id) = clock::timestamp_ms(clock) / 1000;
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

    public fun reward_per_token<X, Y, T>(
        self: &InternalBribe<X,Y>,
        clock: &Clock
    ): u256{
        let reward = borrow_reward<X,Y,T>(self);
        let reward_stored = reward.reward_per_token_stored;

        if(self.total_supply == 0){
            return reward_stored
        };
        let elapsed = ((last_time_reward_applicable(reward, clock) - math::min(reward.last_update_time, reward.period_finish)) as u256);
        return reward_stored + elapsed * (reward.reward_rate as u256) * PRECISION / (self.total_supply as u256)
    }

    /// update obsolete reward per token data
    public entry fun batch_reward_per_token<X,Y,T>(
        self: &mut InternalBribe<X,Y>,
        max_run:u64,
        clock: &Clock,
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        let ( reward_per_token_stored, last_update_time ) = batch_reward_per_token_<X,Y,Y>(self, max_run, clock);
        let reward = borrow_reward_mut<X,Y,Y>(self);
        reward.reward_per_token_stored = reward_per_token_stored;
        reward.last_update_time = last_update_time;
    }

    fun batch_reward_per_token_<X,Y,T>(
        self: &mut InternalBribe<X,Y>,
        max_run:u64, // useful when tx might be out of gas
        clock: &Clock,
    ):(u256, u64) // ( reward_per_token_stored, last_update_time)
    {
        assert_generic_type<X,Y,T>();

        let ts = clock::timestamp_ms(clock) / 1000;
        let reward = borrow_reward<X,Y,T>(self);
        let start_timestamp = reward.last_update_time;
        let reward_token_stored = reward.reward_per_token_stored;

        if(table_vec::length(&self.supply_checkpoints) == 0){
            return ( reward_token_stored, start_timestamp )
        };

        if(reward.reward_rate == 0){
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

    fun calc_reward_per_token<X, Y, T>(
        reward: &Reward<X, Y, T>,
        timestamp_1: u64,
        timestamp_0: u64,
        supply: u64,
        start_timestamp: u64
    ):(u256, u64){
        let end_time = math::max(timestamp_1, start_timestamp);
        let start_time = math::max(timestamp_0, start_timestamp);
        let reward =  ((math::min(end_time, reward.period_finish) - math::min(start_time, reward.period_finish)) as u256) * (reward.reward_rate as u256) * PRECISION / (supply as u256) ;
        (reward, end_time)
    }

    public entry fun batch_update_reward_per_token<X,Y,T>(
        self: &mut InternalBribe<X,Y>,
        max_run:u64,
        clock: &Clock,
    ){
        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token_<X,Y,T>(self, max_run, false, clock);
        let reward = borrow_reward_mut<X,Y,X>(self);
        reward.reward_per_token_stored = reward_per_token_stored;
        reward.last_update_time = last_update_time;
    }

    fun update_reward_for_all_tokens_<X,Y>(
        self: &mut InternalBribe<X,Y>,
        clock: &Clock,
    ){
        // reward_y
        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token_<X,Y,X>(self, MAX_U64, true, clock);
        let reward = borrow_reward_mut<X,Y,X>(self);
        reward.reward_per_token_stored = reward_per_token_stored;
        reward.last_update_time = last_update_time;
        // reward_x
        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token_<X,Y,Y>(self, MAX_U64, true, clock);
        let reward = borrow_reward_mut<X,Y,Y>(self);
        reward.reward_per_token_stored = reward_per_token_stored;
        reward.last_update_time = last_update_time;
    }

    fun update_reward_per_token_<X,Y,T>(
        self: &mut InternalBribe<X,Y>,
        max_run:u64, // useful when tx might be out of gas
        actual_last: bool,
        clock: &Clock,
    ):(u256, u64) // ( reward_per_token_stored, last_update_time)
    {
        assert_generic_type<X,Y,T>();

        let ts = clock::timestamp_ms(clock) / 1000;
        let reward = borrow_reward<X,Y,T>(self);
        let start_timestamp = reward.last_update_time;
        let reward_token_stored = reward.reward_per_token_stored;

        if(table_vec::length(&self.supply_checkpoints) == 0){
            return ( reward_token_stored, start_timestamp )
        };

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
                write_reward_per_token_checkpoint_(borrow_reward_mut<X,Y,T>(self), reward_token_stored, ts);
                start_timestamp = ts;
            };
        };
        return ( reward_token_stored, start_timestamp )
    }

    public fun earned<X,Y,T>(
        self: &InternalBribe<X,Y>,
        vsdb: &Vsdb,
        clock: &Clock
    ):u64{
        assert_generic_type<X,Y,T>();

        let reward = borrow_reward<X,Y,T>(self);
        let rps_borrow = &reward.reward_per_token_checkpoints;
        let id = object::id(vsdb);
        if( !table::contains(&self.checkpoints, id) || table_vec::length(rps_borrow) == 0 ){
            return 0
        };
        let last_earn = if(table::contains(&reward.last_earn, id)){
            *table::borrow(&reward.last_earn, id)
        }else{
            0
        };
        let start_timestamp = math::max(last_earn, checkpoints::reward_ts(table_vec::borrow(rps_borrow, 0)));

        let bps_borrow = table::borrow(&self.checkpoints, id);

        let start_idx = get_prior_balance_index(self, vsdb, start_timestamp);
        let end_idx = vec::length(bps_borrow) - 1;
        let earned_reward = 0;

        // accumulate rewards in each reward checkpoints
        if(end_idx > 0){
            let i = start_idx;
            while( i <= end_idx - 1){
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
        let user_reward_per_token_stored = if(table::contains(&reward.user_reward_per_token_stored, id)){
            *table::borrow(&reward.user_reward_per_token_stored, id)
        }else{
            0
        };
        let acc = (checkpoints::balance(cp) as u256) * ((reward_per_token<X,Y,T>(self, clock) - amm_math::max_u256(perior_reward, user_reward_per_token_stored)) as u256) / PRECISION;
        earned_reward = earned_reward + (acc as u64);

        return earned_reward
    }

    public (friend) fun deposit<X,Y>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &Vsdb,
        amount: u64,
        clock: &Clock,
        _ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        let id = object::id(vsdb);
        update_reward_for_all_tokens_(self, clock);

        self.total_supply = self.total_supply + amount;

        if(table::contains(&self.balance_of, id)){
            *table::borrow_mut(&mut self.balance_of, id) = *table::borrow(& self.balance_of, id) + amount;
        }else{
            table::add(&mut self.balance_of, id, amount);
        };

        write_checkpoint_(self, vsdb, amount, clock);
        write_supply_checkpoint_(self, clock);
    }

    public (friend) fun withdraw<X,Y>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &Vsdb,
        amount: u64,
        clock: &Clock,
        _ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        update_reward_for_all_tokens_(self, clock);

        let id = object::id(vsdb);
        assert!(table::contains(&self.balance_of, id), E_INVALID_VOTER);
        let supply = self.total_supply;
        let balance = *table::borrow(& self.balance_of, id);
        assert!(supply >= amount, E_INSUFFICIENT_VOTES);
        assert!(balance >= amount, E_INSUFFICIENT_VOTES);
        self.total_supply = supply - amount;
        *table::borrow_mut(&mut self.balance_of, id) = balance - amount;

        write_checkpoint_(self, vsdb, amount, clock);
        write_supply_checkpoint_(self, clock);
    }

    public fun left<X, Y, T>(reward: &Reward<X, Y, T>, clock: &Clock):u64{
        let ts = clock::timestamp_ms(clock) / 1000;

        if(ts >= reward.period_finish) return 0;

        let _remaining = reward.period_finish - ts;
        return _remaining * reward.reward_rate
    }

    public fun deposit_pool_fees<X,Y,T>(
        self: &mut InternalBribe<X,Y>,
        coin: Coin<T>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        assert_generic_type<X,Y,T>();

        let value = coin::value(&coin);
        let reward = borrow_reward<X,Y,T>(self);
        assert!(value > 0, E_EMPTY_VALUE);

        let ts = clock::timestamp_ms(clock) / 1000;
        if(reward.reward_rate == 0){
            write_reward_per_token_checkpoint_(borrow_reward_mut<X,Y,T>(self), 0, ts);
        };

        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token_<X,Y,T>(self, MAX_U64, true, clock);
        let reward = borrow_reward_mut<X,Y,T>(self);
        reward.reward_per_token_stored = reward_per_token_stored;
        reward.last_update_time = last_update_time;

        // new epoch
        if(ts >= reward.period_finish){
            coin::put(&mut reward.balance, coin);
            reward.reward_rate = value/ DURATION;
        }else{
            let _remaining = reward.period_finish - ts;
            let _left = _remaining * reward.reward_rate;
            assert!(value > _left, E_INSUFFICENT_BRIBES);
            coin::put(&mut reward.balance, coin);
            reward.reward_rate = ( value + _left ) / DURATION;
        };

        assert!(reward.reward_rate > 0, E_INVALID_REWARD_RATE);
        assert!( reward.reward_rate <= balance::value(&reward.balance) / DURATION, E_MAX_REWARD);

        reward.period_finish = ts + DURATION;

        event::notify_reward<X>(tx_context::sender(ctx), value);
    }
}