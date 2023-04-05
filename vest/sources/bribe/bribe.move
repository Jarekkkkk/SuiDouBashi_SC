module suiDouBashiVest::bribe{
    use std::type_name::{Self, TypeName};
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{TxContext};
    use sui::dynamic_field as df;
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::object_table::{Self as ot, ObjectTable};

    //use suiDouBashiVest::vsdb::{Self, VSDB};


    // use suiDouBashiVest::vsdb::VSDB;
    // use suiDouBashi::amm_v1::Pool;
    use sui::table::{ Self, Table};

    const DURATION: u64 = { 7 * 86400 };
    const PRECISION: u64 = 1_000_000_000_000_000_000;
    const MAX_REWARD_TOKENS: u64 = 16;



    /// Rough illustration of the dynamic field architecture for reg:
    /// ```
    ///            type_name /--->Brbe--->Balance
    /// (Reg)-     type_name  -->Brbe--->Balance
    ///            type_name \--->Brbe--->Balance
    /// ```
    struct Reg has key{
        id: UID,
        // we wrapp the balance into coin_lsiting through df for hiding types
        rewards: ObjectTable<TypeName, Bribe>,
        total_supply: u64,
        balace_of: Table<ID, u64>,
    }


    // per token_ads
    struct Bribe has key, store{
        id: UID,
        reward_rate: u64,
        period_finish: u64,
        last_update_time: u64,
        reward_per_token_stored: u64,

        last_earn: Table<ID, u64>, // VSDB -> ts
        user_reward_per_token_stored: Table<ID, u64>, // VSDB -> token_value
        isReward: bool,

        checkpoints: Table<ID, Checkpoint>,
        reward_per_token_checkpoints: Table<u64, RewardPerTokenCheckpoint>,
        supply_checkpoints: Table<u64, SupplyCheckpoint>,

        // type_name -> Balance<T>
    }

    ///checkpoint for marking balance
    struct Checkpoint has store {
        timestamp: u64,
        balance: u64
    }
    ///checkpoint for marking supply
    struct SupplyCheckpoint has store {
        timestamp: u64,
        supply: u64
    }
    ///checkpoint for marking reward rate
    struct RewardPerTokenCheckpoint has store {
        timestamp: u64,
        rewardPerToken: u64

    }

    fun init(ctx: &mut TxContext){
        let reg = Reg{
            id: object::new(ctx),
            rewards: ot::new<TypeName, Bribe>(ctx),
            total_supply: 0,
            balace_of: table::new<ID, u64>(ctx)
        };
        transfer::share_object(reg);
    }

    // register Bribe for specific coin_type
    public fun register_balance<T>(
        reg: &mut Reg,
        ctx: &mut TxContext
    ) {
        let balance = balance::zero<T>();
        let type_name = type_name::get<T>();

        let bribe = Bribe {
            id: object::new(ctx),
            reward_rate: 0,
            period_finish: 0,
            last_update_time: 0,
            reward_per_token_stored: 0,
            last_earn: table::new<ID, u64>(ctx),
            user_reward_per_token_stored: table::new<ID, u64>(ctx),
            isReward: false,
            checkpoints: table::new<ID, Checkpoint>(ctx),
            reward_per_token_checkpoints: table::new<u64, RewardPerTokenCheckpoint>(ctx),
            supply_checkpoints: table::new<u64, SupplyCheckpoint>(ctx),
        };
        // hide the balance in coin_bribe
        df::add(&mut bribe.id, true, balance);
        // register coin_list by type_name
        ot::add(&mut reg.rewards, type_name, bribe);
    }

    /// we are unable ot specify the balance as it requires generic type arguments
    public fun get_mut_balance<T: store>(
        reg: &mut Reg,
        name: TypeName,
    ): &mut T {
        let coin_list = ot::borrow_mut(&mut reg.rewards, name);
        let item = df::borrow_mut(&mut coin_list.id, true);

        item
    }
    public fun get_balance<T: store>(
        reg: &mut Reg,
        name: TypeName,
    ): &T {
        // WHY ot::get fial ?
        let coin_list = ot::borrow(&mut reg.rewards, name);
        let item = df::borrow(&coin_list.id, true);

        item
    }

    public fun deposit<T>(reg: &mut Reg, coin: Coin<T>, ctx: &mut TxContext){
        let type_name = type_name::get<T>();
        if(!ot::contains(&mut reg.rewards, type_name)){
            register_balance<T>(reg, ctx);
        };

        let balance: &mut Balance<T> = get_mut_balance(reg, type_name);
        coin::put<T>(balance, coin);
    }


    // ===== getter =====
    public fun get_balance_value<T>(reg: &mut Reg):u64{
        let type_name = type_name::get<T>();
        let bal: &mut Balance<T> = get_mut_balance(reg, type_name);
        balance::value(bal)
    }


    #[test_only]public fun mock_init(ctx: &mut TxContext){
        init(ctx);
    }

}