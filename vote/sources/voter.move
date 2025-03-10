/// Admin to govern all the contracts
module suiDouBashi_vote::voter{
    use std::option;
    use std::vector as vec;
    use std::type_name::{Self, TypeName};

    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::clock::{Self, Clock};
    use sui::vec_set::{Self, VecSet};
    use sui::vec_map::{Self, VecMap};
    use sui::table::{Self, Table};

    use suiDouBashi_vsdb::vsdb::{Self, Vsdb, VSDBRegistry};
    use suiDouBashi_vsdb::sdb::{SDB};
    use suiDouBashi_amm::pool::Pool;
    use suiDouBashi_vote::gauge::{Self, Gauge, Stake};
    use suiDouBashi_vote::event;
    use suiDouBashi_vote::minter::{Self, Minter, package_version};
    use suiDouBashi_vote::bribe::{Self, Bribe, Rewards};

    // ====== Constants =======

    const WEEK: u64 = { 7 * 86400 };
    const HOUR: u64 = 3600;
    const PRECISION: u256 = 1_000_000_000_000_000_000;
    const SCALING: u64 = 10000;


    // ====== Constants =======

    // ====== Error =======

    const E_WRONG_VERSION: u64 = 001;
    const E_EMPTY_VALUE: u64 = 100;
    const E_VOTED: u64 = 101;
    const E_NOT_RESET: u64 = 102;
    const E_NOT_VOTE: u64 = 103;
    const E_INVALID_VOTING_DURATOIN: u64 = 104;
    const E_DEAD_GAUGE: u64 = 105;
    const E_ALIVE_GAUGE: u64 = 106;

    // ====== Error =======

    // ===== Assertion =====

    fun assert_available_voting( ts: u64 ){
        assert!(ts >= vote_start(ts) && ts <= vote_end(ts), E_INVALID_VOTING_DURATOIN)
    }

    // ===== Assertion =====

    /// Capability of Voter package
    struct VoterCap has key { id: UID }

    /// Voter shared obj takes care of collecting weekly votes & distributing weeklu SDB emissions
    struct Voter has key, store{
        id: UID,
        /// package version
        version: u64,
        /// balance of Coin SDB
        balance: Balance<SDB>,
        /// total collected voting weights
        total_weight: u64,
        /// voted weights for each pool
        pool_weights: Table<ID, u64>,
        /// registered members [gauge, bribe, rewards] for each pool
        registry: Table<ID, ID>,
        /// accumulating distribution of weekly SDB emissions
        index: u256
    }

    public fun index(self: &Voter): u256 { self.index }

    public fun sdb_balance(self: &Voter): u64 { balance::value(&self.balance) }

    /// Key to VSDB dynamic fields
    struct VSDB has drop {}

    struct VotingState has drop, store{
        /// voted pools & amount of votes
        pool_votes: VecMap<ID, u64>,
        /// determine whether NFT is voted
        voted: bool,
        /// used weights for voting
        used_weights: u64,
        /// last time VSDB votes
        last_voted: u64,
        /// unclaimed rewards & its corresponding types
        unclaimed_rewards: VecMap<ID, VecSet<TypeName>>
    }

    public fun is_initialized(vsdb: &Vsdb): bool{
        vsdb::df_exists(vsdb, VSDB{})
    }

    public entry fun initialize(reg: &VSDBRegistry, vsdb: &mut Vsdb){
        let value = VotingState{
            pool_votes: vec_map::empty(),
            voted: false,
            used_weights: 0,
            last_voted: 0,
            unclaimed_rewards: vec_map::empty<ID, VecSet<TypeName>>()
        };
        vsdb::df_add(VSDB{}, reg, vsdb, value);
    }

    public fun clear(vsdb: &mut Vsdb){
        let voting_state:VotingState = vsdb::df_remove(VSDB{}, vsdb);
        let VotingState{
            pool_votes,
            voted,
            used_weights: _,
            last_voted: _,
            unclaimed_rewards: _
        } = voting_state;
        assert!(!voted, E_NOT_RESET);
        vec_map::destroy_empty(pool_votes);
    }

    public fun voting_state_borrow(vsdb: &Vsdb):&VotingState{
        vsdb::df_borrow(vsdb, VSDB {})
    }

    fun voting_state_borrow_mut(vsdb: &mut Vsdb):&mut VotingState{
        vsdb::df_borrow_mut(vsdb, VSDB {})
    }

    public fun pool_votes(vsdb: &Vsdb, pool_id: &ID):u64 {
        let pool_votes = &voting_state_borrow(vsdb).pool_votes;
        let pool_opt = vec_map::try_get(pool_votes, pool_id);
        if(option::is_some(&pool_opt)){
            option::destroy_some(pool_opt)
        }else{
            option::destroy_none(pool_opt);
            0
        }
    }

    public fun voted(vsdb: &Vsdb): bool{ voting_state_borrow(vsdb).voted }

    public fun used_weights(vsdb: &Vsdb): u64{ voting_state_borrow(vsdb).used_weights }

    public fun last_voted(vsdb: &Vsdb): u64{ voting_state_borrow(vsdb).last_voted }

    // POTATO to realize one-time action ( voting, reset )
    struct Potato{
        reset: bool,
        weights: VecMap<ID, u64>,
        used_weight: u64,
        total_weight: u64
    }

    public fun total_weight(self: &Voter):u64 { self.total_weight }

    public fun pool_weights<X,Y>(self:&Voter, pool: &Pool<X,Y>): u64{
        *table::borrow(&self.pool_weights, object::id(pool))
    }

    // public fun registry_members<X,Y>(self:&Voter, pool: &Pool<X,Y>):vector<ID>{
    //     let vec_set = *table::borrow(&self.registry, object::id(pool));
    //     vec_set::into_keys(vec_set)
    // }

    public fun is_registry<X,Y>(self: &Voter, pool: &Pool<X,Y>):bool {
        table::contains(&self.registry, object::id(pool))
    }

    // ===== Entry =====

    fun init(ctx: &mut TxContext){
        let voter = Voter{
            id: object::new(ctx),
            version: package_version(),
            balance: balance::zero<SDB>(),
            total_weight: 0,
            registry: table::new<ID, ID>(ctx),
            pool_weights: table::new<ID, u64>(ctx),
            index: 0
        };
        transfer::share_object(voter);
        transfer::transfer(
            VoterCap{ id: object::new(ctx) },
            tx_context::sender(ctx)
        );
    }

    /// Entrance for voting action
    public fun voting_entry(
        vsdb: &mut Vsdb,
        clock: &Clock
    ):Potato{
        let ts = unix_timestamp(clock);

        assert_available_voting(ts);
        let voting_state = voting_state_borrow_mut(vsdb);
        assert!((ts/ WEEK) * WEEK > voting_state.last_voted, E_VOTED);
        voting_state.last_voted = ts;
        // copy and clear pool_votes fields
        let weights = voting_state.pool_votes;
        voting_state.pool_votes = vec_map::empty<ID, u64>();

        Potato{
            reset: false,
            weights,
            used_weight: 0,
            total_weight: 0
        }
    }

    /// Exit for reset action
    public fun reset_exit(
        potato: Potato,
        self: &mut Voter,
        vsdb: &mut Vsdb
    ){
        let voting_state = voting_state_borrow_mut(vsdb);
        let Potato {
            reset,
            weights,
            used_weight,
            total_weight
        } = potato;

        assert!(!reset && total_weight == 0 && vec_map::size(&weights) == 0 , E_NOT_RESET);

        voting_state.used_weights = 0;
        voting_state.voted = false;

        self.total_weight = self.total_weight - used_weight;
    }

    /// Should be called after reset
    public fun vote_entry(
        potato: Potato,
        self: &mut Voter,
        vsdb: &Vsdb,
        pools: vector<address>,
        weights: vector<u64>
    ):Potato{
        assert!(potato.total_weight == 0 && vec_map::size(&potato.weights) == 0, E_NOT_RESET);
        assert!(vec::length(&pools) == vec::length(&weights), E_NOT_VOTE);
        self.total_weight = self.total_weight - potato.used_weight;
        let total_weight = 0;

        let (i, len) = (0, vec::length(&weights));
        while(i < len){
            let weight = vec::pop_back(&mut weights);
            weight = weight + weight * (vsdb::level(vsdb) % 2 as u64)/ SCALING;
            let pool = vec::pop_back(&mut pools);
            total_weight = total_weight + weight;
            vec_map::insert(&mut potato.weights, object::id_from_address(pool), weight);
            i = i + 1;
        };

        potato.used_weight = 0;
        potato.total_weight = total_weight;
        potato.reset = true;

        potato
    }

    public fun vote_exit(
        potato: Potato,
        self: &mut Voter,
        vsdb: &mut Vsdb
    ){
        let Potato {
            reset,
            weights,
            used_weight,
            total_weight: _
        } = potato;
        assert!(reset && vec_map::size(&weights) == 0, E_NOT_VOTE);

        vsdb::earn_xp(VSDB{}, vsdb, 10);
        let voting_state = voting_state_borrow_mut(vsdb);

        voting_state.used_weights = used_weight;
        voting_state.voted = true;
        self.total_weight = self.total_weight + used_weight;
    }

    /// Be called in programmable tx
    public fun reset_<X,Y>(
        potato: Potato,
        self: &mut Voter,
        minter: &mut Minter,
        vsdb: &mut Vsdb,
        gauge: &mut Gauge<X,Y>,
        bribe: &mut Bribe<X,Y>,
        clock: &Clock
    ):Potato{
        assert!(self.version == package_version(), E_WRONG_VERSION);

        assert!(!potato.reset, E_NOT_RESET);
        let pool_id = gauge::pool_id(gauge);
        if(vec_map::contains(&potato.weights, &pool_id) && potato.total_weight == 0){
            let ( pool_id, pool_weight ) = vec_map::remove(&mut potato.weights, &pool_id);

            assert!(pool_weight > 0, E_NOT_RESET);

            update_for(self, gauge, minter);

            *table::borrow_mut(&mut self.pool_weights, pool_id) = *table::borrow(&self.pool_weights, pool_id) - pool_weight;

            bribe::revoke<X,Y>(bribe, vsdb, pool_weight, clock);

            event::abstain<X,Y>(object::id(vsdb), pool_weight);

            potato.used_weight = potato.used_weight + pool_weight;
        };

        potato
    }

    public fun vote_<X,Y>(
        potato: Potato,
        self: &mut Voter,
        minter: &mut Minter,
        vsdb: &mut Vsdb,
        gauge: &mut Gauge<X,Y>,
        bribe: &mut Bribe<X,Y>,
        rewards: &Rewards<X,Y>,
        clock: &Clock
    ): Potato{
        assert!(self.version == package_version(), E_WRONG_VERSION);

        assert!(potato.reset, E_NOT_VOTE);
        assert!(gauge::is_alive(gauge), E_DEAD_GAUGE);
        let pool_id = gauge::pool_id(gauge);

        if(vec_map::contains(&potato.weights, &pool_id)){
            let (_, weights) = vec_map::remove(&mut potato.weights, &pool_id);

            assert!(weights > 0, E_NOT_VOTE);
            let pool_weight = ((weights as u256) * (vsdb::voting_weight(vsdb, clock) as u256) / (potato.total_weight as u256) as u64);

            assert!(pool_weight > 0, E_EMPTY_VALUE);
            update_for(self, gauge, minter);

            let voting_state_mut = voting_state_borrow_mut(vsdb);
            vec_map::insert(&mut voting_state_mut.pool_votes, pool_id, pool_weight);
            *table::borrow_mut(&mut self.pool_weights, pool_id) = *table::borrow(&self.pool_weights, pool_id) + pool_weight;

            let rewards_id = gauge::rewards_id(gauge);
            if(vec_map::contains(&voting_state_mut.unclaimed_rewards, &rewards_id)){
               vec_map::remove(&mut voting_state_mut.unclaimed_rewards, &rewards_id);
            };
            vec_map::insert(&mut voting_state_mut.unclaimed_rewards, rewards_id, bribe::rewards_type(rewards));

            bribe::cast<X,Y>(bribe, vsdb, pool_weight, clock);

            potato.used_weight = potato.used_weight + pool_weight;

            event::voted<X,Y>(object::id(vsdb), pool_weight);
        };
        potato
    }

    // - Gauge
    public entry fun create_gauge<X,Y>(
        self: &mut Voter,
        _cap: &VoterCap,
        pool: &Pool<X,Y>,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);

        let gauge= gauge::new(pool, ctx);
        let gauge_id = object::id(&gauge);

        table::add(&mut self.registry, object::id(pool), gauge_id);
        table::add(&mut self.pool_weights, object::id(pool), 0);

        gauge::update_voting_index(&mut gauge, self.index);

        event::gauge_created<X,Y>(object::id(pool), gauge_id, gauge::bribe_id(&gauge), gauge::rewards_id(&gauge));

        transfer::public_share_object(gauge);
    }

    entry public fun kill_gauge<X,Y>(
        _cap: &VoterCap,
        self: &mut Voter,
        gauge: &mut Gauge<X,Y>,
        minter: &mut Minter
    ){
        assert!(gauge::is_alive(gauge), E_DEAD_GAUGE);
        gauge::update_is_alive(gauge, false);
        let claimable = gauge::claimable(gauge);
        if(claimable > 0){
            gauge::update_claimable(gauge, 0);
            minter::join(minter, balance::split(&mut self.balance, claimable));
        };
        gauge::update_is_alive(gauge, false);
    }

    entry public fun revive_gauge<X,Y>(
        _cap: &VoterCap,
        gauge: &mut Gauge<X,Y>
    ){
        assert!(gauge::is_alive(gauge), E_ALIVE_GAUGE);
        gauge::update_is_alive(gauge, true);
    }

    /// create additional types of Bribe Rewards for each Pool
    public entry fun new_reward<X,Y,T>(_: &VoterCap, rewards: &mut Rewards<X,Y>, ctx: &mut TxContext){
        bribe::new_reward_<X,Y,T>(rewards, ctx);
    }

    /// weekly minted SDB to incentivize pools --> LP_Staker
    public entry fun claim_rewards<X,Y>(
        self: &mut Voter,
        gauge: &mut Gauge<X,Y>,
        stake: &mut Stake<X,Y>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);

        gauge::get_reward<X,Y>(gauge, stake, clock, ctx);
    }

    // /// External Bribe --> voter
    // public entry fun claim_bribes<X,Y>(
    //     bribe: &mut Bribe<X,Y>,
    //     rewards: &mut Rewards<X,Y>,
    //     vsdb: &mut Vsdb,
    //     clock: &Clock,
    //     ctx: &mut TxContext
    // ){
    //     bribe::get_all_rewards<X,Y>(bribe, rewards, vsdb, clock, ctx);

    //     let voting_state_mut = voting_state_borrow_mut(vsdb);
    //     let unclaimed_rewards = vec_map::get_mut(&mut voting_state_mut.unclaimed_rewards, &object::id(rewards));
    // }

    public entry fun claim_bribes<X,Y,T>(
        bribe: &mut Bribe<X,Y>,
        rewards: &mut Rewards<X,Y>,
        vsdb: &mut Vsdb,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        bribe::get_reward<X,Y,T>(bribe, rewards, vsdb, clock, ctx);
        let voting_state_mut = voting_state_borrow_mut(vsdb);
        let unclaimed_rewards = vec_map::get_mut(&mut voting_state_mut.unclaimed_rewards, &object::id(rewards));
        vec_set::remove(unclaimed_rewards, &type_name::get<T>());

        if(vec_set::is_empty(unclaimed_rewards)){
            vec_map::remove(&mut voting_state_mut.unclaimed_rewards, &object::id(rewards));
        };
    }

    // ===== Entry =====

    entry public fun distribute<X,Y>(
        self: &mut Voter,
        minter: &mut Minter,
        gauge: &mut Gauge<X,Y>,
        rewards: &mut Rewards<X,Y>,
        pool: &mut Pool<X,Y>,
        vsdb_reg: &mut VSDBRegistry,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);

        let coin_option = minter::update_period(minter, vsdb_reg, clock, ctx);
        if(option::is_some(&coin_option)){
            deposit_sdb(self , option::extract(&mut coin_option))
        };
        option::destroy_none(coin_option);

        update_for(self, gauge, minter);

        let claimable = gauge::claimable(gauge);
        if(claimable > gauge::left(gauge, clock) && claimable > WEEK){
            gauge::update_claimable(gauge, 0);
            let coin_sdb = coin::take(&mut self.balance, claimable, ctx);

            gauge::distribute_emissions<X,Y>(gauge, rewards, pool, coin_sdb, clock, ctx);
        }
    }

    entry public fun update_for<X,Y>(self: &mut Voter, gauge: &mut Gauge<X,Y>, minter: &mut Minter){
        assert!(self.version == package_version(), E_WRONG_VERSION);

        let gauge_weights = *table::borrow(&self.pool_weights, gauge::pool_id(gauge));

        if(gauge_weights > 0){
            let s_idx = gauge::voting_index(gauge);

            let delta = self.index - s_idx;
            if(delta > 0){
                let share = ((gauge_weights as u256) * (delta as u256) / PRECISION as u64);
                if(gauge::is_alive(gauge)){
                    let updated = share + gauge::claimable(gauge);
                    gauge::update_claimable(gauge, updated);
                }else{
                     minter::join(minter, balance::split(&mut self.balance, share));
                }
            };
        };
        gauge::update_voting_index(gauge, self.index);
    }

    entry public fun deposit_sdb(self: &mut Voter, sdb: Coin<SDB>){
        assert!(self.version == package_version(), E_WRONG_VERSION);

        let value = coin::value(&sdb);
        let ratio = (value as u256) * PRECISION / (self.total_weight as u256) ;
        if(ratio > 0){
            self.index = self.index + (ratio as u256);
        };
        coin::put(&mut self.balance, sdb);

        event::notify_reward<SDB>(value);
    }

    // ====== UTILS ======

    public fun unix_timestamp(clock: &Clock):u64 { clock::timestamp_ms(clock) / 1000 }

    public fun round_down_week(ts: u64):u64 { ts / WEEK * WEEK }

    public fun vote_start(ts: u64): u64 { round_down_week(ts) + HOUR }

    public fun vote_end(ts: u64): u64 { round_down_week(ts) + WEEK - HOUR }

    // ====== UTILS ======

    #[test]
    fun test_voting(){
        let ts = 1690349951;
        assert_available_voting(ts);
    }

    #[test]
    #[expected_failure(abort_code = E_INVALID_VOTING_DURATOIN)]
    fun test_err_voting(){
        let ts = 1673913427200;
        assert_available_voting(ts);
    }

     #[test_only]
     public fun init_for_testing(ctx: &mut TxContext){
        init(ctx);
     }
}