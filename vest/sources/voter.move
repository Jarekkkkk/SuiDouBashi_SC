/// Admin to govern all the contracts
module suiDouBashiVest::voter{
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

    use suiDouBashi::pool::Pool;

    use suiDouBashiVest::vsdb::{Self, VSDB, VSDBRegistry};
    use suiDouBashiVest::sdb::{SDB};
    use suiDouBashiVest::gauge::{Self, Gauge};
    use suiDouBashiVest::event;
    use suiDouBashiVest::err;
    use suiDouBashiVest::minter::{Self, Minter};
    use suiDouBashiVest::reward_distributor::Distributor;
    use suiDouBashiVest::internal_bribe::{Self, InternalBribe};
    use suiDouBashiVest::external_bribe::{Self, ExternalBribe};

    const DURATION: u64 = { 7 * 86400 };
    const SCALE_FACTOR: u256 = 1_000_000_000_000_000_000; // 10e18

    const E_EMPTY_VALUE: u64 = 0;
    const E_NOT_RESET: u64 = 1;
    const E_NOT_VOTE: u64 = 2;

    /// OTW is not allowed to own drop attribution
    struct VOTER_SDB has store, drop {}

    struct Voter has key, store{
        id: UID,
        witness: VOTER_SDB, // stand for witness & capability
        balance: Balance<SDB>,

        governor: address,
        emergency: address,

        total_weight: u64, // always <= total_minted
        weights: Table<ID, u64>, // gauge -> distributed weights
        registry: Table<ID, VecSet<ID>>, // pool -> [gauge, i_bribe, e_bribe]: for front_end fetching

        index: u256 // distributed_sdb per voting weights ( 1e18 exntension )
    }
    #[test_only] public fun get_index(self: &Voter): u256 { self.index }
    #[test_only] public fun get_balance(self: &Voter): u64 { balance::value(&self.balance)}

    // TODO: seperate Fields in VSDB
    struct VotingState has store{
        attachments: u64,
        voted: bool,
        pool_votes: VecMap<ID, u64>, // pool -> voting weight
        used_weights: u64,
        last_voted: u64 // ts
    }
    /// HOT POTATO to realize the functionality of calling multiple tx at once
    struct Potato{
        reset: bool,
        weights: VecMap<ID, u64>,
        used_weight: u64,
        /// distinguished from voting function
        total_weight: u64
    }

    // assertion
    fun assert_new_epoch(vsdb: &VSDB, clock: &Clock){
        assert!((clock::timestamp_ms(clock) / DURATION) * DURATION > vsdb::last_voted(vsdb), err::already_voted());
    }
    fun assert_governor(self: &Voter, ctx: &mut TxContext){
        assert!(self.governor == tx_context::sender(ctx), err::invalid_governor());
    }
    fun assert_emergency(self: &Voter, ctx: &mut TxContext){
        assert!(self.emergency == tx_context::sender(ctx), err::invalid_emergency());
    }

    // - Getter
    public fun get_governor(self: &Voter): address { self.governor }
    public fun get_emergency(self: &Voter): address { self.emergency}
    public fun get_total_weight(self: &Voter): u64 { self.total_weight }
    public fun get_weights_by_pool<X,Y>(self:&Voter, pool: &Pool<X,Y>): u64{
        *table::borrow(&self.weights, object::id(pool))
    }

    // TODO: remove
    public fun get_gauge_and_bribes_by_pool<X,Y>(self:&Voter, pool: &Pool<X,Y>):VecSet<ID>{
        *table::borrow(&self.registry, object::id(pool))
    }
    public fun get_registry_length(self:&Voter): u64 { table::length(&self.registry) }
    public fun get_pool_exists<X,Y>(self: &Voter, pool: &Pool<X,Y>):bool {
        table::contains(&self.registry, object::id(pool))
    }

    // ===== Entry =====
    fun init(ctx: &mut TxContext){
        let sender = tx_context::sender(ctx);
        let voter = Voter{
            id: object::new(ctx),
            witness: VOTER_SDB{},
            balance: balance::zero<SDB>(),
            governor: sender,
            emergency: sender,
            total_weight: 0,
            registry: table::new<ID, VecSet<ID>>(ctx),// pool -> (gauge, internal_bribe, external_bribe)
            weights: table::new<ID, u64>(ctx), // pool -> voting_weight
            index: 0
        };
        transfer::share_object(voter);
    }

    /// Entrance for voting action
    public fun voting_entry(
        vsdb: &mut VSDB,
        clock: &Clock,
    ):Potato{
        assert_new_epoch(vsdb, clock);
        vsdb::update_last_voted(vsdb, clock::timestamp_ms(clock));

        let weights = vec_map::empty<ID, u64>();
        let ( i, len ) = ( 0, vsdb::pool_votes_length(vsdb) );

        // TODO: copy or loop ?
        while( i < len ){
            let (pool_id, value ) = vsdb::clear_pool_votes(vsdb, i);
            vec_map::insert(&mut weights, pool_id, value);
            i = i + 1;
        };
        // successfully clean the vec_map in vsdb
        assert!(vec_map::size(vsdb::pool_votes_borrow(vsdb)) == 0, E_NOT_RESET);

        Potato{
            reset: false,
            weights,
            used_weight: 0,
            total_weight: 0
        }
    }
    public fun reset_exit(
        potato: Potato,
        self: &mut Voter,
        vsdb: &mut VSDB,
    ){
        let Potato {
            reset,
            weights,
            used_weight,
            total_weight
        } = potato;

        assert!(!reset && total_weight == 0 && vec_map::size(&weights) == 0 , E_NOT_RESET);

        vsdb::update_used_weights(vsdb, 0);
        self.total_weight = self.total_weight - used_weight;
        vsdb::abstain(vsdb);
    }

    /// Be called in multiple function
    public fun reset_<X,Y>(
        potato: Potato,
        self: &mut Voter,
        vsdb: &mut VSDB,
        gauge: &mut Gauge<X,Y>,
        internal_bribe: &mut InternalBribe<X,Y>,
        external_bribe: &mut ExternalBribe<X,Y>,
        clock: &Clock,
        ctx: &mut TxContext
    ):Potato{
        assert!(!potato.reset, E_NOT_RESET);
        let pool_id = gauge::pool_id(gauge);
        // Potato to verify reset function
        if(vec_map::contains(&potato.weights, &pool_id) && potato.total_weight == 0){
            let ( pool_id, pool_weight ) = vec_map::remove(&mut potato.weights, &pool_id);

            assert!(pool_weight > 0, E_NOT_RESET);

            update_for_(self, gauge);

            *table::borrow_mut(&mut self.weights, pool_id) = *table::borrow(&self.weights, pool_id) - pool_weight;

            internal_bribe::withdraw<X,Y>(internal_bribe, vsdb, pool_weight, clock, ctx);
            external_bribe::withdraw<X,Y>(external_bribe, vsdb, pool_weight, clock, ctx);

            event::abstain<X,Y>(object::id(vsdb), pool_weight);

            potato.used_weight = potato.used_weight + pool_weight;
        };

        potato
    }

    public fun poke_entry(
        potato: Potato,
        vsdb: &mut VSDB,
    ):Potato{
        assert!(!potato.reset && potato.total_weight == 0 && vec_map::size(&potato.weights) == 0 , E_NOT_RESET);
        let pool_votes_borrow = vsdb::pool_votes_borrow(vsdb);
        let pool_ids = vec_map::keys(pool_votes_borrow);

        let weights = vec::empty<u64>();
        let pools = vec::empty<address>();
        let i = 0;
        while( i <  vec_map::size(pool_votes_borrow)){
            let pool_id = vec::borrow(&pool_ids, i);
            vec::push_back( &mut weights, vsdb::pool_votes(vsdb, pool_id));
            vec::push_back( &mut pools, object::id_to_address(pool_id));
        };

        vote_entry(potato, pools, weights)
    }

    public fun vote_<X,Y>(
        potato: Potato,
        self: &mut Voter,
        vsdb: &mut VSDB,
        gauge: &mut Gauge<X,Y>,
        internal_bribe: &mut InternalBribe<X,Y>,
        external_bribe: &mut ExternalBribe<X,Y>,
        clock: &Clock,
        ctx: &mut TxContext
    ): Potato{
        assert!(potato.reset, E_NOT_VOTE);
        // index weights by given gauge
        let pool_id = gauge::pool_id(gauge);

        if(vec_map::contains(&potato.weights, &pool_id)){
            let (_, weights) = vec_map::remove(&mut potato.weights, &gauge::pool_id(gauge));

            assert!(weights > 0, E_NOT_VOTE);
            let player_weight = vsdb::latest_voting_weight(vsdb, clock);

            let pool_weight = ((weights as u128) * (player_weight as u128) / (potato.total_weight as u128) as u64); // get the pro rata voting weight
            assert!(pool_weight > 0, err::invalid_weight());

            update_for_(self, gauge);

            // add vec_map entry
            vsdb::add_pool_votes(vsdb, pool_id, pool_weight);
            *table::borrow_mut(&mut self.weights, pool_id) = *table::borrow(&self.weights, pool_id) + pool_weight;

            // vote for voting power
            internal_bribe::deposit<X,Y>(internal_bribe, vsdb, pool_weight, clock, ctx);
            external_bribe::deposit<X,Y>(external_bribe, vsdb, pool_weight, clock, ctx);

            potato.used_weight = potato.used_weight + pool_weight;

            event::voted<X,Y>(object::id(vsdb), pool_weight);
        };
        potato
    }

    /// Should be called after reset
    public fun vote_entry(
        potato: Potato,
        pools: vector<address>,
        weights: vector<u64>,
    ):Potato{
        assert!(potato.total_weight == 0 && vec_map::size(&potato.weights) == 0 , E_NOT_RESET);
        assert!(vec::length(&pools) == vec::length(&weights), E_NOT_VOTE );

        let total_weight = 0;

        let i = 0;
        while( i < vec::length(&weights)){
            let weight = vec::pop_back(&mut weights);
            let pool = vec::pop_back(&mut pools);
            total_weight = total_weight + weight;
            vec_map::insert(&mut potato.weights, object::id_from_address(pool), weight);
        };

        potato.used_weight = 0;
        potato.total_weight = total_weight;
        potato.reset = true;

        potato
    }
    public fun vote_exit(
        potato: Potato,
        self: &mut Voter,
        vsdb: &mut VSDB,
    ){
        let Potato {
            reset,
            weights,
            used_weight,
            total_weight: _
        } = potato;
        assert!(reset && vec_map::size(&weights) == 0 , E_NOT_VOTE);

        vsdb::update_used_weights(vsdb, used_weight);
        self.total_weight = self.total_weight + used_weight;

        vsdb::voting(vsdb);

        vsdb::update_used_weights(vsdb, used_weight);
    }

    // - Gauge
    public entry fun create_gauge<X,Y>(self: &mut Voter, pool: &Pool<X,Y>, ctx: &mut TxContext){
        assert_governor(self, ctx);

        let (gauge, in_bribe, ex_bribe) = gauge::new(pool, ctx);
        let gauge_id = object::id(&gauge);
        let created = vec_set::singleton(gauge_id);
        vec_set::insert(&mut created, in_bribe);
        vec_set::insert(&mut created, ex_bribe);

        table::add(&mut self.registry, object::id(pool), created);
        table::add(&mut self.weights, object::id(pool), 0);

        update_for_(self, &mut gauge);

        transfer::public_share_object(gauge);

        event::gauge_created<X,Y>(object::id(pool), gauge_id, in_bribe, ex_bribe);
    }
    entry fun kill_gauge<X,Y>(self: &Voter, gauge: &mut Gauge<X,Y>, ctx: &mut TxContext){
        assert_emergency(self, ctx);
        assert!(gauge::is_alive(gauge), err::dead_gauge());
        gauge::kill_gauge_(gauge);
    }
    entry fun revive_gauge<X,Y>(self: &Voter, gauge: &mut Gauge<X,Y>, ctx: &mut TxContext){
        assert_emergency(self, ctx);
        gauge::revive_gauge_(gauge);
    }

    // - Governor
    entry fun set_governor(self: &mut Voter, new_gov: address, ctx: &mut TxContext){
        assert_governor(self, ctx);
        self.governor = new_gov;
    }
    entry fun set_emergency(self: &mut Voter, new_emergency: address, ctx: &mut TxContext){
        assert_emergency(self, ctx);
        self.emergency = new_emergency;
    }

    // - Rewards
    /// weekly minted SDB to incentivize pools --> LP_Staker
    public entry fun claim_rewards<X,Y>(
        self: &mut Voter,
        minter: &mut Minter,
        distributor: &mut Distributor,
        gauge: &mut Gauge<X,Y>,
        internal_bribe: &mut InternalBribe<X,Y>,
        pool: &mut Pool<X,Y>,
        vsdb_reg: &mut VSDBRegistry,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        distribute(self, minter, distributor, gauge, internal_bribe, pool, vsdb_reg, clock, ctx);
        // Guage collect SDB weekly emission
        gauge::get_reward<X,Y>(gauge, clock, ctx);
    }

    /// External Bribe --> voter
    entry fun claim_bribes<X,Y, T>(
        external_bribe: &mut ExternalBribe<X,Y>,
        vsdb: &VSDB,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        // external
        external_bribe::get_reward<X,Y,T>(external_bribe, vsdb, clock, ctx);
    }

    /// Internal Bribe --> voter
    entry fun claim_fees<X,Y, T>(
        internal_bribe: &mut InternalBribe<X,Y>,
        vsdb: &VSDB,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        internal_bribe::get_reward<X,Y,T>(internal_bribe, vsdb, clock, ctx);
    }

    // collect Fees from Pool
    entry fun distribute_fees<X,Y>(
        gauge: &mut Gauge<X,Y>,
        internal_bribe: &mut InternalBribe<X,Y>,
        pool: &mut Pool<X,Y>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        gauge::claim_fee(gauge, internal_bribe, pool, clock, ctx);
    }

    // TODO: remove public
    /// distribute weekly emission
    public fun distribute<X,Y>(
        self: &mut Voter,
        minter: &mut Minter,
        distributor: &mut Distributor,
        gauge: &mut Gauge<X,Y>,
        internal_bribe: &mut InternalBribe<X,Y>,
        pool: &mut Pool<X,Y>,
        vsdb_reg: &mut VSDBRegistry,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        let coin_option = minter::update_period(minter, distributor, vsdb_reg, clock, ctx);
        if(option::is_some(&coin_option)){
            notify_reward_amount_(self , option::extract(&mut coin_option))
        };
        option::destroy_none(coin_option);

        update_for_(self, gauge);

        let claimable = gauge::get_claimable(gauge);
        if( claimable > gauge::left(gauge::borrow_reward<X,Y>(gauge), clock) && claimable / DURATION > 0 ){
            gauge::update_claimable(gauge, 0);
            // deposit the rebase to gauge
            let coin_sdb = coin::take(&mut self.balance, claimable, ctx);

            gauge::distribute_emissions<X,Y>(gauge, internal_bribe, pool, coin_sdb, clock, ctx);

            event::distribute_reward<X,Y>(tx_context::sender(ctx), claimable);
        }
    }

    // ===== Internal =====
    // TODO: remove public
    /// update gauge's index to check if there's any distributed emissions
    public fun update_for_<X,Y>(self: &Voter, gauge: &mut Gauge<X,Y>){
        let gauge_weights = *table::borrow(&self.weights, gauge::pool_id(gauge));
        if(gauge_weights > 0){
            let s_idx = gauge::get_supply_index(gauge);
            let index_ = self.index;
            gauge::update_supply_index(gauge, index_);

            let delta = index_ - s_idx;
            if(delta > 0){
                let share = (gauge_weights as u256) * (delta as u256) / SCALE_FACTOR;// add accrued difference for each supplied token
                if(gauge::is_alive(gauge)){
                    let updated = (share as u64) + gauge::get_claimable(gauge);
                    gauge::update_claimable(gauge, updated);
                }
            };
        }else{
            // new gauge set to global state
            gauge::update_supply_index(gauge, self.index);
        };
    }

    /// update self.index by given weekly emissions
    public fun notify_reward_amount_(self: &mut Voter, sdb: Coin<SDB>){
        // update global index
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