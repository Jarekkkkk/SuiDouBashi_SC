module suiDouBashi::pool{
    use sui::object::{Self,UID, ID};
    use sui::balance::{Self,Supply, Balance};
    use sui::coin::{Self,Coin, CoinMetadata};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::table_vec::{Self,TableVec};
    use sui::math;
    use sui::clock::{Self, Clock};
    use std::option::{Self, Option};
    use std::type_name;

    use suiDouBashi::event;
    use suiDouBashi::amm_math;
    use suiDouBashi::formula;

    friend suiDouBashi::pool_reg;

    const FEE_SCALING:u64 = 10000; //fee percentage: [0.01%, 0.050%]

    const PERIOD_SIZE:u64 = 1800; // update for esch 30 minutes

    const SCALE_FACTOR: u256 = 1_000_000_000_000_000_000; // 10e18

    const MINIMUM_LIQUIDITY: u64 = 1_000;

    // ERROR
    // - Pool
    const ERR_INVALID_TYPE: u64 = 000;
    const ERR_POOL_LOCK: u64 = 001;
    const ERR_EMPTY_INPUT: u64 = 002;
    const ERR_INSIFFICIENT_INPUT: u64 = 003;
    const ERR_EMPTY_RESERVE: u64 = 004;
    const ERR_K: u64 = 005;
    // - Flashloan
    const ERR_INSUFFICIENT_LOAN: u64 = 100;
    const ERR_INVALID_REPAY: u64 = 101;

    struct Pool<phantom X, phantom Y> has key {
        id: UID,
        stable:bool,
        locked: bool,
        lp_supply: Supply<LP_TOKEN<X, Y>>,
        /// reserves
        reserve_x: Balance<X>,
        reserve_y: Balance<Y>,
        reserve_lp: Balance<LP_TOKEN<X, Y>>,
        // decimals
        decimal_x: u8,
        decimal_y: u8,
        /// oracle
        last_block_timestamp: u64,
        last_price_x_cumulative: u256,
        last_price_y_cumulative: u256,
        observations: TableVec<Observation>,
        // Pool Fees
        fee:Fee<X,Y>,
    }

    // - Fee
    struct Fee<phantom X, phantom Y> has store{
        fee_x:  Balance<X>,
        fee_y:  Balance<Y>,
        index_x: u256, // fee_x/ total_supply * 10e18
        index_y: u256, // fee_y/ total_supply * 10e18
        fee_percentage: u8, // 2 decimal placee, range[ 1%, 5% ]
    }

    public fun get_fee_x<X,Y>(self:&Pool<X,Y>):u64{ balance::value(&self.fee.fee_x) }
    public fun get_fee_y<X,Y>(self:&Pool<X,Y>):u64{ balance::value(&self.fee.fee_y) }

    // - Oracle
    struct Observation has store {
        timestamp: u64,
        reserve_x_cumulative: u256,
        reserve_y_cumulative: u256,
    }

    fun get_observation<X,Y>(self: &Pool<X,Y>, idx: u64):&Observation{
        table_vec::borrow(&self.observations, idx)
    }

    fun get_latest_observation<X,Y>(self: &Pool<X,Y>):&Observation{
        get_observation(self, table_vec::length(&self.observations) - 1)
    }

    fun add_reserve_x_cumulative(o: &mut Observation, increment: u256){
        o.reserve_x_cumulative = o.reserve_x_cumulative + increment;
    }

    fun add_reserve_y_cumulative(o: &mut Observation, increment: u256){
        o.reserve_y_cumulative = o.reserve_y_cumulative + increment;
    }

    /// - LP's position
    struct LP_TOKEN<phantom X, phantom Y> has drop {}
    struct LP<phantom X, phantom Y> has key, store{
        id: UID,
        lp_balance: Balance<LP_TOKEN<X,Y>>,
        index_x: u256, //
        index_y: u256,
        claimable_x: u64,
        claimable_y: u64
    }
    /// When adding liquidity, make sure create lp position first
    public fun create_lp<X,Y>(self: &Pool<X,Y>, ctx: &mut TxContext):LP<X,Y>{
        LP<X,Y>{
            id: object::new(ctx),
            lp_balance: balance::zero<LP_TOKEN<X,Y>>(),
            index_x: self.fee.index_x,
            index_y: self.fee.index_y,
            claimable_x: 0,
            claimable_y: 0,
        }
    }

    /// IMPORTANT: all the claimable fees have to be settled before balance changes
    public entry fun join_lp<X,Y>(self: &Pool<X,Y>, payee_lp: &mut LP<X,Y>, payer_lp: &mut LP<X,Y>, value: u64){
        update_lp_(self, payee_lp);
        update_lp_(self, payer_lp);
        let balance = balance::split(&mut payer_lp.lp_balance, value);
        balance::join(&mut payee_lp.lp_balance, balance);
    }
    public entry fun delete_lp<X,Y>(lp: LP<X,Y>){
        let LP {
            id,
            lp_balance,
            index_x: _,
            index_y: _,
            claimable_x: _,
            claimable_y: _
        } = lp;
        balance::destroy_zero(lp_balance);
        object::delete(id);
    }
    public fun get_lp_balance<X,Y>(claim: &LP<X,Y>):u64{ balance::value(&claim.lp_balance) }
    public fun get_claimable_x<X,Y>(lp: &LP<X,Y>):u64{ lp.claimable_x }
    public fun get_claimable_y<X,Y>(lp: &LP<X,Y>):u64{ lp.claimable_y }

    // Flash Loan
    struct Receipt<phantom X, phantom Y, phantom T> {
        amount: u64,
        fee: u64,
    }

    // ===== Assertion =====
    fun assert_pool_unlocked<X, Y>(pool: &Pool<X, Y>){
        assert!(pool.locked == false, ERR_POOL_LOCK);
    }
    fun assert_valid_type<X,Y,T>(){
        let type = type_name::get<T>();
        assert!(type_name::get<X>() == type || type_name::get<Y>() == type, ERR_INVALID_TYPE);
    }

    // ===== getter =====
    public fun get_reserves<X, Y>(pool: &Pool<X, Y>): (u64, u64, u64) {
        (
            balance::value(&pool.reserve_x),
            balance::value(&pool.reserve_y),
            balance::supply_value(&pool.lp_supply)
        )
    }
    public fun get_stable<X,Y>(pool: &Pool<X,Y>):bool { pool.stable }

    public fun get_decimals_x<X, Y>(pool: &Pool<X,Y>): u8 { pool.decimal_x }

    public fun get_decimals_y<X, Y>(pool: &Pool<X,Y>): u8 { pool.decimal_y }

    public fun get_total_supply<X,Y>(self: &Pool<X,Y>): u64 { balance::supply_value(&self.lp_supply)}

    public fun get_last_timestamp<X,Y>(pool: &Pool<X,Y>):u64{ pool.last_block_timestamp }

    public fun calculate_fee(value: u64, fee: u8): u64{
        value * (fee as u64) / FEE_SCALING
    }

    /// b' (optimzied_) = (Y/X) * a, subjected to Y/X = b/a
    public fun quote(res_x:u64, res_y:u64, input_x:u64): u64{
        assert!(res_x > 0 && res_y > 0, ERR_EMPTY_INPUT);
        assert!(input_x > 0, ERR_EMPTY_INPUT);
        let res = ( res_y as u128 ) * ( input_x as u128) / ( res_x as u128);
        ( res as u64 )
    }

    /// T = input_type, input_x: inupt_amount
    public fun get_output<X,Y,T>(
        self: &Pool<X,Y>,
        input_x: u64,
    ):u64{
        get_output_<X,Y,T>(self, input_x - calculate_fee(input_x, self.fee.fee_percentage))
    }

    fun get_output_<X,Y,T>(
        self: &Pool<X,Y>,
        dx: u64,
    ):u64{
        let type_input = type_name::get<T>();
        let type_x = type_name::get<X>();
        let type_y = type_name::get<Y>();
        assert!( type_input == type_x || type_input == type_y, ERR_INVALID_TYPE);

        let (reserve_x, reserve_y, _) = get_reserves(self);
        if(type_x == type_input){
            if(self.stable){
            (formula::stable_swap_output(
                    dx,
                    reserve_x,
                    reserve_y,
                    math::pow(10, self.decimal_x),
                    math::pow(10, self.decimal_y)
                ) as u64)
            }else{
                (formula::variable_swap_output( dx, reserve_x, reserve_y) as u64)
            }
        }else{
            if(self.stable){
            (formula::stable_swap_output(
                    dx,
                    reserve_y,
                    reserve_x,
                    math::pow(10, self.decimal_y),
                    math::pow(10, self.decimal_x)
                ) as u64)
            }else{
                (formula::variable_swap_output( dx, reserve_y, reserve_x) as u64)
            }
        }
    }

    // ===== Setter =====
    public (friend) fun update_fee<X,Y>(self: &mut Pool<X,Y>, fee: u8){
        self.fee.fee_percentage = fee;
    }
    public (friend) fun udpate_lock<X,Y>(self: &mut Pool<X,Y>, locked: bool){
        self.locked = locked;
    }

    /// Adding liquidity, have to create LP first to record balance first
    public entry fun add_liquidity<X, Y>(
        self: &mut Pool<X, Y>,
        coin_x: Coin<X>,
        coin_y: Coin<Y>,
        lp: &mut LP<X,Y>, // should create in advance
        deposit_x_min:u64,
        deposit_y_min:u64,
        clock: &Clock,
        ctx:&mut TxContext
    ){
        assert_pool_unlocked(self);

        let (lp_bal, deposit_x, deposit_y) = add_liquidity_(self, coin_x, coin_y, deposit_x_min, deposit_y_min
        , clock, ctx);
        let lP_value = balance::value(&lp_bal);

        update_lp_(self, lp);
        balance::join(&mut lp.lp_balance, lp_bal);

        event::liquidity_added<X,Y>(deposit_x, deposit_y, lP_value)
    }

    /// - remove liquidity
    public entry fun remove_liquidity<X, Y>(
        self:&mut Pool<X, Y>,
        lp: &mut LP<X,Y>,
        value: u64,
        withdrawl_x_min:u64,
        withdrawl_y_min:u64,
        clock: &Clock,
        ctx:&mut TxContext
    ){
        assert_pool_unlocked(self);

        update_lp_(self, lp);
        let lp_token = coin::take(&mut lp.lp_balance, value, ctx);

        let ( withdrawl_x, withdrawl_y, burned_lp) = remove_liquidity_(self, lp_token, withdrawl_x_min, withdrawl_y_min, clock, ctx);

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

        event::liquidity_removed<X,Y>( withdrawl_value_x, withdrawl_value_y, burned_lp);
    }

    public entry fun swap_for_y<X, Y>(
        pool: &mut Pool<X, Y>,
        coin_x: Coin<X>,
        output_y_min: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        let coin_y = swap_for_y_dev(pool, coin_x, output_y_min, clock, ctx);

        transfer::public_transfer(coin_y, tx_context::sender(ctx));
    }
    public fun swap_for_y_dev<X, Y>(
        pool: &mut Pool<X, Y>,
        coin_x: Coin<X>,
        output_y_min: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ):Coin<Y>{
        assert_pool_unlocked(pool);

        let (coin_y, input, output) = swap_for_y_(pool, coin_x, output_y_min,clock, ctx);

        event::swap<X,Y>(input, output);

        coin_y
    }
    public entry fun swap_for_x<X, Y>(
        pool: &mut Pool<X, Y>,
        coin_y: Coin<Y>,
        output_x_min: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        let coin_x = swap_for_x_dev(pool, coin_y, output_x_min, clock, ctx,);

        transfer::public_transfer(
            coin_x,
            tx_context::sender(ctx)
        );
    }
    public fun swap_for_x_dev<X, Y>(
        pool: &mut Pool<X, Y>,
        coin_x: Coin<Y>,
        output_y_min: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ):Coin<X>{
        assert_pool_unlocked(pool);

        let (coin_x, input, output) = swap_for_x_(pool, coin_x, output_y_min, clock, ctx,);

        event::swap<X,Y>(input, output);

        coin_x
    }

    // - zap
    /// x: single assets LP hold; y: optimal output assets needed, ( X, Y ) = pool_reserves
    /// holded assumption: (X + dx) / ( Y - dy ) = ( x - dx) / y
    public entry fun zap_x<X,Y>(
        self: &mut Pool<X, Y>,
        coin_x: Coin<X>,
        lp: &mut LP<X,Y>,
        deposit_x_min:u64,
        deposit_y_min:u64,
        clock: &Clock,
        ctx:&mut TxContext
    ){
        assert_pool_unlocked(self);
        let value_x = coin::value<X>(&coin_x);
        let (res_x, _, _) = get_reserves(self);
        value_x = (formula::zap_optimized_output((res_x as u256), (value_x as u256), self.fee.fee_percentage) as u64);
        let coin_x_split = coin::split<X>(&mut coin_x, value_x, ctx);
        let output_min = get_output<X,Y,X>(self, value_x);
        let (coin_y, _, _) = swap_for_y_<X,Y>(self, coin_x_split, output_min, clock, ctx);
        add_liquidity<X,Y>(self, coin_x, coin_y, lp, deposit_x_min, deposit_y_min, clock, ctx);
    }
    public entry fun zap_y<X,Y>(
        self: &mut Pool<X, Y>,
        coin_y: Coin<Y>,
        lp: &mut LP<X,Y>,
        deposit_x_min:u64,
        deposit_y_min:u64,
        clock: &Clock,
        ctx:&mut TxContext
    ){
        assert_pool_unlocked(self);
        let value_y = coin::value<Y>(&coin_y);
        let (_, res_y, _) = get_reserves(self);
        value_y = (formula::zap_optimized_output((res_y as u256), (value_y as u256), self.fee.fee_percentage) as u64);
        let coin_y_split = coin::split<Y>(&mut coin_y, value_y, ctx);
        let output_min = get_output<X,Y,Y>(self, value_y);
        let (coin_x, _, _) = swap_for_x_<X,Y>(self, coin_y_split, output_min, clock, ctx);
        add_liquidity<X,Y>(self, coin_x, coin_y, lp, deposit_x_min, deposit_y_min,clock, ctx);
    }
    /// FlashLoan's fee revenue goes to LP holder
    public fun loan_x<X, Y>(
        self: &mut Pool<X,Y>,
        amount: u64,
        ctx: &mut TxContext
    ):(Coin<X>, Receipt<X,Y,X>){
        let (res_x, _,  _) = get_reserves(self);

        assert!( amount <= res_x, ERR_INSUFFICIENT_LOAN);
        let fee_percentage = ( self.fee.fee_percentage as u64 );
        let fee = amount / ( FEE_SCALING - fee_percentage ) * fee_percentage + 1;
        let loan = coin::take(&mut self.reserve_x, amount, ctx);

        (loan, Receipt{ amount, fee })
    }
    public fun loan_y<X, Y>(
        self: &mut Pool<X,Y>,
        amount: u64,
        ctx: &mut TxContext
    ):(Coin<Y>, Receipt<X,Y,Y>){
        let (_, res_y,  _) = get_reserves(self);

        assert!( amount <= res_y, ERR_INSUFFICIENT_LOAN);
        // charged fee is slightly hider than directly swapping.
        let fee_percentage = ( self.fee.fee_percentage as u64 );
        let fee = amount / ( FEE_SCALING - fee_percentage ) * fee_percentage + 1;
        let loan = coin::take(&mut self.reserve_y, amount, ctx);

        (loan, Receipt{ amount, fee })
    }
    public fun repay_loan_x<X,Y>(self: &mut Pool<X,Y>, payment: Coin<X>, receipt: Receipt<X,Y,X>, clock:&Clock, ctx: &mut TxContext) {
        let Receipt { amount, fee } = receipt;
        assert!(coin::value(&payment) == amount + fee, ERR_INVALID_REPAY);

        let coin_fee = coin::split(&mut payment, fee, ctx);
        coin::put(&mut self.fee.fee_x, coin_fee);
        update_fee_index_x_(self, fee);

        coin::put(&mut self.reserve_x, payment);
        update_timestamp_(self, clock);
    }
    public fun repay_loan_y<X,Y>(self: &mut Pool<X,Y>, payment: Coin<Y>, receipt: Receipt<X,Y,Y>, clock: &Clock, ctx: &mut TxContext) {
        let Receipt { amount, fee } = receipt;
        assert!(coin::value(&payment) == amount + fee, ERR_INVALID_REPAY);

        let coin_fee = coin::split(&mut payment, fee, ctx);
        coin::put(&mut self.fee.fee_y, coin_fee);
        update_fee_index_x_(self, fee);

        coin::put(&mut self.reserve_y, payment);
        update_timestamp_(self, clock);
    }

    // ====== MAIN_LOGIC ======
    public (friend) fun new<X, Y>(
        stable: bool,
        metadata_x: &CoinMetadata<X>,
        metadata_y: &CoinMetadata<Y>,
        fee_percentage: u8,
        ctx: &mut TxContext
    ):ID{
        let lp_supply = balance::create_supply(LP_TOKEN<X, Y>{});
        let ts = tx_context::epoch_timestamp_ms(ctx);
        let fee = Fee{
            fee_x: balance::zero<X>(),
            fee_y: balance::zero<Y>(),
            index_x: 0,
            index_y: 0,
            fee_percentage,
        };
        let observation = Observation{
            timestamp: ts,
            reserve_x_cumulative: 0,
            reserve_y_cumulative: 0
        };
        let pool = Pool<X,Y>{
            id: object::new(ctx),
            stable,
            locked: false,
            lp_supply,
            reserve_x: balance::zero<X>(),
            reserve_y: balance::zero<Y>(),
            reserve_lp: balance::zero<LP_TOKEN<X,Y>>(),

            decimal_x: coin::get_decimals(metadata_x),
            decimal_y: coin::get_decimals(metadata_y),

            last_block_timestamp: ts,
            last_price_x_cumulative: 0,
            last_price_y_cumulative: 0,
            observations: table_vec::singleton( observation, ctx),
            fee,
        };
        let pool_id = object::id(&pool);
        transfer::share_object(
            pool
        );
        pool_id
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
                assert!(opt_y >= deposit_y_min, ERR_INSIFFICIENT_INPUT);

                (input_x, opt_y)
            }else{
                let opt_x = quote(res_y, res_x, input_y);
                assert!(opt_x <= input_x, ERR_INSIFFICIENT_INPUT);
                assert!(opt_x >= deposit_x_min, ERR_INSIFFICIENT_INPUT);

                (opt_x, input_y)
            }
        }
    }
    fun add_liquidity_<X, Y>(
        pool: &mut Pool<X, Y>,
        coin_x: Coin<X>,
        coin_y: Coin<Y>,
        deposit_x_min:u64,
        deposit_y_min:u64,
        clock: &Clock,
        ctx:&mut TxContext
    ):(
        Balance<LP_TOKEN<X,Y>>,
        u64,
        u64
    ){
        let value_x = coin::value(&coin_x);
        let value_y = coin::value(&coin_y);
        assert!(value_x > 0 && value_y > 0, ERR_EMPTY_INPUT);

        // quote the inputs
        let (reserve_x, reserve_y, lp_supply) = get_reserves(pool);
        let ( coin_x, coin_y) = if (reserve_x == 0 && reserve_y == 0){
            (coin_x, coin_y)
        }else{
            let opt_y  = quote(reserve_x, reserve_y, value_x);
            if (opt_y <= value_y){
                assert!(opt_y >= deposit_y_min, ERR_INSIFFICIENT_INPUT);
                let take = if(coin::value(&coin_y) == opt_y){ // Optimized input
                    coin_y
                }else{
                    let take = coin::take<Y>(coin::balance_mut<Y>(&mut coin_y), opt_y, ctx);
                    transfer::public_transfer(coin_y, tx_context::sender(ctx));
                    take
                };
                (coin_x, take)
            }else{
                let opt_x = quote(reserve_y, reserve_x, value_y);
                assert!(opt_x <= value_x, ERR_INSIFFICIENT_INPUT);
                assert!(opt_x >= deposit_x_min, ERR_INSIFFICIENT_INPUT);
                let take = if(coin::value(&coin_x) == opt_y){ // Optimized input
                    coin_x
                }else{
                    let take = coin::take<X>(coin::balance_mut<X>(&mut coin_x), opt_x, ctx);
                    transfer::public_transfer(coin_x, tx_context::sender(ctx));
                    take
                };
                (take, coin_y)
            }
        };
        // mint LP
        let deposit_x = coin::value(&coin_x);
        let deposit_y = coin::value(&coin_y);
        let lp_output = if( balance::supply_value<LP_TOKEN<X,Y>>(&pool.lp_supply) == 0){
            let amount = (amm_math::mul_sqrt(deposit_x, deposit_y) - MINIMUM_LIQUIDITY);
            let min = balance::increase_supply<LP_TOKEN<X, Y>>(&mut pool.lp_supply, MINIMUM_LIQUIDITY);
            transfer::public_transfer(coin::from_balance(min,ctx), @0x00);
            amount
        }else{
            math::min(
                (( deposit_x as u128 ) * ( lp_supply as u128) / ( reserve_x as u128) as u64 ),
                (( deposit_y as u128 ) * ( lp_supply as u128) / ( reserve_y as u128) as u64 )
            )
        };
        // pool update
        update_timestamp_(pool, clock);
        balance::join<X>(&mut pool.reserve_x, coin::into_balance(coin_x));
        balance::join<Y>(&mut pool.reserve_y,  coin::into_balance(coin_y));

        let lp_balance = balance::increase_supply<LP_TOKEN<X, Y>>(&mut pool.lp_supply, lp_output);

        return (
            lp_balance,
            deposit_x,
            deposit_y,
        )
    }
    #[test_only]
    public fun remove_liquidity_validate<X, Y>(
        pool: &Pool<X,Y>,
        lp_value:u64,
        withdrawl_x_min:u64,
        withdrawl_y_min:u64,
    ):(u64, u64){
        let (res_x, res_y, lp_s) = get_reserves(pool);
        let withdrawl_x = quote(lp_s, res_x, lp_value);
        let withdrawl_y = quote(lp_s, res_y, lp_value);

        assert!(withdrawl_x > 0 && withdrawl_y > 0, ERR_EMPTY_INPUT);
        assert!(withdrawl_x >= withdrawl_x_min, ERR_INSIFFICIENT_INPUT);
        assert!(withdrawl_y >= withdrawl_y_min, ERR_INSIFFICIENT_INPUT);

        (withdrawl_x, withdrawl_y)
    }
    fun remove_liquidity_<X, Y>(
        pool:&mut Pool<X, Y>,
        lp_token:Coin<LP_TOKEN<X, Y>>,
        withdrawl_x_min:u64,
        withdrawl_y_min:u64,
        clock: &Clock,
        ctx:&mut TxContext
    ):(
        Coin<X>,
        Coin<Y>,
        u64,
    ){
        let lp_value = coin::value(&lp_token);
        assert!(lp_value > 0, ERR_EMPTY_INPUT);

        let (res_x, res_y, lp_s) = get_reserves(pool);
        let withdrawl_x = quote(lp_s, res_x, lp_value);
        let withdrawl_y = quote(lp_s, res_y, lp_value);

        assert!(withdrawl_x > 0 && withdrawl_y > 0, ERR_EMPTY_INPUT);
        assert!(withdrawl_x >= withdrawl_x_min, ERR_INSIFFICIENT_INPUT);
        assert!(withdrawl_y >= withdrawl_y_min, ERR_INSIFFICIENT_INPUT);

        update_timestamp_(pool, clock);
        let coin_x = coin::take<X>(&mut pool.reserve_x, withdrawl_x, ctx);
        let coin_y = coin::take<Y>(&mut pool.reserve_y, withdrawl_y, ctx);
        balance::decrease_supply<LP_TOKEN<X, Y>>(&mut pool.lp_supply,coin::into_balance(lp_token));

        return (
            coin_x,
            coin_y,
            lp_value
        )
    }
    fun swap_for_y_<X, Y>(
        self: &mut Pool<X, Y>,
        coin_x: Coin<X>,
        output_y_min: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ):(
        Coin<Y>,
        u64,
        u64
    ){
        let value_x = coin::value(&coin_x);
        let (reserve_x, reserve_y, _) = get_reserves(self);
        assert!(value_x > 0, ERR_EMPTY_INPUT);
        assert!(reserve_x > 0 && reserve_y > 0, ERR_EMPTY_RESERVE);

        let fee_x = calculate_fee(value_x, self.fee.fee_percentage);
        let dx = value_x - fee_x;

        let output_y =  get_output_<X,Y,X>(self, dx);
        assert!(output_y >= output_y_min, ERR_INSIFFICIENT_INPUT);
        let _res_x = balance::value(&self.reserve_x);
        let _res_y = balance::value(&self.reserve_y);
        update_timestamp_(self, clock);

        balance::join<X>(&mut self.reserve_x, coin::into_balance(coin_x));
        let coin_y = coin::take<Y>(&mut self.reserve_y, output_y, ctx);

        let coin_fee = coin::take(&mut self.reserve_x, fee_x, ctx);
        coin::put(&mut self.fee.fee_x, coin_fee);
        update_fee_index_x_(self, fee_x);

        if(self.stable){
            let (scale_x, scale_y) = ( math::pow(10, self.decimal_x), math::pow(10, self.decimal_y) );
            assert!(formula::k_(_res_x + value_x, _res_y, scale_x, scale_y) >= formula::k_(_res_x, _res_y, scale_x, scale_y), ERR_K);
        }else{
            assert!(((_res_x + value_x) as u128 ) * (_res_y as u128) >= (_res_x as u128) * (_res_y as u128), ERR_K);
        };

        return(
            coin_y,
            value_x,
            output_y
        )
    }

    fun swap_for_x_<X, Y>(
        self: &mut Pool<X, Y>,
        coin_y: Coin<Y>,
        output_x_min: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ):(
        Coin<X>,
        u64,
        u64
    ){
        let value_y = coin::value(&coin_y);
        let (reserve_x, reserve_y, _) = get_reserves(self);
        assert!(reserve_x > 0 && reserve_y > 0,ERR_EMPTY_RESERVE);
        assert!(value_y > 0, ERR_EMPTY_INPUT);

        let fee_y = calculate_fee(value_y, self.fee.fee_percentage);
        let dy = value_y - fee_y;
        let output_x =  get_output_<X,Y,Y>(self, dy);

        assert!(output_x >= output_x_min, ERR_INSIFFICIENT_INPUT);
        let _res_x = balance::value(&self.reserve_x);
        let _res_y = balance::value(&self.reserve_y);
        update_timestamp_(self, clock);

        let coin_y_balance = coin::into_balance(coin_y);
        balance::join<Y>(&mut self.reserve_y, coin_y_balance);

        let coin_y = coin::take<X>(&mut self.reserve_x, output_x, ctx);

        let coin_fee = coin::take(&mut self.reserve_y, fee_y, ctx);
        coin::put(&mut self.fee.fee_y, coin_fee);

        update_fee_index_y_(self, fee_y);

        if(self.stable){
            let (scale_x, scale_y) = ( math::pow(10, self.decimal_x), math::pow(10, self.decimal_y) );
            assert!(formula::k_(_res_x, _res_y + value_y, scale_x, scale_y) >= formula::k_(_res_x, _res_y, scale_x, scale_y), ERR_K);
        }else{
            assert!(((_res_x) as u128 ) * ((_res_y + value_y) as u128) >= (_res_x as u128) * (_res_y as u128), ERR_K);
        };

        return (
            coin_y,
            value_y,
            output_x
        )
    }

     /// Update cumulative reserves & oracle observations
    fun update_timestamp_<X,Y>(self: &mut Pool<X,Y>, clock: &Clock){
        let res_x = (balance::value<X>(&self.reserve_x) as u256);
        let res_y = (balance::value<Y>(&self.reserve_y) as u256);
        let ts = clock::timestamp_ms(clock);
        let elapsed = ( ts - self.last_block_timestamp );

        if(elapsed > 0 && res_x != 0 && res_y != 0){
            self.last_price_x_cumulative = self.last_price_x_cumulative + (res_x * (elapsed as u256));
            self.last_price_y_cumulative = self.last_price_y_cumulative + (res_y * (elapsed as u256));
        };

        let observation = get_latest_observation(self);
        elapsed = (ts - observation.timestamp);

        // record observation every 30 minutes
        if( elapsed > PERIOD_SIZE ){
            table_vec::push_back(&mut self.observations,
            Observation{
                timestamp: ts,
                reserve_x_cumulative: self.last_price_x_cumulative,
                reserve_y_cumulative: self.last_price_y_cumulative,
            })
        };
        self.last_block_timestamp = ts;
    }

    fun update_lp_<X,Y>(self: &Pool<X,Y>, lp_position: &mut LP<X,Y>){
        let lp_balance = get_lp_balance(lp_position);
        if(lp_balance > 0){
            // record down the percentage diffreence
            let delta_x = self.fee.index_x - lp_position.index_x;
            let delta_y = self.fee.index_y - lp_position.index_y;
            lp_position.index_x = self.fee.index_x;
            lp_position.index_y = self.fee.index_y;

            if(delta_x > 0){
                let share = (lp_balance as u256) * delta_x / SCALE_FACTOR;
                lp_position.claimable_x = lp_position.claimable_x + (share as u64);
            };
            if(delta_y > 0){
                let share = (lp_balance as u256) * delta_y / SCALE_FACTOR;
                lp_position.claimable_y = lp_position.claimable_y + (share as u64);
            };
        }else{
            lp_position.index_x = self.fee.index_x;
            lp_position.index_y = self.fee.index_y;
        };
    }
    /// Update global fee distribution when swapping
    fun update_fee_index_x_<X,Y>(self: &mut Pool<X,Y>, fee_x: u64 ){
        let ratio_x = (fee_x as u256) * SCALE_FACTOR / (get_total_supply(self) as u256);
        self.fee.index_x = self.fee.index_x + ratio_x;
        event::fee<X>(fee_x);
    }
    fun update_fee_index_y_<X,Y>(self: &mut Pool<X,Y>, fee_y: u64 ){
        let ratio_y = (fee_y as u256) * SCALE_FACTOR / (get_total_supply(self) as u256);
        self.fee.index_y = self.fee.index_y + ratio_y;
        event::fee<Y>(fee_y);
    }

    // - Oracle
    public fun current_cumulative_prices<X,Y>(
        self: &Pool<X,Y>,
        clock: &Clock
    ):(u256, u256){
        let ts = clock::timestamp_ms(clock);
        let observation = get_latest_observation(self);
        let reserve_x_cumulative = observation.reserve_x_cumulative;
        let reserve_y_cumulative = observation.reserve_y_cumulative;
        let (res_x, res_y, _) = get_reserves(self);

        if(observation.timestamp != ts){
            let time_elapsed = ts - observation.timestamp;
            reserve_x_cumulative = reserve_x_cumulative + (res_x as u256) * (time_elapsed as u256);
            reserve_y_cumulative = reserve_y_cumulative + (res_y as u256) * (time_elapsed as u256);
        };

        (reserve_x_cumulative, reserve_y_cumulative)
    }

    public fun current_y<X,Y>(
        self: &Pool<X,Y>,
        dx: u64,
        clock: &Clock
    ):u64{
        let ts = clock::timestamp_ms(clock);
        let observation = get_latest_observation(self);
        let ( reserve_x_cumulative, reserve_y_cumulative ) = current_cumulative_prices(self, clock);
        let len = table_vec::length(&self.observations);
        if(len == 1){
            // only gensis observation exist
            return 0
        }else if(ts == observation.timestamp){
            observation = table_vec::borrow(&self.observations, len -2 );
        };

        let elapsed = ts - observation.timestamp;
        let res_x = (reserve_x_cumulative - observation.reserve_x_cumulative) / (elapsed as u256);
        let res_y = (reserve_y_cumulative - observation.reserve_y_cumulative) / (elapsed as u256);
        formula::get_output(self.stable, dx, (res_x as u64), (res_y as u64), self.decimal_x, self.decimal_y)
    }
    public fun current_x<X,Y>(
        self: &Pool<X,Y>,
        dy: u64,
        clock: &Clock
    ):u64{
        let ts = clock::timestamp_ms(clock);
        let observation = get_latest_observation(self);
        let ( reserve_x_cumulative, reserve_y_cumulative ) = current_cumulative_prices(self, clock);
        let len = table_vec::length(&self.observations);
        if(len == 1){
            // only gensis observation exist
            return 0
        }else if(ts == observation.timestamp){
            observation = table_vec::borrow(&self.observations, len -2 );
        };

        let elapsed = ts - observation.timestamp;
        let res_x = (reserve_x_cumulative - observation.reserve_x_cumulative) / (elapsed as u256);
        let res_y = (reserve_y_cumulative - observation.reserve_y_cumulative) / (elapsed as u256);
        formula::get_output(self.stable, dy, (res_y as u64), (res_x as u64), self.decimal_y, self.decimal_x)
    }

    // TODO: remove public, currently for teseting usage
    // - Fee Distribution
    public entry fun claim_fees_player<X,Y>(
        self: &mut Pool<X,Y>,
        lp_position: &mut LP<X,Y>,
        ctx: &mut TxContext
    ){
        let (coin_x, coin_y ) = claim_fees_(self, lp_position, ctx);

        if(option::is_some(&coin_x)){
            let coin_x = option::extract(&mut coin_x);
            transfer::public_transfer(coin_x, tx_context::sender(ctx));
        };
        if(option::is_some(&coin_y)){
            let coin_y = option::extract(&mut coin_y);
            transfer::public_transfer(coin_y, tx_context::sender(ctx));
        };

        option::destroy_none(coin_x);
        option::destroy_none(coin_y);
    }

    public fun claim_fees_gauge<X,Y>(
        self: &mut Pool<X,Y>,
        lp_position: &mut LP<X,Y>,
        ctx: &mut TxContext
    ):(Option<Coin<X>>, Option<Coin<Y>>){
        claim_fees_(self, lp_position, ctx)
    }

    fun claim_fees_<X,Y>(
        self: &mut Pool<X,Y>,
        lp_position: &mut LP<X,Y>,
        ctx: &mut TxContext
    ):(Option<Coin<X>>, Option<Coin<Y>>){
        update_lp_(self, lp_position);

        let coin_x = if(lp_position.claimable_x > 0){
            let coin_x = coin::take(&mut self.fee.fee_x, lp_position.claimable_x, ctx);
            option::some(coin_x)
        }else{
            option::none<Coin<X>>()
        };
        let coin_y = if(lp_position.claimable_y > 0){
            let coin_y = coin::take(&mut self.fee.fee_y, lp_position.claimable_y, ctx);
            option::some(coin_y)
        }else{
            option::none<Coin<Y>>()
        };

        lp_position.claimable_x = 0;
        lp_position.claimable_y = 0;

        (coin_x, coin_y)
    }
}

