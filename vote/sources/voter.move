/// Admin to govern all the contracts
module suiDouBashi_vote::voter{
    use std::option;
    use std::vector as vec;
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::clock::{Self, Clock};
    use sui::vec_set::{Self, VecSet};
    use sui::vec_map::{Self, VecMap};
    use sui::table::{Self, Table};

    use suiDouBashi_amm::pool::Pool;
    use suiDouBashi_vsdb::vsdb::{Self, Vsdb, VSDBRegistry};
    use suiDouBashi_vsdb::sdb::{SDB};
    use suiDouBashi_vote::gauge::{Self, Gauge};
    use suiDouBashi_vote::event;
    use suiDouBashi_vote::minter::{Self, Minter, package_version};
    use suiDouBashi_vote::bribe::{Self, Bribe, Rewards};

    const DURATION: u64 = { 7 * 86400 };
    const SCALE_FACTOR: u256 = 1_000_000_000_000_000_000; // 1e18

    const E_WRONG_VERSION: u64 = 001;

    const E_EMPTY_VALUE: u64 = 100;
    const E_VOTED: u64 = 101;
    const E_NOT_RESET: u64 = 102;
    const E_NOT_VOTE: u64 = 103;

    struct VoterCap has key { id: UID }

    struct Voter has key, store{
        id: UID,
        version: u64,
        balance: Balance<SDB>,
        total_weight: u64,
        weights: Table<ID, u64>, // pool -> distributed weights
        registry: Table<ID, VecSet<ID>>, // pool -> [gauge, i_bribe, e_bribe]
        index: u256 // distributed_sdb per voting weights ( 1e18 exntension )
    }

    #[test_only] public fun get_index(self: &Voter): u256 { self.index }
    #[test_only] public fun get_balance(self: &Voter): u64 { balance::value(&self.balance)}

    struct VOTER_SDB has copy, store, drop {}

    struct VotingState has store{
        pool_votes: VecMap<ID, u64>, // pool -> voting weight
        voted: bool,
        used_weights: u64,
        last_voted: u64 // ts
    }

    public fun is_initialized(vsdb: &Vsdb): bool{
        vsdb::df_exists(vsdb, VOTER_SDB {})
    }
    public entry fun initialize(reg: &VSDBRegistry, vsdb: &mut Vsdb){
        let value = VotingState{
            pool_votes: vec_map::empty(),
            voted: false,
            used_weights: 0,
            last_voted: 0
        };
        vsdb::df_add(VOTER_SDB{}, reg, vsdb, value);
    }
    public fun clear(vsdb: &mut Vsdb){
        let voting_state:VotingState = vsdb::df_remove( VOTER_SDB{}, vsdb );

        let VotingState{
            pool_votes,
            voted,
            used_weights: _,
            last_voted: _
        } = voting_state;

        assert!(!voted, E_NOT_RESET);
        vec_map::destroy_empty(pool_votes);
    }
    public fun voting_state_borrow(vsdb: &Vsdb):&VotingState{
        vsdb::df_borrow(vsdb, VOTER_SDB {})
    }
    fun voting_state_borrow_mut(vsdb: &mut Vsdb):&mut VotingState{
        vsdb::df_borrow_mut(vsdb, VOTER_SDB {})
    }

    public fun pool_votes(vsdb: &Vsdb):&VecMap<ID, u64>{ &voting_state_borrow(vsdb).pool_votes }

    public fun pool_votes_by_pool(vsdb: &Vsdb, pool_id: &ID):u64 {
        let pool_votes = &voting_state_borrow(vsdb).pool_votes;
        *vec_map::get(pool_votes, pool_id)
    }

    public fun used_weights(vsdb: &Vsdb):u64 { voting_state_borrow(vsdb).used_weights }

    public fun voted(vsdb: &Vsdb):bool { voting_state_borrow(vsdb).voted }

    // POTATO to realize one-time action for one-time action ( voting, reset, poke )
    struct Potato{
        reset: bool,
        weights: VecMap<ID, u64>,
        used_weight: u64,
        total_weight: u64
    }

    // - Getter
    public fun get_total_weight(self: &Voter): u64 { self.total_weight }
    public fun get_weights_by_pool<X,Y>(self:&Voter, pool: &Pool<X,Y>): u64{
        *table::borrow(&self.weights, object::id(pool))
    }

    // TODO: remove
    public fun get_members<X,Y>(self:&Voter, pool: &Pool<X,Y>):vector<ID>{
        let vec_set = *table::borrow(&self.registry, object::id(pool));
        vec_set::into_keys(vec_set)
    }

    public fun get_registry_length(self:&Voter): u64 { table::length(&self.registry) }

    public fun get_pool_exists<X,Y>(self: &Voter, pool: &Pool<X,Y>):bool {
        table::contains(&self.registry, object::id(pool))
    }

    // ===== Entry =====
    fun init(ctx: &mut TxContext){
        let voter = Voter{
            id: object::new(ctx),
            version: package_version(),
            balance: balance::zero<SDB>(),
            total_weight: 0,
            registry: table::new<ID, VecSet<ID>>(ctx),// pool -> (gauge, internal_bribe, external_bribe)
            weights: table::new<ID, u64>(ctx), // pool -> voting_weight
            index: 0
        };
        transfer::share_object(voter);
        transfer::transfer(
            VoterCap{
                id: object::new(ctx),
            },
            tx_context::sender(ctx)
        )
    }

    /// Entrance for voting action
    public fun voting_entry(
        vsdb: &mut Vsdb,
        clock: &Clock,
    ):Potato{
        let voting_state = voting_state_borrow_mut(vsdb);
        assert!((clock::timestamp_ms(clock) / 1000 / DURATION) * DURATION > voting_state.last_voted, E_VOTED);
        voting_state.last_voted = clock::timestamp_ms(clock) / 1000;
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
        vsdb: &mut Vsdb,
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

    public fun poke_entry(
        potato: Potato,
        self: &mut Voter,
        vsdb: &mut Vsdb,
    ):Potato{
        assert!(!potato.reset && potato.total_weight == 0 && vec_map::size(&potato.weights) == 0 , E_NOT_RESET);
        let pool_votes_borrow = &voting_state_borrow(vsdb).pool_votes;
        let pool_ids = vec_map::keys(pool_votes_borrow);

        let weights = vec::empty<u64>();
        let pools = vec::empty<address>();
        let i = 0;
        while( i <  vec_map::size(pool_votes_borrow)){
            let pool_id = vec::borrow(&pool_ids, i);
            vec::push_back( &mut weights, *vec_map::get(pool_votes_borrow, pool_id));
            vec::push_back( &mut pools, object::id_to_address(pool_id));
        };

        vote_entry(potato, self, pools, weights)
    }

    /// Should be called after reset
    public fun vote_entry(
        potato: Potato,
        self: &mut Voter,
        pools: vector<address>,
        weights: vector<u64>,
    ):Potato{
        assert!(potato.total_weight == 0 && vec_map::size(&potato.weights) == 0, E_NOT_RESET);
        assert!(vec::length(&pools) == vec::length(&weights), E_NOT_VOTE );
        self.total_weight = self.total_weight - potato.used_weight;
        let total_weight = 0;

        let (i ,len) = ( 0, vec::length(&weights));
        while( i < len){
            let weight = vec::pop_back(&mut weights);
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
        vsdb: &mut Vsdb,
    ){
        let Potato {
            reset,
            weights,
            used_weight,
            total_weight: _
        } = potato;
        assert!(reset && vec_map::size(&weights) == 0, E_NOT_VOTE);

        vsdb::earn_xp(VOTER_SDB{}, vsdb, 6);
        let voting_state_mut = voting_state_borrow_mut(vsdb);

        voting_state_mut.used_weights = used_weight;
        voting_state_mut.voted = true;
        self.total_weight = self.total_weight + used_weight;
    }

    /// Be called in programmable tx
    public fun reset_<X,Y>(
        potato: Potato,
        self: &mut Voter,
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

            update_for(self, gauge);

            *table::borrow_mut(&mut self.weights, pool_id) = *table::borrow(&self.weights, pool_id) - pool_weight;

            bribe::revoke<X,Y>(bribe, vsdb, pool_weight, clock);

            event::abstain<X,Y>(object::id(vsdb), pool_weight);

            potato.used_weight = potato.used_weight + pool_weight;
        };

        potato
    }

    public fun vote_<X,Y>(
        potato: Potato,
        self: &mut Voter,
        vsdb: &mut Vsdb,
        gauge: &mut Gauge<X,Y>,
        bribe: &mut Bribe<X,Y>,
        clock: &Clock,
    ): Potato{
        assert!(self.version == package_version(), E_WRONG_VERSION);
        assert!(potato.reset, E_NOT_VOTE);
        let pool_id = gauge::pool_id(gauge);

        if(vec_map::contains(&potato.weights, &pool_id)){
            let (_, weights) = vec_map::remove(&mut potato.weights, &gauge::pool_id(gauge));

            assert!(weights > 0, E_NOT_VOTE);
            let player_weight = vsdb::voting_weight(vsdb, clock);
            let pool_weight = ((weights as u128) * (player_weight as u128) / (potato.total_weight as u128) as u64);
            assert!(pool_weight > 0, E_EMPTY_VALUE);
            update_for(self, gauge);

            let voting_state_mut = voting_state_borrow_mut(vsdb);
            vec_map::insert(&mut voting_state_mut.pool_votes, pool_id, pool_weight);
            *table::borrow_mut(&mut self.weights, pool_id) = *table::borrow(&self.weights, pool_id) + pool_weight;

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
        let (gauge, in_bribe, ex_bribe) = gauge::new(pool, ctx);
        let gauge_id = object::id(&gauge);
        let created = vec_set::singleton(gauge_id);
        vec_set::insert(&mut created, in_bribe);
        vec_set::insert(&mut created, ex_bribe);

        table::add(&mut self.registry, object::id(pool), created);
        table::add(&mut self.weights, object::id(pool), 0);

        update_for(self, &mut gauge);

        transfer::public_share_object(gauge);

        event::gauge_created<X,Y>(object::id(pool), gauge_id, in_bribe, ex_bribe);
    }

    entry fun update_gauge_is_alive<X,Y>(
        _cap: &VoterCap,
        gauge: &mut Gauge<X,Y>,
        is_alive: bool
    ){
        gauge::update_gauge(gauge, is_alive);
    }

    /// weekly minted SDB to incentivize pools --> LP_Staker
    public entry fun claim_rewards<X,Y>(
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
        distribute(self, minter, gauge, rewards, pool, vsdb_reg, clock, ctx);
        gauge::get_reward<X,Y>(gauge, clock, ctx);
    }

    /// External Bribe --> voter
    public entry fun claim_bribes<X,Y>(
        bribe: &mut Bribe<X,Y>,
        rewards: &mut Rewards<X,Y>,
        vsdb: &Vsdb,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        bribe::get_all_rewards<X,Y>(bribe, rewards, vsdb, clock, ctx);
    }

    // collect Fees from Pool
    public entry fun distribute_fees<X,Y>(
        gauge: &mut Gauge<X,Y>,
        rewards: &mut Rewards<X,Y>,
        pool: &mut Pool<X,Y>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        gauge::claim_fee(gauge, rewards, pool, clock, ctx);
    }

    /// Voted Gauge
    public fun distribute<X,Y>(
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
            notify_reward_amount_(self , option::extract(&mut coin_option))
        };
        option::destroy_none(coin_option);

        update_for(self, gauge);

        let claimable = gauge::get_claimable(gauge);
        if(claimable > gauge::left(gauge::borrow_reward<X,Y>(gauge), clock) && claimable / DURATION > 0){
            gauge::update_claimable(gauge, 0);
            let coin_sdb = coin::take(&mut self.balance, claimable, ctx);

            gauge::distribute_emissions<X,Y>(gauge, rewards, pool, coin_sdb, clock, ctx);

            event::distribute_reward<X,Y>(tx_context::sender(ctx), claimable);
        }
    }

    public fun update_for<X,Y>(self: &Voter, gauge: &mut Gauge<X,Y>){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        let gauge_weights = *table::borrow(&self.weights, gauge::pool_id(gauge));
        if(gauge_weights > 0){
            let s_idx = gauge::get_supply_index(gauge);
            let index_ = self.index;

            let delta = index_ - s_idx;
            if(delta > 0){
                let share = (gauge_weights as u256) * (delta as u256) / SCALE_FACTOR;
                if(gauge::is_alive(gauge)){
                    let updated = (share as u64) + gauge::get_claimable(gauge);
                    gauge::update_claimable(gauge, updated);
                }
            };
        };
        gauge::update_supply_index(gauge, self.index);
    }

    public fun notify_reward_amount_(self: &mut Voter, sdb: Coin<SDB>){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        let value = coin::value(&sdb);
        let ratio = (value as u256) * SCALE_FACTOR / (self.total_weight as u256) ;
        if(ratio > 0){
            self.index = self.index + (ratio as u256);
        };
        coin::put(&mut self.balance, sdb);

        event::voter_notify_reward(value);
    }

     #[test_only]
     public fun init_for_testing(ctx: &mut TxContext){
        init(ctx);
     }
}