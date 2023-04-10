module suiDouBashiVest::voter{
    use std::type_name::{Self, TypeName};
    use std::ascii::String;
    use sui::balance::{Self, Balance, Supply};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::dynamic_object_field as dof;
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::clock::{Self, Clock};
    use sui::math;
    use std::vector as vec;
    use sui::vec_set::{Self, VecSet};
    use sui::table::{Self, Table};

    use suiDouBashi::amm_v1::Pool  ;
    use suiDouBashi::type;

    use suiDouBashiVest::vsdb::{Self, VSDB};
    use suiDouBashiVest::sdb::{Self, SDB};
    use suiDouBashiVest::gauge::{Self, Gauge};
    use suiDouBashiVest::event;
    use suiDouBashiVest::err;
    use suiDouBashiVest::reward::{Self, Reward};
    use suiDouBashiVest::checkpoints::{Self, SupplyCheckpoint, Checkpoint};
    use suiDouBashiVest::internal_bribe::{Self, InternalBribe};

    const DURATION: u64 = { 7 * 86400 };
    const SCALE_FACTOR: u256 = 1_000_000_000_000_000_000; // 10e18

    struct Voter has key, store{
        id: UID,

        governor: address,
        emergency: address,

        total_weight: u64, // enought
        weights: Table<ID, u64>,

        sdb_supply: Supply<SDB>,

        // TODO: vecset will be too expensive ?
        whitelist: VecSet<String>,
        registry: Table<ID, VecSet<ID>>, // registered_pool -> <gauges, Internal_bribe, external_bribe>

        index: u64
    }

    // assertion
    public fun assert_new_epoch(vsdb: &VSDB, clock: &Clock){
        assert!((clock::timestamp_ms(clock) / DURATION) * DURATION > vsdb::last_voted(vsdb), err::already_voted());
    }
    public fun assert_governor(self: &Voter, ctx: &mut TxContext){
        assert!(self.governor == tx_context::sender(ctx), err::invalid_governor());
    }
    public fun assert_emergency(self: &Voter, ctx: &mut TxContext){
        assert!(self.emergency == tx_context::sender(ctx), err::invalid_emergency());
    }
    public fun assert_whitelist<T>(self: &Voter){
        let type = type_name::borrow_string(&type_name::get<T>());
        assert!(vec_set::contains(&self.whitelist, type), err::non_whitelist());
    }

    // ===== Entry =====
    fun init(ctx: &mut TxContext){
        let sender = tx_context::sender(ctx);
        let voter = Voter{
            id: object::new(ctx),
            governor: sender,
            emergency: sender,

            total_weight: 0,

            sdb_supply: sdb::new(ctx),

            whitelist: vec_set::empty<String>(),

            registry: table::new<ID, VecSet<ID>>(ctx),// pool -> (gauge, internal_bribe, external_bribe)
            weights: table::new<ID, u64>(ctx), // pool -> voting_weight

            index: 0
        };

        transfer::share_object(voter);
    }

    // - player
    public entry fun vote(){}
    public entry fun poke(){}
    public entry fun reset(){}

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

        transfer::share_object(gauge);

        event::gauge_created<X,Y>(object::id(pool), gauge_id, in_bribe, ex_bribe);
    }
    entry fun kill_gauge<X,Y>(self: &Voter, gauge: &mut Gauge<X,Y>, ctx: &mut TxContext){
        assert_emergency(self, ctx);
        assert!(gauge::is_alive(gauge), 0);
        gauge::kill_gauge_(gauge);
    }
    entry fun revive_gauge<X,Y>(self: &Voter, gauge: &mut Gauge<X,Y>, ctx: &mut TxContext){
        assert_emergency(self, ctx);
        assert!(!gauge::is_alive(gauge), 0);
        gauge::revive_gauge_(gauge);
    }

    // - Governor
    entry fun set_governor(self: &mut Voter, new_gov: address, ctx: &mut TxContext){
        assert_governor(self, ctx);
        self.governor = new_gov;
    }
    entry fun whitelist<T>( self: &mut Voter, ctx: &mut TxContext){
        assert_governor(self, ctx);
        let type = type_name::into_string(type_name::get<T>());
        vec_set::insert(&mut self.whitelist, type);
    }
    entry fun set_emergency(self: &mut Voter, new_emergency: address, ctx: &mut TxContext){
        assert_governor(self, ctx);
        self.emergency = new_emergency;
    }


    // ===== Internal =====
    /// update for each Gauge
    fun update_for_<X,Y>(self: &Voter, gauge: &mut Gauge<X,Y>){
        let supply = *table::borrow(&self.weights, gauge::pool_id(gauge));

        if(supply > 0){
            let s_idx = gauge::get_supply_index(gauge);
            let index_ = self.index;
            gauge::update_supply_index(gauge, self.index);

            let delta = index_ - s_idx;
            if(delta > 0){
                let share = (supply as u256) * (delta as u256) / SCALE_FACTOR;// add accrued difference for each supplied token
                if(gauge::is_alive(gauge)){
                    let updated = (share as u64) + gauge::get_claimable(gauge);
                    gauge::update_claimable(gauge, updated);
                }
            }
        }else{
            // new gauge set to global state
            gauge::update_supply_index(gauge, self.index);
        };
    }

    // currently we are unable to loop token ads to reset all of the votes in different pool,
    fun vote_<X,Y,T>(
        self: &mut Voter,
        vsdb: &mut VSDB,
        gauge: &mut Gauge<X,Y>,
        internal_bribe: &mut InternalBribe<X,Y>,
        // external_bribe
        weights: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        reset_<X,Y,T>(self, vsdb, gauge, internal_bribe, clock, ctx);
        let pool_id = gauge::pool_id(gauge);


        let player_weight = vsdb::latest_voting_weight(vsdb, clock);

        //let totalVoteWeight = 0;

        //pools
        let total_weight = 0;
        let used_weight = 0;

        // collect all voting weight
        let totalVoteWeight = weights;


        let pool_weight = weights * player_weight / totalVoteWeight; // get the pro rata voting weight
        assert!(vsdb::pool_votes(vsdb, pool_id) == 0, err::already_voted());
        assert!(pool_weight > 0, err::invalid_weight());

        update_for_(self, gauge);

        // must be add, not aloowing exist empty pool
        let votes = vsdb::pool_votes(vsdb, pool_id);
        vsdb::add_pool_votes(vsdb, pool_id, votes + pool_weight);
        *table::borrow_mut(&mut self.weights, pool_id) = *table::borrow(&self.weights, pool_id) + pool_weight;

        // vote for voting power
        internal_bribe::deposit<X,Y,T>(internal_bribe, vsdb, pool_weight, clock, ctx);

        used_weight = used_weight + pool_weight;
        total_weight = total_weight + pool_weight;

        event::voted<X,Y,T>(object::id(vsdb), pool_weight);

        if(used_weight > 0){
            vsdb::voting(vsdb);
        };

        self.total_weight = self.total_weight + total_weight;
        vsdb::update_used_weights(vsdb, used_weight);
    }

    // currently we are unable to loop token ads to reset all of the votes in different pool,
    fun reset_<X,Y,T>(
        self: &mut Voter,
        vsdb: &mut VSDB,
        gauge: &mut Gauge<X,Y>,
        internal_bribe: &mut InternalBribe<X,Y>,
        // external_bribe
        clock: &Clock,
        ctx: &mut TxContext
    ){
        let pool_id = gauge::pool_id(gauge);
        let votes = vsdb::pool_votes(vsdb, pool_id);
        let total_weight = 0;


        if(votes > 0){
            update_for_(self, gauge);
            let vote_ =  vsdb::pool_votes(vsdb, pool_id);
            vsdb::update_pool_votes(vsdb, pool_id, vote_ - votes);
            *table::borrow_mut(&mut self.weights, pool_id) = *table::borrow(&self.weights, pool_id) - votes;

            // WHY ?
            if(votes > 0){
                internal_bribe::withdraw<X,Y,T>(internal_bribe, vsdb, votes, clock, ctx);
                // withdraw(internal_bribe, vsdb, votes, clock, ctx);
                total_weight = total_weight + votes;
            }else{
                total_weight = total_weight - votes;
            };

            event::abstain<X,Y,T>(object::id(vsdb), votes);
        };

        self.total_weight = self.total_weight - total_weight;
        vsdb::update_used_weights(vsdb, 0);

        // clear all the pool votes
        vsdb::clear_pool_votes(vsdb, pool_id);
    }
}