module test::pool_test{
    use suiDouBashi::pool::{Self, Pool, LP};
    use test::setup;
    use sui::coin::{ Self, mint_for_testing as mint, Coin, burn_for_testing as burn};

    use suiDouBashiVest::sdb::SDB;
    use suiDouBashi::usdc::USDC;
    use suiDouBashi::usdt::USDT;
    use sui::clock::{Clock};
    use sui::transfer;

    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};

    public fun pool_(clock: &mut Clock, s: &mut Scenario){
        let (a, b, _) = setup::people();

        // create USDC-USDT/ SDB-USDC
        setup::deploy_pools(s, clock);

        next_tx(s,a);{ // Action: topup liquidity
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let lp_b = test::take_from_sender<LP<SDB, USDC>>(s);

            let ctx = ctx(s);
            pool::add_liquidity(&mut pool_a, mint<USDC>(setup::usdc_1(), ctx), mint<USDT>(setup::usdc_1(), ctx), &mut lp_a, 0, 0, clock, ctx);
            pool::add_liquidity(&mut pool_b, mint<SDB>(setup::sui_1(), ctx), mint<USDC>(setup::usdc_1(), ctx), &mut lp_b, 0, 0, clock, ctx);

            test::return_shared(pool_a);
            test::return_shared(pool_b);
            test::return_to_sender(s, lp_a);
            test::return_to_sender(s, lp_b);
        };
        next_tx(s,a);{ // Assertion: updated swap amount & lp_balance
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let lp_b = test::take_from_sender<LP<SDB, USDC>>(s);
            assert!(pool::get_lp_balance(&lp_a) == 1999000, 0);
            assert!(pool::get_lp_balance(&lp_b) == 63244552, 0);
            // pool_a
            assert!(pool::get_output<USDC, USDT, USDC>(&pool_a, setup::usdc_1()) == 944968, 0);
            assert!(pool::get_output<USDC, USDT, USDT>(&pool_a, setup::usdc_1()) == 944968, 0);
            // pool_b
            assert!(pool::get_output<SDB, USDC, SDB>(&pool_b, setup::sui_1()) == 666444, 0);
            assert!(pool::get_output<SDB, USDC, USDC>(&pool_b,setup::usdc_1()) == 666444407, 0);

            test::return_shared(pool_a);
            test::return_shared(pool_b);
            test::return_to_sender(s, lp_a);
            test::return_to_sender(s, lp_b);
        };
        next_tx(s,b);{ // Action: LP B open LP position
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let ctx = ctx(s);
            // additionally create LP position
            let lp_a = pool::create_lp(&pool_a, ctx);
            let lp_b = pool::create_lp(&pool_b, ctx);

            pool::add_liquidity(&mut pool_a, mint<USDC>(setup::usdc_1(), ctx), mint<USDT>(setup::usdc_1(), ctx), &mut lp_a, 0, 0, clock, ctx);
            pool::add_liquidity(&mut pool_b, mint<SDB>(setup::sui_1(), ctx), mint<USDC>(setup::usdc_1(), ctx), &mut lp_b, 0, 0, clock, ctx);

            test::return_shared(pool_a);
            test::return_shared(pool_b);
            transfer::public_transfer(lp_a, b);
            transfer::public_transfer(lp_b, b);
        };
        next_tx(s,a);{ // Action: LP A Swap & Claim Fees
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let lp_b = test::take_from_sender<LP<SDB, USDC>>(s);
            let ctx = ctx(s);

            let opt_output = pool::get_output<USDC,USDT,USDC>(&pool_a, setup::usdc_1());
            pool::swap_for_y(&mut pool_a, mint<USDC>(setup::usdc_1(), ctx), opt_output, clock, ctx);
            let opt_output = pool::get_output<SDB, USDC, SDB>(&pool_b, setup::sui_1());
            pool::swap_for_y(&mut pool_b, mint<SDB>(setup::sui_1(), ctx), opt_output, clock, ctx);

            test::return_shared(pool_a);
            test::return_shared(pool_b);
            test::return_to_sender(s, lp_a);
            test::return_to_sender(s, lp_b);
        };
        next_tx(s,a);{ // Action: LP A Claim Fees & Assertion: Fee Deposit
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let lp_b = test::take_from_sender<LP<SDB, USDC>>(s);
            let ctx = ctx(s);

            assert!(pool::get_fee_x(&pool_a) == 300, 1);
            assert!(pool::get_fee_x(&pool_b) == 500_000, 1);

            pool::claim_fees_player(&mut pool_a, &mut lp_a, ctx);
            pool::claim_fees_player(&mut pool_b, &mut lp_b, ctx);

            test::return_shared(pool_a);
            test::return_shared(pool_b);
            test::return_to_sender(s, lp_a);
            test::return_to_sender(s, lp_b);
        };
        next_tx(s,a);{ // Assertion: LP position = 0, fee withdrawl,
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let lp_b = test::take_from_sender<LP<SDB, USDC>>(s);
            // pool's remaining fee
            let pool_a_fee_x = pool::get_fee_x(&pool_a);
            let pool_b_fee_x = pool::get_fee_x(&pool_b);
            // user's fee
            let fee_usdc = test::take_from_sender<Coin<USDC>>(s);
            let fee_sdb = test::take_from_sender<Coin<SDB>>(s);

            assert!(pool::get_claimable_x(&lp_a) == 0, 0);
            assert!(pool::get_claimable_x(&lp_b) == 0, 0);
            assert!( pool_a_fee_x == 101, 1);
            assert!( pool_b_fee_x == 166_672, 1);
            assert!(coin::value(&fee_usdc) == 199, 1);
            assert!(coin::value(&fee_sdb) == 333_328, 1);

            test::return_shared(pool_a);
            test::return_shared(pool_b);
            test::return_to_sender(s, lp_a);
            test::return_to_sender(s, lp_b);
            burn(fee_usdc);
            burn(fee_sdb);
        };
        next_tx(s,b);{ // Action: LP B Swap
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let lp_b = test::take_from_sender<LP<SDB, USDC>>(s);
            let ctx = ctx(s);

            let opt_output = pool::get_output<USDC,USDT,USDC>(&pool_a, setup::usdc_1());
            pool::swap_for_y(&mut pool_a, mint<USDC>(setup::usdc_1(), ctx), opt_output, clock, ctx);
            let opt_output = pool::get_output<SDB, USDC, SDB>(&pool_b, setup::sui_1());
            pool::swap_for_y(&mut pool_b, mint<SDB>(setup::sui_1(), ctx), opt_output, clock, ctx);

            test::return_shared(pool_a);
            test::return_shared(pool_b);
            test::return_to_sender(s, lp_a);
            test::return_to_sender(s, lp_b);
        };
        next_tx(s,b);{ // Action: LP B Claim Fees & Assertion: Fee Deposit
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let lp_b = test::take_from_sender<LP<SDB, USDC>>(s);
            let ctx = ctx(s);
            assert!(pool::get_fee_x(&pool_a) == 401, 1);
            assert!(pool::get_fee_x(&pool_b) == 666_672, 1);

            pool::claim_fees_player(&mut pool_a, &mut lp_a, ctx);
            pool::claim_fees_player(&mut pool_b, &mut lp_b, ctx);

            test::return_shared(pool_a);
            test::return_shared(pool_b);
            test::return_to_sender(s, lp_a);
            test::return_to_sender(s, lp_b);
        };
        next_tx(s,b);{ // Assertion: LP claimbale = 0, fee withdrawl,
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let lp_b = test::take_from_sender<LP<SDB, USDC>>(s);
            // user's fee
            let fee_usdc = test::take_from_sender<Coin<USDC>>(s);
            let fee_sdb = test::take_from_sender<Coin<SDB>>(s);

            assert!(pool::get_claimable_x(&lp_a) == 0, 0);
            assert!(pool::get_claimable_x(&lp_b) == 0, 0);
            assert!(pool::get_fee_x(&pool_a) == 201, 1);
            assert!(pool::get_fee_x(&pool_b) == 333_339, 1);
            assert!(coin::value(&fee_usdc) == 200, 1);
            assert!(coin::value(&fee_sdb) == 333333, 1);

            test::return_shared(pool_a);
            test::return_shared(pool_b);
            test::return_to_sender(s, lp_a);
            test::return_to_sender(s, lp_b);
            burn(fee_usdc);
            burn(fee_sdb);
        };
        next_tx(s,a);{ // Action: LP A Claim Fees & Assertion: Fee Deposit
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let lp_b = test::take_from_sender<LP<SDB, USDC>>(s);
            let ctx = ctx(s);

            pool::claim_fees_player(&mut pool_a, &mut lp_a, ctx);
            pool::claim_fees_player(&mut pool_b, &mut lp_b, ctx);

            test::return_shared(pool_a);
            test::return_shared(pool_b);
            test::return_to_sender(s, lp_a);
            test::return_to_sender(s, lp_b);
        };
        next_tx(s,a);{ // Assertion: fee withdrawl, pool's remaingin fee = 0,
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let lp_b = test::take_from_sender<LP<SDB, USDC>>(s);
            // user's fee
            let fee_usdc = test::take_from_sender<Coin<USDC>>(s);
            let fee_sdb = test::take_from_sender<Coin<SDB>>(s);

            assert!(pool::get_claimable_x(&lp_a) == 0, 0);
            assert!(pool::get_claimable_x(&lp_b) == 0, 0);
            assert!(pool::get_fee_x(&pool_a) == 2, 1);
            assert!(pool::get_fee_x(&pool_b) == 11, 1);
            assert!(coin::value(&fee_usdc) == 199, 1);
            assert!(coin::value(&fee_sdb) == 333_328, 1);

            test::return_shared(pool_a);
            test::return_shared(pool_b);
            test::return_to_sender(s, lp_a);
            test::return_to_sender(s, lp_b);
            burn(fee_usdc);
            burn(fee_sdb);
        };
    }
}


