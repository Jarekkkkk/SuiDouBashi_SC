// Gauges are used to incentivize pools, they emit reward tokens over 7 days for staked LP tokens
module suiDouBashi_vest::gauge{
    use std::type_name;
    use std::option;
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::dynamic_field as df;
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::clock::{Self, Clock};
    use sui::math;
    use sui::table_vec::{Self, TableVec};
    use sui::table::{Self, Table};

    use suiDouBashi_amm::math_u128;
    use suiDouBashi_amm::pool::{Self, Pool, LP};

    use suiDouBashi_vsdb::sdb::SDB;
    use suiDouBashi_vest::event;
    use suiDouBashi_vest::checkpoints::{Self, SupplyCheckpoint, Checkpoint, RewardPerTokenCheckpoint};
    use suiDouBashi_vest::internal_bribe::{Self, InternalBribe};
    use suiDouBashi_vest::external_bribe::{Self};
    use suiDouBashi_vest::minter::package_version;

    const DURATION: u64 = { 7 * 86400 };
    const PRECISION: u128 = 1_000_000_000_000_000_000;
    const MAX_U64: u64 = 18446744073709551615_u64;

    const E_WRONG_VERSION: u64 = 001;

    const E_ALREADY_STAKE: u64 = 100;
    const E_INVALID_STAKER: u64 = 101;
    const E_EMPTY_VALUE: u64 = 102;
    const E_INSUFFICENT_BALANCE: u64 = 103;
    const E_DEAD_GAUGE: u64 = 104;
    const E_INSUFFICENT_BRIBES: u64 = 105;
    const E_INVALID_REWARD_RATE: u64 = 106;
    const E_MAX_REWARD: u64 = 107;

    friend suiDouBashi_vest::voter;

    struct Gauge<phantom X, phantom Y> has key, store{
        id: UID,
        version: u64,
        is_alive:bool,
        pool: ID,
        total_supply: LP<X,Y>,
        balance_of: Table<address, u64>,
        fees_x: Balance<X>,
        fees_y: Balance<Y>,
        supply_checkpoints: TableVec<SupplyCheckpoint>, // total LP staked amount
        checkpoints: Table<address, TableVec<Checkpoint>>, // each address can stake once for each pool
        supply_index: u256,
        claimable: u64
    }

    public fun is_alive<X,Y>(self: &Gauge<X,Y>):bool{ self.is_alive }

    public fun pool_id<X,Y>(self: &Gauge<X,Y>):ID{ self.pool }

    public fun get_supply_index<X,Y>(self: &Gauge<X,Y>):u256{ self.supply_index }

    public fun get_claimable<X,Y>(self: &Gauge<X,Y>):u64{ self.claimable }

    public (friend) fun update_supply_index<X,Y>(self: &mut Gauge<X,Y>, v: u256){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        self.supply_index = v;
    }

    public (friend) fun update_claimable<X,Y>(self: &mut Gauge<X,Y>, v: u64){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        self.claimable = v;
    }

    public (friend) fun update_gauge<X,Y>(self: &mut Gauge<X,Y>, alive: bool ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        self.is_alive = alive
     }

    public fun get_balance_of<X,Y>(self: &Gauge<X,Y>, staker: address):u64{
        *table::borrow(&self.balance_of, staker)
    }
    #[test_only]
    public fun checkpoints_borrow<X,Y>(self: &Gauge<X,Y>, staker: address): &TableVec<Checkpoint>{
        table::borrow(&self.checkpoints, staker)
    }
    #[test_only]
    public fun supply_checkpoints_borrow<X,Y>(self: &Gauge<X,Y>): &TableVec<SupplyCheckpoint>{
        &self.supply_checkpoints
    }
    #[test_only]
    public fun total_supply_borrow<X,Y>(self: &Gauge<X,Y>):&LP<X,Y>{ &self.total_supply }

    struct Reward<phantom X, phantom Y > has key, store{
        id: UID,

        balance: Balance<SDB>,

        reward_rate: u64, // reward_amount / 7 days
        period_finish: u64,

        last_update_time: u64,
        reward_per_token_stored: u128,
        user_reward_per_token_stored: Table<address, u128>,
        last_earn: Table<address, u64>,

        reward_per_token_checkpoints: TableVec<RewardPerTokenCheckpoint>,
    }

    public fun borrow_reward<X,Y>(self: &Gauge<X,Y>):&Reward<X, Y>{
        df::borrow(&self.id, type_name::get<SDB>())
    }
    fun borrow_reward_mut<X,Y>(self: &mut Gauge<X,Y>):&mut Reward<X,Y>{
        assert!(self.version == package_version(), E_WRONG_VERSION);
        df::borrow_mut(&mut self.id, type_name::get<SDB>())
    }
    #[test_only]
    public fun get_reward_balance<X,Y>(reward: &Reward<X,Y>):u64 { balance::value(&reward.balance) }
    #[test_only]
    public fun get_reward_rate<X,Y>(reward: &Reward<X,Y>):u64 { reward.reward_rate }
    #[test_only]
    public fun get_period_finish<X,Y>(reward: &Reward<X,Y>): u64{ reward.period_finish }
    #[test_only]
    public fun get_last_update_time<X,Y>(reward: &Reward<X,Y>): u64{ reward.last_update_time }
    #[test_only]
    public fun get_reward_per_token_stored<X,Y>(reward: &Reward<X,Y>): u128{ reward.reward_per_token_stored }
    #[test_only]
    public fun user_reward_per_token_stored_borrow<X,Y>(reward: &Reward<X,Y>):&Table<address, u128>{
        &reward.user_reward_per_token_stored
    }
    #[test_only]
    public fun last_earn_borrow<X,Y>(reward: &Reward<X,Y>):&Table<address, u64>{
        &reward.last_earn
    }
    #[test_only]
    public fun reward_checkpoints_borrow<X,Y>(reward: &Reward<X,Y>):&TableVec<RewardPerTokenCheckpoint>{
        &reward.reward_per_token_checkpoints
    }

    public (friend) fun new<X,Y>(
        pool: &Pool<X,Y>,
        ctx: &mut TxContext
    ):(Gauge<X,Y>, ID, ID){
        let internal_id = internal_bribe::create_bribe<X,Y>(ctx);
        let external_id = external_bribe::create_bribe<X,Y>(ctx);

        let id = object::new(ctx);
        let gauge = Gauge<X,Y>{
            id,
            version: package_version(),
            is_alive: true,
            pool: object::id(pool),
            total_supply: pool::create_lp(pool, ctx),
            balance_of: table::new<address, u64>(ctx),
            fees_x: balance::zero<X>(),
            fees_y: balance::zero<Y>(),
            supply_checkpoints: table_vec::empty<SupplyCheckpoint>(ctx),
            checkpoints: table::new<address, TableVec<Checkpoint>>(ctx),
            supply_index: 0,
            claimable: 0
        };
        // SDB emission rewards
        let reward =  Reward<X,Y>{
            id: object::new(ctx),
            balance: balance::zero<SDB>(),
            reward_rate: 0,
            period_finish: 0,
            last_update_time: 0,
            reward_per_token_stored: 0,
            reward_per_token_checkpoints: table_vec::empty<RewardPerTokenCheckpoint>(ctx),

            user_reward_per_token_stored: table::new<address, u128>(ctx),
            last_earn: table::new<address, u64>(ctx),
        };

        df::add(&mut gauge.id, type_name::get<SDB>(), reward);

        (gauge, internal_id, external_id)
    }

    /// Claim the fees from pool
    public fun claim_fee<X,Y>(
        self: &mut Gauge<X,Y>,
        bribe: &mut InternalBribe<X,Y>,
        pool: &mut Pool<X,Y>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        let (coin_x, coin_y) = pool::claim_fees_dev(pool, &mut self.total_supply, ctx);
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

            // only deposit when accumulated amount exceed the left amount
            if(bal_x > internal_bribe::left(internal_bribe::borrow_reward<X,Y,X>(bribe),clock) && bal_x / DURATION > 0  ){
                let withdraw = balance::withdraw_all(&mut self.fees_x);
                internal_bribe::deposit_pool_fees(bribe, coin::from_balance(withdraw, ctx), clock, ctx);
            };

            if(bal_y > internal_bribe::left(internal_bribe::borrow_reward<X,Y,Y>(bribe),clock) && bal_y / DURATION > 0  ){
                let withdraw = balance::withdraw_all(&mut self.fees_y);
                internal_bribe::deposit_pool_fees(bribe, coin::from_balance(withdraw, ctx), clock, ctx);
            }
        };

        event::claim_fees(tx_context::sender(ctx), value_x, value_y);
    }

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

    public fun get_prior_reward_per_token<X, Y>(
        reward: &Reward<X, Y>,
        ts:u64
    ):(u64, u128) // ( ts, reward_per_token )
    {
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
        let ts = clock::timestamp_ms(clock) / 1000;

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

    fun write_reward_per_token_checkpoint_<X, Y>(
        reward: &mut Reward<X, Y>,
        reward_per_token: u128,
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
        let ts = clock::timestamp_ms(clock) / 1000;
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

    public fun last_time_reward_applicable<X, Y>(reward: &Reward<X, Y>, clock: &Clock):u64{
        math::min(clock::timestamp_ms(clock) / 1000, reward.period_finish)
    }

    public fun get_reward<X,Y>(
        self: &mut Gauge<X,Y>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        let staker = tx_context::sender(ctx);
        assert!(table::contains(&self.balance_of, staker), E_INVALID_STAKER);

        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token_<X,Y>(self, MAX_U64, true, clock);
        {
            let reward = borrow_reward_mut<X,Y>(self);
            if(!table::contains(&reward.last_earn, staker)){
                table::add(&mut reward.last_earn, staker, 0);
            };
            if(!table::contains(&reward.user_reward_per_token_stored, staker)){
                table::add(&mut reward.user_reward_per_token_stored, staker, 0);
            };
            reward.reward_per_token_stored = reward_per_token_stored;
            reward.last_update_time = last_update_time;
        };

        let _reward = earned<X,Y>(self, staker, clock);
        let reward = borrow_reward_mut<X,Y>(self);
        *table::borrow_mut(&mut reward.last_earn, staker) = clock::timestamp_ms(clock) / 1000;
        *table::borrow_mut(&mut reward.user_reward_per_token_stored, staker) = reward_per_token_stored;
        if(_reward > 0){
            let coin_x = coin::take(&mut reward.balance, _reward, ctx);
            let value_x = coin::value(&coin_x);
            transfer::public_transfer(
                coin_x,
                tx_context::sender(ctx)
            );
            event::claim_reward(tx_context::sender(ctx), value_x);
        };
        let lp_value = *table::borrow(&self.balance_of, tx_context::sender(ctx));
        write_checkpoint_(self, staker, lp_value, clock, ctx);
        write_supply_checkpoint_(self, clock);
    }

    public fun reward_per_token<X, Y>(
        self: &Gauge<X,Y>,
        clock: &Clock
    ): u128{
        let reward = borrow_reward<X,Y>(self);
        let reward_per_token_stored = reward.reward_per_token_stored;
        let total_supply = pool::get_lp_balance(&self.total_supply);

        if(total_supply == 0){
            return reward_per_token_stored
        };

        let last_update = reward.last_update_time;
        let period_finish = reward.period_finish;
        let reward_rate = reward.reward_rate;
        let elapsed = ((last_time_reward_applicable(reward, clock) - math::min(last_update, period_finish)) as u128);
        return reward_per_token_stored + (reward_rate as u128) * PRECISION / (total_supply as u128) * elapsed
    }

    fun calc_reward_per_token<X, Y>(
        reward: &Reward<X, Y>,
        timestamp_1: u64,
        timestamp_0: u64,
        supply: u64,
        start_timestamp: u64
    ):(u128, u64){
        let end_time = math::max(timestamp_1, start_timestamp);
        let start_time = math::max(timestamp_0, start_timestamp);
        let reward =  ((math::min(end_time, reward.period_finish) - math::min(start_time, reward.period_finish)) as u128) * (reward.reward_rate as u128) * PRECISION / (supply as u128);

        (reward, end_time)
    }

    public fun batch_reward_per_token<X,Y>(
        self: &mut Gauge<X,Y>,
        max_run:u64,
        clock: &Clock,
    ):(u128, u64) // ( reward_per_token_stored, last_update_time)
    {
        assert!(self.version == package_version(), E_WRONG_VERSION);
        let ts = clock::timestamp_ms(clock) / 1000;
        let reward = borrow_reward<X,Y>(self);
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
                let reward = borrow_reward_mut<X,Y>(self);
                let (reward_per_token ,end_time) = calc_reward_per_token(reward, sp_1_ts, sp_0_ts, sp_0_supply, start_timestamp);
                reward_token_stored = reward_token_stored + reward_per_token;
                write_reward_per_token_checkpoint_(reward, reward_token_stored, end_time);
                start_timestamp = end_time;
            };
            i = i + 1;
        };

        return ( reward_token_stored, start_timestamp )
    }

    public entry fun batch_update_reward_per_token<X,Y>(
        self: &mut Gauge<X,Y>,
        max_run:u64,
        clock: &Clock,
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token_<X,Y>(self, max_run, false, clock);

        borrow_reward_mut<X,Y>(self).reward_per_token_stored = reward_per_token_stored;
        borrow_reward_mut<X,Y>(self).last_update_time = last_update_time;
    }

    fun update_reward_per_token_<X,Y>(
        self: &mut Gauge<X,Y>,
        max_run:u64,
        actual_last: bool,
        clock: &Clock
    ):(u128, u64) // ( reward_per_token_stored, last_update_time)
    {
        let ts = clock::timestamp_ms(clock) / 1000;
        let reward = borrow_reward<X,Y>(self);
        let start_timestamp = reward.last_update_time;
        let reward_token_stored = reward.reward_per_token_stored;

        if(table_vec::length(&self.supply_checkpoints) == 0){
            return ( reward_token_stored, start_timestamp )
        };

        if(reward.reward_rate == 0){
            return ( reward_token_stored, clock::timestamp_ms(clock) / 1000)
        };

        let start_idx = get_prior_supply_index(self, start_timestamp);
        let end_idx = math::min(table_vec::length(&self.supply_checkpoints) - 1, max_run);

        if(end_idx > 0){
            let i = start_idx;
            while( i <= end_idx - 1){
                let sp_0_ts = checkpoints::supply_ts(table_vec::borrow(&self.supply_checkpoints, i));
                let sp_0_supply = checkpoints::supply(table_vec::borrow(&self.supply_checkpoints, i));
                if(sp_0_supply > 0){
                    let ts = checkpoints::supply_ts(table_vec::borrow(&self.supply_checkpoints, i + 1));
                    let reward = borrow_reward_mut<X,Y>(self);
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
                let reward = borrow_reward<X,Y>(self);
                let ( reward_per_token, _ ) = calc_reward_per_token(reward, last_time_reward_applicable(reward, clock), math::max(sp_ts, start_timestamp), sp_supply, start_timestamp);
                reward_token_stored = reward_token_stored + reward_per_token;

                write_reward_per_token_checkpoint_(borrow_reward_mut<X,Y>(self), reward_token_stored, ts);
                start_timestamp = ts;
            };
        };
        return ( reward_token_stored, start_timestamp )
    }

    /// Calculate staker's SDB reward by weekly
    /// this is estimation, earned will only update after calling update_reward_per_token_()
    public fun earned<X,Y>(
        self: & Gauge<X,Y>,
        staker: address,
        clock: &Clock
    ):u64{
        let reward = borrow_reward<X,Y>(self);
        let rps_borrow = &reward.reward_per_token_checkpoints;

        if(!table::contains(&self.checkpoints, staker) || table_vec::length(rps_borrow) == 0){
            return 0
        };

        let last_earn = if(table::contains(&reward.last_earn, staker)){
            *table::borrow(&reward.last_earn, staker)
        }else{
            0
        };
        let start_timestamp = math::max(last_earn, checkpoints::reward_ts(table_vec::borrow(rps_borrow, 0)));

        let bps_borrow = table::borrow(&self.checkpoints, staker);

        let start_idx = get_prior_balance_index(self, staker, start_timestamp);
        let end_idx = table_vec::length(bps_borrow) - 1;

        let earned_reward = 0;
        if(end_idx > 0){
            let i = start_idx;
            while( i <= end_idx - 1){ // leave last one
                let cp_0 = table_vec::borrow(bps_borrow, i);
                let cp_1 = table_vec::borrow(bps_borrow, i + 1);
                let ( _, reward_per_token_0) = get_prior_reward_per_token(reward, checkpoints::balance_ts(cp_0));
                let ( _, reward_per_token_1 ) = get_prior_reward_per_token(reward, checkpoints::balance_ts(cp_1));
                let acc = (checkpoints::balance(cp_0) as u128) * ((reward_per_token_1 - reward_per_token_0) as u128) / PRECISION;
                earned_reward = earned_reward + (acc as u64);
                i = i + 1;
            }
        };

        // accumulating rewards
        let cp = table_vec::borrow(bps_borrow, end_idx);
        let ( _, reward_stored ) = get_prior_reward_per_token(reward, checkpoints::balance_ts(cp));
        let user_reward_per_token_stored = if(table::contains(&reward.user_reward_per_token_stored, staker)){
            *table::borrow(&reward.user_reward_per_token_stored, staker)
        }else{
            0
        };
        // current slope
        let acc = (checkpoints::balance(cp) as u128) * (reward_per_token<X,Y>(self, clock) - math_u128::max(reward_stored, user_reward_per_token_stored)) / PRECISION;
        earned_reward = earned_reward + (acc as u64);
        return earned_reward
    }

     /// Stake LP_TOKEN
    public entry fun stake_all<X,Y>(
        self: &mut Gauge<X,Y>,
        pool: &Pool<X,Y>,
        lp_position: &mut LP<X,Y>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        let balance = pool::get_lp_balance(lp_position);
        stake(self, pool, lp_position, balance, clock, ctx);
    }
    public entry fun stake<X,Y>(
        self: &mut Gauge<X,Y>,
        pool: &Pool<X,Y>,
        lp_position: &mut LP<X,Y>, // not taking the ownership, otherwise owner lose all of its previous shares
        value: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token_<X,Y>(self, MAX_U64, true, clock);

        borrow_reward_mut<X,Y>(self).reward_per_token_stored = reward_per_token_stored;
        borrow_reward_mut<X,Y>(self).last_update_time = last_update_time;

        let staker = tx_context::sender(ctx);
        let lp_value = pool::get_lp_balance(lp_position);
        assert!(lp_value > 0, E_EMPTY_VALUE);

        pool::join_lp(pool, &mut self.total_supply, lp_position, value);

        if(!table::contains(&self.balance_of, staker)){
            table::add(&mut self.balance_of, staker, value);
        }else{
            *table::borrow_mut(&mut self.balance_of, staker) = *table::borrow(& self.balance_of, staker) + value;
        };

        write_checkpoint_(self, staker, value, clock, ctx);
        write_supply_checkpoint_(self, clock);

        event::deposit_lp<X,Y>(tx_context::sender(ctx), value);
    }

    /// LP unstake lp
    public entry fun unstake_all<X,Y>(
        self: &mut Gauge<X,Y>,
        pool: &Pool<X,Y>,
        lp_position: &mut LP<X,Y>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        let bal = get_balance_of(self, tx_context::sender(ctx));
        unstake(self, pool, lp_position, bal, clock, ctx);
    }
    public entry fun unstake<X,Y>(
        self: &mut Gauge<X,Y>,
        pool: &Pool<X,Y>,
        lp_position: &mut LP<X,Y>,
        value: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        let staker = tx_context::sender(ctx);
        assert!(table::contains(&self.balance_of, staker), E_INVALID_STAKER);
        let bal = get_balance_of(self, staker);
        assert!(value <= bal, E_INSUFFICENT_BALANCE);

        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token_<X,Y>(self, MAX_U64, true, clock);

        borrow_reward_mut<X,Y>(self).reward_per_token_stored = reward_per_token_stored;
        borrow_reward_mut<X,Y>(self).last_update_time = last_update_time;

        // unstake the LP from pool
        pool::join_lp(pool, lp_position, &mut self.total_supply, value);

        *table::borrow_mut(&mut self.balance_of, staker) =  bal - value;
        let bal = get_balance_of(self, staker);

        write_checkpoint_(self, staker, bal, clock, ctx);
        write_supply_checkpoint_(self, clock);

        event::withdraw_lp<X,Y>(tx_context::sender(ctx), value);
    }

    public fun left<X, Y>(reward: &Reward<X, Y>, clock: &Clock):u64{
        let ts = clock::timestamp_ms(clock) / 1000;

        if(ts >= reward.period_finish) return 0;

        let _remaining = reward.period_finish - ts;
        return _remaining * reward.reward_rate
    }

    // distribute pool fees
    public fun distribute_emissions<X,Y>(
        self: &mut Gauge<X,Y>,
        bribe: &mut InternalBribe<X,Y>,
        pool: &mut Pool<X,Y>,
        coin: Coin<SDB>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        let value = coin::value(&coin);
        let reward = borrow_reward<X,Y>(self);
        assert!(value > 0, E_EMPTY_VALUE);
        let ts = clock::timestamp_ms(clock) / 1000;
        if(reward.reward_rate == 0){
            write_reward_per_token_checkpoint_(borrow_reward_mut<X,Y>(self), 0, ts);
        };

        let ( reward_per_token_stored, last_update_time ) = update_reward_per_token_<X,Y>(self, MAX_U64, true, clock);
        borrow_reward_mut<X,Y>(self).reward_per_token_stored = reward_per_token_stored;
        borrow_reward_mut<X,Y>(self).last_update_time = last_update_time;

        claim_fee(self, bribe, pool, clock, ctx);

        let reward = borrow_reward_mut<X,Y>(self);

        if(ts >= reward.period_finish){
            coin::put(&mut reward.balance, coin);
            reward.reward_rate = value / DURATION;
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

        event::notify_reward<SDB>(tx_context::sender(ctx), value);
    }
}