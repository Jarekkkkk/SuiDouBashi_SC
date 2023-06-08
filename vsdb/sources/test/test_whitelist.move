#[test_only]
module suiDouBashi_vsdb::test_whitelist{
    use sui::vec_map::{VecMap};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::TxContext;
    use sui::vec_map;
    use sui::transfer;

    use suiDouBashi_vsdb::vsdb::{Self, Vsdb, VSDBRegistry};

    struct VotingState has store{
        attachments: u64,
        pool_votes: VecMap<ID, u64>, // pool -> voting weight
        voted: bool,
        used_weights: u64,
        last_voted: u64 // ts
    }

    /// Witness + Capability + DF/DOF Entry
    struct MOCK has copy, store, drop {}

    struct Foo has key{
        id: UID,
        witness: MOCK
    }

    fun init(ctx: &mut TxContext){
        let foo = Foo {
            id: object::new(ctx),
            witness: MOCK{}
        };
        transfer::share_object(foo);
    }

    public fun add_pool_votes(self: &Foo, reg: &VSDBRegistry, vsdb: &mut Vsdb){
        let value = VotingState{
            attachments: 1000,
            pool_votes: vec_map::empty(),
            voted: false,
            used_weights: 990,
            last_voted: 1230
        };
        vsdb::df_add(&self.witness, reg, vsdb, value);
    }

    public fun update_pool_votes(self: &Foo, vsdb: &mut Vsdb){
        let voting_mut:&mut VotingState = vsdb::df_borrow_mut(vsdb, self.witness);

        vec_map::insert(&mut voting_mut.pool_votes, object::id(self), 1321321);

        voting_mut.voted = true;
        voting_mut.attachments = 100;
        voting_mut.used_weights = 99;
        voting_mut.last_voted = 131312;
    }

    #[test_only] public fun init_for_testing(ctx: &mut TxContext){ init(ctx) }
}