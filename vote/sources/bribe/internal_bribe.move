module suiDouBashi_vote::internal_bribe{
    use std::type_name;
    use std::vector as vec;

    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::table::{Self, Table};
    use sui::table_vec::{Self, TableVec};
    use sui::balance::{Self, Balance};
    use sui::dynamic_field as df;
    use sui::math;
    use sui::clock::{Self, Clock};

    use suiDouBashi_amm::amm_math;
    use suiDouBashi_vsdb::vsdb::{Self, Vsdb};
    use suiDouBashi_vote::minter::package_version;
    use suiDouBashi_vote::event;
    use suiDouBashi_vote::checkpoints::{Self, SupplyCheckpoint, BalanceCheckpoint, RewardPerTokenCheckpoint};

    friend suiDouBashi_vote::gauge;
    friend suiDouBashi_vote::voter;

    // ====== Constants =======

    const DURATION: u64 = { 7 * 86400 };
    const PRECISION: u256 = 1_000_000_000_000_000_000;
    const MAX_U64: u64 = 18446744073709551615_u64;

    // ====== Constants =======

    // ====== Error =======

    const E_WRONG_VERSION: u64 = 001;
    const E_INVALID_TYPE: u64 = 100;
    const E_INVALID_VOTER: u64 = 100;
    const E_INSUFFICIENT_VOTES: u64 = 100;
    const E_EMPTY_VALUE: u64 = 100;
    const E_INSUFFICENT_BRIBES: u64 = 105;
    const E_INVALID_REWARD_RATE: u64 = 106;
    const E_MAX_REWARD: u64 = 107;

    // ====== Error =======

    /// Internal Bribe, responsible for collecting votes from Vsdb Holder and returning the internal bribes ( pool tx fees ) to the VSDB holder who votes fot the pool
    struct InternalBribe<phantom X, phantom Y> has key, store{
        id: UID,
        /// package version
        version: u64,
        /// total votes the internal_bribe collects
        total_votes: u64,
        /// total votes point history, updated when someone cast/ revoke their votes
        supply_checkpoints: TableVec<SupplyCheckpoint>,
        /// casted polls of each Vsdb
        vsdb_votes: Table<ID, u64>,
        /// voting history, updated when someone vote/ revoke their votes
        vote_bp: Table<ID, vector<BalanceCheckpoint>>,
    }

    public fun total_votes<X,Y>(self: &InternalBribe<X,Y>): u64{ self.total_votes }

    public fun vsdb_votes<X,Y>(self: &InternalBribe<X,Y>, vsdb: &Vsdb): u64{
        *table::borrow(&self.vsdb_votes, object::id(vsdb))
    }

    /// Rewards for Internal Bribe, there are 2 rewards object for each internal_bribes object managing the pool tx fees in pair of coins
    struct Reward<phantom X, phantom Y, phantom T> has store{
        /// total balance of stored rewards<T>
        balance: Balance<T>,
        /// estimated earned reward per second in current epoch ( rewards/ 7 days )
        reward_rate: u64,
        /// the finished period for each rewards, each rewards can stay at most 7 days
        period_finish: u64,
        /// last time when `vsdb casted/ revoked`, `reward deposited/ withdrew in`
        last_update_time: u64,
        /// accumulating index of rewards_per_token
        reward_per_token_stored: u256,
        /// checkpoints of rewards. updated when `vsdb votes`, `reward comes in` or `vsdb claim the rewards`
        reward_per_token_checkpoints: TableVec<RewardPerTokenCheckpoint>,
        /// reward_per_token index of each vsdb
        player_reward_per_token_stored: Table<ID, u256>,
        /// last time VSDB claim the rewards
        last_earn: Table<ID, u64>,
    }

    public fun borrow_reward<X,Y,T>(self: &InternalBribe<X,Y>):&Reward<X, Y, T>{
        assert_generic_type<X,Y,T>();
        df::borrow(&self.id, type_name::get<T>())
    }

    /// Private function, to protect mutable reference
    fun borrow_reward_mut<X,Y, T>(self: &mut InternalBribe<X,Y>):&mut Reward<X, Y, T>{
        assert_generic_type<X,Y,T>();
        df::borrow_mut(&mut self.id, type_name::get<T>())
    }

    public fun reward_balance<X,Y,T>(self: &InternalBribe<X,Y>): u64{
        balance::value(&borrow_reward<X,Y,T>(self).balance)
    }

    // ===== Assertion =====

    public fun assert_generic_type<X,Y,T>(){
        let type_t = type_name::get<T>();
        assert!( type_t == type_name::get<X>() || type_t == type_name::get<Y>(), E_INVALID_TYPE);
    }

    // ===== Assertion =====

    public (friend )fun new<X,Y>( ctx: &mut TxContext ):ID {
        let bribe = InternalBribe<X,Y>{
            id: object::new(ctx),
            version: package_version(),
            total_votes:0,
            supply_checkpoints: table_vec::empty<SupplyCheckpoint>(ctx),
            vsdb_votes: table::new<ID, u64>(ctx),
            vote_bp: table::new<ID, vector<BalanceCheckpoint>>(ctx),
        };
        let id = object::id(&bribe);

        let reward_x = Reward<X,Y,X>{
            balance: balance::zero<X>(),
            reward_rate: 0,
            period_finish: 0,
            last_update_time: 0,
            reward_per_token_stored: 0,
            reward_per_token_checkpoints: table_vec::empty<RewardPerTokenCheckpoint>(ctx),
            player_reward_per_token_stored: table::new<ID, u256>(ctx),
            last_earn: table::new<ID, u64>(ctx),
        };
        let reward_y = Reward<X,Y,Y>{
            balance: balance::zero<Y>(),
            reward_rate: 0,
            period_finish: 0,
            last_update_time: 0,
            reward_per_token_stored: 0,
            reward_per_token_checkpoints: table_vec::empty<RewardPerTokenCheckpoint>(ctx),
            player_reward_per_token_stored: table::new<ID, u256>(ctx),
            last_earn: table::new<ID, u64>(ctx),
        };

        df::add(&mut bribe.id, type_name::get<X>(), reward_x);
        df::add(&mut bribe.id, type_name::get<Y>(), reward_y);

        transfer::share_object(bribe);

        id
    }

    // ====== GETTER ======

    public fun get_prior_balance_index<X,Y>(
        self: & InternalBribe<X,Y>,
        vsdb: &Vsdb,
        ts:u64
    ):u64 {
        let id = object::id(vsdb);
        if( !table::contains(&self.vote_bp, id)) return 0;

        let bps = table::borrow(&self.vote_bp, id);
        let len = vec::length(bps);

        if( len == 0){
            return 0
        };

        if( checkpoints::balance_ts(vec::borrow(bps, len - 1)) <= ts ){
            return len - 1
        };

        if( checkpoints::balance_ts(vec::borrow(bps, 0)) > ts){
            return 0
        };

        let lower = 0;
        let upper = len - 1;
        let _center = 0;
        let _bp_ts = 0;
        while ( lower < upper){
            _center = upper - (upper - lower) / 2;
            _bp_ts = checkpoints::balance_ts(vec::borrow(bps, _center));
            if(_bp_ts == ts ){
                return _center
            }else if (_bp_ts < ts){
                lower = _center;
            }else{
                upper = _center - 1 ;
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
        let _center = 0;
        let _sp_ts = 0;
        while ( lower < upper){
            _center = upper - (upper - lower) / 2;
            _sp_ts = checkpoints::supply_ts(table_vec::borrow(&self.supply_checkpoints, _center));
            if( _sp_ts == ts ){
                return _center
            }else if ( _sp_ts < ts){
                lower = _center;
            }else{
                upper = _center - 1 ;
            }
        };
        return lower
    }

    public fun get_prior_reward_per_token<X,Y,T>(
        reward: &Reward<X, Y, T>,
        ts:u64
    ):(u64, u256) // ( ts, reward_per_token )
    {
        assert_generic_type<X,Y,T>();

        let rps = &reward.reward_per_token_checkpoints;
        let len = table_vec::length(rps);

        if( len == 0){
            return ( 0, 0 )
        };

        if( checkpoints::reward_ts(table_vec::borrow(rps, len - 1)) <= ts ){
            let rp = table_vec::borrow(rps, len - 1);
            return ( checkpoints::reward_ts(rp), checkpoints::reward(rp))
        };

        if( checkpoints::reward_ts(table_vec::borrow(rps, 0)) > ts){
            return ( 0, 0 )
        };

        let lower = 0;
        let upper = len - 1;
        let _center = 0;
        let rp = table_vec::borrow(rps, _center);
        let _rp_ts = checkpoints::reward_ts(rp);
        while (lower < upper){
            _center = upper - (upper - lower) / 2;
            rp = table_vec::borrow(rps, _center);
            _rp_ts = checkpoints::reward_ts(rp);

            if(_rp_ts == ts){
                return (_rp_ts, checkpoints::reward(rp) )
            }else if (_rp_ts < ts){
                lower = _center;
            }else{
                upper = _center - 1 ;
            }
        };
        rp = table_vec::borrow(rps, lower);
        return ( checkpoints::reward_ts(rp), checkpoints::reward(rp))
    }

    public fun earned<X,Y,T>(
        self: &InternalBribe<X,Y>,
        vsdb: &Vsdb,
        clock: &Clock
    ):u64{
        assert_generic_type<X,Y,T>();

        let reward = borrow_reward<X,Y,T>(self);
        let rps = &reward.reward_per_token_checkpoints;
        let id = object::id(vsdb);
        if( !table::contains(&self.vote_bp, id) || table_vec::length(rps) == 0 ){
            return 0
        };
        let last_earn = if(table::contains(&reward.last_earn, id)){
            *table::borrow(&reward.last_earn, id)
        }else{
            0
        };

        let bps = table::borrow(&self.vote_bp, id);

        let start_idx = get_prior_balance_index(self, vsdb, math::max(last_earn, checkpoints::reward_ts(table_vec::borrow(rps, 0))));
        let end_idx = vec::length(bps) - 1;

        let earned_reward = 0;
        if(end_idx > 0){
            let i = start_idx;
            while( i <= end_idx - 1){
                let cp_0 = vec::borrow(bps, i);
                let cp_1 = vec::borrow(bps, i + 1);
                let (_, reward_per_token_0) = get_prior_reward_per_token(reward, checkpoints::balance_ts(cp_0));
                let (_, reward_per_token_1) = get_prior_reward_per_token(reward, checkpoints::balance_ts(cp_1));
                earned_reward = earned_reward + ((checkpoints::balance(cp_0) as u256) * ((reward_per_token_1 - reward_per_token_0) as u256) / PRECISION as u64);
                i = i + 1;
            }
        };

        let bp = vec::borrow(bps, end_idx);
        // last time voted
        let ( _,perior_reward ) = get_prior_reward_per_token(reward, checkpoints::balance_ts(bp));

        // current slope
        let player_reward_per_token_stored = if(table::contains(&reward.player_reward_per_token_stored, id)){
            *table::borrow(&reward.player_reward_per_token_stored, id)
        }else{
            0
        };

        // stop accumulating rewards after vsdb expires
        let ( _,final_reward ) = get_prior_reward_per_token(reward, vsdb::locked_end(vsdb));

        let acc = ((checkpoints::balance(bp) as u256) * (amm_math::min_u256(reward_per_token<X,Y,T>(self, clock), final_reward) - amm_math::max_u256(perior_reward, player_reward_per_token_stored)))/ PRECISION;
        earned_reward = earned_reward + (acc as u64);

        return earned_reward
    }

    // ====== GETTER ======


    // ====== ENTRY ======

    public entry fun batch_reward_per_token<X,Y,T>(
        self: &mut InternalBribe<X,Y>,
        max_run:u64,
        clock: &Clock
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        let ( reward_per_token_stored, last_update_time ) = batch_reward_per_token_<X,Y,Y>(self, max_run, clock);
        let reward = borrow_reward_mut<X,Y,Y>(self);
        reward.reward_per_token_stored = reward_per_token_stored;
        reward.last_update_time = last_update_time;
    }

    public entry fun batch_update_reward_per_token<X,Y,T>(
        self: &mut InternalBribe<X,Y>,
        max_run:u64,
        clock: &Clock
    ){
        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token_<X,Y,T>(self, max_run, false, clock);
        let reward = borrow_reward_mut<X,Y,X>(self);
        reward.reward_per_token_stored = reward_per_token_stored;
        reward.last_update_time = last_update_time;
    }

    public (friend) fun deposit<X,Y>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &Vsdb,
        amount: u64,
        clock: &Clock
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        assert!(amount > 0, E_EMPTY_VALUE);

        let id = object::id(vsdb);
        update_reward_for_all_tokens_(self, clock);

        self.total_votes = self.total_votes + amount;

        if(table::contains(&self.vsdb_votes, id)){
            *table::borrow_mut(&mut self.vsdb_votes, id) = *table::borrow(&self.vsdb_votes, id) + amount;
        }else{
            table::add(&mut self.vsdb_votes, id, amount);
        };

        amount = *table::borrow(&self.vsdb_votes, id);
        write_checkpoint_(self, vsdb, amount, clock);
        write_supply_checkpoint_(self, clock);
    }

    public (friend) fun withdraw<X,Y>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &Vsdb,
        amount: u64,
        clock: &Clock
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        assert!(amount > 0, E_EMPTY_VALUE);

        update_reward_for_all_tokens_(self, clock);

        let id = object::id(vsdb);
        assert!(table::contains(&self.vsdb_votes, id), E_INVALID_VOTER);

        let supply = self.total_votes;
        let balance = *table::borrow(& self.vsdb_votes, id);
        assert!(supply >= amount && balance >= amount, E_INSUFFICIENT_VOTES);
        self.total_votes = supply - amount;
        *table::borrow_mut(&mut self.vsdb_votes, id) = balance - amount;

        amount = *table::borrow(&self.vsdb_votes, id);
        write_checkpoint_(self, vsdb, amount, clock);
        write_supply_checkpoint_(self, clock);
    }

    public entry fun deposit_pool_fees<X,Y,T>(
        self: &mut InternalBribe<X,Y>,
        coin: Coin<T>,
        clock: &Clock,
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        assert_generic_type<X,Y,T>();

        let value = coin::value(&coin);
        let reward = borrow_reward<X,Y,T>(self);
        assert!(value > 0, E_EMPTY_VALUE);

        let ts = unix_timestamp(clock);
        if(reward.reward_rate == 0){
            // gensis rewards checkpoint
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

        event::notify_reward<X>(value);
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

    public entry fun get_reward<X,Y,T>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &Vsdb,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        assert_generic_type<X,Y,T>();

        let id = object::id(vsdb);

        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token_<X,Y,T>(self, MAX_U64, true, clock);
        {
            let reward = borrow_reward_mut<X,Y,T>(self);
            reward.reward_per_token_stored = reward_per_token_stored;
            reward.last_update_time = last_update_time;
        };

        let earned = earned<X,Y,T>(self, vsdb, clock);

        let reward = borrow_reward_mut<X,Y,T>(self);
        if(!table::contains(&reward.last_earn, id)){
            table::add(&mut reward.last_earn, id, 0);
        };
        if(!table::contains(&reward.player_reward_per_token_stored, id)){
            table::add(&mut reward.player_reward_per_token_stored, id, 0);
        };
        *table::borrow_mut(&mut reward.last_earn, id) = unix_timestamp(clock);
        *table::borrow_mut(&mut reward.player_reward_per_token_stored, id) = reward_per_token_stored;

        if(earned > 0){
            let coin_x = coin::take(&mut reward.balance, earned, ctx);
            let value_x = coin::value(&coin_x);
            transfer::public_transfer(
                coin_x,
                tx_context::sender(ctx)
            );
            event::claim_reward(tx_context::sender(ctx), value_x);
        }
    }

    // ====== ENTRY ======



    // ====== UTILS ======

    fun unix_timestamp(clock: &Clock):u64 { clock::timestamp_ms(clock) / 1000 }

    public fun left<X,Y,T>(reward: &Reward<X,Y,T>, clock: &Clock):u64{
        let ts = unix_timestamp(clock);

        if(ts >= reward.period_finish) return 0;

        return ( reward.period_finish - ts ) * reward.reward_rate
    }

    public fun last_time_reward_applicable<X,Y,T>(reward: &Reward<X,Y,T>, clock: &Clock): u64{
        math::min(unix_timestamp(clock), reward.period_finish)
    }

    /// Calculate the reward_per_token by 2 given checkpoints ts
    public fun calc_reward_per_token<X,Y,T>(
        reward: &Reward<X, Y, T>,
        ts_1: u64,
        ts_0: u64,
        supply: u64,
        start_ts: u64
    ):(u256, u64){
        let end_time = math::max(ts_1, start_ts);
        let start_time = math::max(ts_0, start_ts);
        let reward_per_token =  ((math::min(end_time, reward.period_finish) - math::min(start_time, reward.period_finish)) as u256) * (reward.reward_rate as u256) * PRECISION / (supply as u256);
        (reward_per_token, end_time)
    }

    public fun reward_per_token<X,Y,T>(
        self: &InternalBribe<X,Y>,
        clock: &Clock
    ): u256{
        let reward = borrow_reward<X,Y,T>(self);
        let reward_stored = reward.reward_per_token_stored;

        if(self.total_votes == 0){
            return reward_stored
        };
        let elapsed = ((last_time_reward_applicable(reward, clock) - math::min(reward.last_update_time, reward.period_finish)) as u256);

        return reward_stored + elapsed * (reward.reward_rate as u256) * PRECISION / (self.total_votes as u256)
    }

    // ====== UTILS ======

    // ====== LOGIC ======

    fun write_checkpoint_<X,Y>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &Vsdb,
        balance: u64,
        clock: &Clock
    ){
        let id = object::id(vsdb);
        let ts = unix_timestamp(clock);

        if(!table::contains(&self.vote_bp, id)){
            table::add(&mut self.vote_bp, id, vec::empty());
        };

        let bps = table::borrow_mut(&mut self.vote_bp, id);
        let len = vec::length(bps);

        if( len > 0 && checkpoints::balance_ts(vec::borrow(bps, len - 1)) == ts){
            checkpoints::update_balance(vec::borrow_mut(bps, len - 1 ), balance);
        }else{
            vec::push_back(bps, checkpoints::new_cp(ts, balance));
        };
    }

    fun write_supply_checkpoint_<X,Y>(
        self: &mut InternalBribe<X,Y>,
        clock: &Clock,
    ){
        let ts = unix_timestamp(clock);

        let len = table_vec::length(&self.supply_checkpoints);

        if( len > 0 && checkpoints::supply_ts(table_vec::borrow(&self.supply_checkpoints, len - 1)) == ts){
            checkpoints::update_supply(table_vec::borrow_mut(&mut self.supply_checkpoints, len - 1 ), self.total_votes);
        }else{
            table_vec::push_back(&mut self.supply_checkpoints, checkpoints::new_sp(ts, self.total_votes));
        };
    }

    fun write_reward_per_token_checkpoint_<X, Y, T>(
        reward: &mut Reward<X, Y, T>,
        reward_per_token: u256,
        ts: u64,
    ){
        let rps = &mut reward.reward_per_token_checkpoints;
        let len = table_vec::length(rps);
        if(len > 0 && checkpoints::reward_ts(table_vec::borrow(rps, len - 1)) == ts){
            checkpoints::update_reward(table_vec::borrow_mut(rps, len - 1), reward_per_token);
        }else{
            table_vec::push_back(rps, checkpoints::new_rp(ts, reward_per_token));
        };
    }

    fun update_reward_for_all_tokens_<X,Y>(
        self: &mut InternalBribe<X,Y>,
        clock: &Clock,
    ){
        // reward_x
        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token_<X,Y,X>(self, MAX_U64, true, clock);
        let reward = borrow_reward_mut<X,Y,X>(self);
        reward.reward_per_token_stored = reward_per_token_stored;
        reward.last_update_time = last_update_time;
        // reward_y
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

        let ts = unix_timestamp(clock);
        let reward = borrow_reward<X,Y,T>(self);
        let start_timestamp = reward.last_update_time;
        let reward_token_stored = reward.reward_per_token_stored;

        // no any votes
        if(table_vec::length(&self.supply_checkpoints) == 0){
            return ( reward_token_stored, start_timestamp )
        };

        // no any rewards
        if(reward.reward_rate == 0){
            return ( reward_token_stored, ts )
        };

        let start_idx = get_prior_supply_index(self, start_timestamp);
        let end_idx = math::min(table_vec::length(&self.supply_checkpoints) - 1, max_run);

        // update obsolete reward checkpoints
        if(end_idx > 0){
            let i = start_idx;
            while(i <= end_idx - 1){
                let sp_0_ts = checkpoints::supply_ts(table_vec::borrow(&self.supply_checkpoints, i));
                let sp_0_supply = checkpoints::supply(table_vec::borrow(&self.supply_checkpoints, i));
                if(sp_0_supply > 0){
                    let sp_1_ts = checkpoints::supply_ts(table_vec::borrow(&self.supply_checkpoints, i + 1));
                    let reward = borrow_reward_mut<X,Y,T>(self);
                    let (reward_per_token, end_time) = calc_reward_per_token(reward, sp_1_ts, sp_0_ts, sp_0_supply, start_timestamp);
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

    fun batch_reward_per_token_<X,Y,T>(
        self: &mut InternalBribe<X,Y>,
        max_run:u64, // useful when tx might be out of gas
        clock: &Clock,
    ):(u256, u64) // ( reward_per_token_stored, last_update_time)
    {
        assert_generic_type<X,Y,T>();

        let ts = unix_timestamp(clock);
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
                let (reward_per_token, end_time) = calc_reward_per_token(reward, sp_1_ts, sp_0_ts, sp_0_supply, start_timestamp);
                reward_token_stored = reward_token_stored + reward_per_token;
                write_reward_per_token_checkpoint_(reward, reward_token_stored, end_time);
                start_timestamp = end_time;
            };
            i = i + 1;
        };

        return ( reward_token_stored, start_timestamp )
    }
}