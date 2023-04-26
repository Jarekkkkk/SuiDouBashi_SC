#[test_only]
module test::amm_test{
    use sui::coin::{Self, Coin, mint_for_testing as mint, burn_for_testing as burn,  CoinMetadata };
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::clock::{Self, Clock};
    use suiDouBashi::amm_math;
    use sui::math;
    use suiDouBashi::formula;
    use sui::transfer;

    use suiDouBashi::pool::{Self, Pool, LP};
    use suiDouBashi::pool_reg::{Self, PoolReg};
    use suiDouBashi::dai::{Self, DAI};
    use suiDouBashi::usdc::{Self, USDC};

    const MINIMUM_LIQUIDITY: u64 = 1000;

    //X/Y = 1/2
    const DAI_AMT:u64 = 9_000_000;
    const USDC_AMT: u64 = 10_000_000;

    const FEE: u64 = 3;

    #[test]
    fun test_init_pool(){
        let scenario = test::begin(@0x1);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        dai::deploy_coin(ctx(&mut scenario));
        usdc::deploy_coin(ctx(&mut scenario));
        test_init_pool_<DAI, USDC>(&mut clock, &mut scenario);

        clock::destroy_for_testing(clock);
        test::end(scenario);
    }
    #[test]
    fun test_add_liquidity() {
        let scenario = test::begin(@0x1);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        dai::deploy_coin(ctx(&mut scenario));
        usdc::deploy_coin(ctx(&mut scenario));

        let deposit_x = 30000;
        let deposit_y = 3000;
        add_liquidity_<DAI, USDC>(deposit_x, deposit_y, &mut clock, &mut scenario);

        clock::destroy_for_testing(clock);
        test::end(scenario);
    }
    #[test]
    fun test_swap_for_y() {
        let scenario = test::begin(@0x1);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        dai::deploy_coin(ctx(&mut scenario));
        usdc::deploy_coin(ctx(&mut scenario));
        test_swap_for_y_<DAI,USDC>(DAI_AMT, USDC_AMT, &mut clock, &mut scenario);

        clock::destroy_for_testing(clock);
        test::end(scenario);
    }
    #[test]
    fun test_swap_for_x() {
        let scenario = test::begin(@0x1);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        dai::deploy_coin(ctx(&mut scenario));
        usdc::deploy_coin(ctx(&mut scenario));
        test_swap_for_x_<DAI, USDC>(DAI_AMT, USDC_AMT, &mut clock, &mut scenario);

        clock::destroy_for_testing(clock);
        test::end(scenario);
    }
    #[test]
    fun test_remove_liquidity() {
        let scenario = test::begin(@0x1);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        dai::deploy_coin(ctx(&mut scenario));
        usdc::deploy_coin(ctx(&mut scenario));
        remove_liquidity_<DAI, USDC>(DAI_AMT, USDC_AMT, &mut clock, &mut scenario);

        clock::destroy_for_testing(clock);
        test::end(scenario);
    }
    #[test]
    fun test_zap_x(){
        let scenario = test::begin(@0x1);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        dai::deploy_coin(ctx(&mut scenario));
        usdc::deploy_coin(ctx(&mut scenario));
        zap_x_<DAI, USDC>(DAI_AMT, USDC_AMT,&mut  clock, &mut scenario);

        clock::destroy_for_testing(clock);
        test::end(scenario);
    }
    fun test_init_pool_<X, Y>(_clock: &mut Clock, test:&mut Scenario) {
        let ( creator, _) = people();

        next_tx(test, creator);{
            pool_reg::init_for_testing(ctx(test));
        };

        next_tx(test, creator); {//create pool
            let meta_x = test::take_immutable<CoinMetadata<X>>(test);
            let meta_y = test::take_immutable<CoinMetadata<Y>>(test);
            let pool_gov = test::take_shared<PoolReg>(test);
            pool_reg::create_pool<X, Y>(
                &mut pool_gov,
                false,
                &meta_x,
                &meta_y,
                FEE,
                ctx(test)
            );

            test::return_shared(pool_gov);
            test::return_immutable<CoinMetadata<X>>(meta_x);
            test::return_immutable<CoinMetadata<Y>>(meta_y);
        };

        next_tx(test, creator);{//shared_pool
            let pool = test::take_shared<Pool< X, Y>>(test);
            let pool_gov = test::take_shared<PoolReg>(test);
            let (res_x, res_y, _lp_s) = pool::get_reserves< X, Y>(&mut pool);

            assert!(res_x == 0, 0);
            assert!(res_y == 0, 0);

            test::return_shared(pool);
            test::return_shared(pool_gov)
            ;
        };
     }
    fun add_liquidity_<X, Y>(deposit_x: u64, deposit_y:u64, clock: &mut Clock, test: &mut Scenario){
        let (creator, _) = people();
        next_tx(test, creator);{
            test_init_pool_< X, Y>(clock, test);
        };
        next_tx(test, creator);
        let minted_lp ={
            let pool = test::take_shared<Pool< X, Y>>(test);
            let (res_x, res_y, lp_supply) = pool::get_reserves< X, Y>(&mut pool);
            let lp = pool::create_lp(&pool, ctx(test));

            pool::add_liquidity(&mut pool, mint<X>(deposit_x, ctx(test)), mint<Y>(deposit_y, ctx(test)), &mut lp, 0, 0 , clock , ctx(test));

            transfer::public_transfer(lp, creator);
            test::return_shared(pool);

            if(lp_supply == 0){
                (amm_math::mul_sqrt(deposit_x, deposit_y) - MINIMUM_LIQUIDITY)
            }else{
                math::min(
                    amm_math::mul_div(deposit_x, lp_supply, res_x),
                    amm_math::mul_div(deposit_y, lp_supply, res_y),
                )
            }
        };
        next_tx(test, creator);{
            let pool = test::take_shared<Pool< X, Y>>(test);
            let lp_position = test::take_from_sender<LP<X,Y>>(test);
            let lp_value = pool::get_lp_balance(&lp_position);

            assert!(lp_value == minted_lp, 0);

            test::return_to_sender(test, lp_position);
            test::return_shared(pool);
        }
    }
    fun test_swap_for_y_<X, Y>(amt_x: u64, amt_y:u64, clock: &mut Clock, test: &mut Scenario){
        let (_, trader) = people();
        let input_x = 500000;

        add_liquidity_< X, Y>(amt_x, amt_y, clock, test);

        next_tx(test, trader);
        let swap_y = {// swap X for Y
            let pool = test::take_shared<Pool< X, Y>>(test);
            let (res_x, res_y, _) = pool::get_reserves< X, Y>(&mut pool);
            let coin_x =  mint<X>(input_x, ctx(test));

            let scale_x = math::pow(10, pool::get_decimals_x(&pool));
            let scale_y = math::pow(10, pool::get_decimals_y(&pool));
            let dx = input_x - pool::calculate_fee(input_x, 3);

            let desired_y = if(pool::get_stable<X,Y>(&pool)){
             (formula::stable_swap_output(dx, res_x, res_y, scale_x, scale_y) as u64)
            }else{
                (formula::variable_swap_output(dx, res_x, res_y) as u64)
            };

            pool::swap_for_y< X, Y>(&mut pool, coin_x, 0 , clock, ctx(test));
            test::return_shared(pool);
            desired_y
        };
        next_tx(test, trader);{
            let coin_y = test::take_from_sender<Coin<Y>>(test);
            let coin_value = coin::value(&coin_y);
            assert!(coin_value == swap_y, 0);
            test::return_to_sender(test, coin_y);
        }
    }
    fun test_swap_for_x_<X, Y>(amt_x: u64, amt_y:u64, clock: &mut Clock, test: &mut Scenario){
        let (_, trader) = people();
        let input_y = 5000;

        add_liquidity_< X, Y>(amt_x, amt_y, clock, test);

        next_tx(test, trader);
        let swap_x = {// swap Y for X
            let pool = test::take_shared<Pool< X, Y>>(test);

            let (res_x, res_y, _) = pool::get_reserves< X, Y>(&mut pool);
            let coin_y=  mint<Y>(input_y, ctx(test));

            let scale_x = math::pow(10, pool::get_decimals_x(&pool));
            let scale_y = math::pow(10, pool::get_decimals_y(&pool));
            let dy = input_y - pool::calculate_fee(input_y, 3);

            let desired_x = if(pool::get_stable<X,Y>(&pool)){
             (formula::stable_swap_output(dy, res_y, res_x, scale_y, scale_x) as u64)
            }else{
                (formula::variable_swap_output(dy, res_y, res_x) as u64)
            };

            pool::swap_for_x< X, Y>(&mut pool, coin_y, 0 , clock, ctx(test));
            test::return_shared(pool);
            (desired_x as u64)
        };

        next_tx(test, trader);{
            let coin_x = test::take_from_sender<Coin<X>>(test);

            assert!(coin::value(&coin_x) == swap_x , 0);
            test::return_to_sender(test, coin_x);
        }
    }
    fun remove_liquidity_<X, Y>(amt_x: u64, amt_y:u64, clock: &mut Clock, test: &mut Scenario){
        let (creator, trader) = people();

        next_tx(test, creator);{
            add_liquidity_< X, Y>(amt_x, amt_y, clock, test);
        };
        next_tx(test, trader);{
            test_swap_for_y_< X, Y>(amt_x, amt_y, clock, test);
        };
        next_tx(test, creator);
        let (withdraw_x, withdraw_y) = {
            let pool = test::take_shared<Pool< X, Y>>(test);

            let (res_x, res_y, lp_supply) = pool::get_reserves(&mut pool);
            let lp_position = test::take_from_sender<LP<X,Y>>(test);
            let lp_value = pool::get_lp_balance(&lp_position);

            let withdraw_x = pool::quote(lp_supply, res_x, lp_value);
            let withdraw_y = pool::quote(lp_supply, res_y, lp_value);

            pool::remove_liquidity<X,Y>(&mut pool, &mut lp_position, lp_value, 0, 0, clock, ctx(test));
            test::return_to_sender(test, lp_position);
            test::return_shared(pool);

            (withdraw_x, withdraw_y)
        };
        next_tx(test, creator);{
            let pool = test::take_shared<Pool< X, Y>>(test);
            let coin_x = test::take_from_sender<Coin<X>>(test);
            let coin_y = test::take_from_sender<Coin<Y>>(test);
            let value_x = coin::value(&coin_x);
            let value_y = coin::value(&coin_y);
            assert!(value_x == withdraw_x, 0);
            assert!(value_y == withdraw_y, 0);

            test::return_to_sender(test, coin_x);
            test::return_to_sender(test, coin_y);
            test::return_shared(pool);
        };

    }
    fun zap_x_<X, Y>(amt_x: u64, amt_y:u64, clock: &mut Clock, test: &mut Scenario){
        let (creator, trader) = people();
        let deposit_x = 30_000;

        next_tx(test, creator);{
            add_liquidity_< X, Y>(amt_x, amt_y, clock, test);
        };
        next_tx(test, trader);{
            test_swap_for_y_< X, Y>(amt_x, amt_y, clock, test);
        };
        next_tx(test, trader);{
            let coin_x = mint<X>(deposit_x, ctx(test));
            sui::transfer::public_transfer(coin_x, trader);
        };
        next_tx(test, trader);{// single zap
            let pool = test::take_shared<Pool< X, Y>>(test);
            let coin_x = test::take_from_sender<Coin<X>>(test);
            let coin_y = test::take_from_sender<Coin<Y>>(test);
            let lp = pool::create_lp(&pool, ctx(test));
            pool::zap_x(&mut pool, mint<X>(deposit_x, ctx(test)), &mut lp, 0, 0, clock, ctx(test));

            transfer::public_transfer(lp, trader);
            test::return_shared(pool);
            test::return_to_sender(test, coin_x);
            burn(coin_y);
        };
        next_tx(test, trader);{ // empty Coin<Y> inventory
            let is_coin_y = test::has_most_recent_for_address<Coin<Y>>(trader);
            assert!(!is_coin_y, 0);
        };
        next_tx(test, creator);{
            let pool = test::take_shared<Pool< X, Y>>(test);
            let lp_position = test::take_from_sender<LP<X,Y>>(test);
            pool::claim_fees_player(&mut pool, &mut lp_position, ctx(test));

            test::return_shared(pool);
            test::return_to_sender(test, lp_position);
        }
    }
    fun people(): (address, address) { (@0xABCD, @0x1234 ) }
}