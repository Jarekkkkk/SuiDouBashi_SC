#[test_only]
module test::main{
    use suiDouBashi::pool::{Self, Pool, LP};
    use suiDouBashiVest::sdb::SDB;
    use suiDouBashiVest::vsdb::{Self, VSDB, VSDBRegistry};
    use suiDouBashi::usdc::USDC;
    use suiDouBashi::usdt::USDT;


    use test::setup;
    use sui::coin::{ Self, mint_for_testing as mint, Coin, burn_for_testing as burn};
    use sui::object;

    use sui::clock::{Self, timestamp_ms as get_time, increment_for_testing as add_time, Clock};
    use sui::transfer;
    use std::debug::print;

    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};

    #[test] fun main(){
        let (a,_,_) = setup::people();
        let scenario = test::begin(a);
        let clock = clock::create_for_testing(ctx(&mut scenario));

        setup_(&mut clock, &mut scenario);
        vest_(&mut clock, &mut scenario);
        pool_(&mut clock, &mut scenario);

        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    fun setup_(clock: &mut Clock, test: &mut Scenario){
        let (a,_,_) = setup::people();
        add_time(clock, 1672531200);
        print(&get_time(clock));

        setup::deploy_coins(test);
        setup::mint_stable(test);

        vsdb::init_for_testing(ctx(test));
        transfer::public_transfer(mint<SDB>(18 * setup::sui_1B(), ctx(test)), a);
    }

    fun vest_(clock: &mut Clock, s: &mut Scenario){
        let (a,_,_) = setup::people();

        next_tx(s, a);{ // create lock
            let reg = test::take_shared<VSDBRegistry>(s);
            let sdb = test::take_from_sender<Coin<SDB>>(s);
            vsdb::lock(&mut reg, coin::split(&mut sdb, 5 * setup::sui_1B(), ctx(s)), setup::four_years(), clock, ctx(s));

            test::return_to_sender(s, sdb);
            test::return_shared(reg);
        };
        next_tx(s, a);{
            let vsdb = test::take_from_sender<VSDB>(s);
            let voting = vsdb::latest_voting_weight(&vsdb, clock);
            let reg = test::take_shared<VSDBRegistry>(s);
            assert!(voting >=  4999999999910976000, 1);
            assert!(vsdb::locked_balance(&vsdb) == 5 * setup::sui_1B(),1);
            assert!(vsdb::total_supply(&reg) == 5 * setup::sui_1B(), 1);
            assert!(vsdb::total_minted(&reg) == 1, 1);
            assert!( vsdb::get_user_epoch(&vsdb) == 1, 0);

            test::return_to_sender(s, vsdb);
            test::return_shared(reg);
        };

        add_time(clock, setup::week());

        next_tx(s, a);{ // increase lock amount & time
            let sdb = test::take_from_sender<Coin<SDB>>(s);
            let vsdb = test::take_from_sender<VSDB>(s);
            let reg = test::take_shared<VSDBRegistry>(s);

            vsdb::increase_unlock_amount(&mut reg, &mut vsdb, coin::split(&mut sdb, 5 * setup::sui_1B(), ctx(s)), clock, ctx(s));
              vsdb::increase_unlock_time(&mut reg, &mut vsdb, setup::four_years(), clock, ctx(s));

            test::return_to_sender(s, sdb);
            test::return_to_sender(s, vsdb);
            test::return_shared(reg);
        };
        next_tx(s, a);{
            let vsdb = test::take_from_sender<VSDB>(s);
            let voting = vsdb::latest_voting_weight(&vsdb, clock);
            let reg = test::take_shared<VSDBRegistry>(s);
            assert!(voting >= 9999999999948096000, 1);
            assert!(vsdb::locked_balance(&vsdb) == 10 * setup::sui_1B(),1);
            assert!(vsdb::total_supply(&reg) == 10 * setup::sui_1B(), 1);
            assert!(vsdb::total_minted(&reg) == 1, 1);
            assert!( vsdb::get_user_epoch(&vsdb) == 3, 0);

            test::return_to_sender(s, vsdb);
            test::return_shared(reg);
        };

        next_tx(s,a);{ // create 2 additional new VeSDB
            let reg = test::take_shared<VSDBRegistry>(s);
            let sdb = test::take_from_sender<Coin<SDB>>(s);
            vsdb::lock(&mut reg, coin::split(&mut sdb, 5 * setup::sui_100M(), ctx(s)), setup::four_years(), clock, ctx(s));
            vsdb::lock(&mut reg, coin::split(&mut sdb, 5 * setup::sui_100M(), ctx(s)), setup::four_years(), clock, ctx(s));

            test::return_to_sender(s, sdb);
            test::return_shared(reg);
        };
        next_tx(s, a);{
            let vsdb = test::take_from_sender<VSDB>(s);
            let voting = vsdb::latest_voting_weight(&vsdb, clock);
            let reg = test::take_shared<VSDBRegistry>(s);

            assert!(voting >= 499999999877568000, 1);
            assert!(vsdb::locked_balance(&vsdb) == 5 * setup::sui_100M(),1);
            assert!(vsdb::total_supply(&reg) == 110 * setup::sui_100M(), 1);
            assert!(vsdb::total_minted(&reg) == 3, 1);
            assert!( vsdb::get_user_epoch(&vsdb) == 1, 0);

            test::return_to_sender(s, vsdb);
            test::return_shared(reg);
        };

        next_tx(s,a);
        let (id, id_1) = {
            let vsdb = test::take_from_sender<VSDB>(s);
            let vsdb_merged = test::take_from_sender<VSDB>(s);
            let vsdb_merged_1 = test::take_from_sender<VSDB>(s);
            let id = object::id(&vsdb_merged);
            let id_1 = object::id(&vsdb_merged_1);
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::merge(&mut reg, &mut vsdb, vsdb_merged, clock, ctx(s));
            vsdb::merge(&mut reg, &mut vsdb, vsdb_merged_1, clock, ctx(s));

            test::return_to_sender(s, vsdb);
            test::return_shared(reg);
            (id, id_1)
        };
        next_tx(s,a);{
            let vsdb = test::take_from_sender<VSDB>(s);
            let voting = vsdb::latest_voting_weight(&vsdb, clock);
            let reg = test::take_shared<VSDBRegistry>(s);

            assert!(voting >= 10999999999955520000, 1);
            assert!(vsdb::locked_balance(&vsdb) == 110 * setup::sui_100M(),1);
            assert!( vsdb::get_user_epoch(&vsdb) == 3, 0);
            // check NFTs are removed from global storage
            assert!(!test::was_taken_from_address(a, id),1); // not exist
            assert!(!test::was_taken_from_address(a, id_1),1); // not exist
            assert!(vsdb::total_supply(&reg) == 110 * setup::sui_100M(), 1);
            assert!(vsdb::total_minted(&reg) == 1, 1);


            test::return_to_sender(s, vsdb);
            test::return_shared(reg);
        }
    }

    fun pool_(clock: &mut Clock, s: &mut Scenario){
        let (a, b, _c ) = setup::people();

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
        next_tx(s,b);{ // Action: LP B Swap & Claim Fees
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
        next_tx(s,b);{ // Assertion: LP position = 0, fee withdrawl,
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let lp_b = test::take_from_sender<LP<SDB, USDC>>(s);
            // user's fee
            let fee_usdc = test::take_from_sender<Coin<USDC>>(s);
            let fee_sdb = test::take_from_sender<Coin<SDB>>(s);

          std::debug::print(&coin::value(&fee_usdc));
          std::debug::print(&coin::value(&fee_sdb));

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
    }
}