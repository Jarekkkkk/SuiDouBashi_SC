// SPDX-License-Identifier: MIT
module suiDouBashi_amm::pool{
    /// Package Version
    const VERSION: u64 = 1;

    use std::option::{Self, Option};
    use std::type_name;
    use std::string::String;
    use std::vector as vec;

    use sui::object::{Self,UID, ID};
    use sui::balance::{Self,Supply, Balance};
    use sui::coin::{Self,Coin, CoinMetadata};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::table_vec::{Self,TableVec};
    use sui::math;
    use sui::clock::{Self, Clock};

    use suiDouBashi_amm::event;
    use suiDouBashi_amm::amm_math;
    use suiDouBashi_vsdb::vsdb::{Self, Vsdb, VSDBRegistry};

    friend suiDouBashi_amm::pool_reg;

    // ====== Constants =======

    const FEE_SCALING: u64 = 10000;
    const PERIOD_SIZE: u64 = 1800; // 30 minutes TWAP
    const SCALE_FACTOR: u256 = 1_000_000_000_000_000_000;
    const DURATION: u64 = { 7 * 86400 };
    const MINIMUM_LIQUIDITY: u64 = 1_000;

    // ====== Constants =======

    // ====== Error =======

    const E_WRONG_VERSION: u64 = 001;

    const E_INVALID_TYPE: u64 = 100;
    const E_POOL_LOCK: u64 = 101;
    const E_EMPTY_INPUT: u64 = 102;
    const E_INSIFFICIENT_INPUT: u64 = 103;
    const E_EMPTY_RESERVE: u64 = 104;
    const E_K: u64 = 105;
    const E_INSUFFICIENT_LOAN: u64 = 106;
    const E_INVALID_REPAY: u64 = 107;

    // ====== Error =======

    // ====== Assertion =======

    fun assert_pool_unlocked<X, Y>(self: &Pool<X, Y>){
        assert!(self.locked == false, E_POOL_LOCK);
    }

    fun assert_valid_type<X,Y,T>(){
        let type = type_name::get<T>();
        assert!(type_name::get<X>() == type || type_name::get<Y>() == type, E_INVALID_TYPE);
    }

    // ====== Assertion =======

    /// iquidity Pools, allowing LP to deposit liquidity and Trader do the swap trade
    /// to provide access to the best rates, we define 2 types of pools: correlated/ uncorrelated
    /// correlated, for example stablecoins
    /// uncorrelated, for example SUI and USDC
    struct Pool<phantom X, phantom Y> has key {
        id: UID,
        name: String,
        version: u64,
        stable:bool,
        locked: bool,
        lp_supply: Supply<LP_TOKEN<X,Y>>,
        reserve_x: Balance<X>,
        reserve_y: Balance<Y>,
        decimal_x: u8,
        decimal_y: u8,
        last_update_time: u64,
        last_price_x_cumulative: u256,
        last_price_y_cumulative: u256,
        observations: TableVec<Observation>,
        fee:Fee<X,Y>,
    }
    /// Seperated fees revenue from pool reserves
    struct Fee<phantom X, phantom Y> has store{
        fee_x: Balance<X>,
        fee_y: Balance<Y>,
        index_x: u256,
        index_y: u256,
        fee_percentage: u8,
    }

    public fun name<X, Y>(self: &Pool<X,Y>):String{ self.name }

    public fun stable<X,Y>(self: &Pool<X,Y>):bool { self.stable }

    public fun get_reserves<X,Y>(self: &Pool<X,Y>): (u64, u64, u64) {
        (
            balance::value(&self.reserve_x),
            balance::value(&self.reserve_y),
            balance::supply_value(&self.lp_supply)
        )
    }

    public fun decimal_x<X, Y>(self: &Pool<X,Y>): u8 { self.decimal_x }

    public fun decimal_y<X, Y>(self: &Pool<X,Y>): u8 { self.decimal_y }

    public fun lp_supply<X,Y>(self: &Pool<X,Y>): u64 { balance::supply_value(&self.lp_supply)}

    public fun fee_x<X,Y>(self:&Pool<X,Y>):u64{ balance::value(&self.fee.fee_x) }

    public fun fee_y<X,Y>(self:&Pool<X,Y>):u64{ balance::value(&self.fee.fee_y) }

    public (friend) fun update_fee<X,Y>(self: &mut Pool<X,Y>, fee: u8){
        assert!(self.version == VERSION, E_WRONG_VERSION);
        self.fee.fee_percentage = fee;
    }

    public (friend) fun update_stable<X,Y>(self: &mut Pool<X,Y>, stable: bool){
        assert!(self.version == VERSION, E_WRONG_VERSION);
        self.stable = stable;
    }

    public (friend) fun udpate_lock<X,Y>(self: &mut Pool<X,Y>, locked: bool){
        assert!(self.version == VERSION, E_WRONG_VERSION);
        self.locked = locked;
    }

    /// Entry of dynamic fields/ dynamic object fields of Vsdb Vesting NFT
    struct AMM_SDB has copy, store, drop {}

    /// The state we are going to record on Vsdb
    struct AMMState has store{
        last_swap: u64,
        earneed_times: u8
    }

    public fun is_initialized(vsdb: &Vsdb): bool{
        vsdb::df_exists(vsdb, AMM_SDB {})
    }

    public entry fun initialize(reg: &VSDBRegistry, vsdb: &mut Vsdb){
        let value = AMMState{
            last_swap: 0,
            earneed_times: 0
        };
        vsdb::df_add(AMM_SDB{}, reg, vsdb, value);
    }

    fun earn_xp(vsdb: &mut Vsdb, clock: &Clock){
        let ts = unix_timestamp(clock);
        let amm_state = amm_state_borrow_mut(vsdb);

        if( ts / DURATION * DURATION > amm_state.last_swap) amm_state.earneed_times = 0;
        amm_state.last_swap = ts;

        if(amm_state.earneed_times < 3){
            amm_state.earneed_times = amm_state.earneed_times + 1;
            vsdb::earn_xp(AMM_SDB{}, vsdb, 2);
        };
    }

    public fun clear(vsdb: &mut Vsdb){
        let amm_state:AMMState = vsdb::df_remove(AMM_SDB{}, vsdb );
        let AMMState{
            last_swap:_,
            earneed_times: _
        } = amm_state;
    }

    public fun amm_state_borrow(vsdb: &Vsdb):&AMMState{
        vsdb::df_borrow(vsdb, AMM_SDB {})
    }

    fun amm_state_borrow_mut(vsdb: &mut Vsdb):&mut AMMState{
        vsdb::df_borrow_mut(vsdb, AMM_SDB {})
    }

    // - Oracle
    struct Observation has store {
        timestamp: u64,
        reserve_x_cumulative: u256,
        reserve_y_cumulative: u256,
    }

    fun get_observation<X,Y>(self: &Pool<X,Y>, idx: u64):&Observation{
        table_vec::borrow(&self.observations, idx)
    }

    public fun get_latest_observation<X,Y>(self: &Pool<X,Y>):&Observation{
        get_observation(self, table_vec::length(&self.observations) - 1)
    }

    // OTW of LP_TOKEN
    struct LP_TOKEN<phantom X, phantom Y> has drop {}

    /// LP position NFT, liquidity provider needs to own the LP NFT first to deposit/ withdraw liquidity
    struct LP<phantom X, phantom Y> has key, store{
        id: UID,
        lp_balance: Balance<LP_TOKEN<X,Y>>,
        index_x: u256,
        index_y: u256,
        claimable_x: u64,
        claimable_y: u64
    }

    public fun create_lp<X,Y>(self: &Pool<X,Y>, ctx: &mut TxContext):LP<X,Y>{
        assert!(self.version == VERSION, E_WRONG_VERSION);
        assert_pool_unlocked(self);
        LP<X,Y>{
            id: object::new(ctx),
            lp_balance: balance::zero<LP_TOKEN<X,Y>>(),
            index_x: self.fee.index_x,
            index_y: self.fee.index_y,
            claimable_x: 0,
            claimable_y: 0,
        }
    }

    // claimable fees have to be settled before balance changes
    public entry fun join_lp<X,Y>(
        self: &Pool<X,Y>,
        payee_lp: &mut LP<X,Y>,
        payer_lp: &mut LP<X,Y>,
        value: u64
    ){
        assert!(self.version == VERSION, E_WRONG_VERSION);
        assert_pool_unlocked(self);
        update_lp_(self, payee_lp);
        update_lp_(self, payer_lp);

        balance::join(&mut payee_lp.lp_balance, balance::split(&mut payer_lp.lp_balance, value));
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

    public fun lp_balance<X,Y>(claim: &LP<X,Y>):u64{ balance::value(&claim.lp_balance) }

    public fun claimable_x<X,Y>(self: &Pool<X,Y>, lp: &LP<X,Y>):u64{
        let lp_balance = lp_balance(lp);
        let claimable_x = lp.claimable_x;
        if(lp_balance > 0){
            let delta = self.fee.index_x - lp.index_x;
            if(delta > 0){
                let share = (lp_balance as u256) * delta / SCALE_FACTOR;
                claimable_x = claimable_x + (share as u64);
            };
        };
        claimable_x
    }

    public fun claimable_y<X,Y>(self: &Pool<X,Y>, lp: &LP<X,Y>):u64{
        let lp_balance = lp_balance(lp);
        let claimable_y = lp.claimable_y;
        if(lp_balance > 0){
            let delta = self.fee.index_y - lp.index_y;
            if(delta > 0){
                let share = (lp_balance as u256) * delta / SCALE_FACTOR;
                claimable_y = claimable_y + (share as u64);
            };
        };
        claimable_y
    }

    public fun calculate_fee(value: u64, fee_percentage: u8): u64{
        value * (fee_percentage as u64) / FEE_SCALING + 1
    }

    /// b' (optimzied_) = (Y/X) * a, subject to Y/X = b/a
    public fun quote(res_x:u64, res_y:u64, input_x:u64): u64{
        assert!(res_x > 0 && res_y > 0, E_EMPTY_INPUT);
        assert!(input_x > 0, E_EMPTY_INPUT);
        let res = ( res_y as u128 ) * ( input_x as u128) / ( res_x as u128);
        ( res as u64 )
    }

    /// T = input_type, input_x: inupt_amount
    public fun get_output<X,Y,T>(
        self: &Pool<X,Y>,
        input_x: u64,
    ):u64{
        assert_valid_type<X,Y,T>();
        let (res_x, res_y, _) = get_reserves(self);
        amm_math::get_output_<X,Y,T>(self.stable, input_x - calculate_fee(input_x, self.fee.fee_percentage), res_x, res_y, self.decimal_x, self.decimal_y)
    }

    public fun quote_add_liquidity<X,Y>(
        self: &Pool<X,Y>,
        value_x: u64,
        value_y: u64,
    ):(u64, u64, u64){
        let (reserve_x, reserve_y, lp_supply) = get_reserves(self);
        if(reserve_x == 0 && reserve_y == 0){
            return (value_x, value_y, (amm_math::mul_sqrt(value_x, value_y) - MINIMUM_LIQUIDITY))
        }else{
            let opt_y  = quote(reserve_x, reserve_y, value_x);
            let (deposit_x, deposit_y) = if (opt_y <= value_y){
                (value_x, opt_y)
            }else{
                let opt_x = quote(reserve_y, reserve_x, value_y);
                (opt_x, value_y)
            };
            return (
                deposit_x,
                deposit_y,
                math::min(
                    (( deposit_x as u128 ) * ( lp_supply as u128) / ( reserve_x as u128) as u64 ),
                    (( deposit_y as u128 ) * ( lp_supply as u128) / ( reserve_y as u128) as u64 )
                )
            )
        }
    }

    public fun quote_remove_liquidity<X,Y>(
        self: &Pool<X,Y>,
        value_lp: u64
    ):(u64, u64){
        let (reserve_x, reserve_y, lp_supply) = get_reserves(self);
        (quote(lp_supply, reserve_x, value_lp), quote(lp_supply, reserve_y, value_lp))
    }

    fun unix_timestamp(clock: &Clock):u64 { clock::timestamp_ms(clock)/ 1000 }

    public entry fun add_liquidity<X,Y>(
        self: &mut Pool<X,Y>,
        coin_x: Coin<X>,
        coin_y: Coin<Y>,
        lp: &mut LP<X,Y>,
        deposit_x_min:u64,
        deposit_y_min:u64,
        clock: &Clock,
        ctx:&mut TxContext
    ){
        assert_pool_unlocked(self);
        assert!(self.version == VERSION, E_WRONG_VERSION);

        update_lp_(self, lp);
        balance::join(&mut lp.lp_balance, add_liquidity_(self, coin_x, coin_y, deposit_x_min, deposit_y_min
        , clock, ctx));
    }

    public entry fun remove_liquidity<X,Y>(
        self:&mut Pool<X, Y>,
        lp: &mut LP<X,Y>,
        value: u64,
        withdrawl_x_min:u64,
        withdrawl_y_min:u64,
        clock: &Clock,
        ctx:&mut TxContext
    ){
        assert_pool_unlocked(self);
        assert!(self.version == VERSION, E_WRONG_VERSION);

        update_lp_(self, lp);
        let lp_token = coin::take(&mut lp.lp_balance, value, ctx);

        let ( withdrawl_x, withdrawl_y) = remove_liquidity_(self, lp_token, withdrawl_x_min, withdrawl_y_min, clock, ctx);

        transfer::public_transfer(
            withdrawl_x,
            tx_context::sender(ctx)
        );
        transfer::public_transfer(
            withdrawl_y,
            tx_context::sender(ctx)
        );
    }

    public entry fun swap_for_y_vsdb<X,Y>(
        self: &mut Pool<X,Y>,
        coin_x: Coin<X>,
        output_y_min: u64,
        vsdb: &mut Vsdb,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert_pool_unlocked(self);
        assert!(self.version == VERSION, E_WRONG_VERSION);

        earn_xp(vsdb, clock);
        let level = vsdb::level(vsdb);

        let fee_deduction = if(self.stable){
            level / 3
        }else{
            level
        };
        let fee_percentage = if(self.fee.fee_percentage <= fee_deduction){
            1
        }else{
            self.fee.fee_percentage - fee_deduction
        };

        let coin_y = swap_for_y_(self, option::some(fee_percentage), coin_x, output_y_min, clock, ctx);

        transfer::public_transfer(coin_y, tx_context::sender(ctx));
    }

    public entry fun swap_for_y<X,Y>(
        self: &mut Pool<X,Y>,
        coin_x: Coin<X>,
        output_y_min: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert_pool_unlocked(self);
        assert!(self.version == VERSION, E_WRONG_VERSION);

        transfer::public_transfer(swap_for_y_(self, option::none<u8>(), coin_x, output_y_min, clock, ctx), tx_context::sender(ctx));
    }

    public fun swap_for_y_dev<X,Y>(
        self: &mut Pool<X,Y>,
        coin_x: Coin<X>,
        output_y_min: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ):(Coin<Y>, u64){
        assert_pool_unlocked(self);
        assert!(self.version == VERSION, E_WRONG_VERSION);

        let coin_y = swap_for_y_(self, option::none<u8>(), coin_x, output_y_min, clock, ctx);
        let value_y = coin::value(&coin_y);

        (coin_y, value_y)
    }

    public entry fun swap_for_x_vsdb<X,Y>(
        self: &mut Pool<X,Y>,
        coin_x: Coin<Y>,
        output_x_min: u64,
        vsdb: &mut Vsdb,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert_pool_unlocked(self);
        assert!(self.version == VERSION, E_WRONG_VERSION);

        earn_xp(vsdb, clock);
        let level = vsdb::level(vsdb);

        let fee_deduction = if(self.stable){
            level / 3
        }else{
            level
        };
        let fee_percentage = if(self.fee.fee_percentage <= fee_deduction){
            1
        }else{
            self.fee.fee_percentage - fee_deduction
        };

        let coin_y = swap_for_x_(self, option::some(fee_percentage), coin_x, output_x_min, clock, ctx);

        transfer::public_transfer(coin_y, tx_context::sender(ctx));
    }

    public entry fun swap_for_x<X,Y>(
        self: &mut Pool<X,Y>,
        coin_y: Coin<Y>,
        output_x_min: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert_pool_unlocked(self);
        assert!(self.version == VERSION, E_WRONG_VERSION);

        transfer::public_transfer(
            swap_for_x_(self, option::none<u8>(), coin_y, output_x_min, clock, ctx),
            tx_context::sender(ctx)
        );
    }

    public fun swap_for_x_dev<X, Y>(
        self: &mut Pool<X, Y>,
        coin_x: Coin<Y>,
        output_y_min: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ):(Coin<X>, u64){
        assert_pool_unlocked(self);
        assert!(self.version == VERSION, E_WRONG_VERSION);

        let coin_x = swap_for_x_(self, option::none<u8>(),coin_x, output_y_min, clock, ctx);
        let value_x = coin::value(&coin_x);

        (coin_x, value_x)
    }

    // - zap
    /// zapping to variable pools can promise no additional deposit left, however there might be the mild deopsit returned when zapping into stable pools
    /// x: single assets LP hold; y: optimal output assets needed, ( X, Y ) = pool_reserves
    /// holded assumption: ( X + dx ) / ( Y - dy ) = ( x - dx ) / dy
    public entry fun zap_x<X,Y>(
        self: &mut Pool<X, Y>,
        coin_x: Coin<X>,
        lp: &mut LP<X,Y>,
        deposit_x_min: u64,
        deposit_y_min: u64,
        clock: &Clock,
        ctx:&mut TxContext
    ){
        assert_pool_unlocked(self);
        assert!(self.version == VERSION, E_WRONG_VERSION);

        let value_x = coin::value<X>(&coin_x);
        let (res_x, _, _) = get_reserves(self);
        value_x = if(self.stable){
            value_x / 2
        }else{
            amm_math::zap_optimized_input((res_x as u256), (value_x as u256), self.fee.fee_percentage)
        };
        let output_min = get_output<X,Y,X>(self, value_x);
        let coin_y = swap_for_y_<X,Y>(self, option::none<u8>(), coin::split<X>(&mut coin_x, value_x, ctx), output_min, clock, ctx);
        add_liquidity<X,Y>(self, coin_x, coin_y, lp, deposit_x_min, deposit_y_min, clock, ctx);
    }
    public entry fun zap_y<X,Y>(
        self: &mut Pool<X, Y>,
        coin_y: Coin<Y>,
        lp: &mut LP<X,Y>,
        deposit_x_min: u64,
        deposit_y_min: u64,
        clock: &Clock,
        ctx:&mut TxContext
    ){
        assert_pool_unlocked(self);
        assert!(self.version == VERSION, E_WRONG_VERSION);

        let value_y = coin::value<Y>(&coin_y);
        let (_, res_y, _) = get_reserves(self);
        value_y = if(self.stable){
            value_y / 2
        }else{
            amm_math::zap_optimized_input((res_y as u256), (value_y as u256), self.fee.fee_percentage)
        };
        let output_min = get_output<X,Y,Y>(self, value_y);
        let coin_x = swap_for_x_<X,Y>(self, option::none<u8>(),coin::split<Y>(&mut coin_y, value_y, ctx), output_min, clock, ctx);
        add_liquidity<X,Y>(self, coin_x, coin_y, lp, deposit_x_min, deposit_y_min,  clock, ctx);
    }

    // Flash Loan
    struct Receipt<phantom X, phantom Y, phantom T> {
        amount: u64,
        fee: u64
    }

    /// FlashLoan's fee revenue goes to LP holder
    public fun loan_x<X, Y>(
        self: &mut Pool<X,Y>,
        amount: u64,
        ctx: &mut TxContext
    ):(Coin<X>, Receipt<X,Y,X>){
        assert_pool_unlocked(self);
        assert!(self.version == VERSION, E_WRONG_VERSION);

        let (res_x, _,  _) = get_reserves(self);

        assert!( amount <= res_x, E_INSUFFICIENT_LOAN);
        let fee_percentage = ( self.fee.fee_percentage as u64 );
        // charged fee is slightly higher than directly swapping
        let fee = amount / ( FEE_SCALING - fee_percentage ) * fee_percentage + 1;
        let loan = coin::take(&mut self.reserve_x, amount, ctx);

        (loan, Receipt{ amount, fee })
    }

    public fun loan_y<X, Y>(
        self: &mut Pool<X,Y>,
        amount: u64,
        ctx: &mut TxContext
    ):(Coin<Y>, Receipt<X,Y,Y>){
        assert_pool_unlocked(self);
        assert!(self.version == VERSION, E_WRONG_VERSION);

        let (_, res_y,  _) = get_reserves(self);

        assert!( amount <= res_y, E_INSUFFICIENT_LOAN);
        let fee_percentage = ( self.fee.fee_percentage as u64 );
        let fee = amount / ( FEE_SCALING - fee_percentage ) * fee_percentage + 1;
        let loan = coin::take(&mut self.reserve_y, amount, ctx);

        (loan, Receipt{ amount, fee })
    }

    public fun repay_loan_x<X,Y>(
        self: &mut Pool<X,Y>,
        payment: Coin<X>,
        receipt: Receipt<X,Y,X>,
        clock:&Clock,
        ctx: &mut TxContext
    ) {
        assert!(self.version == VERSION, E_WRONG_VERSION);
        let Receipt { amount, fee } = receipt;
        assert!(coin::value(&payment) == amount + fee, E_INVALID_REPAY);

        let coin_fee = coin::split(&mut payment, fee, ctx);
        coin::put(&mut self.fee.fee_x, coin_fee);
        update_fee_index_x_(self, fee);

        coin::put(&mut self.reserve_x, payment);
        update_timestamp_(self, clock);
    }

    public fun repay_loan_y<X,Y>(
        self: &mut Pool<X,Y>,
        payment: Coin<Y>,
        receipt: Receipt<X,Y,Y>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(self.version == VERSION, E_WRONG_VERSION);
        let Receipt { amount, fee } = receipt;
        assert!(coin::value(&payment) == amount + fee, E_INVALID_REPAY);

        let coin_fee = coin::split(&mut payment, fee, ctx);
        coin::put(&mut self.fee.fee_y, coin_fee);
        update_fee_index_x_(self, fee);

        coin::put(&mut self.reserve_y, payment);
        update_timestamp_(self, clock);
    }

    // ====== MAIN_LOGIC ======
    public (friend) fun new<X, Y>(
        name: String,
        stable: bool,
        metadata_x: &CoinMetadata<X>,
        metadata_y: &CoinMetadata<Y>,
        fee_percentage: u8,
        ctx: &mut TxContext
    ):ID{
        let lp_supply = balance::create_supply(LP_TOKEN<X, Y>{});
        let ts = tx_context::epoch_timestamp_ms(ctx) / 1000;
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
            name,
            version: VERSION,
            stable,
            locked: false,
            lp_supply,
            reserve_x: balance::zero<X>(),
            reserve_y: balance::zero<Y>(),

            decimal_x: coin::get_decimals(metadata_x),
            decimal_y: coin::get_decimals(metadata_y),

            last_update_time: ts,
            last_price_x_cumulative: 0,
            last_price_y_cumulative: 0,
            observations: table_vec::singleton(observation, ctx),
            fee,
        };
        let pool_id = object::id(&pool);
        transfer::share_object(
            pool
        );
        pool_id
    }
    fun add_liquidity_<X,Y>(
        self: &mut Pool<X, Y>,
        coin_x: Coin<X>,
        coin_y: Coin<Y>,
        deposit_x_min:u64,
        deposit_y_min:u64,
        clock: &Clock,
        ctx:&mut TxContext
    ):(
        Balance<LP_TOKEN<X,Y>>
    ){
        let value_x = coin::value(&coin_x);
        let value_y = coin::value(&coin_y);
        assert!(value_x > 0 && value_y > 0, E_EMPTY_INPUT);
        let (reserve_x, reserve_y, lp_supply) = get_reserves(self);
        // quote
        let ( coin_x, coin_y) = if (reserve_x == 0 && reserve_y == 0){
            (coin_x, coin_y)
        }else{
            let opt_y  = quote(reserve_x, reserve_y, value_x);
            if (opt_y <= value_y){
                assert!(opt_y >= deposit_y_min, E_INSIFFICIENT_INPUT);
                let take = if(coin::value(&coin_y) == opt_y){ // Optimized input
                    coin_y
                }else{
                    let take = coin::split<Y>(&mut coin_y, opt_y, ctx);
                    transfer::public_transfer(coin_y, tx_context::sender(ctx));
                    take
                };
                (coin_x, take)
            }else{
                let opt_x = quote(reserve_y, reserve_x, value_y);
                assert!(opt_x <= value_x, E_INSIFFICIENT_INPUT);
                assert!(opt_x >= deposit_x_min, E_INSIFFICIENT_INPUT);
                let take = if(coin::value(&coin_x) == opt_y){ // Optimized input
                    coin_x
                }else{
                    let take = coin::split(&mut coin_x, opt_x, ctx);
                    transfer::public_transfer(coin_x, tx_context::sender(ctx));
                    take
                };
                (take, coin_y)
            }
        };
        // mint LP
        let deposit_x = coin::value(&coin_x);
        let deposit_y = coin::value(&coin_y);
        let lp_output = if(balance::supply_value<LP_TOKEN<X,Y>>(&self.lp_supply) == 0){
            let amount = (amm_math::mul_sqrt(deposit_x, deposit_y) - MINIMUM_LIQUIDITY);
            let min = balance::increase_supply<LP_TOKEN<X, Y>>(&mut self.lp_supply, MINIMUM_LIQUIDITY);
            transfer::public_transfer(coin::from_balance(min,ctx), @0x00);
            amount
        }else{
            math::min(
                (( deposit_x as u128 ) * ( lp_supply as u128) / ( reserve_x as u128) as u64 ),
                (( deposit_y as u128 ) * ( lp_supply as u128) / ( reserve_y as u128) as u64 )
            )
        };
        // pool update
        update_timestamp_(self, clock);
        balance::join<X>(&mut self.reserve_x, coin::into_balance(coin_x));
        balance::join<Y>(&mut self.reserve_y,  coin::into_balance(coin_y));

        event::liquidity_added<X,Y>(deposit_x, deposit_y, lp_output);

        balance::increase_supply<LP_TOKEN<X, Y>>(&mut self.lp_supply, lp_output)
    }

    fun remove_liquidity_<X, Y>(
        self:&mut Pool<X, Y>,
        lp_token:Coin<LP_TOKEN<X, Y>>,
        withdrawl_x_min:u64,
        withdrawl_y_min:u64,
        clock: &Clock,
        ctx:&mut TxContext
    ):(
        Coin<X>,
        Coin<Y>,
    ){
        let lp_value = coin::value(&lp_token);
        assert!(lp_value > 0, E_EMPTY_INPUT);

        let (res_x, res_y, lp_s) = get_reserves(self);
        let (withdrawl_x, withdrawl_y) = (quote(lp_s, res_x, lp_value), quote(lp_s, res_y, lp_value));

        assert!(withdrawl_x > 0 && withdrawl_y > 0, E_EMPTY_INPUT);
        assert!(withdrawl_x >= withdrawl_x_min, E_INSIFFICIENT_INPUT);
        assert!(withdrawl_y >= withdrawl_y_min, E_INSIFFICIENT_INPUT);

        update_timestamp_(self, clock);
        balance::decrease_supply<LP_TOKEN<X, Y>>(&mut self.lp_supply,coin::into_balance(lp_token));

        event::liquidity_removed<X,Y>( withdrawl_x, withdrawl_y, lp_value);

        return (
            coin::take<X>(&mut self.reserve_x, withdrawl_x, ctx),
            coin::take<Y>(&mut self.reserve_y, withdrawl_y, ctx),
        )
    }

    fun swap_for_y_<X,Y>(
        self: &mut Pool<X, Y>,
        fee_percentage: Option<u8>,
        coin_x: Coin<X>,
        output_y_min: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ):(
        Coin<Y>
    ){
        let value_x = coin::value(&coin_x);
        let (reserve_x, reserve_y, _) = get_reserves(self);
        assert!(value_x > 0, E_EMPTY_INPUT);
        assert!(reserve_x > 0 && reserve_y > 0, E_EMPTY_RESERVE);

        let _fee_percentage = if(option::is_some(&fee_percentage)){
            option::extract(&mut fee_percentage)
        }else{
            self.fee.fee_percentage
        };
        option::destroy_none(fee_percentage);
        let fee_x = calculate_fee(value_x, _fee_percentage);

        let dx = value_x - fee_x;
        let output_y =  amm_math::get_output_<X,Y,X>(self.stable, dx, reserve_x, reserve_y, self.decimal_x, self.decimal_y);
        assert!(output_y >= output_y_min, E_INSIFFICIENT_INPUT);
        update_timestamp_(self, clock);
        balance::join<X>(&mut self.reserve_x, coin::into_balance(coin_x));

        coin::put(&mut self.fee.fee_x, coin::take(&mut self.reserve_x, fee_x, ctx));
        update_fee_index_x_(self, fee_x);

        if(self.stable){
            let (scale_x, scale_y) = ( math::pow(10, self.decimal_x), math::pow(10, self.decimal_y) );
            assert!(amm_math::k_(reserve_x + value_x, reserve_y, scale_x, scale_y) >= amm_math::k_(reserve_x, reserve_y, scale_x, scale_y), E_K);
        }else{
            assert!(((reserve_x + value_x) as u128 ) * (reserve_y as u128) >= (reserve_x as u128) * (reserve_y as u128), E_K);
        };

        event::swap<X,Y>(value_x, output_y);

        coin::take<Y>(&mut self.reserve_y, output_y, ctx)
    }

    fun swap_for_x_<X, Y>(
        self: &mut Pool<X, Y>,
        fee_percentage: Option<u8>,
        coin_y: Coin<Y>,
        output_x_min: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ):(
        Coin<X>,
    ){
        let value_y = coin::value(&coin_y);
        let (reserve_x, reserve_y, _) = get_reserves(self);
        assert!(reserve_x > 0 && reserve_y > 0,E_EMPTY_RESERVE);
        assert!(value_y > 0, E_EMPTY_INPUT);

        let _fee_percentage = if(option::is_some(&fee_percentage)){
            option::extract(&mut fee_percentage)
        }else{
            self.fee.fee_percentage
        };
        option::destroy_none(fee_percentage);
        let fee_y = calculate_fee(value_y, _fee_percentage);

        let dy = value_y - fee_y;
        let output_x =  amm_math::get_output_<X,Y,Y>(self.stable, dy, reserve_x, reserve_y, self.decimal_x, self.decimal_y);
        assert!(output_x >= output_x_min, E_INSIFFICIENT_INPUT);
        update_timestamp_(self, clock);
        balance::join<Y>(&mut self.reserve_y, coin::into_balance(coin_y));

        coin::put(&mut self.fee.fee_y, coin::take(&mut self.reserve_y, fee_y, ctx));
        update_fee_index_y_(self, fee_y);

        if(self.stable){
            let (scale_x, scale_y) = ( math::pow(10, self.decimal_x), math::pow(10, self.decimal_y) );
            assert!(amm_math::k_(reserve_x, reserve_y + value_y, scale_x, scale_y) >= amm_math::k_(reserve_x, reserve_y, scale_x, scale_y), E_K);
        }else{
            assert!(((reserve_x) as u128 ) * ((reserve_y + value_y) as u128) >= (reserve_x as u128) * (reserve_y as u128), E_K);
        };

        event::swap<X,Y>(value_y, output_x);

        coin::take<X>(&mut self.reserve_x, output_x, ctx)
    }

    /// Update cumulative reserves & oracle observations
    fun update_timestamp_<X,Y>(self: &mut Pool<X,Y>, clock: &Clock){
        let res_x = (balance::value<X>(&self.reserve_x) as u256);
        let res_y = (balance::value<Y>(&self.reserve_y) as u256);
        let ts = unix_timestamp(clock);
        let elapsed = ( ts - self.last_update_time );

        if(elapsed > 0 && res_x != 0 && res_y != 0){
            self.last_price_x_cumulative = self.last_price_x_cumulative + (res_x * (elapsed as u256));
            self.last_price_y_cumulative = self.last_price_y_cumulative + (res_y * (elapsed as u256));
        };

        elapsed = (ts - get_latest_observation(self).timestamp);
        // record observation every 30 minutes
        if( elapsed > PERIOD_SIZE ){
            table_vec::push_back(&mut self.observations,
            Observation{
                timestamp: ts,
                reserve_x_cumulative: self.last_price_x_cumulative,
                reserve_y_cumulative: self.last_price_y_cumulative,
            })
        };
        self.last_update_time = ts;
    }

    /// IMPORTANT: have to be called for settlement before any lp balance updated
    fun update_lp_<X,Y>(self: &Pool<X,Y>, lp_position: &mut LP<X,Y>){
        let lp_balance = lp_balance(lp_position);
        if(lp_balance > 0){
            let delta_x = self.fee.index_x - lp_position.index_x;
            let delta_y = self.fee.index_y - lp_position.index_y;

            if(delta_x > 0){
                lp_position.claimable_x = lp_position.claimable_x + ((lp_balance as u256) * delta_x / SCALE_FACTOR as u64);
            };
            if(delta_y > 0){
                lp_position.claimable_y = lp_position.claimable_y + ((lp_balance as u256) * delta_y / SCALE_FACTOR as u64);
            };
        };
        lp_position.index_x = self.fee.index_x;
        lp_position.index_y = self.fee.index_y;
    }

    fun update_fee_index_x_<X,Y>(self: &mut Pool<X,Y>, fee_x: u64 ){
        self.fee.index_x = self.fee.index_x + (fee_x as u256) * SCALE_FACTOR / (lp_supply(self) as u256);
        event::fee<X>(fee_x);
    }

    fun update_fee_index_y_<X,Y>(self: &mut Pool<X,Y>, fee_y: u64 ){
        self.fee.index_y = self.fee.index_y + (fee_y as u256) * SCALE_FACTOR / (lp_supply(self) as u256);
        event::fee<Y>(fee_y);
    }

    // - Oracle
    public fun current_cumulative_prices<X,Y>(
        self: &Pool<X,Y>,
        clock: &Clock
    ):(u256, u256){
        let ts = unix_timestamp(clock);
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

    /// <T>, Input Type
    /// dx, Input Amount
    public fun current<X,Y,T>(
        self: &Pool<X,Y>,
        dx: u64,
        clock: &Clock
    ):u64{
        assert_valid_type<X,Y,T>();
        let ts = unix_timestamp(clock);
        let observation = get_latest_observation(self);
        let ( reserve_x_cumulative, reserve_y_cumulative ) = current_cumulative_prices(self, clock);
        let len = table_vec::length(&self.observations);
        if(len == 1){
            return 0
        }else if(ts == observation.timestamp){
            observation = table_vec::borrow(&self.observations, len - 2 );
        };

        let elapsed = ts - observation.timestamp;
        amm_math::get_output_<X,Y,T>(self.stable, dx, (((reserve_x_cumulative - observation.reserve_x_cumulative) / (elapsed as u256)) as u64), (((reserve_y_cumulative - observation.reserve_y_cumulative) / (elapsed as u256)) as u64), self.decimal_x, self.decimal_y)
    }

    public fun quote_TWAP<X,Y,T>(self: &Pool<X,Y>, input: u64, granularity: u64): u64{
        assert_valid_type<X,Y,T>();
        let prices = prices<X,Y,T>(self, input, granularity);
        let cumulative = 0;
        let (i, len) = (0, vec::length(&prices));
        while( i < len ){
            cumulative = cumulative + *vec::borrow(&prices, i);
            i = i + 1 ;
        };
        cumulative / granularity
    }

    public fun prices<X,Y,T>(self: &Pool<X,Y>, input: u64, points: u64): vector<u64> {
        assert_valid_type<X,Y,T>();
        smaple<X,Y,T>(self, input, points, 1)
    }

    public fun smaple<X,Y,T>(self: &Pool<X,Y>, input: u64, points: u64, size: u64):vector<u64>{
        assert_valid_type<X,Y,T>();
        let (prices, len) = (vec::empty<u64>(), table_vec::length(&self.observations) - 1);
        let (start_idx, _next_idx) = (len - ( points * size ), 0);

        while( start_idx < len ){
            _next_idx = start_idx + size;

            let next_observation = table_vec::borrow(&self.observations, _next_idx);
            let start_observation = table_vec::borrow(&self.observations, start_idx);

            let elapsed = next_observation.timestamp - start_observation.timestamp;
            let res_x = (next_observation.reserve_x_cumulative - start_observation.reserve_x_cumulative) / (elapsed as u256);
            let res_y = (next_observation.reserve_y_cumulative - start_observation.reserve_y_cumulative) / (elapsed as u256);
            vec::push_back(&mut prices, amm_math::get_output_<X,Y,T>(self.stable, input, (res_x as u64), (res_y as u64), self.decimal_x, self.decimal_y));

            start_idx = start_idx + size ;
        };
        prices
    }

    public entry fun claim_fees_player<X,Y>(
        self: &mut Pool<X,Y>,
        lp_position: &mut LP<X,Y>,
        ctx: &mut TxContext
    ){
        assert!(self.version == VERSION, E_WRONG_VERSION);
        let (coin_x, coin_y, _, _ ) = claim_fees_(self, lp_position, ctx);

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

    public fun claim_fees_dev<X,Y>(
        self: &mut Pool<X,Y>,
        lp_position: &mut LP<X,Y>,
        ctx: &mut TxContext
    ):(Option<Coin<X>>, Option<Coin<Y>>, u64, u64){
        assert!(self.version == VERSION, E_WRONG_VERSION);
        claim_fees_(self, lp_position, ctx)
    }

    fun claim_fees_<X,Y>(
        self: &mut Pool<X,Y>,
        lp_position: &mut LP<X,Y>,
        ctx: &mut TxContext
    ):(Option<Coin<X>>, Option<Coin<Y>>, u64, u64){
        update_lp_(self, lp_position);

        let claimable_x = lp_position.claimable_x;
        let claimable_y = lp_position.claimable_y;

        let coin_x = if( claimable_x> 0){
            option::some(coin::take(&mut self.fee.fee_x, claimable_x, ctx))
        }else{
            option::none<Coin<X>>()
        };
        let coin_y = if(claimable_y > 0){
            option::some(coin::take(&mut self.fee.fee_y, claimable_y, ctx))
        }else{
            option::none<Coin<Y>>()
        };

        lp_position.claimable_x = 0;
        lp_position.claimable_y = 0;

        (coin_x, coin_y, claimable_x, claimable_y)
    }
}

