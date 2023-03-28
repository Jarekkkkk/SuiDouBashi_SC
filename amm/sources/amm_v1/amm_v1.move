module suiDouBashi::amm_v1{
    use sui::object::{Self,UID, ID};
    use sui::balance::{Self,Supply, Balance};
    use sui::coin::{Self,Coin, CoinMetadata};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use std::vector;
    use sui::table::{Self, Table};
    use sui::pay;
    use sui::math;
    use std::string::{Self, String};
    use sui::clock::{Self, Clock};

    use suiDouBashi::err;
    use suiDouBashi::event;
    use suiDouBashi::amm_math;
    use suiDouBashi::uq128x128;
    use suiDouBashi::type;
    use suiDouBashi::formula;

    // === Const ===
    /// range of possible fee percentage: [0.01%, 100%]
    const FEE_SCALING:u64 = 10000;

    const MINIMUM_LIQUIDITY: u64 = 10000;
    const MAX_POOL_VALUE: u64 = { // MAX_U64 / 10000
        18446744073709551615 / 10000
    };

    const MAX_U128: u128 = 340282366920938463463374607431768211455_u128;

    // ===== Object =====
    // - OTW
    // TODO: distinguished by pool type
    struct AMM_V1 has drop {}
    struct LP_TOKEN<phantom V, phantom X, phantom Y> has drop {}

    // - GOV
    struct PoolGov has key {
        id: UID,
        pools: Table<String, ID>,
        guardian: address
    }
    // - Pool
    struct Pool<phantom V, phantom X, phantom Y> has key {
        id: UID,
        stable:bool,
        reserve_x: Balance<X>,
        reserve_y: Balance<Y>,
        lp_supply: Supply<LP_TOKEN<V, X, Y>>,
        last_block_timestamp: u32,
        last_price_x_cumulative: u256,
        last_price_y_cumulative: u256,
        fee:Fee,
        // TODO: falshloan uage
        locked: bool,
    }
    struct Fee has store, copy, drop{
        fee_percentage:u64, // 2 decimal places
        fee_on: bool,
        fee_to: address,
        k_last: u128, // TODO: extend the size after sui update u64 value to u256 in coin package
    }

    // ===== Assertion =====
    fun assert_guardian(gov:&PoolGov, guardian: address){
        assert!(gov.guardian == guardian,err::invalid_guardian());
    }
    fun assert_pool_unlocked<V, X, Y>(pool: &Pool<V, X, Y>){
        assert!(pool.locked == false, err::pool_unlocked());
    }
    fun assert_sorted<X, Y>() {
        let (_,_,coin_x_symbol) = type::get_package_module_type<X>();
        let (_,_,coin_y_symbol) = type::get_package_module_type<Y>();

        assert!(coin_x_symbol != coin_y_symbol, err::same_type());

        let coin_x_bytes = std::string::bytes(&coin_x_symbol);
        let coin_y_bytes = std::string::bytes(&coin_y_symbol);

        assert!(vector::length<u8>(coin_x_bytes) <= vector::length<u8>(coin_y_bytes), err::wrong_pair_ordering());

        if (vector::length<u8>(coin_x_bytes) == vector::length<u8>(coin_y_bytes)) {
            let length = vector::length<u8>(coin_x_bytes);
            let i = 0;
            while (i < length) {
                assert!(*vector::borrow<u8>(coin_x_bytes, i) <= *vector::borrow<u8>(coin_y_bytes, i), err::wrong_pair_ordering());
                i = i + 1;
            }
        };
    }

    // ===== Utils =====
    // Preset function to execute merge and split
    fun merge_and_split<T>(
        coins: vector<Coin<T>>,
        amount: u64,
        ctx: &mut TxContext
    ): (Coin<T>) {/*( amount, remainder )*/
        let base = vector::pop_back(&mut coins);
        pay::join_vec(&mut base, coins);
        assert!(coin::value(&base) >= amount, err::insufficient_input());
        let coin = coin::split(&mut base, amount, ctx);

        if (coin::value(&base) > 0) {
                transfer::public_transfer(base, tx_context::sender(ctx));
        } else {
                coin::destroy_zero(base);
        };
        coin
    }
    public fun get_pool_name<X,Y>():String{
        let (_, _, symbol_x) = type::get_package_module_type<X>();
        let (_, _, symbol_y) = type::get_package_module_type<Y>();

        string::append(&mut symbol_x, string::utf8(b"-"));
        string::append(&mut symbol_x, symbol_y);
        symbol_x
    }
    public fun get_reserves<V, X, Y>(pool: &Pool<V, X, Y>): (u64, u64, u64) {
        (
            balance::value(&pool.reserve_x),
            balance::value(&pool.reserve_y),
            balance::supply_value(&pool.lp_supply)
        )
    }
    public fun get_last_timestamp<V,X,Y>(pool: &Pool<V,X,Y>):u32{
        pool.last_block_timestamp
    }
    public fun get_cumulative_prices<V,X,Y>(pool: &Pool<V,X,Y>):(u256, u256){
        (pool.last_price_x_cumulative, pool.last_price_y_cumulative)
    }
    /// currently we are unable to get either block.timestamp & epoch, so we directly fetch the reserve's pool
    public fun get_x_price(res_x: u64, res_y:u64): u64{
        res_y / res_x
    }
    /// for fetching pool info
    public fun get_l(res_x:u64, res_y: u64): u64{
        amm_math::mul_sqrt(res_x, res_y)
    }
    /// Action: adding liquidity
    /// b' (optimzied_) = (Y/X) * a, subjected to Y/X = b/a
    public fun quote(res_x:u64, res_y:u64, input_x:u64): u64{
        assert!(res_x > 0 && res_y > 0, err::empty_reserve());
        assert!(input_x > 0, err::zero_amount());

        amm_math::mul_div(res_y, input_x, res_x)
    }

    public fun swap_input(output_y:u64, res_x:u64, res_y:u64, fee:u64, fee_scaling: u64): u64{
        assert!(res_x > 0 && res_y > 0, err::empty_reserve());
        assert!(output_y > 0, err::zero_amount());
        let numerator = amm_math::mul_to_u128(res_x, output_y) * 1000;
        let denominator =  (res_y - output_y) * (fee_scaling - fee) + 1;
        ((numerator / (denominator as u128)) as u64)
    }
    /// record the last block_timestamp before any pool mutation
    fun update_timestamp<V,X,Y>(pool: &mut Pool<V,X,Y>, clock: &Clock){
        let res_x = ( balance::value<X>(&pool.reserve_x) as u128);
        let res_y = ( balance::value<Y>(&pool.reserve_y) as u128);
        let block_timestamp = (( clock::timestamp_ms(clock) % (sui::math::pow(2,32)) ) as u32);
        let elapsed =(( block_timestamp - pool.last_block_timestamp) as u256);

        if(elapsed > 0 && res_x != 0 && res_y != 0){
            let p_0 = uq128x128::to_u256(uq128x128::div(uq128x128::encode(res_y), res_x));
            let p_1 = uq128x128::to_u256(uq128x128::div(uq128x128::encode(res_x), res_y));
            pool.last_price_x_cumulative = pool.last_price_x_cumulative + p_0 * elapsed;
            pool.last_price_y_cumulative = pool.last_price_y_cumulative + p_1 * elapsed;
        };
        pool.last_block_timestamp = block_timestamp;
    }

    // ===== public Entry =====
    fun init(_witness: AMM_V1, ctx:&mut TxContext){
        let pool_gov = PoolGov{
            id: object::new(ctx),
            pools: table::new<String, ID>(ctx),
            guardian: tx_context::sender(ctx)
        };
        transfer::share_object(
            pool_gov
        );
    }
    // - gov
    public entry fun lock_pool<V, X, Y>(
        pool: &mut Pool<V, X, Y>,
        pool_gov: &PoolGov,
        locked: bool,
        ctx: &mut TxContext
    ){
        assert_guardian(pool_gov, tx_context::sender(ctx));
        assert_pool_unlocked(pool);
        pool.locked = locked;
    }
    public entry fun update_fee_on<V,X,Y>(pool_gov: &PoolGov,pool: &mut Pool<V,X,Y>, fee_on: bool, ctx:&mut TxContext){
        assert_guardian(pool_gov, tx_context::sender(ctx));
        assert_pool_unlocked(pool);
        pool.fee.fee_on = fee_on;
    }
    public entry fun update_fee_percentage<V,X,Y>(pool_gov: &PoolGov,pool: &mut Pool<V,X,Y>, fee_percentage: u64, ctx:&mut TxContext){
        assert_guardian(pool_gov, tx_context::sender(ctx));
        assert_pool_unlocked(pool);
        pool.fee.fee_percentage = fee_percentage;
    }
    public entry fun update_fee_to<V,X,Y>(pool_gov: &PoolGov, pool: &mut Pool<V,X,Y>, _fee_to:address, ctx: &mut TxContext){
        assert_guardian(pool_gov, tx_context::sender(ctx));
        assert_pool_unlocked(pool);
        pool.fee.fee_to = _fee_to;
    }
    // - pool
    public entry fun create_pool<V, X, Y>(
        pool_gov: &mut PoolGov,
        stable: bool,
        fee_percentage: u64,
        ctx: &mut TxContext
    ){
        assert_sorted<X, Y>();
        assert_guardian(pool_gov, tx_context::sender(ctx));

        let pool = create_pool_<V, X, Y>(
            &mut pool_gov.pools, stable, fee_percentage, ctx
        );
        let pool_id = object::id(&pool);

        transfer::share_object(
            pool
        );

        event::pool_created<V,X,Y>(pool_id, tx_context::sender(ctx))
    }
    // - add liquidity
    /// Since this functino would directly deposit coins in pool, assert of coin_value is omited
    public entry fun add_liquidity<V, X, Y>(
        pool: &mut Pool<V, X, Y>,
        coin_x: Coin<X>,
        coin_y: Coin<Y>,
        deposit_x_min:u64,
        deposit_y_min:u64,
        // clock: &Clock,
        ctx:&mut TxContext
    ){
        assert_pool_unlocked(pool);
        // main execution
        let (output_lp_coin, lp_output, deposit_x, deposit_y) = add_liquidity_(pool, coin_x, coin_y, deposit_x_min, deposit_y_min
        , /*clock,*/ ctx);

        transfer::public_transfer(
            output_lp_coin,
            tx_context::sender(ctx)
        );
        event::liquidity_added<V,X,Y>(deposit_x, deposit_y, lp_output)
    }
    public entry fun add_liquidity_pay<V, X, Y>(
        pool: &mut Pool<V, X, Y>,
        coin_x: vector<Coin<X>>,
        coin_y: vector< Coin<Y>>,
        value:u64,
        deposit_x_min:u64,
        deposit_y_min:u64,
        // clock: &Clock,
        ctx:&mut TxContext
    ){
        let coin_x = merge_and_split(coin_x, value, ctx);
        let coin_y = merge_and_split(coin_y, value, ctx);
        add_liquidity<V,X,Y>(pool, coin_x, coin_y, deposit_x_min, deposit_y_min, /*clock,*/ ctx);
    }
    // - remove liquidity
    public entry fun remove_liquidity<V, X, Y>(
        pool:&mut Pool<V, X, Y>,
        lp_token:Coin<LP_TOKEN<V, X, Y>>,
        withdrawl_x_min:u64,
        withdrawl_y_min:u64,
        // clock: &Clock,
        ctx:&mut TxContext
    ){
        assert_pool_unlocked(pool);

        let ( withdrawl_x, withdrawl_y, burned_lp) = remove_liquidity_(pool, lp_token, withdrawl_x_min, withdrawl_y_min, /*clock,*/ ctx);

        let withdrawl_value_x = coin::value(&withdrawl_x);
        let withdrawl_value_y = coin::value(&withdrawl_y);

        transfer::public_transfer(
            withdrawl_x,
            tx_context::sender(ctx)
        );
        transfer::public_transfer(
            withdrawl_y,
            tx_context::sender(ctx)
        );

        event::liquidity_removed<V,X,Y>( withdrawl_value_x, withdrawl_value_y, burned_lp);
    }
    public entry fun remove_liquidity_pay<V,X,Y>(
        pool:&mut Pool<V, X, Y>,
        lp_token:vector<Coin<LP_TOKEN<V, X, Y>>>,
        value: u64,
        withdrawl_x_min:u64,
        withdrawl_y_min:u64,
        // clock: &Clock,
        ctx:&mut TxContext
    ){
        let lp_token = merge_and_split(lp_token, value, ctx);
        remove_liquidity<V,X,Y>(pool, lp_token, withdrawl_x_min, withdrawl_y_min, /*clock*/ ctx);
    }
    // - swap
    public entry fun swap_for_y<V, X, Y>(
        pool: &mut Pool<V, X, Y>,
        coin_x: Coin<X>,
        metadata_x: &CoinMetadata<X>,
        metadata_y: &CoinMetadata<Y>,
        output_y_min: u64,
        // clock: &Clock,
        ctx: &mut TxContext
    ){
        assert_pool_unlocked(pool);

        let (coin_y, input, output) = swap_for_y_(pool, coin_x, metadata_x, metadata_y, output_y_min,/*clock*/ ctx);

        transfer::public_transfer(coin_y, tx_context::sender(ctx));

        event::swap<V,X,Y>(input, output);
    }
    public entry fun swap_for_y_pay<V,X,Y>(
        pool: &mut Pool<V, X, Y>,
        coin_x: vector<Coin<X>>,
        value: u64,
        metadata_x: &CoinMetadata<X>,
        metadata_y: &CoinMetadata<Y>,
        output_y_min: u64,
        // clock: &Clock,
        ctx: &mut TxContext
    ){
        let coin_x = merge_and_split(coin_x, value, ctx);
        swap_for_y(pool, coin_x,  metadata_x, metadata_y, output_y_min, /*clock*/ ctx);
    }
    public entry fun swap_for_x<V, X, Y>(
        pool: &mut Pool<V, X, Y>,
        coin_y: Coin<Y>,
        metadata_x: &CoinMetadata<X>,
        metadata_y: &CoinMetadata<Y>,
        output_x_min: u64,
        // clock: &Clock,
        ctx: &mut TxContext
    ){
        assert_pool_unlocked(pool);

        let (coin_x, input, output) = swap_for_x_(pool, coin_y, metadata_x, metadata_y, output_x_min,/*clock*/ctx);

        transfer::public_transfer(
            coin_x,
            tx_context::sender(ctx)
        );

        event::swap<V,X,Y>(input, output);
    }
    public entry fun swap_for_x_pay<V,X,Y>(
        pool: &mut Pool<V, X, Y>,
        coin_y: vector<Coin<Y>>,
        value: u64,
        metadata_x: &CoinMetadata<X>,
        metadata_y: &CoinMetadata<Y>,
        output_x_min: u64,
        // clock: &Clock,
        ctx: &mut TxContext
    ){
        let coin_y = merge_and_split(coin_y, value, ctx);
        swap_for_x(pool, coin_y, metadata_x, metadata_y, output_x_min, /*clock*/ ctx);
    }
    // - zap
    /// x: single assets LP hold; y: optimal output assets needed
    // holded assumption: (X + dx) / ( Y - dy ) = ( x - dx) / y
    public entry fun zap_x<V,X,Y>(
        pool: &mut Pool<V, X, Y>,
        coin_x: Coin<X>,
        metadata_x: &CoinMetadata<X>,
        metadata_y: &CoinMetadata<Y>,
        output_y_min:u64,
        deposit_x_min:u64,
        deposit_y_min:u64,
        // clock: &Clock,
        ctx:&mut TxContext
    ){
        assert_pool_unlocked(pool);
        let x_value = coin::value<X>(&coin_x);
        let coin_x_split = coin::split<X>(&mut coin_x, x_value/ 2, ctx);
        let (coin_y, _, _) = swap_for_y_<V,X,Y>(pool, coin_x_split, metadata_x, metadata_y, output_y_min,  /*clock*/ ctx);
        add_liquidity<V,X,Y>(pool, coin_x, coin_y, deposit_x_min, deposit_y_min, /*clock*/ ctx);
    }
    public entry fun zap_x_pay<V,X,Y>(
        pool: &mut Pool<V, X, Y>,
        coin_x: vector<Coin<X>>,
        value: u64,
        metadata_x: &CoinMetadata<X>,
        metadata_y: &CoinMetadata<Y>,
        output_y_min:u64,
        deposit_x_min:u64,
        deposit_y_min:u64,
        // clock: &Clock,
        ctx:&mut TxContext
    ){
        let coin_x = merge_and_split(coin_x, value, ctx);
        zap_x(pool, coin_x, metadata_x, metadata_y, output_y_min, deposit_x_min, deposit_y_min, /*clock*/ ctx);
    }
     public entry fun zap_y<V,X,Y>(
        pool: &mut Pool<V, X, Y>,
        coin_y: Coin<Y>,
        metadata_x: &CoinMetadata<X>,
        metadata_y: &CoinMetadata<Y>,
        output_x_min:u64,
        deposit_x_min:u64,
        deposit_y_min:u64,
        // clock: &Clock,
        ctx:&mut TxContext
    ){
        assert_pool_unlocked(pool);
        let y_value = coin::value<Y>(&coin_y);
        // simplest way to deposit single assets, to calculate exact output of another assets, use zap_optimized_output in formula module
        let coin_y_split = coin::split<Y>(&mut coin_y, y_value/ 2, ctx);
        let (coin_x, _, _) = swap_for_x_<V,X,Y>(pool, coin_y_split, metadata_x, metadata_y, output_x_min,/*clock*/ ctx);
        add_liquidity<V,X,Y>(pool, coin_x, coin_y, deposit_x_min, deposit_y_min,/*clock*/ ctx);
    }
    public entry fun zapy_pay<V,X,Y>(
        pool: &mut Pool<V, X, Y>,
        coin_y: vector<Coin<Y>>,
        value: u64,
        metadata_x: &CoinMetadata<X>,
        metadata_y: &CoinMetadata<Y>,
        output_x_min:u64,
        deposit_x_min:u64,
        deposit_y_min:u64,
        // clock: &Clock,
        ctx:&mut TxContext
    ){
        let coin_y = merge_and_split(coin_y, value, ctx);
        zap_y(pool, coin_y, metadata_x, metadata_y, output_x_min, deposit_x_min, deposit_y_min, /*clock*/ctx);
    }

    // ====== MAIN_LOGIC ======
    public fun create_pool_<V, X, Y>(
        pool_list:&mut Table<String, ID>,
        stable: bool,
        fee_percentage: u64,
        ctx: &mut TxContext
    ):(Pool<V, X, Y>){
        let lp_supply = balance::create_supply(LP_TOKEN<V, X, Y>{});

        let fee = Fee{
            fee_on: false,
            fee_percentage,
            fee_to: tx_context::sender(ctx),
            k_last: 0,
        };

        let pool = Pool{
            id: object::new(ctx),
            stable,
            reserve_x: balance::zero<X>(),
            reserve_y: balance::zero<Y>(),
            lp_supply,
            last_block_timestamp: (tx_context::epoch(ctx) as u32),
            last_price_x_cumulative: 0,
            last_price_y_cumulative: 0,
            fee,
            locked: false,
        };
        let pool_name = get_pool_name<X,Y>();
        //TODO: register whole name including involved coin type
        table::add(pool_list, pool_name, object::id(&pool));

        pool
    }
    #[test_only]
    public fun add_liquidity_validate(
        input_x:u64,
        input_y:u64,
        res_x:u64,
        res_y:u64,
        deposit_x_min:u64,
        deposit_y_min:u64,
    ):(u64, u64){
        if (res_x == 0 && res_y == 0){
            (input_x, input_y)
        }else{
            let opt_y  = quote(res_x, res_y, input_x);
            if (opt_y <= input_y){
                assert!(opt_y >= deposit_y_min, err::insufficient_input());

                (input_x, opt_y)
            }else{
                let opt_x = quote(res_y, res_x, input_y);
                assert!(opt_x <= input_x, err::insufficient_input());
                assert!(opt_x >= deposit_x_min, err::below_minimum());

                (opt_x, input_y)
            }
        }
    }
    fun add_liquidity_<V, X, Y>(
        pool: &mut Pool<V, X, Y>,
        coin_x: Coin<X>,
        coin_y: Coin<Y>,
        deposit_x_min:u64,
        deposit_y_min:u64,
        // clock: &Clock,
        ctx:&mut TxContext
    ):(
        Coin<LP_TOKEN<V, X, Y>>,
        u64,
        u64,
        u64
    ){
        let value_x = coin::value(&coin_x);
        let value_y = coin::value(&coin_y);
        assert!(value_x > 0 && value_y > 0, err::zero_amount());

        // charge the fee when fee is on
        charge_fee_(pool, ctx);

        let (reserve_x, reserve_y, lp_supply) = get_reserves(pool);
        let (deposit_x, deposit_y, coin_x, coin_y) = if (reserve_x == 0 && reserve_y == 0){
            (value_x, value_y, coin_x, coin_y)
        }else{
            let opt_y  = quote(reserve_x, reserve_y, value_x);
            if (opt_y <= value_y){
                assert!(opt_y >= deposit_y_min, err::insufficient_input());

                let take = coin::take<Y>(coin::balance_mut<Y>(&mut coin_y), opt_y, ctx);
                transfer::public_transfer(coin_y, tx_context::sender(ctx));

                (value_x, opt_y, coin_x, take)
            }else{
                let opt_x = quote(reserve_y, reserve_x, value_y);
                assert!(opt_x <= value_x, err::insufficient_input());
                assert!(opt_x >= deposit_x_min, err::below_minimum());

                let take = coin::take<X>(coin::balance_mut<X>(&mut coin_x), opt_x, ctx);
                transfer::public_transfer(coin_x, tx_context::sender(ctx));

                (opt_x, value_y, take, coin_y)
            }
        };

        let lp_output = if( balance::supply_value<LP_TOKEN<V,X,Y>>(&pool.lp_supply) == 0){
            let amount = (amm_math::mul_sqrt(deposit_x, deposit_y) - MINIMUM_LIQUIDITY);
            let min = balance::increase_supply<LP_TOKEN<V, X, Y>>(&mut pool.lp_supply, MINIMUM_LIQUIDITY);
            transfer::public_transfer(coin::from_balance(min,ctx), sui::address::from_u256(0));
            amount
        }else{
            math::min(
                amm_math::mul_div(deposit_x, lp_supply, reserve_x),
                amm_math::mul_div(deposit_y, lp_supply, reserve_y),
            )
        };
        //update_timestamp(pool, clock);

        let pool_coin_x = balance::join<X>(&mut pool.reserve_x, coin::into_balance(coin_x));
        let pool_coin_y = balance::join<Y>(&mut pool.reserve_y,  coin::into_balance(coin_y));
        assert!(pool_coin_x < MAX_POOL_VALUE && pool_coin_y < MAX_POOL_VALUE ,err::pool_max_value());

        if(pool.fee.fee_on) pool.fee.k_last = amm_math::mul_to_u128(pool_coin_x, pool_coin_y);
        let lp_balance = balance::increase_supply<LP_TOKEN<V, X, Y>>(&mut pool.lp_supply, lp_output);
        return (
            coin::from_balance(lp_balance, ctx),
            lp_output,
            deposit_x,
            deposit_y
        )
    }
    #[test_only]
    public fun remove_liquidity_validate<V, X, Y>(
        pool: &Pool<V,X,Y>,
        lp_value:u64,
        withdrawl_x_min:u64,
        withdrawl_y_min:u64,
    ):(u64, u64){
        let (res_x, res_y, lp_s) = get_reserves(pool);
        let withdrawl_x = quote(lp_s, res_x, lp_value);
        let withdrawl_y = quote(lp_s, res_y, lp_value);

        assert!(withdrawl_x > 0 && withdrawl_y > 0, err::insufficient_liquidity());
        assert!(withdrawl_x >= withdrawl_x_min, err::below_minimum());
        assert!(withdrawl_y >= withdrawl_y_min, err::below_minimum());

        (withdrawl_x, withdrawl_y)
    }
    fun remove_liquidity_<V, X, Y>(
        pool:&mut Pool<V, X, Y>,
        lp_token:Coin<LP_TOKEN<V, X, Y>>,
        withdrawl_x_min:u64,
        withdrawl_y_min:u64,
        // clock: &Clock,
        ctx:&mut TxContext
    ):(
        Coin<X>,
        Coin<Y>,
        u64,
    ){
        charge_fee_(pool, ctx);

        let lp_value = coin::value(&lp_token);
        assert!(lp_value > 0, err::zero_amount());

        let (res_x, res_y, lp_s) = get_reserves(pool);
        let withdrawl_x = quote(lp_s, res_x, lp_value);// quote base
        let withdrawl_y = quote(lp_s, res_y, lp_value);

        assert!(withdrawl_x > 0 && withdrawl_y > 0, err::insufficient_liquidity());
        assert!(withdrawl_x >= withdrawl_x_min, err::below_minimum());
        assert!(withdrawl_y >= withdrawl_y_min, err::below_minimum());

        //update_timestamp(pool, clock);

        let coin_x = coin::take<X>(&mut pool.reserve_x, withdrawl_x, ctx);
        let coin_y = coin::take<Y>(&mut pool.reserve_y, withdrawl_y, ctx);
        balance::decrease_supply<LP_TOKEN<V, X, Y>>(&mut pool.lp_supply,coin::into_balance(lp_token));

        if(pool.fee.fee_on) pool.fee.k_last = amm_math::mul_to_u128(balance::value<X>(&pool.reserve_x),balance::value<Y>(&pool.reserve_y));
        return (
            coin_x,
            coin_y,
            lp_value
        )
    }
    #[test_only]
    public fun charge_fee_validate(x_1: u64, y_1:u64, x_2: u64, y_2:u64, init_supply:u64):u64{
        let prev_root_k = amm_math::mul_sqrt(x_1, y_1);
        let root_k = amm_math::mul_sqrt(x_2, y_2);
        let numerator = amm_math::mul_to_u128(init_supply, (root_k - prev_root_k));
        let denominator = amm_math::mul_to_u128(5, root_k) + (prev_root_k as u128);
        let minted_lp = numerator / denominator;

        (minted_lp as u64)
    }
    /// Assume: LP_Provider hold t amount of LP_TOKEN in the period [t1, t2]
    /// Accumlated Fee between interval as a percentage of the pool  = `(( t / sqrt(k1) ) - ( t / sqrt(k2) ) / ( t/sqrt(k2) )` when k2 is larger than k1
    fun charge_fee_<V,X,Y>(pool: &mut Pool<V,X,Y>, ctx: &mut TxContext){
        if(pool.fee.fee_on){
            let (reserve_x, reserve_y, _) = get_reserves(pool);
            let root_k = amm_math::mul_sqrt(reserve_x, reserve_y);
            let root_k_last = amm_math::sqrt_u64(pool.fee.k_last);
            if(root_k > root_k_last){  // we only charge the fee when liquidity increase
                let numerator = amm_math::mul_to_u128(balance::supply_value<LP_TOKEN<V,X,Y>>(&pool.lp_supply), (root_k - root_k_last));
                let denominator = amm_math::mul_to_u128(5, root_k) + (root_k_last as u128);
                let liquidity = ((numerator / denominator) as u64 );
                if(liquidity > 0){
                    let lp_balance = balance::increase_supply<LP_TOKEN<V, X, Y>>(&mut pool.lp_supply, liquidity);
                    transfer::public_transfer(coin::from_balance<LP_TOKEN<V,X,Y>>(lp_balance,ctx),tx_context::sender(ctx));
                }
            }
        }else if(pool.fee.k_last != 0){
            pool.fee.k_last = 0
        }
    }
    // ===== SWAP =====
    fun swap_for_y_<V, X, Y>(
        pool: &mut Pool<V, X, Y>,
        coin_x: Coin<X>,
        metadata_x: &CoinMetadata<X>,
        metadata_y: &CoinMetadata<Y>,
        output_y_min: u64,
        // clock: &Clock,
        ctx: &mut TxContext
    ):(
        Coin<Y>,
        u64,
        u64
    ){
        let value_x = coin::value(&coin_x);
        let (reserve_x, reserve_y, _) = get_reserves(pool);
        assert!(value_x >0, err::zero_amount());
        assert!(reserve_x > 0 && reserve_y > 0, err::empty_reserve());

        let _value_x = ( value_x as u256 );
        let dx = _value_x - _value_x * (pool.fee.fee_percentage as u256) / (FEE_SCALING as u256);

        let  output_y = if(pool.stable){
           ( formula::stable_swap_output(
                dx,
                (reserve_x as u256),
                (reserve_y as u256),
                (math::pow(10, coin::get_decimals(metadata_x)) as u256),
                (math::pow(10, coin::get_decimals(metadata_y)) as u256)
            ) as u64)
        }else{
             ( formula::variable_swap_output(dx, (reserve_x as u256), (reserve_y as u256)) as u64)
        };


        assert!(output_y > output_y_min, err::slippage());

        // store prev value to verify after tx execution
        let _res_x = balance::value(&pool.reserve_x);
        let _res_y = balance::value(&pool.reserve_y);
        //update_timestamp(pool, clock);

        let pool_bal_x = balance::join<X>(&mut pool.reserve_x, coin::into_balance(coin_x));
        assert!(pool_bal_x <= MAX_POOL_VALUE, err::pool_max_value());
        let coin_y = coin::take<Y>(&mut pool.reserve_y, output_y, ctx);

        let updated_res_x = amm_math::mul_to_u128(balance::value<X>(&pool.reserve_x), 1000) - (( value_x * 3 ) as u128 );
        let updated_res_y = amm_math::mul_to_u128(balance::value<Y>(&pool.reserve_y), 1000);
        assert!(updated_res_x * updated_res_y >= amm_math::mul_to_u128(_res_x, _res_y), err::k_value());

        return(
            coin_y,
            value_x,
            output_y
        )
    }
    fun swap_for_x_<V, X, Y>(
        pool: &mut Pool<V, X, Y>,
        coin_y: Coin<Y>,
        metadata_x: &CoinMetadata<X>,
        metadata_y: &CoinMetadata<Y>,
        output_x_min: u64,
        // clock: &Clock,
        ctx: &mut TxContext
    ):(
        Coin<X>,
        u64,
        u64
    ){
        let value_y = coin::value(&coin_y);
        let (reserve_x, reserve_y, _) = get_reserves(pool);
        assert!(reserve_x > 0 && reserve_y > 0, err::empty_reserve());
        assert!(value_y > 0, err::zero_amount());

        let _value_y = ( value_y as u256 );
        let dy = _value_y - _value_y * (pool.fee.fee_percentage as u256) / (FEE_SCALING as u256);

        let  output_x = if(pool.stable){
           ( formula::stable_swap_output(
                dy,
                (reserve_y as u256),
                (reserve_x as u256),
                (math::pow(10, coin::get_decimals(metadata_y)) as u256),
                (math::pow(10, coin::get_decimals(metadata_x)) as u256)
            ) as u64)
        }else{
             ( formula::variable_swap_output(dy, (reserve_y as u256), (reserve_x as u256)) as u64)
        };


        assert!(output_x > output_x_min, err::slippage());
        let _res_x = balance::value(&pool.reserve_x);
        let _res_y = balance::value(&pool.reserve_y);
        //update_timestamp(pool, clock);

        let coin_y_balance = coin::into_balance(coin_y);
        let pool_bal_y = balance::join<Y>(&mut pool.reserve_y, coin_y_balance);
        assert!(pool_bal_y <= MAX_POOL_VALUE, err::pool_max_value());
        let coin_y = coin::take<X>(&mut pool.reserve_x, output_x, ctx);

        let updated_res_x = amm_math::mul_to_u128(balance::value<X>(&pool.reserve_x), 1000);
        let updated_res_y = amm_math::mul_to_u128(balance::value<Y>(&pool.reserve_y), 1000) - (( value_y * 3 ) as u128 );
        assert!(updated_res_x * updated_res_y >= amm_math::mul_to_u128(_res_x, _res_y), err::k_value());

        return (
            coin_y,
            value_y,
            output_x
        )
    }
    // ------ FOR DEPLOYMNT ------
    use sui::sui::SUI;
    use suiDouBashi::dai::DAI;
    use suiDouBashi::usdc::USDC;
    use suiDouBashi::usdt::USDT;
    entry fun mint_coins(
        d : &mut coin::TreasuryCap<DAI>,
        usdc : &mut coin::TreasuryCap<USDC>,
        usdt : &mut coin::TreasuryCap<USDT>,
        ctx: &mut TxContext
    ){
        let sender = tx_context::sender(ctx);
        coin::mint_and_transfer(d, 30000*math::pow(10, 8), sender, ctx);
        coin::mint_and_transfer(usdc, 30000*math::pow(10, 6), sender, ctx);
        coin::mint_and_transfer(usdt, 30000*math::pow(10, 6), sender, ctx);
    }
    entry fun create_pools(
        gov: &mut PoolGov,
        ctx: &mut TxContext
    ){
        create_pool<AMM_V1, DAI, SUI>(gov, false, 3, ctx);// dai-jrk
        create_pool<AMM_V1, SUI, USDC>(gov, false, 3, ctx);// jrk-usdc
        create_pool<AMM_V1, SUI, USDT>(gov, false, 3, ctx);// jrk-usdt
        create_pool<AMM_V1, DAI, USDC>(gov, true, 1, ctx);// dai-usdc
        create_pool<AMM_V1, DAI, USDT>(gov, true, 1, ctx);// dai-usdt
        create_pool<AMM_V1, USDC, USDT>(gov, true, 1, ctx);// usdc-usdt
    }

    //glue calling for init the module
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(AMM_V1{}, ctx)
    }
    #[test]
    fun test_quote(){
        let input_x = 8000000000;
        let input_y = 300000000;
        let res_x = 123541344046;
        let res_y = 8134798939;

        let _quote_y = quote(res_x, res_y, input_x);
        let _quote_x = quote(res_y, res_x, input_y);

        assert!(4 == 4, 1);
    }
    #[test]fun test_add_liquidity(){
        let input_x = 8000000000;
        let input_y = 300000000;
        let res_x = 123541344046;
        let res_y = 8134798939;
        let lp_supply = 32976994805;
        let (x,y) = add_liquidity_validate(input_x, input_y, res_x, res_y, 0, 0);

         let _lp_output = math::min(
            (x / res_x)  * lp_supply,
            (y  / res_y) * lp_supply
         );
    }

    #[test]fun type_name(){
        let type_name = std::type_name::get<AMM_V1>();
        let _mod = std::type_name::get_module(&type_name);
        let _ads = std::type_name::get_address(&type_name);
    }
    #[test] fun test_fee(){
        let x_1 = 100000;
        let y_1 = 1000;
        let x_2 = 90000;
        let y_2 = 2000;
        let init_supply = 10000;
        let _charged_lp = charge_fee_validate(x_1, y_1, x_2, y_2, init_supply);
    }
    #[test] fun test_pay(){
        let ctx = tx_context::dummy();
        let coin_x = coin::mint_for_testing<LP_TOKEN<AMM_V1,SUI, suiDouBashi::usdc::USDC>>(1000, &mut ctx);
        let coin = coin::mint_for_testing<LP_TOKEN<AMM_V1,SUI, suiDouBashi::usdc::USDC>>(100,&mut ctx);
        let vec = std::vector::empty<Coin<LP_TOKEN<AMM_V1,SUI, suiDouBashi::usdc::USDC>>>();
        vector::push_back(&mut vec, coin);
        sui::pay::join_vec<LP_TOKEN<AMM_V1,SUI, suiDouBashi::usdc::USDC>>(&mut coin_x, vec);
         coin::burn_for_testing(coin_x);
    }
}

