// Gauges are used to incentivize pools, they emit reward tokens over 7 days for staked LP tokens
module suiDouBashiVest::gauge{
    use std::type_name::{Self, TypeName};
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::dynamic_object_field as dof;
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::clock::{Self, Clock};
    use sui::math;
    use std::vector as vec;


    use suiDouBashiVest::vsdb::{Self, VSDB};
    use suiDouBashiVest::event;
    use suiDouBashiVest::err;
    use suiDouBashiVest::reward::{Self, Reward};
    use suiDouBashiVest::checkpoints::{Self, SupplyCheckpoint, Checkpoint};
    use suiDouBashiVest::internal_bribe::{Self, InternalBribe};


    use sui::table::{ Self, Table};
    use suiDouBashi::amm_v1::{Self, Pool, LP_TOKEN};

    const DURATION: u64 = { 7 * 86400 };
    const PRECISION: u64 = 1_000_000_000_000_000_000;
    const MAX_REWARD_TOKENS: u64 = 16;
    const MAX_U64: u64 = 18446744073709551615_u64;


    struct Guage<phantom X, phantom Y> has key, store{
        id: UID,
        bribes: vector<ID>,//[ Internal, External ]
        total_supply: Balance<LP_TOKEN<X,Y>>,
        // TODO: move to VSDB
        balance_of: Table<ID, u64>,

        token_ids: Table<address, ID>, // each player cna only depoist once for each pool

        is_for_pair: bool,

        fees_x: Balance<X>,
        fees_y: Balance<Y>,

        supply_checkpoints: Table<u64, SupplyCheckpoint>,


        checkpoints: Table<ID, Table<u64, Checkpoint>>,
    }

    fun create_reward<X,Y,T>(self: &mut Guage<X,Y>, ctx: &mut TxContext){
        assert_generic_type<X,Y,T>();

        let type_name = type_name::get<T>();
        let reward =  reward::new<X,Y,T>(ctx);

        dof::add(&mut self.id, type_name, reward);
    }

    fun borrow_reward<X,Y,T>(self: &Guage<X,Y>):&Reward<X, Y, T>{
        let type_name = type_name::get<T>();
        assert_reward_created<X,Y,T>(self, type_name);
        dof::borrow(&self.id, type_name)
    }

    fun borrow_reward_mut<X,Y,T>(self: &mut Guage<X,Y>):&mut Reward<X, Y, T>{
        let type_name = type_name::get<T>();
        assert_reward_created<X,Y,T>(self, type_name);
        dof::borrow_mut(&mut self.id, type_name)
    }

    public fun assert_generic_type<X,Y,T>(){
        let type_t = type_name::get<T>();
        let type_x = type_name::get<X>();
        let type_y = type_name::get<Y>();

        assert!( type_t == type_x || type_t == type_y, err::invalid_type_argument());
    }

    public fun assert_reward_created<X,Y,T>(self: &Guage<X,Y>, type_name: TypeName){
        assert!(dof::exists_(&self.id, type_name), err::reward_not_exist());
    }

    /// Create
    fun create_gauge<X,Y>(
        pool: &Pool<X,Y>,
        ctx: &mut TxContext
    ) {
        let b_id = internal_bribe::create_bribe(pool, ctx);

        let gauge = Guage<X,Y>{
            id: object::new(ctx),
            bribes: vec::singleton(b_id),

            total_supply: balance::zero<LP_TOKEN<X,Y>>(),
            balance_of: table::new<ID, u64>(ctx),

            token_ids: table::new<address, ID>(ctx),

            is_for_pair: false,

            fees_x: balance::zero<X>(),
            fees_y: balance::zero<Y>(),

            supply_checkpoints: table::new<u64, SupplyCheckpoint>(ctx),

            checkpoints: table::new<ID, Table<u64, Checkpoint>>(ctx), // voting weights for each voter
        };

        create_reward<X,Y,X>(&mut gauge, ctx);
        create_reward<X,Y,Y>(&mut gauge, ctx);

        transfer::share_object(gauge);
    }

    // For voter distribure fees, LP trenasfer Fees to Internal Bribe
    /// Instead of receiving pairs of coins from each pool, LPs receive protocol emissions depending on votes each pool accumulate
    fun claim_fee<X,Y>(
        self: &mut Guage<X,Y>,
        bribe: &mut InternalBribe<X,Y>,
        pool: &mut Pool<X,Y>,
        vsdb: &VSDB,
        // LP_TOKEN
        clock: &Clock,
        ctx: &mut TxContext
    ){
        // assert pair exists

        let (coin_x, coin_y) = amm_v1::claim_fee_guage(pool, ctx);
        let value_x = coin::value(&coin_x);
        let value_y = coin::value(&coin_y);

        coin::put(&mut self.fees_x, coin_x);
        coin::put(&mut self.fees_y, coin_y);

        if(value_x > 0 || value_y > 0){
            let bal_x = balance::value(&self.fees_x);
            let bal_y = balance::value(&self.fees_y);

            // why checking left
            if(bal_x > internal_bribe::left(internal_bribe::borrow_reward<X,Y,X>(bribe),clock) && bal_x / DURATION > 0  ){
                let withdraw = balance::withdraw_all(&mut self.fees_x);
                internal_bribe::notify_reward_amount(bribe, vsdb, coin::from_balance(withdraw, ctx), clock, ctx);
            };

            if(bal_y > internal_bribe::left(internal_bribe::borrow_reward<X,Y,Y>(bribe),clock) && bal_y / DURATION > 0  ){
                let withdraw = balance::withdraw_all(&mut self.fees_y);
                internal_bribe::notify_reward_amount(bribe, vsdb, coin::from_balance(withdraw, ctx), clock, ctx);
            }
        }

    }
}
