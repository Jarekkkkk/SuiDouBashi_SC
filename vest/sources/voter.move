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

    use suiDouBashiVest::vsdb::{Self, VSDB};
    use suiDouBashiVest::sdb::{Self, SDB};
    use suiDouBashiVest::gauge::{Self, Gauge};
    use suiDouBashiVest::event;
    use suiDouBashiVest::err;
    use suiDouBashiVest::reward::{Self, Reward};
    use suiDouBashiVest::checkpoints::{Self, SupplyCheckpoint, Checkpoint};
    use suiDouBashiVest::internal_bribe::{Self, InternalBribe};

    const DURATION: u64 = { 7 * 86400 };

    struct Voter has key, store{
        id: UID,

        governor: address,
        emergency: address,

        total_weight: u64, // enought

        sdb_supply: Supply<SDB>,


        // TODO: vecset will be too expensive ?
        whielist: VecSet<String>, // coin type_name
        pools: VecSet<ID>
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
        assert!(vec_set::contains(&self.whielist, type), err::non_whitelist());
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

            whielist: vec_set::empty<String>(),
            pools: vec_set::empty<ID>()
        };

        transfer::share_object(voter);
    }

    // - player
    public entry fun vote(){}
    public entry fun poke(){}
    public entry fun reset(){}

    // - Gauge
    public entry fun create_gauge<X,Y>(self: &mut Voter, ctx: &mut TxContext){
        assert_governor(self, ctx);
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

    // ===== Setter =====
    entry fun set_governor(self: &mut Voter, new_gov: address, ctx: &mut TxContext){
        assert_governor(self, ctx);
        self.governor = new_gov;
    }
    entry fun whitelist<T>( self: &mut Voter, ctx: &mut TxContext){
        assert_governor(self, ctx);
        let type = type_name::into_string(type_name::get<T>());
        vec_set::insert(&mut self.whielist, type);
    }
    entry fun set_emergency(self: &mut Voter, new_emergency: address, ctx: &mut TxContext){
        assert_governor(self, ctx);
        self.emergency = new_emergency;
    }



}