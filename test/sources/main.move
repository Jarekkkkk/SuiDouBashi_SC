#[test_only]
module test::main{
    use std::vector as vec;
    use suiDouBashi::pool::{Self, Pool, LP};

    use suiDouBashiVest::sdb::SDB;
    use suiDouBashi::usdc::USDC;
    use suiDouBashi::usdt::USDT;

    use test::setup;
    use sui::coin::{ Self, mint_for_testing as mint, Coin, burn_for_testing as burn};
    use sui::object;
    use sui::vec_map;

    use sui::clock::{Self, timestamp_ms as get_time, increment_for_testing as add_time, Clock};
    use sui::transfer;

    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};

    use test::gauge_test;
    use test::bribe_test;

    #[test] fun main(){
        let (a,_,_) = setup::people();
        let s = test::begin(a);
        let clock = clock::create_for_testing(ctx(&mut s));

        setup_(&mut clock, &mut s);
        vest_(&mut clock, &mut s);
        pool_(&mut clock, &mut s);
        setup::deploy_minter(&mut s);
        setup::deploy_voter(&mut s);
        setup::deploy_gauge(&mut s);

        gauge_test::gauge_(&mut clock, &mut s);
        bribe_test::bribe_(&mut clock, &mut s);
        vote_(&mut clock, &mut s);
        distribute_fees_(&mut clock, &mut s);

        clock::destroy_for_testing(clock);
        test::end(s);
    }

    fun setup_(clock: &mut Clock, test: &mut Scenario){
        let (a,_,_) = setup::people();
        add_time(clock, setup::start_time());
        std::debug::print(&get_time(clock));

        setup::deploy_coins(test);
        setup::mint_stable(test);

        vsdb::init_for_testing(ctx(test));
        transfer::public_transfer(mint<SDB>(18 * setup::sui_1B(), ctx(test)), a);
    }

    use suiDouBashiVest::vsdb::{Self, VSDB, VSDBRegistry};
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
            assert!(voting >=  4404404404910976000, 1);
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
            assert!(voting >= 4044044049948096000, 1);
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

            assert!(voting >= 440440499877568000, 1);
            assert!(vsdb::locked_balance(&vsdb) == 5 * setup::sui_100M(),1);
            assert!(vsdb::total_supply(&reg) == 110 * setup::sui_100M(), 1);
            assert!(vsdb::total_minted(&reg) == 3, 1);
            assert!( vsdb::get_user_epoch(&vsdb) == 1, 0);

            test::return_to_sender(s, vsdb);
            test::return_shared(reg);
        };
        next_tx(s,a);
        let (id, id_1) = { // Action: Merge 3 vsdb into single
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

            assert!(voting >= 10404404404955520000, 1);
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


    use suiDouBashiVest::internal_bribe::{Self as i_bribe, InternalBribe};
    use suiDouBashiVest::external_bribe::{Self as e_bribe, ExternalBribe};
    use suiDouBashiVest::gauge::{Self, Gauge};
    use suiDouBashiVest::voter::{Self, Voter};
    fun vote_(clock: &mut Clock, s: &mut Scenario){
        let ( a, _, _ ) = setup::people();

        next_tx(s,a);{ //Action: VeSDB holder reset the votes
            let voter = test::take_shared<Voter>(s);
            let vsdb = test::take_from_sender<VSDB>(s);

            { // pool_a
                let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
                let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);
                let e_bribe = test::take_shared<ExternalBribe<USDC, USDT>>(s);

                {
                    let potato = voter::voting_entry(&mut vsdb, clock);
                    let potato = voter::reset_(potato, &mut voter, &mut vsdb, &mut gauge, &mut i_bribe, &mut e_bribe, clock, ctx(s));
                    voter::reset_exit(potato, &mut voter, &mut vsdb);
                };

                test::return_shared(gauge);
                test::return_shared(i_bribe);
                test::return_shared(e_bribe);
            };
            test::return_shared(voter);
            test::return_to_sender(s, vsdb);
        };

        add_time(clock, setup::week());

        next_tx(s,a);{ // Action: poke
            let voter = test::take_shared<Voter>(s);
            let vsdb = test::take_from_sender<VSDB>(s);
            { // pool_a
                let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
                let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);
                let e_bribe = test::take_shared<ExternalBribe<USDC, USDT>>(s);

               {
                    let potato = voter::voting_entry(&mut vsdb, clock);
                    // just in case, this can keep if no record
                    potato = voter::reset_(potato, &mut voter, &mut vsdb, &mut gauge, &mut i_bribe, &mut e_bribe, clock, ctx(s));
                    potato = voter::poke_entry(potato, &mut vsdb);
                    // can be skipped as well
                    potato = voter::vote_(potato, &mut voter, &mut vsdb, &mut gauge, &mut i_bribe, &mut e_bribe, clock, ctx(s));
                    voter::vote_exit(potato, &mut voter, &mut vsdb);
                };

                test::return_shared(gauge);
                test::return_shared(i_bribe);
                test::return_shared(e_bribe);
            };
            test::return_shared(voter);
            test::return_to_sender(s, vsdb);
        };

        next_tx(s,a);{ // Action: create new VSDB
            let reg = test::take_shared<VSDBRegistry>(s);
            let sdb = test::take_from_sender<Coin<SDB>>(s);
            vsdb::lock(&mut reg, coin::split(&mut sdb, setup::sui_1B(), ctx(s)), setup::four_years(), clock, ctx(s));

            test::return_to_sender(s, sdb);
            test::return_shared(reg);
        };

        next_tx(s,a);{ // Assertion: new VSDB & total supply
            let vsdb = test::take_from_sender<VSDB>(s);
            let voting = vsdb::latest_voting_weight(&vsdb, clock);
            let reg = test::take_shared<VSDBRegistry>(s);
            assert!(voting >= 998630128940296005, 404);
            assert!(vsdb::locked_balance(&vsdb) == setup::sui_1B(),404);
            assert!(vsdb::total_supply(&reg) == 120 * setup::sui_100M(), 404);
            assert!(vsdb::total_minted(&reg) == 2, 404);
            assert!( vsdb::get_user_epoch(&vsdb) == 1, 404);
            test::return_to_sender(s, vsdb);
            test::return_shared(reg);
        };

        next_tx(s,a);{ // Action: VSDB holder A voting
            let voter = test::take_shared<Voter>(s);
            let vsdb = test::take_from_sender<VSDB>(s);
            let weights = 1;
            {// pool_a
                let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
                let pool_id = gauge::pool_id(&gauge);
                let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);
                let e_bribe = test::take_shared<ExternalBribe<USDC, USDT>>(s);

                { // Potato
                    let potato = voter::voting_entry(&mut vsdb, clock);
                    potato = voter::vote_entry(potato, vec::singleton(object::id_to_address(&pool_id)), vec::singleton(weights));
                    potato = voter::vote_(potato, &mut voter, &mut vsdb, &mut gauge, &mut i_bribe, &mut e_bribe, clock, ctx(s));
                    voter::vote_exit(potato, &mut voter, &mut vsdb);
                };

                test::return_shared(gauge);
                test::return_shared(i_bribe);
                test::return_shared(e_bribe);
            };
            test::return_shared(voter);
            test::return_to_sender(s, vsdb);
        };

        next_tx(s,a);{ // Assertion: voting successfully
            let voter = test::take_shared<Voter>(s);
            let vsdb = test::take_from_sender<VSDB>(s);
            {// pool_a
                let pool = test::take_shared<Pool<USDC, USDT>>(s);
                let pool_id = object::id(&pool);
                let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
                let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);
                let e_bribe = test::take_shared<ExternalBribe<USDC, USDT>>(s);
                //voter
                assert!(voter::get_weights_by_pool(&voter, &pool) == 998630128940296005, 404);
                assert!(voter::get_total_weight(&voter) == 998630128940296005, 404);
                // gauge
                assert!(gauge::get_supply_index(&gauge) == 0, 404);
                assert!(gauge::get_claimable(&gauge) == 0, 404);
                // i_brbie
                assert!(i_bribe::total_voting_weight(&i_bribe) == 998630128940296005, 404);
                assert!(i_bribe::get_balance_of(&i_bribe, &vsdb) == 998630128940296005, 404);
                // e_bribe
                assert!(e_bribe::total_voting_weight(&e_bribe) == 998630128940296005, 404);
                assert!(e_bribe::get_balance_of(&e_bribe, &vsdb) == 998630128940296005, 404);
                // vsdb
                assert!(vsdb::pool_votes(&vsdb, &pool_id) == 998630128940296005, 404);
                assert!(vsdb::get_used_weights(&vsdb) == 998630128940296005, 404);
                assert!(vsdb::get_voted(&vsdb), 404);

                test::return_shared(gauge);
                test::return_shared(i_bribe);
                test::return_shared(e_bribe);
                test::return_shared(pool);
            };
            test::return_shared(voter);
            test::return_to_sender(s, vsdb);
        };

        // // Unable reset until the epoch pass
        add_time(clock, setup::week());

        next_tx(s,a);{
            let voter = test::take_shared<Voter>(s);
            let vsdb = test::take_from_sender<VSDB>(s);
            {
                let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
                let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);
                let e_bribe = test::take_shared<ExternalBribe<USDC, USDT>>(s);
                {
                    let potato = voter::voting_entry(&mut vsdb, clock);
                    let potato = voter::reset_(potato, &mut voter, &mut vsdb, &mut gauge, &mut i_bribe, &mut e_bribe, clock, ctx(s));
                    voter::reset_exit(potato, &mut voter, &mut vsdb);
                };
                test::return_shared(gauge);
                test::return_shared(i_bribe);
                test::return_shared(e_bribe);
            };
            test::return_shared(voter);
            test::return_to_sender(s, vsdb);
        };
        next_tx(s,a);{ // Assertion: clean voting state
            let voter = test::take_shared<Voter>(s);
            let vsdb = test::take_from_sender<VSDB>(s);
            {// pool_a
                let pool = test::take_shared<Pool<USDC, USDT>>(s);
                let pool_id = object::id(&pool);
                let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
                let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);
                let e_bribe = test::take_shared<ExternalBribe<USDC, USDT>>(s);
                //voter
                assert!(voter::get_weights_by_pool(&voter, &pool) == 0, 404);
                assert!(voter::get_total_weight(&voter) == 0, 404);
                // gauge
                assert!(gauge::get_supply_index(&gauge) == 0, 404);
                assert!(gauge::get_claimable(&gauge) == 0, 404);
                // i_brbie
                assert!(i_bribe::total_voting_weight(&i_bribe) == 0, 404);
                assert!(i_bribe::get_balance_of(&i_bribe, &vsdb) == 0, 404);
                // e_bribe
                assert!(e_bribe::total_voting_weight(&e_bribe) == 0, 404);
                assert!(e_bribe::get_balance_of(&e_bribe, &vsdb) == 0, 404);
                // vsdb
                let pool_votes_borrow = vsdb::pool_votes_borrow(&vsdb);
                assert!(vec_map::try_get(pool_votes_borrow, &pool_id) == std::option::none<u64>(), 404);
                assert!(vsdb::get_used_weights(&vsdb) == 0, 404);
                assert!(!vsdb::get_voted(&vsdb), 404);

                test::return_shared(gauge);
                test::return_shared(i_bribe);
                test::return_shared(e_bribe);
                test::return_shared(pool);
            };
            test::return_shared(voter);
            test::return_to_sender(s, vsdb);
        };

        add_time(clock, setup::week());

        next_tx(s,a);{ // Action: VSDB holder A voting
            let voter = test::take_shared<Voter>(s);
            let vsdb = test::take_from_sender_by_id<VSDB>(s, object::id_from_address(@0x80c3903e5c4101a9a9a40a79a7f3345ded4dd973917eb06a9c706f2824f1b2b3));
            {
                // pool_a
                let gauge_a = test::take_shared<Gauge<USDC, USDT>>(s);
                let pool_id_a = gauge::pool_id(&gauge_a);
                let i_bribe_a = test::take_shared<InternalBribe<USDC, USDT>>(s);
                let e_bribe_a = test::take_shared<ExternalBribe<USDC, USDT>>(s);
                // pool_b
                let gauge_b = test::take_shared<Gauge<SDB, USDC>>(s);
                let pool_id_b = gauge::pool_id(&gauge_b);
                let i_bribe_b = test::take_shared<InternalBribe<SDB, USDC>>(s);
                let e_bribe_b = test::take_shared<ExternalBribe<SDB, USDC>>(s);

                { // Potato
                    let weights = vec::singleton(5000);
                    vec::push_back(&mut weights, 5000);
                    let pools = vec::singleton(object::id_to_address(&pool_id_a));
                    vec::push_back(&mut pools, object::id_to_address(&pool_id_b));

                    let potato = voter::voting_entry(&mut vsdb, clock);
                    potato = voter::vote_entry(potato, pools, weights);
                    potato = voter::vote_(potato, &mut voter, &mut vsdb, &mut gauge_a, &mut i_bribe_a, &mut e_bribe_a, clock, ctx(s));
                    potato = voter::vote_(potato, &mut voter, &mut vsdb, &mut gauge_b, &mut i_bribe_b, &mut e_bribe_b, clock, ctx(s));
                    voter::vote_exit(potato, &mut voter, &mut vsdb);
                };

                test::return_shared(gauge_a);
                test::return_shared(i_bribe_a);
                test::return_shared(e_bribe_a);

                test::return_shared(gauge_b);
                test::return_shared(i_bribe_b);
                test::return_shared(e_bribe_b);
            };
            test::return_shared(voter);
            test::return_to_sender(s, vsdb);
        };

        next_tx(s,a);{ // Assertion: VSDB A holder voting successfully
            let voter = test::take_shared<Voter>(s);
            let vsdb = test::take_from_sender_by_id<VSDB>(s, object::id_from_address(@0x80c3903e5c4101a9a9a40a79a7f3345ded4dd973917eb06a9c706f2824f1b2b3));
            let vsdb_voting = vsdb::latest_voting_weight(&vsdb, clock);
            {// pool_a
                let pool = test::take_shared<Pool<USDC, USDT>>(s);
                let pool_id = object::id(&pool);
                let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
                let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);
                let e_bribe = test::take_shared<ExternalBribe<USDC, USDT>>(s);

                // voter
                assert!(voter::get_weights_by_pool(&voter, &pool) == vsdb_voting / 2, 404);
                // gauge
                assert!(gauge::get_supply_index(&gauge) == 0, 404);
                assert!(gauge::get_claimable(&gauge) == 0, 404);
                // i_brbie
                assert!(i_bribe::total_voting_weight(&i_bribe) == vsdb_voting / 2, 404);
                assert!(i_bribe::get_balance_of(&i_bribe, &vsdb) == vsdb_voting / 2, 404);
                // e_bribe
                assert!(e_bribe::total_voting_weight(&e_bribe) == vsdb_voting / 2, 404);
                assert!(e_bribe::get_balance_of(&e_bribe, &vsdb) == vsdb_voting / 2, 404);
                // pools
                assert!(vsdb::pool_votes(&vsdb, &pool_id) == vsdb_voting / 2, 404);

                test::return_shared(gauge);
                test::return_shared(i_bribe);
                test::return_shared(e_bribe);
                test::return_shared(pool);
            };
            {// pool_b
                let pool = test::take_shared<Pool<SDB, USDC>>(s);
                let pool_id = object::id(&pool);
                let gauge = test::take_shared<Gauge<SDB, USDC>>(s);
                let i_bribe = test::take_shared<InternalBribe<SDB, USDC>>(s);
                let e_bribe = test::take_shared<ExternalBribe<SDB, USDC>>(s);
                // voter
                assert!(voter::get_weights_by_pool(&voter, &pool) == vsdb_voting / 2, 404);
                // gauge
                assert!(gauge::get_supply_index(&gauge) == 0, 404);
                assert!(gauge::get_claimable(&gauge) == 0, 404);
                // i_brbie
                assert!(i_bribe::total_voting_weight(&i_bribe) == vsdb_voting / 2, 404);
                assert!(i_bribe::get_balance_of(&i_bribe, &vsdb) == vsdb_voting / 2, 404);
                // e_bribe
                assert!(e_bribe::total_voting_weight(&e_bribe) == vsdb_voting / 2, 404);
                assert!(e_bribe::get_balance_of(&e_bribe, &vsdb) == vsdb_voting / 2, 404);
                // pools
                assert!(vsdb::pool_votes(&vsdb, &pool_id) == vsdb_voting / 2, 404);

                test::return_shared(gauge);
                test::return_shared(i_bribe);
                test::return_shared(e_bribe);
                test::return_shared(pool);
            };
            //voter
            assert!(voter::get_total_weight(&voter) == vsdb_voting / 2 * 2, 404);
            // vsdb
            assert!(vsdb::get_used_weights(&vsdb) == vsdb_voting / 2 * 2, 404);
            assert!(vsdb::get_voted(&vsdb), 404);

            test::return_shared(voter);
            test::return_to_sender(s, vsdb);
        };
        next_tx(s,a);{ // Action: VSDB holder B voting
            let voter = test::take_shared<Voter>(s);
            let vsdb = test::take_from_sender_by_id<VSDB>(s, object::id_from_address(@0x84550b111b9b3595f7fc6263993e4f2d368d59e99531c2be9eb89dbc03b1524));
            {
                // pool_a
                let gauge_a = test::take_shared<Gauge<USDC, USDT>>(s);
                let pool_id_a = gauge::pool_id(&gauge_a);
                let i_bribe_a = test::take_shared<InternalBribe<USDC, USDT>>(s);
                let e_bribe_a = test::take_shared<ExternalBribe<USDC, USDT>>(s);
                // pool_b
                let gauge_b = test::take_shared<Gauge<SDB, USDC>>(s);
                let pool_id_b = gauge::pool_id(&gauge_b);
                let i_bribe_b = test::take_shared<InternalBribe<SDB, USDC>>(s);
                let e_bribe_b = test::take_shared<ExternalBribe<SDB, USDC>>(s);

                { // Potato
                    let weights = vec::singleton(50000);
                    vec::push_back(&mut weights, 50000);
                    let pools = vec::singleton(object::id_to_address(&pool_id_a));
                    vec::push_back(&mut pools, object::id_to_address(&pool_id_b));

                    let potato = voter::voting_entry(&mut vsdb, clock);
                    potato = voter::vote_entry(potato, pools, weights);
                    potato = voter::vote_(potato, &mut voter, &mut vsdb, &mut gauge_a, &mut i_bribe_a, &mut e_bribe_a, clock, ctx(s));
                    potato = voter::vote_(potato, &mut voter, &mut vsdb, &mut gauge_b, &mut i_bribe_b, &mut e_bribe_b, clock, ctx(s));
                    voter::vote_exit(potato, &mut voter, &mut vsdb);
                };

                test::return_shared(gauge_a);
                test::return_shared(i_bribe_a);
                test::return_shared(e_bribe_a);

                test::return_shared(gauge_b);
                test::return_shared(i_bribe_b);
                test::return_shared(e_bribe_b);
            };
            test::return_shared(voter);
            test::return_to_sender(s, vsdb);
        };
        next_tx(s,a);{ // Assertion: VSDB B  holder voting successfully
            let voter = test::take_shared<Voter>(s);
            let vsdb = test::take_from_sender_by_id<VSDB>(s, object::id_from_address(@0x84550b111b9b3595f7fc6263993e4f2d368d59e99531c2be9eb89dbc03b1524));

            let vsdb_voting = vsdb::latest_voting_weight(&vsdb, clock);
            {// pool_a
                let pool = test::take_shared<Pool<USDC, USDT>>(s);
                let pool_id = object::id(&pool);
                let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
                let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);
                let e_bribe = test::take_shared<ExternalBribe<USDC, USDT>>(s);

                // voter
                assert!(voter::get_weights_by_pool(&voter, &pool) == 494520543922772002 + vsdb_voting / 2, 404);
                // gauge
                assert!(gauge::get_supply_index(&gauge) == 0, 404);
                assert!(gauge::get_claimable(&gauge) == 0, 404);
                // i_brbie
                assert!(i_bribe::total_voting_weight(&i_bribe) == 494520543922772002 + vsdb_voting / 2, 404);
                assert!(i_bribe::get_balance_of(&i_bribe, &vsdb) == vsdb_voting / 2, 404);
                // e_bribe
                assert!(e_bribe::total_voting_weight(&e_bribe) == 494520543922772002 + vsdb_voting / 2, 404);
                assert!(e_bribe::get_balance_of(&e_bribe, &vsdb) == vsdb_voting / 2, 404);
                // pools
                assert!(vsdb::pool_votes(&vsdb, &pool_id) == vsdb_voting / 2, 404);

                test::return_shared(gauge);
                test::return_shared(i_bribe);
                test::return_shared(e_bribe);
                test::return_shared(pool);
            };
            {// pool_b
                let pool = test::take_shared<Pool<SDB, USDC>>(s);
                let pool_id = object::id(&pool);
                let gauge = test::take_shared<Gauge<SDB, USDC>>(s);
                let i_bribe = test::take_shared<InternalBribe<SDB, USDC>>(s);
                let e_bribe = test::take_shared<ExternalBribe<SDB, USDC>>(s);
                // voter
                assert!(voter::get_weights_by_pool(&voter, &pool) == 494520543922772002 + vsdb_voting / 2, 404);
                // gauge
                assert!(gauge::get_supply_index(&gauge) == 0, 404);
                assert!(gauge::get_claimable(&gauge) == 0, 404);
                // i_brbie
                assert!(i_bribe::total_voting_weight(&i_bribe) == 494520543922772002 + vsdb_voting / 2, 404);
                assert!(i_bribe::get_balance_of(&i_bribe, &vsdb) == vsdb_voting / 2, 404);
                // e_bribe
                assert!(e_bribe::total_voting_weight(&e_bribe) == 494520543922772002 + vsdb_voting / 2, 404);
                assert!(e_bribe::get_balance_of(&e_bribe, &vsdb) == vsdb_voting / 2, 404);
                // pools
                assert!(vsdb::pool_votes(&vsdb, &pool_id) == vsdb_voting / 2, 404);

                test::return_shared(gauge);
                test::return_shared(i_bribe);
                test::return_shared(e_bribe);
                test::return_shared(pool);
            };
            //voter
            assert!(voter::get_total_weight(&voter) == 989041087845544004 + vsdb_voting / 2 * 2, 404);
            // vsdb
            assert!(vsdb::get_used_weights(&vsdb) == vsdb_voting / 2 * 2, 404);
            assert!(vsdb::get_voted(&vsdb), 404);

            test::return_shared(voter);
            test::return_to_sender(s, vsdb);
        };
    }

    const SCALE_FACTOR: u128 = 1_000_000_000_000_000_000; // 10e18
    fun distribute_fees_(_clock: &mut Clock, s: &mut Scenario){
        let ( a, _, _ ) = setup::people();

        next_tx(s,a);{ // Action: Protocol distribute weekly emissions
            let voter = test::take_shared<Voter>(s);
            let gauge_a = test::take_shared<Gauge<USDC, USDT>>(s);
            let gauge_b = test::take_shared<Gauge<SDB, USDC>>(s);

            voter::notify_reward_amount_(&mut voter, mint<SDB>(setup::stake_1(), ctx(s)));
            voter::update_for_(&voter, &mut gauge_a);
            voter::update_for_(&voter, &mut gauge_b);

            test::return_shared(gauge_a);
            test::return_shared(gauge_b);
            test::return_shared(voter);
        };
        next_tx(s,a);{ // Assertion: voter state is successfully updated
            let voter = test::take_shared<Voter>(s);
            let total_voting_weight = voter::get_total_weight(&voter);
            let index = (setup::stake_1() as u128) * SCALE_FACTOR / (total_voting_weight as u128);

            // voter
            assert!(voter::get_index(&voter) == index, 404);
            assert!(voter::get_balance(&voter) == setup::stake_1(), 404);
            {// pool_a
                let pool = test::take_shared<Pool<USDC, USDT>>(s);
                let gauge= test::take_shared<Gauge<USDC, USDT>>(s);
                let gauge_weights =( voter::get_weights_by_pool(&voter, &pool) as u128);

                assert!(gauge::get_supply_index(&gauge) == index, 404);
                assert!(gauge::get_claimable(&gauge) == ((index * gauge_weights / SCALE_FACTOR )as u64), 404);

                test::return_shared(pool);
                test::return_shared(gauge);
            };
            {// pool_b
                let pool = test::take_shared<Pool<SDB, USDC>>(s);
                let gauge= test::take_shared<Gauge<SDB, USDC>>(s);
                let gauge_weights =( voter::get_weights_by_pool(&voter, &pool) as u128);

                assert!(gauge::get_supply_index(&gauge) == index, 404);
                assert!(gauge::get_claimable(&gauge) == ((index * gauge_weights / SCALE_FACTOR )as u64), 404);

                test::return_shared(pool);
                test::return_shared(gauge);
            };
            test::return_shared(voter);
        }
    }
}

// VSDB(sui::1B());@0x80c3903e5c4101a9a9a40a79a7f3345ded4dd973917eb06a9c706f2824f1b2b3
// VSDB(110 * sui::100M()): @0x84550b111b9b3595f7fc6263993e4f2d368d59e99531c2be9eb89dbc03b1524
