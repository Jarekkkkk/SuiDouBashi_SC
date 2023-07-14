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
    use suiDouBashi_vest::checkpoints::{Self, SupplyCheckpoint, BalanceCheckpoint};
    use suiDouBashi_vest::minter::package_version;

    friend suiDouBashi_vest::gauge;
    friend suiDouBashi_vest::voter;

    // ====== Constants =======

    const DURATION: u64 = { 7 * 86400 };
    const PRECISION: u256 = 1_000_000_000_000_000_000;
    const MAX_REWARD_TOKENS: u64 = 16;
    const MAX_U64: u64 = 18446744073709551615_u64;

    // ====== Constants =======

    // ====== Error =======

    const E_WRONG_VERSION: u64 = 001;
    const E_INVALID_TYPE: u64 = 100;
    const E_INVALID_VOTER: u64 = 101;
    const E_INSUFFICIENT_VOTES: u64 = 103;
    const E_INSUFFICENT_BALANCE: u64 = 103;
    const E_EMPTY_VALUE: u64 = 104;

    // ====== Error =======

    /// External Bribe, responsible for collecting votes from Vsdb Holder and returning the external bribes ( incentives from protocol ) to the VSDB holder who votes for the pool
    struct ExternalBribe<phantom X, phantom Y> has key, store{
        id: UID,
        /// package version
        version: u64,
        /// total votes the external_bribe collects
        total_votes: u64,
        /// total votes point history, updated when someone cast/ revoke their votes
        supply_checkpoints: TableVec<SupplyCheckpoint>,
        /// casted polls of each Vsdb
        vsdb_votes: Table<ID, u64>,
        /// voting history, updated when someone vote/ revoke their votes
        checkpoints: Table<ID, vector<BalanceCheckpoint>>,
    }

    public fun total_voting_weight<X,Y>(self: &ExternalBribe<X,Y>):u64{ self.total_votes }
    public fun vsdb_votes<X,Y>(self: &ExternalBribe<X,Y>, vsdb: &Vsdb):u64 {
        *table::borrow(&self.vsdb_votes, object::id(vsdb))
    }

    /// Bribe Rewards for each pool, there are 4 types of rewards object at most for each external_bribes
    /// Protocol can bribe a pair of coin types of each pool and addiontal bribes, SDB, SUI
    struct Reward<phantom X, phantom Y, phantom T> has store{
        /// total balance of stored rewards<T>
        balance: Balance<T>,
        /// estimated bribes reward per second in each epoch ( rewards/ 7 days )
        rewards_per_epoch: Table<u64, u64>,
        /// the finished period for each rewards to brib, which is identical with finished time of voting
        period_finish: u64,
        /// last time VSDB claim the rewards
        last_earn: Table<ID, u64>
    }

    // - Reward
    fun new_reward_<X,Y,T>(self: &mut ExternalBribe<X,Y>, ctx: &mut TxContext){
        let reward =  Reward<X,Y,T>{
            balance: balance::zero<T>(),
            rewards_per_epoch: table::new<u64, u64>(ctx),
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

    public fun reward_balance<X,Y,T>(self: &ExternalBribe<X,Y>):u64 {
        let reward = borrow_reward<X,Y,T>(self);
        balance::value(&reward.balance)
    }

    #[test_only]
    public fun get_reward_per_token_stored<X,Y,T>(reward: &Reward<X,Y,T>): &Table<u64, u64>{ &reward.rewards_per_epoch }

    #[test_only]
    public fun get_period_finish<X,Y,T>(reward: &Reward<X,Y,T>): u64{ reward.period_finish }

    // ===== Assertion =====

    public fun assert_generic_type<X,Y,T>(){
        let type_t = type_name::get<T>();
        assert!( type_t == type_name::get<X>() || type_t == type_name::get<Y>() || type_t == type_name::get<SUI>() || type_t == type_name::get<SDB>(), E_INVALID_TYPE);
    }

    // ===== Assertion =====

    /// Bribes will be created along with Gaguge
    public (friend )fun create_bribe<X,Y>(
        ctx: &mut TxContext
    ):ID {
        let bribe = ExternalBribe<X,Y>{
            id: object::new(ctx),
            version: package_version(),
            total_votes:0,
            vsdb_votes: table::new<ID, u64>(ctx),
            supply_checkpoints: table_vec::empty<SupplyCheckpoint>(ctx),

            checkpoints: table::new<ID, vector<BalanceCheckpoint>>(ctx),
        };
        let id = object::id(&bribe);

        // create reward
        let type_x = type_name::get<X>();
        let type_y = type_name::get<Y>();
        let type_sdb = type_name::get<SDB>();
        let type_sui = type_name::get<SUI>();

        new_reward_<X,Y,X>(&mut bribe, ctx);
        new_reward_<X,Y,Y>(&mut bribe, ctx);
        if(type_sui != type_x && type_sui != type_y){
            new_reward_<X,Y,SUI>(&mut bribe, ctx);
        };
        if(type_sdb != type_x && type_sdb != type_y){
            new_reward_<X,Y,SDB>(&mut bribe, ctx);
        };
        transfer::share_object(bribe);
        id
    }

    // ====== GETTER ======

    public fun get_prior_balance_index<X,Y>(
        self: & ExternalBribe<X,Y>,
        vsdb: &Vsdb,
        ts:u64
    ):u64 {
        let id = object::id(vsdb);
        if( !table::contains(&self.checkpoints, id)) return 0;

        let bps = table::borrow(&self.checkpoints, id);
        let len = vec::length(bps);

        if(len == 0){
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
        while (lower < upper){
            _center = upper - (upper - lower) / 2;
            _bp_ts = checkpoints::balance_ts(vec::borrow(bps, _center));
            if(_bp_ts == ts ){
                return _center
            }else if (_bp_ts < ts){
                lower = _center;
            }else{
                upper = _center -1 ;
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
                upper = _center -1 ;
            }
        };
        return lower
    }


    // ====== GETTER ======

    // ====== ENTRY ======
    // ====== ENTRY ======
    // ====== UTILS ======
    fun unix_timestamp(clock: &Clock):u64 { clock::timestamp_ms(clock) / 1000 }
    // ====== UTILS ======
    // ====== LOGIC ======
    // ====== LOGIC ======

    fun bribe_start(ts: u64):u64{
        ts - (ts % DURATION)
    }

    public fun epoch_start(ts: u64):u64{
        let bribe_start = bribe_start(ts);
        let bribe_end = bribe_start + DURATION;
        if( ts < bribe_end){
            return bribe_start
        }else{
            return bribe_end
        }
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
        let supply = self.total_votes;

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
        let ts = unix_timestamp(clock);
        let reward = borrow_reward<X,Y,T>(self);
        if(!table::contains(&self.checkpoints, id) || table::length(&reward.rewards_per_epoch) == 0 ){
            return 0
        };

        let bps = table::borrow(&self.checkpoints, id);
        if(vec::length(bps) == 0) return 0;

        let last_earn = if(table::contains(&reward.last_earn, id)){
            *table::borrow(&reward.last_earn, id)
        }else{
            0
        };

        if(vec::length(bps) == 0) return 0;

        let earned = 0;
        let _supply = 1;
        let _rewards_per_epoch = 0;
        let start_ts = bribe_start(last_earn);
        let idx = get_prior_balance_index(self, vsdb, start_ts);

        let bp = vec::borrow(bps, idx);
        let _bal = checkpoints::balance(bp);
        let _ts = checkpoints::balance_ts(bp);
        start_ts = sui::math::max(start_ts, bribe_start(_ts));
        let num_epoch = (bribe_start(ts) - start_ts) / DURATION;
        if( num_epoch > 0 ){
            let i = 0;
            while( i < num_epoch ){
                idx = get_prior_balance_index(self, vsdb, start_ts + DURATION);
                bp = vec::borrow(bps, idx);
                _bal = checkpoints::balance(bp);
                _ts = checkpoints::balance_ts(bp);
                _supply = checkpoints::supply(table_vec::borrow(&self.supply_checkpoints, get_prior_supply_index(self, start_ts + DURATION)));
                _rewards_per_epoch = if(table::contains(&reward.rewards_per_epoch, start_ts)){
                    *table::borrow(&reward.rewards_per_epoch, start_ts)
                }else {
                    0
                };

                let acc = if(_bal > 0){
                    ((_bal as u128) * (_rewards_per_epoch as u128) / (_supply as u128) as u64)
                }else {
                    0
                };
                earned = earned + acc;

                start_ts = start_ts + DURATION;
                i = i + 1;
            };
        };

        earned

        // let start_idx = get_prior_balance_index(self, vsdb, last_earn);
        // let end_idx = vec::length(bps) - 1;
        // let earned_reward = 0;
        // let pre_reward_bal = 0;
        // let pre_reward_ts = bribe_start(last_earn);
        // let _pre_supply = 1;
        // if(end_idx > 0){
        //     let i = start_idx;
        //     while( i <= end_idx - 1){
        //         let cp_0 = vec::borrow(bps, i);
        //         let _next_epoch_start = bribe_start(checkpoints::balance_ts(cp_0));
        //         // check that you've earned it
        //         // this won't happen until a week has passed
        //         if(_next_epoch_start > pre_reward_ts){
        //             earned_reward = earned_reward + pre_reward_bal;
        //         };

        //         pre_reward_ts = _next_epoch_start;
        //         _pre_supply = checkpoints::supply(table_vec::borrow(&self.supply_checkpoints, get_prior_supply_index(self, _next_epoch_start + DURATION)));

        //         let rewards =  if(table::contains(&reward.rewards_per_epoch, _next_epoch_start)){
        //             *table::borrow(&reward.rewards_per_epoch, _next_epoch_start)
        //         }else{
        //             0
        //         };

        //         pre_reward_bal = (checkpoints::balance(cp_0) as u128) * (rewards as u128) / ((_pre_supply + 1 ) as u128);

        //         i = i + 1;
        //     }
        //         };

        // let cp = vec::borrow(bps, end_idx);
        // let last_epoch_start = sui::math::max(bribe_start(checkpoints::balance_ts(cp)), bribe_start(last_earn));
        // let last_epoch_end = last_epoch_start + DURATION;

        // if(clock::timestamp_ms(clock) / 1000 > last_epoch_end){
        //     let supply = checkpoints::supply(table_vec::borrow(&self.supply_checkpoints, get_prior_supply_index(self, last_epoch_end)));

        //     let rewards =  if(table::contains(&reward.rewards_per_epoch, last_epoch_start)){
        //         *table::borrow(&reward.rewards_per_epoch, last_epoch_start)
        //     }else {
        //         0
        //     };

        //     earned_reward = earned_reward + (checkpoints::balance(cp) as u128) * (rewards as u128) / (supply as u128);
        // };

        // ( earned_reward as u64 )
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
        self.total_votes = self.total_votes + amount;

        if(table::contains(&self.vsdb_votes, id)){
            *table::borrow_mut(&mut self.vsdb_votes, id) = *table::borrow(& self.vsdb_votes, id) + amount;
        }else{
            table::add(&mut self.vsdb_votes, id, amount);
        };

        amount = *table::borrow(&self.vsdb_votes, id);
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
        assert!(table::contains(&self.vsdb_votes, id), E_INVALID_VOTER);
        let supply = self.total_votes;
        let balance = *table::borrow(& self.vsdb_votes, id);
        assert!(supply >= amount, E_INSUFFICENT_BALANCE);
        assert!(balance >= amount, E_INSUFFICIENT_VOTES);

        self.total_votes = self.total_votes - amount;
        *table::borrow_mut(&mut self.vsdb_votes, id) = balance - amount;

        amount = *table::borrow(&self.vsdb_votes, id);
        write_checkpoint_(self, vsdb, amount, clock);
        write_supply_checkpoint_(self, clock);
    }

    public fun left<X,Y, T>(reward: &Reward<X, Y, T>, clock: &Clock):u64{
        let adjusted_ts = epoch_start(clock::timestamp_ms(clock) / 1000);
        if (!table::contains(&reward.rewards_per_epoch, adjusted_ts)){
            0
        }else{
            *table::borrow(&reward.rewards_per_epoch, adjusted_ts)
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
        let adjusted_ts = epoch_start(clock::timestamp_ms(clock) / 1000);
        let epoch_rewards = if(table::contains(&reward.rewards_per_epoch, adjusted_ts)){
            *table::borrow(&reward.rewards_per_epoch, adjusted_ts)
        }else{
            0
        };

        coin::put(&mut reward.balance, coin);
        if(table::contains(&reward.rewards_per_epoch, adjusted_ts)){
            *table::borrow_mut(&mut reward.rewards_per_epoch, adjusted_ts) = epoch_rewards + value;
        }else{
            table::add(&mut reward.rewards_per_epoch, adjusted_ts, epoch_rewards + value);
        };
        reward.period_finish = adjusted_ts + DURATION;

        event::notify_reward<T>(tx_context::sender(ctx), value);
    }
}