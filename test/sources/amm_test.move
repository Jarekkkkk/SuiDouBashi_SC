
#[test_only]
module suiDouBashi::test{
    use sui::coin::{Self, Coin, mint_for_testing as mint, CoinMetadata };
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::clock::{Self, Clock};
    use suiDouBashi::amm_v1::{Self, PoolGov, Pool};
    use suiDouBashi::amm_math;
    use sui::math;
    use suiDouBashi::formula;
    use std::debug::print;
    use std::string;
    use std::vector;

    // coin pkg
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
        clock::create_for_testing(ctx(&mut scenario));
        dai::deploy_coin(ctx(&mut scenario));
        usdc::deploy_coin(ctx(&mut scenario));
        test_init_pool_<DAI, USDC>(&mut scenario);
        test::end(scenario);

        print(&string::utf8(b"--"));
    }
    #[test]
    fun test_add_liquidity() {
        let scenario = test::begin(@0x1);
        clock::create_for_testing(ctx(&mut scenario));
        dai::deploy_coin(ctx(&mut scenario));
        usdc::deploy_coin(ctx(&mut scenario));
        let deposit_x = 30000;
        let deposit_y = 3000;
        add_liquidity_<DAI, USDC>(deposit_x, deposit_y, &mut scenario);
        test::end(scenario);
        print(&string::utf8(b"--"));
    }
    #[test]
    fun test_swap_for_y() {
        let scenario = test::begin(@0x1);
        clock::create_for_testing(ctx(&mut scenario));
        dai::deploy_coin(ctx(&mut scenario));
        usdc::deploy_coin(ctx(&mut scenario));
        test_swap_for_y_<DAI,USDC>(DAI_AMT, USDC_AMT, &mut scenario);
        test::end(scenario);
        print(&string::utf8(b"--"));
    }
    #[test]
    fun test_swap_for_x() {
        let scenario = test::begin(@0x1);
        clock::create_for_testing(ctx(&mut scenario));
        dai::deploy_coin(ctx(&mut scenario));
        usdc::deploy_coin(ctx(&mut scenario));
        test_swap_for_x_<DAI, USDC>(DAI_AMT, USDC_AMT, &mut scenario);
        test::end(scenario);
        print(&string::utf8(b"--"));
    }
    #[test]
    fun test_remove_liquidity() {
        let scenario = test::begin(@0x1);
        clock::create_for_testing(ctx(&mut scenario));
        dai::deploy_coin(ctx(&mut scenario));
        usdc::deploy_coin(ctx(&mut scenario));
        remove_liquidity_<DAI, USDC>(DAI_AMT, USDC_AMT, &mut scenario);
        test::end(scenario);
        print(&string::utf8(b"--"));
    }
    #[test]
    fun test_zap_x(){
        let scenario = test::begin(@0x1);
        clock::create_for_testing(ctx(&mut scenario));
        dai::deploy_coin(ctx(&mut scenario));
        usdc::deploy_coin(ctx(&mut scenario));
        zap_x_<DAI, USDC>(DAI_AMT, USDC_AMT, &mut scenario);
        test::end(scenario);
        print(&string::utf8(b"--"));
    }
    fun test_init_pool_<X, Y>(test:&mut Scenario) {
        let ( creator, _) = people();

        next_tx(test, creator);{
            amm_v1::init_for_testing(ctx(test));
        };

        next_tx(test, creator); {//create pool
            let pool_gov = test::take_shared<PoolGov>(test);
            amm_v1::create_pool< X, Y>(
                &mut pool_gov,
                true,
                FEE,
                ctx(test)
            );
            test::return_shared(pool_gov);
        };

        next_tx(test, creator);{//shared_pool
            let pool = test::take_shared<Pool< X, Y>>(test);
            let pool_gov = test::take_shared<PoolGov>(test);
            let (res_x, res_y, _lp_s) = amm_v1::get_reserves< X, Y>(&mut pool);

            assert!(res_x == 0, 0);
            assert!(res_y == 0, 0);

            test::return_shared(pool);
            test::return_shared(pool_gov);
        };
     }
    fun add_liquidity_<X, Y>(deposit_x: u64, deposit_y:u64, test: &mut Scenario){
        let (creator, _) = people();
        next_tx(test, creator);{
            test_init_pool_< X, Y>(test);
        };
        next_tx(test, creator);
        let minted_lp ={
            let pool = test::take_shared<Pool< X, Y>>(test);
            let clock = test::take_shared<Clock>(test);
            let (res_x, res_y, lp_supply) = amm_v1::get_reserves< X, Y>(&mut pool);

            amm_v1::add_liquidity(&mut pool, mint<X>(deposit_x, ctx(test)), mint<Y>(deposit_y, ctx(test)), 0, 0 , &clock , ctx(test));
            test::return_shared(pool);
            test::return_shared(clock);

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
            let lp_value = amm_v1::get_player_balance<X,Y>(&pool, creator);
            assert!(lp_value == minted_lp, 0);

            test::return_shared(pool);
        }
    }
    fun test_swap_for_y_<X, Y>(amt_x: u64, amt_y:u64, test: &mut Scenario){
        let (_, trader) = people();
        let input_x = 5000;

        add_liquidity_< X, Y>(amt_x, amt_y, test);
        next_tx(test, trader);
        let swap_y = {// swap X for Y
            let pool = test::take_shared<Pool< X, Y>>(test);
            let clock = test::take_shared<Clock>(test);
            let meta_x = test::take_immutable<CoinMetadata<X>>(test);
            let meta_y = test::take_immutable<CoinMetadata<Y>>(test);
            let (res_x, res_y, _) = amm_v1::get_reserves< X, Y>(&mut pool);
            let coin_x =  mint<X>(input_x, ctx(test));

            let scale_x = math::pow(10, coin::get_decimals(&meta_x));
            let scale_y = math::pow(10, coin::get_decimals(&meta_y));
            let dx = input_x - amm_v1::calculate_fee(input_x, 3, 10000);

            let desired_y = if(amm_v1::get_stable<X,Y>(&pool)){
             (formula::stable_swap_output((dx as u256),( res_x as u256), (res_y as u256), (scale_x as u256), (scale_y as u256)) as u64)
            }else{
                (formula::variable_swap_output((dx as u256),( res_x as u256), (res_y as u256)) as u64)
            };

            amm_v1::swap_for_y< X, Y>(&mut pool, coin_x, &meta_x, &meta_y, 0 , &clock, ctx(test));
            test::return_shared(pool);
            test::return_shared(clock);
            test::return_immutable(meta_x);
            test::return_immutable(meta_y);
            desired_y
        };
        next_tx(test, trader);{
            let coin_y = test::take_from_sender<Coin<Y>>(test);
            let coin_value = coin::value(&coin_y);
            assert!(coin_value == swap_y, 0);
            test::return_to_sender(test, coin_y);
        }
    }
    fun test_swap_for_x_<X, Y>(amt_x: u64, amt_y:u64, test: &mut Scenario){
        let (_, trader) = people();
        let input_y = 5000;

        add_liquidity_< X, Y>(amt_x, amt_y, test);

        next_tx(test, trader);
        let swap_x = {// swap Y for X
            let pool = test::take_shared<Pool< X, Y>>(test);
            let clock = test::take_shared<Clock>(test);
            let meta_x = test::take_immutable<CoinMetadata<X>>(test);
            let meta_y = test::take_immutable<CoinMetadata<Y>>(test);

            let (res_x, res_y, _) = amm_v1::get_reserves< X, Y>(&mut pool);
            let coin_y=  mint<Y>(input_y, ctx(test));

            let scale_x = math::pow(10, coin::get_decimals(&meta_x));
            let scale_y = math::pow(10, coin::get_decimals(&meta_y));
            let dy = input_y - amm_v1::calculate_fee(input_y, 3, 10000);

            let desired_x = if(amm_v1::get_stable<X,Y>(&pool)){
             (formula::stable_swap_output((dy as u256),( res_y as u256), (res_x as u256), (scale_y as u256), (scale_x as u256)) as u64)
            }else{
                (formula::variable_swap_output((dy as u256),( res_y as u256), (res_x as u256)) as u64)
            };

            amm_v1::swap_for_x< X, Y>(&mut pool, coin_y, &meta_x, &meta_y, 0 , &clock, ctx(test));
            test::return_shared(pool);
            test::return_shared(clock);
            test::return_immutable(meta_x);
            test::return_immutable(meta_y);
            (desired_x as u64)
        };

        next_tx(test, trader);{
            let coin_x = test::take_from_sender<Coin<X>>(test);

            assert!(coin::value(&coin_x) == swap_x , 0);
            test::return_to_sender(test, coin_x);
        }
    }
    fun remove_liquidity_<X, Y>(amt_x: u64, amt_y:u64, test: &mut Scenario){
        let (creator, trader) = people();

        next_tx(test, creator);{
            add_liquidity_< X, Y>(amt_x, amt_y, test);
        };
        next_tx(test, trader);{
            test_swap_for_y_< X, Y>(amt_x, amt_y, test);
        };
        next_tx(test, creator);
        let (withdraw_x, withdraw_y) = {
            let pool = test::take_shared<Pool< X, Y>>(test);
            let clock = test::take_shared<Clock>(test);
            let (res_x, res_y, lp_supply) = amm_v1::get_reserves(&mut pool);
            let lp_value = amm_v1::get_player_balance<X,Y>(&pool, creator);
            let withdraw_x = amm_v1::quote(lp_supply, res_x, lp_value);
            let withdraw_y = amm_v1::quote(lp_supply, res_y, lp_value);

            amm_v1::remove_liquidity<X,Y>(&mut pool, lp_value, 0, 0, &clock, ctx(test));
            test::return_shared(pool);
            test::return_shared(clock);

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
    fun zap_x_<X, Y>(amt_x: u64, amt_y:u64, test: &mut Scenario){
        let (creator, trader) = people();
        let deposit_x = 30000;

        next_tx(test, creator);{
            add_liquidity_< X, Y>(amt_x, amt_y, test);
        };
        next_tx(test, trader);{
            test_swap_for_y_< X, Y>(amt_x, amt_y, test);
        };
        next_tx(test, trader);{// single zap
            let pool = test::take_shared<Pool< X, Y>>(test);
            let clock = test::take_shared<Clock>(test);
            let meta_x = test::take_immutable<CoinMetadata<X>>(test);
            let meta_y = test::take_immutable<CoinMetadata<Y>>(test);

            amm_v1::zap_x(&mut pool, mint<X>(deposit_x, ctx(test)), &meta_x, &meta_y, 0, 0,0, &clock, ctx(test));

            test::return_shared(pool);
            test::return_shared(clock);
            test::return_immutable(meta_x);
            test::return_immutable(meta_y);
        };
        next_tx(test, trader);{// mul_coin zap
            let clock = test::take_shared<Clock>(test);
            let pool = test::take_shared<Pool< X, Y>>(test);
            let meta_x = test::take_immutable<CoinMetadata<X>>(test);
            let meta_y = test::take_immutable<CoinMetadata<Y>>(test);
            let vec = vector::empty<Coin<X>>();

            vector::push_back(&mut vec, mint<X>(1000, ctx(test)));
            vector::push_back(&mut vec, mint<X>(1250, ctx(test)));
            amm_v1::zap_x_pay(&mut pool, vec, 1500, &meta_x, &meta_y, 0, 0,0, &clock, ctx(test));

            test::return_shared(pool);
            test::return_shared(clock);
            test::return_immutable(meta_x);
            test::return_immutable(meta_y);
        }
    }
    fun people(): (address, address) { (@0xABCD, @0x1234 ) }
}