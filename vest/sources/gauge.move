// Gauges are used to incentivize pools, they emit reward tokens over 7 days for staked LP tokens
module suiDouBashiVest::gauge{
    use std::type_name::{Self, TypeName};
    use std::option;
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::dynamic_object_field as dof;
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::clock::{Self, Clock};
    use sui::math;
    use std::vector as vec;
    use sui::vec_set::{Self, VecSet};
    use std::ascii::String;
    use sui::table::{ Self, Table};
    use sui::table_vec::{Self};

    use suiDouBashiVest::vsdb::{Self, VSDB};
    use suiDouBashiVest::event;
    use suiDouBashiVest::err;
    use suiDouBashiVest::reward::{Self, Reward};
    use suiDouBashiVest::checkpoints::{Self, SupplyCheckpoint, Checkpoint};
    use suiDouBashiVest::internal_bribe::{Self, InternalBribe};
    use suiDouBashiVest::external_bribe::{Self};

    use suiDouBashi::pool::{Self, Pool, LP_Position};

    const DURATION: u64 = { 7 * 86400 };
    const PRECISION: u64 = 1_000_000_000_000_000_000;
    const MAX_REWARD_TOKENS: u64 = 16;
    const MAX_U64: u64 = 18446744073709551615_u64;

    friend suiDouBashiVest::voter;

    struct Gauge<phantom X, phantom Y> has key, store{
        id: UID,
        is_alive:bool,

        bribes: vector<ID>,//[ Internal, External ]
        pool: ID,

        rewards: VecSet<String>,

        total_supply: LP_Position<X,Y>,

        balance_of: Table<ID, u64>,

        token_ids: Table<address, ID>, // each player cna only stake once for each pool

        is_for_pair: bool,

        fees_x: Balance<X>,
        fees_y: Balance<Y>,

        supply_checkpoints: Table<u64, SupplyCheckpoint>,

        checkpoints: Table<ID, Table<u64, Checkpoint>>,

        // voting, distributing, fee
        supply_index: u64,
        claimable: u64
    }

    public (friend) fun create_reward<X,Y,T>(self: &mut Gauge<X,Y>, ctx: &mut TxContext){
        assert_generic_type<X,Y,T>();

        let type_name = type_name::get<T>();
        let reward =  reward::new<X,Y,T>(ctx);

        dof::add(&mut self.id, type_name, reward);
    }

    public fun borrow_reward<X,Y,T>(self: &Gauge<X,Y>):&Reward<X, Y, T>{
        let type_name = type_name::get<T>();
        assert_reward_created<X,Y,T>(self, type_name);
        dof::borrow(&self.id, type_name)
    }

    fun borrow_reward_mut<X,Y,T>(self: &mut Gauge<X,Y>):&mut Reward<X, Y, T>{
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

    public fun assert_reward_created<X,Y,T>(self: &Gauge<X,Y>, type_name: TypeName){
        assert!(dof::exists_(&self.id, type_name), err::reward_not_exist());
    }

    public fun assert_alive<X,Y>(self: &Gauge<X,Y>){
        assert!(self.is_alive, err::dead_gauge());
    }

    public (friend) fun new<X,Y>(
        pool: &Pool<X,Y>,
        ctx: &mut TxContext
    ):(Gauge<X,Y>, ID, ID){
        let internal_id = internal_bribe::create_bribe(pool, ctx);
        let external_id = external_bribe::create_bribe(pool, ctx);

        let bribes = vec::singleton(internal_id);
        vec::push_back(&mut bribes, external_id);

        let id = object::new(ctx);
        let id_ads = object::uid_to_address(&id);
        let gauge = Gauge<X,Y>{
            id,

            is_alive: true,

            bribes,
            pool: object::id(pool),

            rewards: vec_set::empty<String>(),

            total_supply: pool::create_lp_position(pool, id_ads, ctx), // no owner
            balance_of: table::new<ID, u64>(ctx),

            token_ids: table::new<address, ID>(ctx),

            is_for_pair: false,

            fees_x: balance::zero<X>(),
            fees_y: balance::zero<Y>(),

            supply_checkpoints: table::new<u64, SupplyCheckpoint>(ctx),

            checkpoints: table::new<ID, Table<u64, Checkpoint>>(ctx), // voting weights for each voter

            supply_index: 0,
            claimable: 0
        };

        create_reward<X,Y,X>(&mut gauge, ctx);
        create_reward<X,Y,Y>(&mut gauge, ctx);

        (gauge, internal_id, external_id)
    }


    // ===== Getter =====
    public fun is_alive<X,Y>(self: &Gauge<X,Y>):bool{ self.is_alive }

    public fun pool_id<X,Y>(self: &Gauge<X,Y>):ID{ self.pool }
    public fun get_supply_index<X,Y>(self: &Gauge<X,Y>):u64{ self.supply_index }
    public fun get_claimable<X,Y>(self: &Gauge<X,Y>):u64{ self.claimable }

    public (friend) fun update_supply_index<X,Y>(self: &mut Gauge<X,Y>, v: u64){ self.supply_index = v; }
    public (friend) fun update_claimable<X,Y>(self: &mut Gauge<X,Y>, v: u64){ self.claimable = v; }


    public fun get_prior_balance_index<X,Y>(
        self: & Gauge<X,Y>,
        vsdb: &VSDB,
        ts:u64
    ):u64 {
        let checkpoints = table::borrow(&self.checkpoints, object::id(vsdb));
        let len = table::length(checkpoints);

        if( len == 0){
            return 0
        };

        if(!table::contains(&self.checkpoints, object::id(vsdb))){
            return 0
        };

        if( checkpoints::balance_ts(table::borrow(checkpoints, len - 1)) <= ts ){
            return len - 1
        };

        if( checkpoints::balance_ts(table::borrow(checkpoints, 0)) > ts){
            return 0
        };

        let lower = 0;
        let upper = len - 1;
        while ( lower < upper){
            let center = upper - (upper - lower) / 2;
            let cp_ts = checkpoints::balance_ts(table::borrow(checkpoints, center));
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
        self: & Gauge<X,Y>,
        ts:u64
    ):u64 {
        let len = table::length(&self.supply_checkpoints);

        if( len == 0){
            return 0
        };

        if( checkpoints::supply_ts(table::borrow(&self.supply_checkpoints, len - 1)) <= ts ){
            return len - 1
        };

        if( checkpoints::supply_ts(table::borrow(&self.supply_checkpoints, 0)) > ts){
            return 0
        };

        let lower = 0;
        let upper = len - 1;
        while ( lower < upper){
            let center = upper - (upper - lower) / 2;
            let sp_ts = checkpoints::supply_ts(table::borrow(&self.supply_checkpoints, center));
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

    public fun last_time_reward_applicable<X, Y, T>(reward: &Reward<X, Y, T>, clock: &Clock):u64{
        math::min(clock::timestamp_ms(clock), reward::period_finish(reward))
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
        let reward =  (math::min(end_time, reward::period_finish(reward)) - math::min(math::max(timestamp_0, start_timestamp), reward::period_finish(reward))) * reward::reward_rate(reward) * PRECISION / supply ;

        return ( reward, end_time )
    }

    fun get_reward_per_token<X, Y, T>(
        self: &Gauge<X,Y>,
        clock: &Clock
    ): u64{
        let reward = borrow_reward<X,Y,T>(self);
        let reward_stored = reward::reward_per_token_stored(reward);
        let total_supply = pool::get_lp_balance(&self.total_supply);
        // no accumualated voting
        if(total_supply == 0){
            return reward_stored
        };

        let last_update = reward::last_update_time(reward);
        let period_finish = reward::period_finish(reward);
        let reward_rate = reward::reward_rate(reward);

        return  reward_stored + (last_time_reward_applicable(reward, clock) - math::min(last_update, period_finish)) * reward_rate * PRECISION / total_supply
    }

     fun earned<X,Y,T>(
        self: &Gauge<X,Y>,
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
        let end_idx = table::length(bps_borrow) - 1;
        let earned_reward = 0;

        // accumulate rewards in each reward checkpoints derived from balance checkpoints
        if(end_idx > 0){
            let i = start_idx;
            while( i <= end_idx - 1){ // leave last one
                let cp_0 = table::borrow(bps_borrow, i);
                let cp_1 = table::borrow(bps_borrow, i + 1);
                let ( _, reward_per_token_0) = get_prior_reward_per_token(reward, checkpoints::balance_ts(cp_0));
                let ( _, reward_per_token_1 ) = get_prior_reward_per_token(reward, checkpoints::balance_ts(cp_1));
                earned_reward =  earned_reward +  checkpoints::balance(cp_0) *  ( reward_per_token_1 - reward_per_token_0) / PRECISION;
                i = i + 1;
            }
        };

        let cp = table::borrow(bps_borrow, end_idx);
        let ( _, reward_per_token ) = get_prior_reward_per_token(reward, checkpoints::balance_ts(cp));

        // HOw ?
        earned_reward = earned_reward + checkpoints::balance(cp) * (get_reward_per_token<X,Y,T>(self, clock) - math::max(reward_per_token, reward::user_reward_per_token_stored(reward, id))) / PRECISION;

        return earned_reward
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

    // ===== Setter =====
    public (friend) fun kill_gauge_<X,Y>(self: &mut Gauge<X,Y> ){ self.is_alive = false }
    public (friend) fun revive_gauge_<X,Y>(self: &mut Gauge<X,Y>){ self.is_alive = true }

    fun write_checkpoint<X,Y>(
        self: &mut Gauge<X,Y>,
        vsdb: &VSDB,
        balance: u64, // record down balance
        clock: &Clock,
        ctx: &mut TxContext
    ){
        let vsdb = object::id(vsdb);
        let timestamp = clock::timestamp_ms(clock);

        // create table for new registry
        if( !table::contains(&self.checkpoints, vsdb)){
            let checkpoints = table::new(ctx);
            table::add(&mut self.checkpoints, vsdb, checkpoints);
        };

        let player_checkpoint = table::borrow_mut(&mut self.checkpoints, vsdb);
        let len = table::length(player_checkpoint);

        if( len > 0 && checkpoints::balance_ts(table::borrow(player_checkpoint, len - 1)) == timestamp){
            let cp_mut = table::borrow_mut(player_checkpoint, len - 1 );
            checkpoints::update_balance(cp_mut, balance);
        }else{
            let checkpoint = checkpoints::new_cp(timestamp, balance);
            table::add(player_checkpoint, len, checkpoint);
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
        self: &mut Gauge<X,Y>,
        clock: &Clock,
        //ctx: &mut TxContext
    ){
        let timestamp = clock::timestamp_ms(clock);
        let supply = pool::get_lp_balance(&self.total_supply);

        let len = table::length(&self.supply_checkpoints);

        if( len > 0 && checkpoints::supply_ts(table::borrow(&self.supply_checkpoints, len - 1)) == timestamp){
            let cp_mut = table::borrow_mut(&mut self.supply_checkpoints, len - 1 );
            checkpoints::update_supply(cp_mut, supply)
        }else{
            let checkpoint = checkpoints::new_sp(timestamp, supply);
            table::add(&mut self.supply_checkpoints, len, checkpoint);
        };
    }

    /// require when
    /// 1. reward claims,
    /// 2. deposit ( votes )
    /// 3. withdraw ( revoke )
    /// 4. distribute
    /// update both global & plyaer state repsecitvley
    fun update_reward_per_token<X,Y,T>(
        self: &mut Gauge<X,Y>,
        max_run:u64,
        actual_last: bool,
        clock: &Clock
    ):(u64, u64) // ( reward_per_token_stored, last_update_time)
    {
        assert_generic_type<X,Y,T>();

        let start_timestamp = reward::last_update_time(borrow_reward<X,Y,T>(self));
        let reward_ = reward::reward_per_token_stored(borrow_reward<X,Y,T>(self));

        if(table::length(&self.supply_checkpoints) == 0){
            return ( reward_, start_timestamp )
        };

        if(reward::reward_rate(borrow_reward<X,Y,T>(self)) == 0){
            return ( reward_, clock::timestamp_ms(clock))
        };

        let start_idx = get_prior_supply_index(self, start_timestamp);
        let end_idx = math::min(table::length(&self.supply_checkpoints) - 1, max_run);

        // update reward_per_token_checkpoints
        if(end_idx > 0){
            let i = start_idx;
            while( i <= end_idx - 1){
                let sp_0_ts = checkpoints::supply_ts(table::borrow(&self.supply_checkpoints, i));
                let sp_0_supply = checkpoints::supply(table::borrow(&self.supply_checkpoints, i));
                if(sp_0_supply > 0){
                    let ts = checkpoints::supply_ts(table::borrow(&self.supply_checkpoints, i + 1));
                    let reward = borrow_reward_mut<X,Y,T>(self);
                    let ( reward_per_token , end_time) = calc_reward_per_token(reward, ts, sp_0_ts, sp_0_supply, start_timestamp);
                    reward_ = reward_ + reward_per_token;
                    write_reward_per_token_checkpoint(reward, reward_, end_time);
                    start_timestamp = end_time;
                };
                i = i + 1;
            }
        };

        if(actual_last){
            let sp_supply = checkpoints::supply(table::borrow(&self.supply_checkpoints, end_idx));
            let sp_ts = checkpoints::supply_ts(table::borrow(&self.supply_checkpoints, end_idx));
            if(sp_supply > 0){
                let reward = borrow_reward_mut<X,Y,T>(self);
                let last_time_reward = last_time_reward_applicable(reward, clock);
                let ( reward_per_token, _ ) = calc_reward_per_token(reward, last_time_reward, math::max(sp_ts, start_timestamp), sp_supply, start_timestamp);
                reward_ = reward_ + reward_per_token;
                let reward = borrow_reward_mut<X,Y,T>(self);
                write_reward_per_token_checkpoint(reward, reward_, clock::timestamp_ms(clock));
                start_timestamp = clock::timestamp_ms(clock);
            };
        };

        return ( reward_, start_timestamp )
    }

    public (friend) fun get_reward<X, Y, T>(
        self: &mut Gauge<X,Y>,
        vsdb: &VSDB,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert_generic_type<X,Y,T>();

        let id = object::id(vsdb);
        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token<X,Y,T>(self, MAX_U64, true, clock);

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

    /// Stake LP_TOKEN
    fun deposit<X,Y,T>(
        self: &mut Gauge<X,Y>,
        pool: &Pool<X,Y>,
        vsdb: &mut VSDB,
        lp_position: &mut LP_Position<X,Y>, // borrow_mut or take ?
        value: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert_generic_type<X,Y,T>();

        let id = object::id(vsdb);
        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token<X,Y,T>(self, MAX_U64, true, clock);

        let reward = borrow_reward_mut<X,Y,T>(self);
        reward::update_reward_per_token_stored(reward, reward_per_token_stored);
        reward::update_last_update_time(reward, last_update_time);

        pool::top_up_claim_lp_balance(pool, &mut self.total_supply, lp_position, value );

        let lp_value = pool::get_lp_balance(lp_position);

        *table::borrow_mut(&mut self.balance_of, object::id(vsdb)) = *table::borrow(& self.balance_of, object::id(vsdb)) + lp_value;

        //TODO: attach token to gauge, and move assertion in the front of respective functions
        // each address can only register once for each pool
        let sender = tx_context::sender(ctx);
        assert!(vsdb::owner(vsdb) == sender, err::invalid_owner());
        if(!table::contains(&self.token_ids, sender)){
            table::add(&mut self.token_ids, sender, id);
            // attahc
            vsdb::attach<X,Y>(vsdb, ctx);
        };
        assert!(table::borrow(&self.token_ids, sender) == &id, err::already_stake());
        //voter::attachTokenToGauge() // move to voter

        write_checkpoint(self, vsdb, lp_value, clock, ctx);
        write_supply_checkpoint(self, clock);

        event::deposit_lp<X,Y>(tx_context::sender(ctx), id, lp_value);
    }

    // unstake
    fun withdraw_<X,Y,T>(
        self: &mut Gauge<X,Y>,
        pool: &Pool<X,Y>,
        vsdb: &mut VSDB,
        value: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ):LP_Position<X,Y>{
        assert_generic_type<X,Y,T>();

        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token<X,Y,T>(self, MAX_U64, true, clock);
        let id = object::id(vsdb);

        let reward = borrow_reward_mut<X,Y,T>(self);
        reward::update_reward_per_token_stored(reward, reward_per_token_stored);
        reward::update_last_update_time(reward, last_update_time);

        // unstake the LP from pool
        let lp_position = pool::create_lp_position(pool, tx_context::sender(ctx), ctx);

        pool::top_up_claim_lp_balance(pool, &mut lp_position, &mut self.total_supply, value);
        let lp_value = pool::get_lp_balance(&lp_position);

        // record check
        *table::borrow_mut(&mut self.balance_of, id) = *table::borrow(&self.balance_of, id) - lp_value;

        // detach & validation
        let sender = tx_context::sender(ctx);
        assert!(vsdb::owner(vsdb) == sender, err::invalid_owner());

        let id = table::remove(&mut self.token_ids, sender);
        // detach
        vsdb::detach<X,Y>(vsdb, ctx);

        assert!(table::borrow(&self.token_ids, sender) == &id, err::already_stake());

        write_checkpoint(self, vsdb, lp_value, clock, ctx);
        write_supply_checkpoint(self, clock);

        event::withdraw_lp<X,Y>(tx_context::sender(ctx), id, lp_value);

        lp_position
    }

    // TODO: whitelist check
    /// distribute the weekly rebase amonut
    public fun notify_reward_amount<X,Y,T>(
        self: &mut Gauge<X,Y>,
        bribe: &mut InternalBribe<X,Y>,
        pool: &mut Pool<X,Y>,
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

        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token<X,Y,T>(self, MAX_U64, true, clock);

        reward::update_reward_per_token_stored(borrow_reward_mut<X,Y,T>(self), reward_per_token_stored);
        reward::update_last_update_time(borrow_reward_mut<X,Y,T>(self), last_update_time);

        // Charge fees when
        claim_fee(self, bribe, pool, clock, ctx);

        let reward = borrow_reward_mut<X,Y,T>(self);
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

        assert!(reward::reward_rate(reward) > 0, err::invalid_reward_rate());
        let bal_total = reward::balance(reward);
        assert!( reward::reward_rate(reward) <= bal_total / DURATION, err::max_reward());

        reward::update_period_finish(reward, ts + DURATION);

        event::notify_reward<X>(tx_context::sender(ctx), value);
    }


    // ===== Other =====
    /// Collect the fees from Pool, then deposit into internal bribe
    public (friend) fun claim_fee<X,Y>(
        self: &mut Gauge<X,Y>,
        bribe: &mut InternalBribe<X,Y>,
        pool: &mut Pool<X,Y>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        // assert pair exists
        let (coin_x, coin_y) = pool::claim_fees_gauge(pool, &mut self.total_supply, ctx);
        let value_x = if(option::is_some(&coin_x)){
            let coin_x = option::extract(&mut coin_x);
            let value_x = coin::value(&coin_x);
            coin::put(&mut self.fees_x, coin_x);
            value_x
        }else{
            0
        };
        let value_y = if(option::is_some(&coin_y)){
            let coin_y = option::extract(&mut coin_y);
            let value_y = coin::value(&coin_y);
            coin::put(&mut self.fees_y, coin_y);
            value_y
        }else{
            0
        };
        option::destroy_none(coin_x);
        option::destroy_none(coin_y);

        if(value_x > 0 || value_y > 0){
            let bal_x = balance::value(&self.fees_x);
            let bal_y = balance::value(&self.fees_y);

            // why checking left
            if(bal_x > internal_bribe::left(internal_bribe::borrow_reward<X,Y,X>(bribe),clock) && bal_x / DURATION > 0  ){
                let withdraw = balance::withdraw_all(&mut self.fees_x);
                internal_bribe::notify_reward_amount(bribe, coin::from_balance(withdraw, ctx), clock, ctx);
            };

            if(bal_y > internal_bribe::left(internal_bribe::borrow_reward<X,Y,Y>(bribe),clock) && bal_y / DURATION > 0  ){
                let withdraw = balance::withdraw_all(&mut self.fees_y);
                internal_bribe::notify_reward_amount(bribe, coin::from_balance(withdraw, ctx), clock, ctx);
            }
        };

        event::claim_fees(tx_context::sender(ctx), value_x, value_y);
    }
}
