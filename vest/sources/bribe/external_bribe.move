// External Bribes represent coin brbies from protocol
module suiDouBashi_vest::external_bribe{
    use std::vector as vec;
    use std::type_name;

    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::clock::{Self, Clock};
    use sui::math;
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::table_vec::{Self, TableVec};
    use sui::dynamic_field as df;

    use suiDouBashi_vsdb::vsdb::Vsdb;
    use suiDouBashi_vsdb::sdb::SDB;
    use suiDouBashi_vest::event;
    use suiDouBashi_vest::checkpoints::{Self, SupplyCheckpoint, Checkpoint};
    use suiDouBashi_vest::minter::package_version;

    friend suiDouBashi_vest::gauge;
    friend suiDouBashi_vest::voter;

    const DURATION: u64 = { 7 * 86400 };
    const PRECISION: u256 = 1_000_000_000_000_000_000;
    const MAX_REWARD_TOKENS: u64 = 16;
    const MAX_U64: u64 = 18446744073709551615_u64;

    const E_WRONG_VERSION: u64 = 001;
    const E_INVALID_TYPE: u64 = 100;
    const E_INVALID_VOTER: u64 = 101;
    const E_INSUFFICIENT_VOTES: u64 = 103;
    const E_INSUFFICENT_BALANCE: u64 = 103;
    const E_EMPTY_VALUE: u64 = 104;

    struct ExternalBribe<phantom X, phantom Y> has key, store{
        id: UID,
        version: u64,
        total_supply: u64,
        balance_of: Table<ID, u64>,
        supply_checkpoints: TableVec<SupplyCheckpoint>,

        checkpoints: Table<ID, vector<Checkpoint>>,
    }

    public fun total_voting_weight<X,Y>(self: &ExternalBribe<X,Y>):u64{ self.total_supply }
    public fun get_balance_of<X,Y>(self: &ExternalBribe<X,Y>, vsdb: &Vsdb):u64 {
        *table::borrow(&self.balance_of, object::id(vsdb))
    }

    // 4 coins at most are allowed to bribe, [coin pair of pool, SDB, SUI]
    struct Reward<phantom X, phantom Y, phantom T> has store{
        balance: Balance<T>,
        token_rewards_per_epoch: Table<u64, u64>,
        period_finish: u64,
        last_earn: Table<ID, u64>,
    }

    // - Reward
    fun create_reward<X,Y,T>(self: &mut ExternalBribe<X,Y>, ctx: &mut TxContext){
        let reward =  Reward<X,Y,T>{
            balance: balance::zero<T>(),
            token_rewards_per_epoch: table::new<u64, u64>(ctx),
            period_finish: 0,
            last_earn: table::new<ID, u64>(ctx)
        };
        df::add(&mut self.id, type_name::get<T>(), reward);
    }
    public fun borrow_reward<X,Y,T>(self: &ExternalBribe<X,Y>):&Reward<X, Y, T>{
        assert_generic_type<X,Y,T>();
        df::borrow(&self.id, type_name::get<T>())
    }
    fun borrow_reward_mut<X,Y,T>(self: &mut ExternalBribe<X,Y>):&mut Reward<X, Y, T>{
        assert_generic_type<X,Y,T>();
        df::borrow_mut(&mut self.id, type_name::get<T>())
    }

    public fun get_reward_balance<X,Y,T>(self: &ExternalBribe<X,Y>):u64 {
        let reward = borrow_reward<X,Y,T>(self);
        balance::value(&reward.balance)
    }
    #[test_only]
    public fun get_reward_per_token_stored<X,Y,T>(reward: &Reward<X,Y,T>): &Table<u64, u64>{ &reward.token_rewards_per_epoch }
    #[test_only]
    public fun get_period_finish<X,Y,T>(reward: &Reward<X,Y,T>): u64{ reward.period_finish }

    // ===== Assertion =====
    public fun assert_generic_type<X,Y,T>(){
        let type_t = type_name::get<T>();
        assert!( type_t == type_name::get<X>() || type_t == type_name::get<Y>() || type_t == type_name::get<SUI>() || type_t == type_name::get<SDB>(), E_INVALID_TYPE);
    }
    // called in gauge constructor
    public (friend )fun create_bribe<X,Y>(
        ctx: &mut TxContext
    ):ID {
        let bribe = ExternalBribe<X,Y>{
            id: object::new(ctx),
            version: package_version(),
            total_supply:0,
            balance_of: table::new<ID, u64>(ctx),
            supply_checkpoints: table_vec::empty<SupplyCheckpoint>(ctx),

            checkpoints: table::new<ID, vector<Checkpoint>>(ctx),
        };
        let id = object::id(&bribe);

        // create reward
        let type_x = type_name::get<X>();
        let type_y = type_name::get<Y>();
        let type_sdb = type_name::get<SDB>();
        let type_sui = type_name::get<SUI>();

        create_reward<X,Y,X>(&mut bribe, ctx);
        create_reward<X,Y,Y>(&mut bribe, ctx);
        if(type_sui != type_x && type_sui != type_y){
            create_reward<X,Y,SUI>(&mut bribe, ctx);
        };
        if(type_sdb != type_x && type_sdb != type_y){
            create_reward<X,Y,SDB>(&mut bribe, ctx);
        };
        transfer::share_object(bribe);
        id
    }

    fun bribe_start(ts: u64):u64{
        ts - (ts % DURATION)
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

    public fun get_prior_balance_index<X,Y>(
        self: & ExternalBribe<X,Y>,
        vsdb: &Vsdb,
        ts:u64
    ):u64 {
        let id = object::id(vsdb);
        if( !table::contains(&self.checkpoints, id)) return 0;

        let checkpoints = table::borrow(&self.checkpoints, id);
        let len = vec::length(checkpoints);

        if(len == 0){
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
        while (lower < upper){
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
        self: & ExternalBribe<X,Y>,
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

    fun write_checkpoint_<X,Y>(
        self: &mut ExternalBribe<X,Y>,
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

    fun write_supply_checkpoint_<X,Y>(
        self: &mut ExternalBribe<X,Y>,
        clock: &Clock,
    ){
        let ts = clock::timestamp_ms(clock) / 1000;
        let supply = self.total_supply;

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
        math::min(clock::timestamp_ms(clock) / 1000, reward.period_finish)
    }

    public entry fun get_all_rewards<X,Y>(
        self: &mut ExternalBribe<X,Y>,
        vsdb: &Vsdb,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        let type_x = type_name::get<X>();
        let type_y = type_name::get<Y>();
        let type_sdb = type_name::get<SDB>();
        let type_sui = type_name::get<SUI>();

        get_reward<X,Y,X>(self, vsdb, clock, ctx);
        get_reward<X,Y,Y>(self, vsdb, clock, ctx);
        if(type_sui != type_x && type_sui != type_y){
            get_reward<X,Y,SUI>(self, vsdb, clock, ctx);
        };
        if(type_sdb != type_x && type_sdb != type_y){
            get_reward<X,Y,SDB>(self, vsdb, clock, ctx);
        };
    }

    public entry fun get_reward<X, Y, T>(
        self: &mut ExternalBribe<X,Y>,
        vsdb: &Vsdb,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        assert_generic_type<X,Y,T>();

        let id = object::id(vsdb);

        let _reward = earned<X,Y,T>(self, vsdb, clock);
        let reward = borrow_reward_mut<X,Y,T>(self);

        if(!table::contains(&reward.last_earn, id)){
            table::add(&mut reward.last_earn, id, 0);
        };
        *table::borrow_mut(&mut reward.last_earn, id) = clock::timestamp_ms(clock) / 1000;

        if(_reward > 0){
            let coin = coin::take(&mut reward.balance, _reward, ctx);
            let value_x = coin::value(&coin);
            transfer::public_transfer(
                coin,
                tx_context::sender(ctx)
            );
            event::claim_reward(tx_context::sender(ctx), value_x);
        }
    }

    public fun earned<X,Y,T>(
        self: &ExternalBribe<X,Y>,
        vsdb: &Vsdb,
        clock: &Clock
    ):u64{
        assert_generic_type<X,Y,T>();
        let id = object::id(vsdb);
        let reward = borrow_reward<X,Y,T>(self);
        if(!table::contains(&self.checkpoints, id) || table::length(&reward.token_rewards_per_epoch) == 0 ){
            return 0
        };

        let bps_borrow = table::borrow(&self.checkpoints, id);
        if(vec::length(bps_borrow) == 0) return 0;

        let last_earn = if(table::contains(&reward.last_earn, id)){
            *table::borrow(&reward.last_earn, id)
        }else{
            0
        };

        let bps_borrow = table::borrow(&self.checkpoints, id);
        if(vec::length(bps_borrow) == 0) return 0;

        let start_idx = get_prior_balance_index(self, vsdb, last_earn);
        let end_idx = vec::length(bps_borrow) - 1;
        let earned_reward = 0;
        let pre_reward_bal = 0;
        let pre_reward_ts = bribe_start(last_earn);
        let _pre_supply = 1;
        if(end_idx > 0){
            let i = start_idx;
            while( i <= end_idx - 1){
                let cp_0 = vec::borrow(bps_borrow, i);
                let _next_epoch_start = bribe_start(checkpoints::balance_ts(cp_0));
                // check that you've earned it
                // this won't happen until a week has passed
                if(_next_epoch_start > pre_reward_ts){
                    earned_reward = earned_reward + pre_reward_bal;
                };

                pre_reward_ts = _next_epoch_start;
                _pre_supply = checkpoints::supply(table_vec::borrow(&self.supply_checkpoints, get_prior_supply_index(self, _next_epoch_start + DURATION)));

                let rewards =  if(table::contains(&reward.token_rewards_per_epoch, _next_epoch_start)){
                    *table::borrow(&reward.token_rewards_per_epoch, _next_epoch_start)
                }else{
                    0
                };

                pre_reward_bal = (checkpoints::balance(cp_0) as u128) * (rewards as u128) / ((_pre_supply + 1 ) as u128);

                i = i + 1;
            }
                };

        let cp = vec::borrow(bps_borrow, end_idx);
        let last_epoch_start = sui::math::max(bribe_start(checkpoints::balance_ts(cp)), bribe_start(last_earn));
        let last_epoch_end = last_epoch_start + DURATION;

        if(clock::timestamp_ms(clock) / 1000 > last_epoch_end){
            let supply = checkpoints::supply(table_vec::borrow(&self.supply_checkpoints, get_prior_supply_index(self, last_epoch_end)));

            let rewards =  if(table::contains(&reward.token_rewards_per_epoch, last_epoch_start)){
                *table::borrow(&reward.token_rewards_per_epoch, last_epoch_start)
            }else {
                0
            };

            earned_reward = earned_reward + (checkpoints::balance(cp) as u128) * (rewards as u128) / (supply as u128);
        };

        ( earned_reward as u64 )
    }

    //// [voter]: receive votintg
    public (friend) fun deposit<X,Y>(
        self: &mut ExternalBribe<X,Y>,
        vsdb: &Vsdb,
        amount: u64,
        clock: &Clock
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        let id = object::id(vsdb);
        self.total_supply = self.total_supply + amount;

        if(table::contains(&self.balance_of, id)){
            *table::borrow_mut(&mut self.balance_of, id) = *table::borrow(& self.balance_of, id) + amount;
        }else{
            table::add(&mut self.balance_of, id, amount);
        };

        write_checkpoint_(self, vsdb, amount, clock);
        write_supply_checkpoint_(self, clock);
    }

    //// [voter]: abstain votintg
    public (friend) fun withdraw<X,Y>(
        self: &mut ExternalBribe<X,Y>,
        vsdb: &Vsdb,
        amount: u64,
        clock: &Clock
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        let id = object::id(vsdb);
        assert!(table::contains(&self.balance_of, id), E_INVALID_VOTER);
        let supply = self.total_supply;
        let balance = *table::borrow(& self.balance_of, id);
        assert!(supply >= amount, E_INSUFFICENT_BALANCE);
        assert!(balance >= amount, E_INSUFFICIENT_VOTES);
        self.total_supply = self.total_supply - amount;
        *table::borrow_mut(&mut self.balance_of, id) = *table::borrow(& self.balance_of, id) - amount;
        write_checkpoint_(self, vsdb, amount, clock);
        write_supply_checkpoint_(self, clock);
    }

    public fun left<X,Y, T>(reward: &Reward<X, Y, T>, clock: &Clock):u64{
        let adjusted_ts = get_epoch_start(clock::timestamp_ms(clock) / 1000);
        if (!table::contains(&reward.token_rewards_per_epoch, adjusted_ts)){
            0
        }else{
            *table::borrow(&reward.token_rewards_per_epoch, adjusted_ts)
        }
    }

    /// Allow protoocl deposit the bribes
    public entry fun bribe<X,Y,T>(
        self: &mut ExternalBribe<X,Y>,
        coin: Coin<T>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        assert_generic_type<X,Y,T>();

        let value = coin::value(&coin);
        let reward = borrow_reward_mut<X,Y,T>(self);
        assert!(value > 0, E_EMPTY_VALUE);

        // bribes kick in at the start of next bribe period
        let adjusted_ts = get_epoch_start(clock::timestamp_ms(clock) / 1000);
        let epoch_rewards = if(table::contains(&reward.token_rewards_per_epoch, adjusted_ts)){
            *table::borrow(&reward.token_rewards_per_epoch, adjusted_ts)
        }else{
            0
        };

        coin::put(&mut reward.balance, coin);
        if(table::contains(&reward.token_rewards_per_epoch, adjusted_ts)){
            *table::borrow_mut(&mut reward.token_rewards_per_epoch, adjusted_ts) = epoch_rewards + value;
        }else{
            table::add(&mut reward.token_rewards_per_epoch, adjusted_ts, epoch_rewards + value);
        };
        reward.period_finish = adjusted_ts + DURATION;

        event::notify_reward<T>(tx_context::sender(ctx), value);
    }
}