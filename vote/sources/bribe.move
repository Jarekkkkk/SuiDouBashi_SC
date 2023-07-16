// External Bribe represent coin brbies from protocol
module suiDouBashi_vote::bribe{
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

    use suiDouBashi_vsdb::vsdb::{Self, Vsdb};
    use suiDouBashi_vsdb::sdb::SDB;
    use suiDouBashi_vote::event;
    use suiDouBashi_vote::checkpoints::{Self, SupplyCheckpoint, BalanceCheckpoint};
    use suiDouBashi_vote::minter::package_version;

    friend suiDouBashi_vote::gauge;
    friend suiDouBashi_vote::voter;

    // ====== Constants =======

    const WEEK: u64 = { 7 * 86400 };
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

    /// Bribe, responsible for collecting votes from Vsdb Holder and returning the bribes ( transaction fees + bribrs from protocol ) to the VSDB holder who votes for the pool
    struct Bribe<phantom X, phantom Y> has key{
        id: UID,
        /// package version
        version: u64,
        /// total votes the bribes collects
        total_votes: u64,
        /// total votes point history, updated when someone cast/ revoke their votes
        supply_checkpoints: TableVec<SupplyCheckpoint>,
        /// casted polls of each Vsdb
        vsdb_votes: Table<ID, u64>,
        /// voting history of each vsdb, updated when someone vote/ revoke their votes
        checkpoints: Table<ID, vector<BalanceCheckpoint>>,
    }

    public fun total_votes<X,Y>(self: &Bribe<X,Y>):u64{ self.total_votes }

    public fun vsdb_votes<X,Y>(self: &Bribe<X,Y>, vsdb: &Vsdb):u64 {
        *table::borrow(&self.vsdb_votes, object::id(vsdb))
    }

    /// Collected Rewards from pool transaction fees & bribes from protocol
    struct Rewards<phantom X, phantom Y> has key{
        id: UID,
        version: u64,
    }

    /// store in dynamic fields to prevent generic type assertion
    struct Reward<phantom X, phantom Y, phantom T> has store{
        /// total balance of stored rewards<T>
        balance: Balance<T>,
        /// estimated bribes reward per second in each epoch ( rewards/ 7 days )
        rewards_per_epoch: Table<u64, u64>,
        /// last time VSDB claim the rewards
        last_earn: Table<ID, u64>
    }

    // - Reward
    fun new_reward_<X,Y,T>(rewards: &mut Rewards<X,Y>, ctx: &mut TxContext){
        let reward =  Reward<X,Y,T>{
            balance: balance::zero<T>(),
            rewards_per_epoch: table::new<u64, u64>(ctx),
            last_earn: table::new<ID, u64>(ctx)
        };
        df::add(&mut rewards.id, type_name::get<T>(), reward);
    }

    public fun borrow_reward<X,Y,T>(rewards: &Rewards<X,Y>):&Reward<X,Y,T>{
        assert_rewards_type<X,Y,T>();
        df::borrow(&rewards.id, type_name::get<T>())
    }

    fun borrow_reward_mut<X,Y,T>(rewards: &mut Rewards<X,Y>):&mut Reward<X, Y, T>{
        assert_rewards_type<X,Y,T>();
        df::borrow_mut(&mut rewards.id, type_name::get<T>())
    }

    public fun reward_balance<X,Y,T>(rewards: &Rewards<X,Y>): u64{
        balance::value(&borrow_reward<X,Y,T>(rewards).balance)
    }

    public fun rewards_per_epoch<X,Y,T>(rewards: &Rewards<X,Y>, ts: u64): u64{
        let ts_ =round_down_week(ts);
        let reward = borrow_reward<X,Y,T>(rewards);

        if(!table::contains(&reward.rewards_per_epoch, ts_)) return 0;
        *table::borrow(&reward.rewards_per_epoch, ts_)
    }

    // ===== Assertion =====

    public fun assert_rewards_type<X,Y,T>(){
        let type_t = type_name::get<T>();
        assert!( type_t == type_name::get<X>()
            || type_t == type_name::get<Y>()
            || type_t == type_name::get<SUI>()
            || type_t == type_name::get<SDB>(), E_INVALID_TYPE
        );
    }

    // ===== Assertion =====

    /// Bribe will be created along with Gaguge
    public (friend )fun new<X,Y>(
        ctx: &mut TxContext
    ):(ID, ID) {
        // bribe
        let bribe = Bribe<X,Y>{
            id: object::new(ctx),
            version: package_version(),
            total_votes:0,
            vsdb_votes: table::new<ID, u64>(ctx),
            supply_checkpoints: table_vec::empty<SupplyCheckpoint>(ctx),

            checkpoints: table::new<ID, vector<BalanceCheckpoint>>(ctx),
        };
        let bribe_id = object::id(&bribe);
        transfer::share_object(bribe);

        // reward
        let type_x = type_name::get<X>();
        let type_y = type_name::get<Y>();
        let type_sdb = type_name::get<SDB>();
        let type_sui = type_name::get<SUI>();

        let rewards = Rewards{
            id: object::new(ctx),
            version: package_version()
        };
        new_reward_<X,Y,X>(&mut rewards, ctx);
        new_reward_<X,Y,Y>(&mut rewards, ctx);
        if(type_sui != type_x && type_sui != type_y){
            new_reward_<X,Y,SUI>(&mut rewards, ctx);
        };
        if(type_sdb != type_x && type_sdb != type_y){
            new_reward_<X,Y,SDB>(&mut rewards, ctx);
        };

        let rewards_id = object::id(&rewards);
        transfer::share_object(rewards);

        (bribe_id, rewards_id)
    }

    // ====== GETTER ======

    public fun get_prior_balance_index<X,Y>(
        self: & Bribe<X,Y>,
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
        self: & Bribe<X,Y>,
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

    public fun earned<X,Y,T>(
        self: &Bribe<X,Y>,
        rewards: &Rewards<X,Y>,
        vsdb: &Vsdb,
        clock: &Clock
    ):u64{
        assert_rewards_type<X,Y,T>();
        let id = object::id(vsdb);
        let ts = unix_timestamp(clock);
        let reward = borrow_reward<X,Y,T>(rewards);
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
        let start_ts = round_down_week(last_earn);
        let idx = get_prior_balance_index(self, vsdb, start_ts);

        let bp = vec::borrow(bps, idx);
        let _bal = checkpoints::balance(bp);
        let _ts = checkpoints::balance_ts(bp);
        start_ts = math::max(start_ts, round_down_week(_ts));
        let num_epoch = (math::min(round_down_week(ts), round_down_week(vsdb::locked_end(vsdb))) - start_ts) / WEEK;
        if( num_epoch > 0 ){
            let i = 0;
            while( i < num_epoch ){
                idx = get_prior_balance_index(self, vsdb, start_ts + WEEK);
                bp = vec::borrow(bps, idx);
                _bal = checkpoints::balance(bp);
                _ts = checkpoints::balance_ts(bp);
                _supply = checkpoints::supply(table_vec::borrow(&self.supply_checkpoints, get_prior_supply_index(self, start_ts + WEEK)));
                _rewards_per_epoch = if(table::contains(&reward.rewards_per_epoch, start_ts)){
                    *table::borrow(&reward.rewards_per_epoch, start_ts)
                }else {
                    0
                };

                if(_bal > 0 && _supply > 0){
                    earned = earned + ((_bal as u128) * (_rewards_per_epoch as u128) / (_supply as u128) as u64);
                };

                start_ts = start_ts + WEEK;
                i = i + 1;
            };
        };

        earned
    }

    // ====== GETTER ======

    // ====== ENTRY ======

    public (friend) fun cast<X,Y>(
        self: &mut Bribe<X,Y>,
        vsdb: &Vsdb,
        amount: u64,
        clock: &Clock
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        assert!(amount > 0, E_EMPTY_VALUE);

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

    public (friend) fun revoke<X,Y>(
        self: &mut Bribe<X,Y>,
        vsdb: &Vsdb,
        amount: u64,
        clock: &Clock
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        assert!(amount > 0, E_EMPTY_VALUE);

        let id = object::id(vsdb);
        assert!(table::contains(&self.vsdb_votes, id), E_INVALID_VOTER);

        let supply = self.total_votes;
        let balance = *table::borrow(& self.vsdb_votes, id);
        assert!(supply >= amount, E_INSUFFICENT_BALANCE);
        assert!(balance >= amount, E_INSUFFICIENT_VOTES);

        self.total_votes = supply - amount;
        *table::borrow_mut(&mut self.vsdb_votes, id) = balance - amount;

        amount = *table::borrow(&self.vsdb_votes, id);
        write_checkpoint_(self, vsdb, amount, clock);
        write_supply_checkpoint_(self, clock);
    }

    /// Allow protoocl deposit the bribes
    public entry fun bribe<X,Y,T>(
        rewards: &mut Rewards<X,Y>,
        coin: Coin<T>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(rewards.version == package_version(), E_WRONG_VERSION);
        assert_rewards_type<X,Y,T>();

        let value = coin::value(&coin);
        let reward = borrow_reward_mut<X,Y,T>(rewards);
        assert!(value > 0, E_EMPTY_VALUE);

        coin::put(&mut reward.balance, coin);

        let epoch_ts = round_down_week(unix_timestamp(clock));
        if(table::contains(&reward.rewards_per_epoch, epoch_ts)){
            *table::borrow_mut(&mut reward.rewards_per_epoch, epoch_ts) = *table::borrow(&reward.rewards_per_epoch, epoch_ts) + value;
        }else{
            table::add(&mut reward.rewards_per_epoch, epoch_ts, value);
        };

        event::notify_reward<T>(tx_context::sender(ctx), value);
    }

    public entry fun get_all_rewards<X,Y>(
        self: &mut Bribe<X,Y>,
        rewards: &mut Rewards<X,Y>,
        vsdb: &Vsdb,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        assert!(rewards.version == package_version(), E_WRONG_VERSION);

        let type_x = type_name::get<X>();
        let type_y = type_name::get<Y>();
        let type_sdb = type_name::get<SDB>();
        let type_sui = type_name::get<SUI>();

        get_reward<X,Y,X>(self, rewards, vsdb, clock, ctx);
        get_reward<X,Y,Y>(self, rewards, vsdb, clock, ctx);
        if(type_sui != type_x && type_sui != type_y){
            get_reward<X,Y,SUI>(self, rewards, vsdb, clock, ctx);
        };
        if(type_sdb != type_x && type_sdb != type_y){
            get_reward<X,Y,SDB>(self, rewards, vsdb, clock, ctx);
        };
    }

    public entry fun get_reward<X, Y, T>(
        self: &mut Bribe<X,Y>,
        rewards: &mut Rewards<X,Y>,
        vsdb: &Vsdb,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        assert!(rewards.version == package_version(), E_WRONG_VERSION);

        assert_rewards_type<X,Y,T>();

        let id = object::id(vsdb);

        let earned = earned<X,Y,T>(self, rewards, vsdb, clock);
        let reward = borrow_reward_mut<X,Y,T>(rewards);

        if(!table::contains(&reward.last_earn, id)){
            table::add(&mut reward.last_earn, id, 0);
        };
        *table::borrow_mut(&mut reward.last_earn, id) = unix_timestamp(clock);

        if(earned > 0){
            transfer::public_transfer(
                coin::take(&mut reward.balance, earned, ctx),
                tx_context::sender(ctx)
            );
            event::claim_reward(tx_context::sender(ctx), earned);
        }
    }

    // ====== ENTRY ======

    // ====== UTILS ======

    fun unix_timestamp(clock: &Clock):u64 { clock::timestamp_ms(clock) / 1000 }

    public fun round_down_week(ts: u64):u64{
        ts / WEEK * WEEK
    }

    // ====== UTILS ======

    // ====== LOGIC ======

    fun write_checkpoint_<X,Y>(
        self: &mut Bribe<X,Y>,
        vsdb: &Vsdb,
        balance: u64,
        clock: &Clock,
    ){
        let id = object::id(vsdb);
        let ts = unix_timestamp(clock);

        if(!table::contains(&self.checkpoints, id)){
            table::add(&mut self.checkpoints, id, vec::empty());
        };

        let bps = table::borrow_mut(&mut self.checkpoints, id);
        let len = vec::length(bps);

        if( len > 0 && round_down_week(checkpoints::balance_ts(vec::borrow(bps, len - 1))) == round_down_week(ts)){
            checkpoints::update_balance(vec::borrow_mut(bps, len - 1), balance);
        }else{
            vec::push_back(bps, checkpoints::new_cp(ts, balance));
        };
    }

    fun write_supply_checkpoint_<X,Y>(
        self: &mut Bribe<X,Y>,
        clock: &Clock,
    ){
        let ts = unix_timestamp(clock);

        let len = table_vec::length(&self.supply_checkpoints);

        if( len > 0 && round_down_week(checkpoints::supply_ts(table_vec::borrow(&self.supply_checkpoints, len - 1))) == round_down_week(ts)){
            checkpoints::update_supply(table_vec::borrow_mut(&mut self.supply_checkpoints, len - 1 ), self.total_votes);
        }else{
            table_vec::push_back(&mut self.supply_checkpoints, checkpoints::new_sp(ts, self.total_votes));
        };
    }

    // ====== LOGIC ======
}