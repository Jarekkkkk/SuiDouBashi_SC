module test::pool_test{
    use suiDouBashi_amm::pool::{Self, Pool, LP};
    use test::setup;
    use sui::coin::{ Self, mint_for_testing as mint, Coin, burn_for_testing as burn};
    use sui::clock::{Clock};
    use sui::transfer;
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};

    use suiDouBashi_vsdb::sdb::SDB;
    use coin_list::mock_usdt::{MOCK_USDT as USDT};
    use coin_list::mock_usdc::{MOCK_USDC as USDC};

    public fun pool_(clock: &mut Clock, s: &mut Scenario){
        let (a, b, _) = setup::people();

        // create USDC-USDT/ SDB-USDC
        deploy_pools(s, clock);

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
            assert!(pool::lp_balance(&lp_a) == 1999000, 0);
            assert!(pool::lp_balance(&lp_b) == 63244552, 0);
            // pool_a
            assert!(pool::get_output<USDC, USDT, USDC>(&pool_a, setup::usdc_1()) == 944967, 0);
            assert!(pool::get_output<USDC, USDT, USDT>(&pool_a, setup::usdc_1()) == 944967, 0);
            // pool_b
            assert!(pool::get_output<SDB, USDC, SDB>(&pool_b, setup::sui_1()) == 664440, 0);
            assert!(pool::get_output<SDB, USDC, USDC>(&pool_b,setup::usdc_1()) == 664440288, 0);

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
            assert!(pool::fee_x(&pool_a) == 301, 1);
            assert!(pool::fee_x(&pool_b) == 5_000_001, 1);

            let (claimable_x, _) = pool::claimable(&pool_a, &lp_a);
            assert!(claimable_x == 200, 0);
            let (claimable_x, _) = pool::claimable(&pool_b, &lp_b);
            assert!(claimable_x == 3333281, 0);
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
            let pool_a_fee_x = pool::fee_x(&pool_a);
            let pool_b_fee_x = pool::fee_x(&pool_b);
            // user's fee
            let fee_usdc = test::take_from_sender<Coin<USDC>>(s);
            let fee_sdb = test::take_from_sender<Coin<SDB>>(s);

            let (claimable_x, _) = pool::claimable(&pool_a, &lp_a);
            assert!(claimable_x == 0, 0);
            let (claimable_x, _) = pool::claimable(&pool_b, &lp_b);
            assert!(claimable_x == 0, 0);
            assert!( pool_a_fee_x == 101, 1);
            assert!( pool_b_fee_x == 1666720, 1);
            assert!(coin::value(&fee_usdc) == 200, 1);
            assert!(coin::value(&fee_sdb) == 3333281, 1);

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
            assert!(pool::fee_x(&pool_a) == 402, 1);
            assert!(pool::fee_x(&pool_b) == 6_666_721, 1);

            let (claimable_x, _) = pool::claimable(&pool_a, &lp_a);
            assert!(claimable_x == 200, 0);
            let (claimable_x, _) = pool::claimable(&pool_b, &lp_b);
            assert!(claimable_x == 3_333_333, 0);
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

            let (claimable_x, _) = pool::claimable(&pool_a, &lp_a);
            assert!(claimable_x == 0, 0);
            let (claimable_x, _) = pool::claimable(&pool_b, &lp_b);
            assert!(claimable_x == 0, 0);
            assert!(pool::fee_x(&pool_a) == 202, 1);
            assert!(pool::fee_x(&pool_b) == 3_333_388, 1);
            assert!(coin::value(&fee_usdc) == 200, 1);
            assert!(coin::value(&fee_sdb) == 3_333_333, 1);

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

            let (claimable_x, _) = pool::claimable(&pool_a, &lp_a);
            assert!(claimable_x == 200, 0);
            let (claimable_x, _) = pool::claimable(&pool_b, &lp_b);
            assert!(claimable_x == 3333281, 0);
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
            let fee_usdc = test::take_from_sender<Coin<USDC>>(s);
            let fee_sdb = test::take_from_sender<Coin<SDB>>(s);

            let (claimable_x, _) = pool::claimable(&pool_a, &lp_a);
            assert!(claimable_x == 0, 0);
            let (claimable_x, _) = pool::claimable(&pool_b, &lp_b);
            assert!(claimable_x == 0, 0);

            assert!(pool::fee_x(&pool_a) == 2, 1);
            assert!(pool::fee_x(&pool_b) == 107, 1);
            assert!(coin::value(&fee_usdc) == 200, 1);
            assert!(coin::value(&fee_sdb) == 3333281, 1);

            test::return_shared(pool_a);
            test::return_shared(pool_b);
            test::return_to_sender(s, lp_a);
            test::return_to_sender(s, lp_b);
            burn(fee_usdc);
            burn(fee_sdb);
        };
    }

    use suiDouBashi_amm::pool_reg::{Self, PoolReg, PoolCap};
    use sui::coin::CoinMetadata;
    use suiDouBashi_vote::minter::{mint_sdb, Minter};
    public fun deploy_pools(s: &mut Scenario, clock: &mut Clock){
        let (a,_,_) = setup::people();

        pool_reg::init_for_testing(ctx(s));

        next_tx(s, a); { // Action: create pool
            let meta_usdc = test::take_immutable<CoinMetadata<USDC>>(s);
            let meta_usdt = test::take_immutable<CoinMetadata<USDT>>(s);
            let meta_sdb = test::take_immutable<CoinMetadata<SDB>>(s);
            let pool_cap = test::take_from_sender<PoolCap>(s);

            let pool_gov = test::take_shared<PoolReg>(s);
            pool_reg::create_pool(
                &mut pool_gov,
                &pool_cap,
                true,
                &meta_usdc,
                &meta_usdt,
                3,
                ctx(s)
            );
            pool_reg::create_pool(
                &mut pool_gov,
                &pool_cap,
                false,
                &meta_sdb,
                &meta_usdc,
                50,
                ctx(s)
            );

            test::return_to_sender(s, pool_cap);
            test::return_shared(pool_gov);
            test::return_immutable(meta_usdc);
            test::return_immutable(meta_sdb);
            test::return_immutable(meta_usdt);
        };
        next_tx(s,a);{ // Action: add liquidity
            let pool_gov = test::take_shared<PoolReg>(s);
            let minter = test::take_shared<Minter>(s);
            assert!(pool_reg::pools_length(&pool_gov) == 2, 0);

            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let ctx = ctx(s);
            let lp_a = pool::create_lp(&pool_a, ctx);
            let lp_b = pool::create_lp(&pool_b, ctx);

            pool::add_liquidity(&mut pool_a, mint<USDC>(setup::usdc_1(), ctx), mint<USDT>(setup::usdc_1(), ctx), &mut lp_a, 0, 0, clock, ctx);
            pool::add_liquidity(&mut pool_b, mint_sdb(&mut minter, setup::sui_1(), ctx), mint<USDC>(setup::usdc_1(), ctx), &mut lp_b, 0, 0, clock, ctx);

            transfer::public_transfer(lp_a, a);
            transfer::public_transfer(lp_b, a);

            test::return_shared(minter);
            test::return_shared(pool_gov);
            test::return_shared(pool_a);
            test::return_shared(pool_b);
        };
        next_tx(s,a);{ // Assertion: swap amount, lp_balance
            let pool_gov = test::take_shared<PoolReg>(s);
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let lp_b = test::take_from_sender<LP<SDB, USDC>>(s);
            let _ctx = ctx(s);

            assert!(pool_reg::pools_length(&pool_gov) == 2, 0);
            let (_, _, res_lp_a) = pool::get_reserves(&pool_a);
            let (_, _, res_lp_b) = pool::get_reserves(&pool_b);

            // pool_a
            assert!(pool::stable(&pool_a) == true, 0);
            assert! (res_lp_a == 1000000, 0);
            assert!(pool::lp_balance(&lp_a) == res_lp_a - 1000, 0);
            assert!(pool::get_output<USDC, USDT, USDC>(&pool_a, setup::usdc_1()) == 753_626, 0);
            assert!(pool::get_output<USDC, USDT, USDT>(&pool_a, setup::usdc_1()) == 753_626, 0);

            // pool_b
            assert!(pool::stable(&pool_b) == false, 0);
            assert!(res_lp_b == 31622776, 0);
            assert!(pool::lp_balance(&lp_b) == res_lp_b - 1000, 0);
            assert!(pool::get_output<SDB, USDC, SDB>(&pool_b, setup::sui_1()) == 498_746, 0);
            assert!(pool::get_output<SDB, USDC, USDC>(&pool_b, setup::usdc_1()) == 498746615, 0);

            test::return_shared(pool_gov);
            test::return_shared(pool_a);
            test::return_shared(pool_b);
            test::return_to_sender(s, lp_a);
            test::return_to_sender(s, lp_b);
        };
    }
}