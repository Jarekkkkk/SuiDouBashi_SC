
// #[test_only]
// module suiDouBashi::amm_test{
//     use sui::coin::{Self, Coin, mint_for_testing as mint};
//     use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
//     use sui::clock::Clock;
//     use suiDouBashi::amm_v1::{Self, AMM_V1, PoolGov, LP_TOKEN, Pool};
//     use suiDouBashi::amm_math;
//     use sui::math;

//     struct TOKEN_X {}
//     struct TOKEN_Y {}

//     const MINIMUM_LIQUIDITY: u64 = 1000;

//     X/Y = 1/2
//     const TOKEN_X_AMT:u64 = 9_000_000;
//     const TOKEN_Y_AMT: u64 = 10_000_000;

//     const FEE_SCALING: u64 = 1000;
//     const FEE: u64 = 3;

//     #[test]
//     fun test_init_pool(){
//         let scenario = test::begin(@0x1);
//         test_init_pool_<AMM_V1, TOKEN_X, TOKEN_Y>(&mut scenario);
//         test::end(scenario);
//     }
//     #[test]
//     fun test_add_liquidity() {
//         let scenario = test::begin(@0x1);
//         let deposit_x = 30000;
//         let deposit_y = 3000;
//         add_liquidity_<AMM_V1, TOKEN_X, TOKEN_Y>(deposit_x, deposit_y, &mut scenario);
//         test::end(scenario);
//     }
//     #[test]
//     fun test_swap_for_y() {
//         let scenario = test::begin(@0x1);
//         test_swap_for_y_<AMM_V1, TOKEN_X, TOKEN_Y>(TOKEN_X_AMT, TOKEN_Y_AMT, &mut scenario);
//         test::end(scenario);
//     }
//     #[test]
//     fun test_swap_for_x() {
//         let scenario = test::begin(@0x1);
//         test_swap_for_x_<AMM_V1, TOKEN_X, TOKEN_Y>(TOKEN_X_AMT, TOKEN_Y_AMT, &mut scenario);
//         test::end(scenario);
//     }
//     #[test]
//     fun test_remove_liquidity() {
//         let scenario = test::begin(@0x1);
//         remove_liquidity_<AMM_V1, TOKEN_X, TOKEN_Y>(TOKEN_X_AMT, TOKEN_Y_AMT, &mut scenario);
//         test::end(scenario);
//     }
//     #[test]
//     fun test_zap_x(){
//         let scenario = test::begin(@0x1);
//         test_swap_for_y_<AMM_V1, TOKEN_X, TOKEN_Y>(TOKEN_X_AMT, TOKEN_Y_AMT, &mut scenario);
//         test::end(scenario);
//     }
//     fun test_init_pool_<V, X, Y>(test:&mut Scenario) {
//         let ( creator, _) = people();

//         next_tx(test, creator);{
//             amm_v1::init_for_testing(ctx(test));
//         };

//         next_tx(test, creator); {//create pool
//             let pool_gov = test::take_shared<PoolGov>(test);
//             amm_v1::create_pool<V, X, Y>(
//                 &mut pool_gov,
//                 FEE,
//                 ctx(test)
//             );
//             test::return_shared(pool_gov);
//         };

//         next_tx(test, creator);{//shared_pool
//             let pool = test::take_shared<Pool<V, X, Y>>(test);
//             let pool_gov = test::take_shared<PoolGov>(test);
//             amm_v1::update_fee_on<V,X,Y>(&pool_gov, &mut pool, true, ctx(test));
//             let (res_x, res_y, _lp_s) = amm_v1::get_reserves<V, X, Y>(&mut pool);

//             assert!(res_x == 0, 0);
//             assert!(res_y == 0, 0);

//             test::return_shared(pool);
//             test::return_shared(pool_gov);
//         };
//      }
//     fun add_liquidity_<V, X, Y>(deposit_x: u64, deposit_y:u64, test: &mut Scenario){
//         let (creator, _) = people();
//         next_tx(test, creator);{
//             test_init_pool_<V, X, Y>(test);
//         };
//         next_tx(test, creator);
//         let minted_lp ={
//             let pool = test::take_shared<Pool<V, X, Y>>(test);
//             let clock = test::take_shared<Clock>(test);
//             let (res_x, res_y, lp_supply) = amm_v1::get_reserves<V, X, Y>(&mut pool);

//             amm_v1::add_liquidity(&mut pool, mint<X>(deposit_x, ctx(test)), mint<Y>(deposit_y, ctx(test)), 0, 0 ,/* &clock ,*/ ctx(test));
//             test::return_shared(pool);
//             test::return_shared(clock);

//             if(lp_supply == 0){
//                 (amm_math::mul_sqrt(deposit_x, deposit_y) - MINIMUM_LIQUIDITY)
//             }else{
//                 math::min(
//                     amm_math::mul_div(deposit_x, lp_supply, res_x),
//                     amm_math::mul_div(deposit_y, lp_supply, res_y),
//                 )
//             }
//         };
//         next_tx(test, creator);{
//             let pool = test::take_shared<Pool<V, X, Y>>(test);
//             let lsp = test::take_from_sender<Coin<LP_TOKEN<V, X, Y>>>(test);
//             assert!(coin::value(&lsp) == minted_lp, 0);

//             test::return_to_sender(test, lsp);
//             test::return_shared(pool);
//         }
//     }
//     fun test_swap_for_y_<V, X, Y>(token_x_amt: u64, token_y_amt:u64, test: &mut Scenario){
//         let (_, trader) = people();
//         let input_x = 5000;

//         add_liquidity_<V, X, Y>(token_x_amt, token_y_amt, test);
//         next_tx(test, trader);
//         let swap_y = {// swap X for Y
//             let pool = test::take_shared<Pool<V, X, Y>>(test);
//             let clock = test::take_shared<Clock>(test);
//             let (res_x, res_y, _) = amm_v1::get_reserves<V, X, Y>(&mut pool);
//             let coin_x =  mint<X>(input_x, ctx(test));
//             let desired_y = amm_v1::swap_output(input_x, res_x, res_y, FEE, FEE_SCALING);

//             amm_v1::swap_for_y<V, X, Y>(&mut pool, coin_x,0 ,/* &clock ,*/ctx(test));
//             test::return_shared(pool);
//             test::return_shared(clock);
//             desired_y
//         };
//         next_tx(test, trader);{
//             let coin_y = test::take_from_sender<Coin<Y>>(test);
//             assert!(coin::value(&coin_y) == swap_y, 0);
//             test::return_to_sender(test, coin_y);
//         }
//     }
//     fun test_swap_for_x_<V, X, Y>(token_x_amt: u64, token_y_amt:u64, test: &mut Scenario){
//         let (_, trader) = people();
//         let input_x = 5000;

//         add_liquidity_<V, X, Y>(token_x_amt, token_y_amt, test);

//         next_tx(test, trader);
//         let swap_x = {// swap Y for X
//             let pool = test::take_shared<Pool<V, X, Y>>(test);
//             let clock = test::take_shared<Clock>(test);
//             let (res_x, res_y, _) = amm_v1::get_reserves<V, X, Y>(&mut pool);
//             let coin_y=  mint<Y>(input_x, ctx(test));
//             let desired_x = amm_v1::swap_output(input_x, res_y, res_x, FEE, FEE_SCALING);

//             amm_v1::swap_for_x<V, X, Y>(&mut pool, coin_y, 0 ,/* &clock ,*/ctx(test));
//             test::return_shared(pool);
//             test::return_shared(clock);
//             desired_x
//         };

//         next_tx(test, trader);{
//             let coin_x = test::take_from_sender<Coin<X>>(test);

//             assert!(coin::value(&coin_x) == swap_x , 0);
//             test::return_to_sender(test, coin_x);
//         }
//     }
//     fun remove_liquidity_<V, X, Y>(token_x_amt: u64, token_y_amt:u64, test: &mut Scenario){
//         let (creator, trader) = people();

//         next_tx(test, creator);{
//             add_liquidity_<V, X, Y>(token_x_amt, token_y_amt, test);
//         };
//         next_tx(test, trader);{
//             test_swap_for_y_<V, X, Y>(token_x_amt, token_y_amt, test);
//         };
//         next_tx(test, creator);
//         let (withdraw_x, withdraw_y) = {
//             let pool = test::take_shared<Pool<V, X, Y>>(test);
//             let clock = test::take_shared<Clock>(test);
//             let (res_x, res_y, lp_supply) = amm_v1::get_reserves(&mut pool);
//             let lp_coin = test::take_from_sender<Coin<LP_TOKEN<V, X, Y>>>(test);
//             let lp_value = coin::value(&lp_coin);
//             let withdraw_x = amm_v1::quote(lp_supply, res_x, lp_value);
//             let withdraw_y = amm_v1::quote(lp_supply, res_y, lp_value);

//             amm_v1::remove_liquidity<V,X,Y>(&mut pool, lp_coin, 0, 0,/* &clock ,*/ ctx(test));
//             test::return_shared(pool);
//             test::return_shared(clock);

//             (withdraw_x, withdraw_y)
//         };
//         next_tx(test, creator);{
//             let pool = test::take_shared<Pool<V, X, Y>>(test);
//             let coin_x = test::take_from_sender<Coin<X>>(test);
//             let coin_y = test::take_from_sender<Coin<Y>>(test);
//             let value_x = coin::value(&coin_x);
//             let value_y = coin::value(&coin_y);
//             assert!(value_x != withdraw_x, 0);
//             assert!(value_y != withdraw_y, 0);

//             test::return_to_sender(test, coin_x);
//             test::return_to_sender(test, coin_y);
//             test::return_shared(pool);
//         };
//     }
//     use std::vector;
//     fun zap_x_<V, X, Y>(token_x_amt: u64, token_y_amt:u64, test: &mut Scenario){
//         let (creator, trader) = people();
//         let deposit_x = 30000;

//         next_tx(test, creator);{
//             add_liquidity_<V, X, Y>(token_x_amt, token_y_amt, test);
//         };
//         next_tx(test, trader);{
//             test_swap_for_y_<V, X, Y>(token_x_amt, token_y_amt, test);
//         };
//         next_tx(test, trader);{// single zap
//             let pool = test::take_shared<Pool<V, X, Y>>(test);
//             let clock = test::take_shared<Clock>(test);
//             amm_v1::zap_x(&mut pool, mint<X>(deposit_x, ctx(test)),0, 0,0,/* &clock ,*/ ctx(test));
//             test::return_shared(pool);
//             test::return_shared(clock);
//         };
//         next_tx(test, trader);{// mul_coin zap
//             let clock = test::take_shared<Clock>(test);
//             let pool = test::take_shared<Pool<V, X, Y>>(test);
//             let vec = vector::empty<Coin<X>>();
//             vector::push_back(&mut vec, mint<X>(1000, ctx(test)));
//             vector::push_back(&mut vec, mint<X>(1250, ctx(test)));
//             amm_v1::zap_x_pay(&mut pool, vec, 1500,0, 0,0,/* &clock ,*/ ctx(test));
//             test::return_shared(pool);
//             test::return_shared(clock);
//         }
//     }
//     fun people(): (address, address) { (@0xABCD, @0x1234 ) }
// }