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
    use sui::table_vec::{Self, TableVec};
    use std::ascii::String;
    use sui::table::{Self, Table};

    use suiDouBashiVest::vsdb::{Self, VSDB};
    use suiDouBashiVest::event;
    use suiDouBashiVest::err;
    use suiDouBashiVest::checkpoints::{Self, SupplyCheckpoint, Checkpoint, RewardPerTokenCheckpoint};
    use suiDouBashiVest::internal_bribe::{Self, InternalBribe};
    use suiDouBashiVest::external_bribe::{Self};

    use suiDouBashi::pool::{Self, Pool, LP};

    const DURATION: u64 = { 7 * 86400 };
    const PRECISION: u256 = 1_000_000_000_000_000_000;
    const MAX_REWARD_TOKENS: u64 = 16;
    const MAX_U64: u64 = 18446744073709551615_u64;

    friend suiDouBashiVest::voter;

    struct Gauge<phantom X, phantom Y> has key, store{
        id: UID,
        is_alive:bool,

        bribes: vector<ID>,//[ Internal, External ]
        pool: ID,

        rewards: VecSet<String>,

        total_supply: LP<X,Y>,

        balance_of: Table<address, u64>,

        token_ids: Table<address, ID>, // each player cna only stake once for each pool

        is_for_pair: bool,

        fees_x: Balance<X>,
        fees_y: Balance<Y>,

        supply_checkpoints: TableVec<SupplyCheckpoint>,

        checkpoints: Table<address, TableVec<Checkpoint>>, // each address can stake only one LP

        // voting, distributing, fee
        supply_index: u64,
        claimable: u64
    }

    struct Reward<phantom X, phantom Y, phantom T> has key, store{
        id: UID,

        balance: Balance<T>,

        //update when bribe is deposited
        reward_rate: u64, // bribe_amount/ 7 days
        period_finish: u64, // update when bribe is deposited, (internal_bribe -> fee ), (external_bribe -> doverse coins)

        last_update_time: u64, // update when someone 1.voting/ 2.reset/ 3.withdraw bribe/ 4. deposite bribe
        reward_per_token_stored: u64,

        user_reward_per_token_stored: Table<address, u64>, // udpate when user deposit

        reward_per_token_checkpoints: TableVec<RewardPerTokenCheckpoint>,
        last_earn: Table<address, u64>, // last time player votes
    }

    public (friend) fun create_reward<X,Y,T>(self: &mut Gauge<X,Y>, ctx: &mut TxContext){
        assert_generic_type<X,Y,T>();

        let type_name = type_name::get<T>();
        let reward =  Reward<X,Y,T>{
            id: object::new(ctx),
            balance: balance::zero<T>(),
            reward_rate: 0,
            period_finish: 0,
            last_update_time: 0,
            reward_per_token_stored: 0,
            reward_per_token_checkpoints: table_vec::empty<RewardPerTokenCheckpoint>(ctx),

            user_reward_per_token_stored: table::new<address, u64>(ctx),
            last_earn: table::new<address, u64>(ctx),
        };

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

            total_supply: pool::create_lp(pool, id_ads, ctx), // no owner
            balance_of: table::new<address, u64>(ctx),

            token_ids: table::new<address, ID>(ctx),

            is_for_pair: false,

            fees_x: balance::zero<X>(),
            fees_y: balance::zero<Y>(),

            supply_checkpoints: table_vec::empty<SupplyCheckpoint>(ctx),

            checkpoints: table::new<address, TableVec<Checkpoint>>(ctx), // voting weights for each voter

            supply_index: 0,
            claimable: 0
        };

        create_reward<X,Y,X>(&mut gauge, ctx);
        create_reward<X,Y,Y>(&mut gauge, ctx);

        (gauge, internal_id, external_id)
    }

    // Claim the fee that this Gauge accumulate
    public (friend) fun claim_fee<X,Y>(
        self: &mut Gauge<X,Y>,
        bribe: &mut InternalBribe<X,Y>,
        pool: &mut Pool<X,Y>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
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

            // only deposit when accumulated amount is over left
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
    // ===== Getter =====
    public fun is_alive<X,Y>(self: &Gauge<X,Y>):bool{ self.is_alive }

    public fun pool_id<X,Y>(self: &Gauge<X,Y>):ID{ self.pool }
    public fun get_supply_index<X,Y>(self: &Gauge<X,Y>):u64{ self.supply_index }
    public fun get_claimable<X,Y>(self: &Gauge<X,Y>):u64{ self.claimable }

    public (friend) fun update_supply_index<X,Y>(self: &mut Gauge<X,Y>, v: u64){ self.supply_index = v; }
    public (friend) fun update_claimable<X,Y>(self: &mut Gauge<X,Y>, v: u64){ self.claimable = v; }


    public fun get_prior_balance_index<X,Y>(
        self: & Gauge<X,Y>,
        staker: address,
        ts:u64
    ):u64 {
        if( !table::contains(&self.checkpoints, staker)) return 0;

        let checkpoints = table::borrow(&self.checkpoints, staker);
        let len = table_vec::length(checkpoints);

        if( len == 0){
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
        self: & Gauge<X,Y>,
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
        self: &mut Gauge<X,Y>,
        staker: address,
        balance: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        let ts = clock::timestamp_ms(clock);

        if(!table::contains(&self.checkpoints, staker)){
            table::add(&mut self.checkpoints, staker, table_vec::empty(ctx));
        };

        let player_checkpoint = table::borrow_mut(&mut self.checkpoints, staker);
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
        reward_per_token: u64, // record down balance
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
        self: &mut Gauge<X,Y>,
        clock: &Clock,
    ){
        let ts = clock::timestamp_ms(clock);
        let supply = pool::get_lp_balance(&self.total_supply);

        let len = table_vec::length(&self.supply_checkpoints);

        if( len > 0 && checkpoints::supply_ts(table_vec::borrow(&self.supply_checkpoints, len - 1)) == ts){
            let cp_mut = table_vec::borrow_mut(&mut self.supply_checkpoints, len - 1 );
            checkpoints::update_supply(cp_mut, supply)
        }else{
            let checkpoint = checkpoints::new_sp(ts, supply);
            table_vec::push_back(&mut self.supply_checkpoints, checkpoint);
        };
    }

    public fun last_time_reward_applicable<X, Y, T>(reward: &Reward<X, Y, T>, clock: &Clock):u64{
        math::min(clock::timestamp_ms(clock), reward.period_finish)
    }

    /// allow staker to withdraw emission, should be called after voter distribute the emissions
    /// T = SDB
    public (friend) fun get_reward<X, Y, T>(
        self: &mut Gauge<X,Y>,
        staker: address,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert_generic_type<X,Y,T>();

        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token_<X,Y,T>(self, MAX_U64, true, clock);

        let _reward = earned<X,Y,T>(self, staker, clock);
        let reward = borrow_reward_mut<X,Y,T>(self);
        reward.reward_per_token_stored = reward_per_token_stored;
        reward.last_update_time = last_update_time;

        *table::borrow_mut(&mut reward.last_earn, staker) = clock::timestamp_ms(clock);
        *table::borrow_mut(&mut reward.user_reward_per_token_stored, staker) = reward_per_token_stored;

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

    fun reward_per_token<X, Y, T>(
        self: &Gauge<X,Y>,
        clock: &Clock
    ): u64{
        let reward = borrow_reward<X,Y,T>(self);
        let reward_stored = reward.reward_per_token_stored;
        let total_supply = pool::get_lp_balance(&self.total_supply);
        // no accumualated voting
        if(total_supply == 0){
            return reward_stored
        };

        let last_update = reward.last_update_time;
        let period_finish = reward.period_finish;
        let reward_rate = reward.reward_rate;
        let elapsed = ((last_time_reward_applicable(reward, clock) - math::min(last_update, period_finish)) as u256);
        return reward_stored + (elapsed * (reward_rate as u256) * PRECISION / (total_supply as u256) as u64)
    }

    fun derived_balance<X, Y, T>(
        self: &Gauge<X,Y>,
        staker: address
    ): u64{
        if(table::contains(&self.balance_of, staker)){
            *table::borrow(&self.balance_of, staker)
        }else{
            0
        }
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

    fun batch_reward_per_token<X,Y,T>(
        self: &mut Gauge<X,Y>,
        max_run:u64, // useful when tx might be out of gas
        clock: &Clock,
    ):(u64, u64) // ( reward_per_token_stored, last_update_time)
    {
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

    public entry fun batch_update_reward_per_token<X,Y,T>(
        self: &mut Gauge<X,Y>,
        max_run:u64,
        clock: &Clock,
    ){
        update_reward_per_token_<X,Y,T>(self, max_run, false, clock);
    }

    fun update_reward_for_all_tokens_<X,Y>(
        self: &mut Gauge<X,Y>,
        clock: &Clock,
    ){
        update_reward_per_token_<X,Y,X>(self, MAX_U64, true, clock);
        update_reward_per_token_<X,Y,Y>(self, MAX_U64, true, clock);
    }

    fun update_reward_per_token_<X,Y,T>(
        self: &mut Gauge<X,Y>,
        max_run:u64,
        actual_last: bool,
        clock: &Clock
    ):(u64, u64) // ( reward_per_token_stored, last_update_time)
    {
        assert_generic_type<X,Y,T>();

        let ts = clock::timestamp_ms(clock);
        let reward = borrow_reward<X,Y,T>(self);
        let start_timestamp = reward.last_update_time;
        let reward_token_stored = reward.reward_per_token_stored;

        if(table_vec::length(&self.supply_checkpoints) == 0){
            return ( reward_token_stored, start_timestamp )
        };

        if(reward.reward_rate == 0){
            return ( reward_token_stored, clock::timestamp_ms(clock))
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
                    let ts = checkpoints::supply_ts(table_vec::borrow(&self.supply_checkpoints, i + 1));
                    let reward = borrow_reward_mut<X,Y,T>(self);
                    let ( reward_per_token , end_time) = calc_reward_per_token(reward, ts, sp_0_ts, sp_0_supply, start_timestamp);
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

    fun earned<X,Y,T>(
        self: &Gauge<X,Y>,
        staker: address,
        clock: &Clock
    ):u64{
        assert_generic_type<X,Y,T>();

        let reward = borrow_reward<X,Y,T>(self);
        let rps_borrow = &reward.reward_per_token_checkpoints;
        // checking contains is sufficient, not allowing to exist any empty table
        if(!table::contains(&reward.last_earn, staker) || !table::contains(&self.checkpoints, staker) || table_vec::length(rps_borrow) == 0){
            return 0
        };

        let last_earn = *table::borrow(&reward.last_earn, staker);
        let start_timestamp =  math::max(last_earn, checkpoints::reward_ts(table_vec::borrow(rps_borrow, 0)));

        let bps_borrow = table::borrow(&self.checkpoints, staker);

        let start_idx = get_prior_balance_index(self, staker, start_timestamp);
        let end_idx = table_vec::length(bps_borrow) - 1;
        let earned_reward = 0;

        // accumulate rewards in each reward checkpoints derived from balance checkpoints
        if(end_idx > 0){
            let i = start_idx;
            while( i <= end_idx - 1){ // leave last one
                let cp_0 = table_vec::borrow(bps_borrow, i);
                let cp_1 = table_vec::borrow(bps_borrow, i + 1);
                let ( _, reward_per_token_0) = get_prior_reward_per_token(reward, checkpoints::balance_ts(cp_0));
                let ( _, reward_per_token_1 ) = get_prior_reward_per_token(reward, checkpoints::balance_ts(cp_1));
                let acc = (checkpoints::balance(cp_0) as u256) * ((reward_per_token_1 - reward_per_token_0) as u256) / PRECISION;
                earned_reward = earned_reward + (acc as u64);
                i = i + 1;
            }
        };

        let cp = table_vec::borrow(bps_borrow, end_idx);
        let ( _, perior_reward ) = get_prior_reward_per_token(reward, checkpoints::balance_ts(cp));

        // current slope
        let acc = (checkpoints::balance(cp) as u256) * ((reward_per_token<X,Y,T>(self, clock) - math::max(perior_reward, *table::borrow(&reward.user_reward_per_token_stored, staker))) as u256) / PRECISION;
        earned_reward = earned_reward + (acc as u64);

        return earned_reward
    }

     /// Stake LP_TOKEN
     /// Why do we need attach ?
    fun deposit<X,Y,T>(
        self: &mut Gauge<X,Y>,
        pool: &Pool<X,Y>,
        vsdb: &mut VSDB,
        lp_position: &mut LP<X,Y>, // borrow_mut or take ?
        value: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert_generic_type<X,Y,T>();
        update_reward_for_all_tokens_(self, clock);

        let staker = tx_context::sender(ctx);
        let lp_value = pool::get_lp_balance(lp_position);
        assert!(lp_value > 0, err::empty_lp());
        let id = object::id(vsdb);

        pool::join_lp(pool, &mut self.total_supply, lp_position, value );

        *table::borrow_mut(&mut self.balance_of, staker) = *table::borrow(& self.balance_of, staker) + lp_value;

        //TODO: attach token to gauge, and move assertion in the front of respective functions
        // each address can only register once for each pool
        let sender = tx_context::sender(ctx);
        assert!(vsdb::owner(vsdb) == sender, err::invalid_owner());
        if(!table::contains(&self.token_ids, sender)){
            table::add(&mut self.token_ids, sender, id);
            // attahc
            vsdb::attach<X,Y>(vsdb, ctx);
        };
        //voter::attachTokenToGauge() // move to voter

        write_checkpoint_(self, staker, lp_value, clock, ctx);
        write_supply_checkpoint_(self, clock);

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
    ):LP<X,Y>{
        assert_generic_type<X,Y,T>();
        update_reward_for_all_tokens_(self, clock);

        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token_<X,Y,T>(self, MAX_U64, true, clock);
        let id = object::id(vsdb);
        let staker = tx_context::sender(ctx);


        // unstake the LP from pool
        let lp_position = pool::create_lp(pool, tx_context::sender(ctx), ctx);

        pool::join_lp(pool, &mut lp_position, &mut self.total_supply, value);
        let lp_value = pool::get_lp_balance(&lp_position);

        // record check
        let bal = *table::borrow(& self.balance_of, staker);
        assert!(bal > lp_value, err::insufficient_lp_balance());
        *table::borrow_mut(&mut self.balance_of, staker) =  bal - lp_value;

        // detach & validation
        let sender = tx_context::sender(ctx);
        assert!(vsdb::owner(vsdb) == sender, err::invalid_owner());

        let id = table::remove(&mut self.token_ids, sender);
        // detach
        vsdb::detach<X,Y>(vsdb, ctx);

        assert!(table::borrow(&self.token_ids, sender) == &id, err::already_stake());

        write_checkpoint_(self, staker, lp_value, clock, ctx);
        write_supply_checkpoint_(self, clock);

        event::withdraw_lp<X,Y>(tx_context::sender(ctx), id, lp_value);

        lp_position
    }


    public fun left<X, Y, T>(reward: &Reward<X, Y, T>, clock: &Clock):u64{
        let ts = clock::timestamp_ms(clock);
        let period_finish = reward.period_finish;
        let reward_rate = reward.reward_rate;

        // no on bribing
        if(ts >= period_finish) return 0;

        let _remaining = period_finish - ts;
        return _remaining * reward_rate
    }

    // ===== Setter =====
    public (friend) fun kill_gauge_<X,Y>(self: &mut Gauge<X,Y> ){ self.is_alive = false }
    public (friend) fun revive_gauge_<X,Y>(self: &mut Gauge<X,Y>){ self.is_alive = true }




    /// distribute the weekly rebase amonut
    public fun notify_reward_amount<X,Y,T>(
        self: &mut Gauge<X,Y>,
        bribe: &mut Gauge<X,Y>,
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
            write_reward_per_token_checkpoint_(borrow_reward_mut<X,Y,T>(self), 0, ts);
        };

        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token_<X,Y,T>(self, MAX_U64, true, clock);

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
    // Collect the fees from Pool, then deposit into internal bribe

}
