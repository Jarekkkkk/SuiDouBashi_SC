#[test_only]
module test::main{
    use suiDouBashi::pool::{Self, Pool, LP};

    use suiDouBashiVest::sdb::SDB;
    use suiDouBashiVest::checkpoints;
    use suiDouBashi::usdc::USDC;
    use suiDouBashi::usdt::USDT;

    use test::setup;
    use sui::coin::{ Self, mint_for_testing as mint, Coin, burn_for_testing as burn};
    use sui::object;
    use sui::table;
    use sui::table_vec;

    use sui::clock::{Self, timestamp_ms as get_time, increment_for_testing as add_time, Clock};
    use sui::transfer;

    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};

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

        gauge_(&mut clock, &mut s);
        bribe_(&mut clock, &mut s);
        vote_(&mut clock, &mut s);

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
    use suiDouBashiVest::gauge::{Self, Gauge};
    use suiDouBashiVest::internal_bribe::{ InternalBribe};
    use suiDouBashiVest::external_bribe::{Self as e_bribe, ExternalBribe};
    fun gauge_(clock: &mut Clock, s: &mut Scenario){
        let ( a, b, _ ) = setup::people();

        next_tx(s,a);{ // Action: LP A stake LP
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let lp_b = test::take_from_sender<LP<SDB, USDC>>(s);
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let gauge_a = test::take_shared<Gauge<USDC, USDT>>(s);
            let gauge_b = test::take_shared<Gauge<SDB, USDC>>(s);

            gauge::stake(&mut gauge_a, &pool_a, &mut lp_a, setup::stake_1(), clock, ctx(s));
            gauge::stake(&mut gauge_b, &pool_b, &mut lp_b, setup::stake_1(), clock, ctx(s));

            test::return_shared(gauge_a);
            test::return_shared(gauge_b);
            test::return_to_sender(s, lp_a);
            test::return_to_sender(s, lp_b);
            test::return_shared(pool_a);
            test::return_shared(pool_b);
        };
        next_tx(s,a);{ // Assertion: Successfully staked & Lp_position == 0
            { // gauge_a
                let lp = test::take_from_sender<LP<USDC, USDT>>(s);
                let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
                assert!(pool::get_lp_balance(&lp) == 1999000 - setup::stake_1(), 0);
                // LP position record in Gauge
                assert!(gauge::get_balance_of(&gauge, a) == setup::stake_1(), 0);
                assert!(checkpoints::balance_ts(table_vec::borrow(gauge::checkpoints_borrow(&gauge, a), 0)) == get_time(clock), 0);
                assert!(checkpoints::balance(table_vec::borrow(gauge::checkpoints_borrow(&gauge, a), 0)) ==  setup::stake_1(), 0);
                // supply points
                assert!(checkpoints::supply_ts(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 0)) == get_time(clock), 0);
                assert!(checkpoints::supply(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 0)) ==  setup::stake_1(), 0);
                // total staked lp
                assert!(pool::get_lp_balance(gauge::total_supply_borrow(&gauge)) ==  setup::stake_1() , 1);
                test::return_shared(gauge);
                test::return_to_sender(s, lp);
            };
            {// guage_b
                let lp = test::take_from_sender<LP<SDB, USDC>>(s);
                let gauge = test::take_shared<Gauge<SDB, USDC>>(s);
                assert!(pool::get_lp_balance(&lp) ==  63244552 - setup::stake_1(), 0);
                // LP position record in Gauge
                assert!(gauge::get_balance_of(&gauge, a) == setup::stake_1(), 0);
                assert!(checkpoints::balance_ts(table_vec::borrow(gauge::checkpoints_borrow(&gauge, a), 0)) == get_time(clock), 0);
                assert!(checkpoints::balance(table_vec::borrow(gauge::checkpoints_borrow(&gauge, a), 0)) ==  setup::stake_1(), 0);
                // supply points
                assert!(checkpoints::supply_ts(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 0)) == get_time(clock), 0);
                assert!(checkpoints::supply(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 0)) ==  setup::stake_1(), 0);
                // total staked lp
                assert!(pool::get_lp_balance(gauge::total_supply_borrow(&gauge)) ==  setup::stake_1() , 1);
                test::return_shared(gauge);
                test::return_to_sender(s, lp);
            }
        };

        add_time(clock, setup::day());

        next_tx(s,b);{ // Action: LP B stake LP
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let lp_b = test::take_from_sender<LP<SDB, USDC>>(s);
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let gauge_a = test::take_shared<Gauge<USDC, USDT>>(s);
            let gauge_b = test::take_shared<Gauge<SDB, USDC>>(s);

            gauge::stake(&mut gauge_a, &pool_a, &mut lp_a,  setup::stake_1(), clock, ctx(s));
            gauge::stake(&mut gauge_b, &pool_b, &mut lp_b,  setup::stake_1(), clock, ctx(s));

            test::return_shared(gauge_a);
            test::return_shared(gauge_b);
            test::return_to_sender(s, lp_a);
            test::return_to_sender(s, lp_b);
            test::return_shared(pool_a);
            test::return_shared(pool_b);
        };

        next_tx(s,b);{ // Assertion: Successfully staked & Lp_position == 0
             { // gauge_a
                let lp = test::take_from_sender<LP<USDC, USDT>>(s);
                let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
                assert!(pool::get_lp_balance(&lp) == 1000000 - setup::stake_1(), 0);
                // LP position record in Gauge
                assert!(gauge::get_balance_of(&gauge, b) == setup::stake_1(), 0);
                assert!(checkpoints::balance_ts(table_vec::borrow(gauge::checkpoints_borrow(&gauge, b), 0)) == get_time(clock), 0);
                assert!(checkpoints::balance(table_vec::borrow(gauge::checkpoints_borrow(&gauge, b), 0)) ==  setup::stake_1(), 0);
                // supply points index at 1
                assert!(checkpoints::supply_ts(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 1)) == get_time(clock), 404);
                assert!(checkpoints::supply(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 1)) ==  2 * setup::stake_1(), 404);
                // total staked lp
                assert!(pool::get_lp_balance(gauge::total_supply_borrow(&gauge)) ==  2 * setup::stake_1() , 1);
                test::return_shared(gauge);
                test::return_to_sender(s, lp);
            };
            {// guage_b
                let lp = test::take_from_sender<LP<SDB, USDC>>(s);
                let gauge = test::take_shared<Gauge<SDB, USDC>>(s);
                assert!(pool::get_lp_balance(&lp) ==  31622776 - setup::stake_1(), 0);
                // LP position record in Gauge
                assert!(gauge::get_balance_of(&gauge, b) == setup::stake_1(), 0);
                assert!(checkpoints::balance_ts(table_vec::borrow(gauge::checkpoints_borrow(&gauge, b), 0)) == get_time(clock), 0);
                assert!(checkpoints::balance(table_vec::borrow(gauge::checkpoints_borrow(&gauge, b), 0)) ==  setup::stake_1(), 0);
                // supply points index at 1
                assert!(checkpoints::supply_ts(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 1)) == get_time(clock), 404);
                assert!(checkpoints::supply(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 1)) ==  2 * setup::stake_1(), 404);
                // total staked lp
                assert!(pool::get_lp_balance(gauge::total_supply_borrow(&gauge)) == 2 * setup::stake_1() , 1);
                test::return_shared(gauge);
                test::return_to_sender(s, lp);
            }
        };
        // checkpoint only update when previous ts is different,
        add_time(clock, setup::day());
        next_tx(s,b);{ // Action: LP B unstake
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let lp_b = test::take_from_sender<LP<SDB, USDC>>(s);
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let gauge_a = test::take_shared<Gauge<USDC, USDT>>(s);
            let gauge_b = test::take_shared<Gauge<SDB, USDC>>(s);

            gauge::unstake(&mut gauge_a, &pool_a, &mut lp_a, setup::stake_1(), clock, ctx(s));
            gauge::unstake(&mut gauge_b, &pool_b, &mut lp_b, setup::stake_1(), clock, ctx(s));

            test::return_shared(gauge_a);
            test::return_shared(gauge_b);
            test::return_to_sender(s, lp_a);
            test::return_to_sender(s, lp_b);
            test::return_shared(pool_a);
            test::return_shared(pool_b);
        };
        next_tx(s,b);{ // Assertion: LP B successfully unstake
             { // gauge_a
                let lp = test::take_from_sender<LP<USDC, USDT>>(s);
                let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
                assert!(pool::get_lp_balance(&lp) == 1000000 , 404);
                // LP position record in Gauge
                assert!(gauge::get_balance_of(&gauge, b) == 0, 404);
                // index at 1
                assert!(checkpoints::balance_ts(table_vec::borrow(gauge::checkpoints_borrow(&gauge, b), 1)) == get_time(clock), 404);
                assert!(checkpoints::balance(table_vec::borrow(gauge::checkpoints_borrow(&gauge, b), 1)) ==  0, 404);
                // supply points index at 1
                assert!(checkpoints::supply_ts(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 2)) == get_time(clock), 404);
                assert!(checkpoints::supply(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 2)) ==  setup::stake_1(), 404);
                // total staked lp
                assert!(pool::get_lp_balance(gauge::total_supply_borrow(&gauge)) ==  setup::stake_1() , 404);
                test::return_shared(gauge);
                test::return_to_sender(s, lp);
            };
            {// guage_b
                let lp = test::take_from_sender<LP<SDB, USDC>>(s);
                let gauge = test::take_shared<Gauge<SDB, USDC>>(s);
                assert!(pool::get_lp_balance(&lp) ==  31622776 , 404);
                // LP position record in Gauge
                assert!(gauge::get_balance_of(&gauge, b) == 0, 404);
                // index at 1
                assert!(checkpoints::balance_ts(table_vec::borrow(gauge::checkpoints_borrow(&gauge, b), 1)) == get_time(clock), 404);
                assert!(checkpoints::balance(table_vec::borrow(gauge::checkpoints_borrow(&gauge, b), 1)) == 0, 404);
                // supply points index at 1
                assert!(checkpoints::supply_ts(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 2)) == get_time(clock), 404);
                assert!(checkpoints::supply(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 2)) ==   setup::stake_1(), 404);
                // total staked lp
                assert!(pool::get_lp_balance(gauge::total_supply_borrow(&gauge)) == setup::stake_1() , 404);
                test::return_shared(gauge);
                test::return_to_sender(s, lp);
            };
        }
    }

    fun bribe_(clock: &mut Clock, s: &mut Scenario){
        let (a,_,_) = setup::people();

        next_tx(s,a);{ // Action: distribute weekly emissions & deposit bribes
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let gauge_a = test::take_shared<Gauge<USDC, USDT>>(s);
            let gauge_b = test::take_shared<Gauge<SDB, USDC>>(s);
            let i_bribe_a = test::take_shared<InternalBribe<USDC, USDT>>(s);
            let i_bribe_b = test::take_shared<InternalBribe<SDB, USDC>>(s);
            let e_bribe_a = test::take_shared<ExternalBribe<USDC, USDT>>(s);
            let e_bribe_b = test::take_shared<ExternalBribe<SDB, USDC>>(s);
            let ctx = ctx(s);
            // weekly emissions
            gauge::distribute_emissions(&mut gauge_a, &mut i_bribe_a, &mut pool_a, mint<SDB>(setup::stake_1(), ctx), clock, ctx);
            gauge::distribute_emissions(&mut gauge_b, &mut i_bribe_b, &mut pool_b, mint<SDB>(setup::stake_1(), ctx), clock, ctx);
            // bribe SDB
            e_bribe::bribe(&mut e_bribe_a, mint<SDB>(setup::stake_1(), ctx), clock, ctx);
            e_bribe::bribe(&mut e_bribe_b, mint<SDB>(setup::stake_1(), ctx), clock, ctx);

            test::return_shared(gauge_a);
            test::return_shared(gauge_b);
            test::return_shared(i_bribe_a);
            test::return_shared(i_bribe_b);
            test::return_shared(e_bribe_a);
            test::return_shared(e_bribe_b);
            test::return_shared(pool_a);
            test::return_shared(pool_b);
        };
        next_tx(s,a);{ // Assertion: successfully deposit weekly emissions, pool_fees, external_ bribes
            {// gauge_a
                let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
                let reward = gauge::borrow_reward(&gauge);
                assert!( gauge::get_reward_rate(reward) == 1, 0);
                assert!( gauge::get_reward_per_token_stored(reward) == 0, 0);
                assert!( gauge::get_period_finish(reward) == get_time(clock) + setup::week(), 0);
                assert!( gauge::get_reward_balance(reward) == setup::stake_1(), 0);
                assert!( table_vec::length(gauge::reward_checkpoints_borrow(reward)) == 1, 0);
                assert!( gauge::get_reward_rate(reward) == 1, 0);
                assert!( gauge::reward_per_token(&gauge, clock) == 0, 404);
                test::return_shared(gauge);
            };
            {// gauge_b
                let gauge = test::take_shared<Gauge<SDB, USDC>>(s);
                let reward = gauge::borrow_reward(&gauge);
                assert!( gauge::get_reward_rate(reward) == 1, 0);
                assert!( gauge::get_reward_per_token_stored(reward) == 0, 0);
                assert!( gauge::get_period_finish(reward) == get_time(clock) + setup::week(), 0);
                assert!( gauge::get_reward_balance(reward) == setup::stake_1(), 0);
                assert!( table_vec::length(gauge::reward_checkpoints_borrow(reward)) == 1, 0);
                assert!( gauge::get_reward_rate(reward) == 1, 0);
                assert!( gauge::reward_per_token(&gauge, clock) == 0, 404);
                test::return_shared(gauge);
            };
            {// e_bribe_a
                let e_bribe = test::take_shared<ExternalBribe<USDC, USDT>>(s);
                let reward = e_bribe::borrow_reward<USDC, USDT, SDB>(&e_bribe);
                let epoch_start = e_bribe::get_epoch_start(get_time(clock));
                assert!( *table::borrow(e_bribe::get_reward_per_token_stored(reward), epoch_start) == setup::stake_1(), 0);
                assert!( table::length(e_bribe::get_reward_per_token_stored(reward)) == 1, 0);
                assert!( e_bribe::get_period_finish(reward) == epoch_start + setup::week(), 0);
                assert!( e_bribe::get_reward_balance(reward) == setup::stake_1(), 0);
                test::return_shared(e_bribe);
            };
            {// e_bribe_a
                let e_bribe = test::take_shared<ExternalBribe<SDB, USDC>>(s);
                let reward = e_bribe::borrow_reward<SDB, USDC, SDB>(&e_bribe);
                let epoch_start = e_bribe::get_epoch_start(get_time(clock));
                assert!( *table::borrow(e_bribe::get_reward_per_token_stored(reward), epoch_start) == setup::stake_1(), 0);
                assert!( table::length(e_bribe::get_reward_per_token_stored(reward)) == 1, 0);
                assert!( e_bribe::get_period_finish(reward) == epoch_start + setup::week(), 0);
                assert!( e_bribe::get_reward_balance(reward) == setup::stake_1(), 0);
                test::return_shared(e_bribe);
            };
        };
        add_time(clock, setup::day());
        next_tx(s,a);{ // Action: LP A unstake & claim rewards
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let lp_b = test::take_from_sender<LP<SDB, USDC>>(s);
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let gauge_a = test::take_shared<Gauge<USDC, USDT>>(s);
            let gauge_b = test::take_shared<Gauge<SDB, USDC>>(s);

            // estimated rewards
            assert!(gauge::earned(&gauge_a, a, clock) == 86400 , 404);
            assert!(gauge::earned(&gauge_b, a, clock) == 86400 , 404);

            gauge::unstake(&mut gauge_a, &pool_a, &mut lp_a, setup::stake_1(), clock, ctx(s));
            gauge::unstake(&mut gauge_b, &pool_b, &mut lp_b, setup::stake_1(), clock, ctx(s));

            gauge::get_reward(&mut gauge_a, clock, ctx(s));
            gauge::get_reward(&mut gauge_b, clock, ctx(s));

            test::return_shared(gauge_a);
            test::return_shared(gauge_b);
            test::return_to_sender(s, lp_a);
            test::return_to_sender(s, lp_b);
            test::return_shared(pool_a);
            test::return_shared(pool_b);
        };
        next_tx(s,a);{// Assetion: nobody stake & LP successfully withdraw the rewards
            { // gauge_a
                let lp = test::take_from_sender<LP<USDC, USDT>>(s);
                let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
                let reward = gauge::borrow_reward(&gauge);
                let sdb_reward = test::take_from_sender<Coin<SDB>>(s);
                assert!(pool::get_lp_balance(&lp) == 1999000 , 404);
                // LP position record in Gauge
                assert!(gauge::get_balance_of(&gauge, a) == 0, 404);
                // index at 1
                assert!(checkpoints::balance_ts(table_vec::borrow(gauge::checkpoints_borrow(&gauge, a), 1)) == get_time(clock), 404);
                assert!(checkpoints::balance(table_vec::borrow(gauge::checkpoints_borrow(&gauge, a), 1)) ==  0, 404);
                // supply points index at 1
                assert!(checkpoints::supply_ts(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 3)) == get_time(clock), 404);
                assert!(checkpoints::supply(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 3)) ==  0, 404);
                // total staked lp
                assert!(pool::get_lp_balance(gauge::total_supply_borrow(&gauge)) ==  0, 404);
                // receeive accumulated rewards
                assert!(coin::value(&sdb_reward) == 86400, 404);
                assert!(*table::borrow(gauge::user_reward_per_token_stored_borrow(reward), a) == 86400000, 404);
                assert!(*table::borrow(gauge::last_earn_borrow(reward), a) == get_time(clock), 404);

                test::return_shared(gauge);
                burn(sdb_reward);
                test::return_to_sender(s, lp);
            };
            {// guage_b
                let lp = test::take_from_sender<LP<SDB, USDC>>(s);
                let gauge = test::take_shared<Gauge<SDB, USDC>>(s);
                let reward = gauge::borrow_reward(&gauge);
                let sdb_reward = test::take_from_sender<Coin<SDB>>(s);
                assert!(pool::get_lp_balance(&lp) ==  63244552 , 404);
                // LP position record in Gauge
                assert!(gauge::get_balance_of(&gauge, a) == 0, 404);
                // index at 1
                assert!(checkpoints::balance_ts(table_vec::borrow(gauge::checkpoints_borrow(&gauge, a), 1)) == get_time(clock), 404);
                assert!(checkpoints::balance(table_vec::borrow(gauge::checkpoints_borrow(&gauge, a), 1)) == 0, 404);
                // supply points index at 1
                assert!(checkpoints::supply_ts(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 3)) == get_time(clock), 404);
                assert!(checkpoints::supply(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 3)) ==   0, 404);
                // total staked lp
                assert!(pool::get_lp_balance(gauge::total_supply_borrow(&gauge)) == 0 , 404);
                // receeive accumulated rewards
                assert!(coin::value(&sdb_reward) == 86400, 404);
                assert!(*table::borrow(gauge::user_reward_per_token_stored_borrow(reward), a) == 86400000, 404);
                assert!(*table::borrow(gauge::last_earn_borrow(reward), a) == get_time(clock), 404);

                test::return_shared(gauge);
                burn(sdb_reward);
                test::return_to_sender(s, lp);
            };
        };
        next_tx(s,a);{// Action: LP A Stake back
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let lp_b = test::take_from_sender<LP<SDB, USDC>>(s);
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let gauge_a = test::take_shared<Gauge<USDC, USDT>>(s);
            let gauge_b = test::take_shared<Gauge<SDB, USDC>>(s);

            gauge::stake(&mut gauge_a, &pool_a, &mut lp_a, setup::stake_1(), clock, ctx(s));
            gauge::stake(&mut gauge_b, &pool_b, &mut lp_b, setup::stake_1(), clock, ctx(s));

            test::return_shared(gauge_a);
            test::return_shared(gauge_b);
            test::return_to_sender(s, lp_a);
            test::return_to_sender(s, lp_b);
            test::return_shared(pool_a);
            test::return_shared(pool_b);
        };

        add_time(clock, setup::week());
    }

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

                voter::reset<USDC, USDT>(&mut voter, &mut vsdb, &mut gauge, &mut i_bribe, &mut e_bribe, clock, ctx(s));

                test::return_shared(gauge);
                test::return_shared(i_bribe);
                test::return_shared(e_bribe);
            };
            { // pool_b //TODO: currently we could do single action for each pool
                // let gauge = test::take_shared<Gauge<SDB, USDC>>(s);
                // let i_bribe = test::take_shared<InternalBribe<SDB, USDC>>(s);
                // let e_bribe = test::take_shared<ExternalBribe<SDB, USDC>>(s);

                // voter::reset<SDB, USDC>(&mut voter, &mut vsdb, &mut gauge, &mut i_bribe, &mut e_bribe, clock, ctx(s));

                // test::return_shared(gauge);
                // test::return_shared(i_bribe);
                // test::return_shared(e_bribe);
            };
            test::return_shared(voter);
            test::return_to_sender(s, vsdb);
        };
        next_tx(s,a);{ // Action: poke
            let voter = test::take_shared<Voter>(s);
            let vsdb = test::take_from_sender<VSDB>(s);
            { // pool_a
                let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
                let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);
                let e_bribe = test::take_shared<ExternalBribe<USDC, USDT>>(s);

                voter::poke<USDC, USDT>(&mut voter, &mut vsdb, &mut gauge, &mut i_bribe, &mut e_bribe, clock, ctx(s));

                test::return_shared(gauge);
                test::return_shared(i_bribe);
                test::return_shared(e_bribe);
            };
            { // pool_b //TODO: currently we could do single action for each pool
                // let gauge = test::take_shared<Gauge<SDB, USDC>>(s);
                // let i_bribe = test::take_shared<InternalBribe<SDB, USDC>>(s);
                // let e_bribe = test::take_shared<ExternalBribe<SDB, USDC>>(s);

                // voter::reset<SDB, USDC>(&mut voter, &mut vsdb, &mut gauge, &mut i_bribe, &mut e_bribe, clock, ctx(s));

                // test::return_shared(gauge);
                // test::return_shared(i_bribe);
                // test::return_shared(e_bribe);
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
        add_time(clock, setup::week());
        next_tx(s,a);{ // Assertion: new VSDB & total supply
            let vsdb = test::take_from_sender<VSDB>(s);
            let vsdb_1 = test::take_from_sender<VSDB>(s);
            let voting = vsdb::latest_voting_weight(&vsdb, clock);
            let reg = test::take_shared<VSDBRegistry>(s);
            assert!(voting >= 993150684813600000, 404);
            assert!(vsdb::locked_balance(&vsdb) == setup::sui_1B(),404);
            assert!(vsdb::total_supply(&reg) == 120 * setup::sui_100M(), 404);
            assert!(vsdb::total_minted(&reg) == 2, 404);
            assert!( vsdb::get_user_epoch(&vsdb) == 1, 404);
            test::return_to_sender(s, vsdb);
            test::return_to_sender(s, vsdb_1);
            test::return_shared(reg);
        };
        next_tx(s,a);{ // Action: VSDB holder A voting
            let voter = test::take_shared<Voter>(s);
            let vsdb = test::take_from_sender<VSDB>(s);
            let weights = 5000;

            {// pool_a
                let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
                let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);
                let e_bribe = test::take_shared<ExternalBribe<USDC, USDT>>(s);

                voter::vote<USDC, USDT>(&mut voter, &mut vsdb, &mut gauge, &mut i_bribe, &mut e_bribe, weights, clock, ctx(s));

                test::return_shared(gauge);
                test::return_shared(i_bribe);
                test::return_shared(e_bribe);
            };
            test::return_shared(voter);
            test::return_to_sender(s, vsdb);
        };
        next_tx(s,a);{ // Assertion: voting successfully
            // check
            // gauge: supply_index, claimable
            // voter: weights, total_weights,
            // vsdb: pool_votes, used_weights, voting_state
            // i_brbie: total_supply(voting), balance_of,
            // ex_brbie: total_supply(voting), balance_of,
        }
    }
}

// VSDB(sui::1B());@0x80c3903e5c4101a9a9a40a79a7f3345ded4dd973917eb06a9c706f2824f1b2b3
// VSDB(110 * sui::100M()): @0x77c036971b0e3b7f9f801d16c99a2fba645aa4ef817e9b780f4fc7cec1bb032a