module test::e_bribe_test{
    use sui::clock::{increment_for_testing as add_time, Clock};
    use sui::coin::{ Self, mint_for_testing as mint, Coin, burn_for_testing as burn};
    use sui::sui::SUI;
    use test::setup;
    use sui::object;
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use std::vector as vec;
    use suiDouBashi_vest::internal_bribe::{Self as i_bribe, InternalBribe};
    use suiDouBashi_vest::external_bribe::{Self as e_bribe, ExternalBribe};
    use suiDouBashi_vest::gauge::{Self, Gauge};
    use suiDouBashi_vest::voter::{Self, Voter};
    use suiDouBashi_vsdb::vsdb::{Self, Vsdb, VSDBRegistry};
    use suiDouBashi_vest::minter::{ mint_sdb, Minter};
    use suiDouBashi_amm::pool::{LP};
    use suiDouBashi_amm::pool::Pool;
    use suiDouBashi_vsdb::sdb::SDB;
    use coin_list::mock_usdt::{MOCK_USDT as USDT};
    use coin_list::mock_usdc::{MOCK_USDC as USDC};

    public fun external_bribe_(clock: &mut Clock, s: &mut Scenario){
        let ( a, _, _ ) = setup::people();

        // new epoch start
        add_time(clock, setup::week() * 1000);

        next_tx(s,a);{ // Distribute the weekly SDB emissions
            let voter = test::take_shared<Voter>(s);
            let minter = test::take_shared<Minter>(s);
            let vsdb_reg = test::take_shared<VSDBRegistry>(s);
            let pool = test::take_shared<Pool<USDC, USDT>>(s);
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
            let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);
            let e_bribe = test::take_shared<ExternalBribe<USDC, USDT>>(s);
            let lp = test::take_from_sender<LP<USDC, USDT>>(s);

            voter::distribute(&mut voter, &mut minter, &mut gauge, &mut i_bribe, &mut pool, &mut vsdb_reg, clock, ctx(s));

            {// bribing 100K for gauge_a
                e_bribe::bribe(&mut e_bribe, mint<USDC>(setup::usdc_100K(), ctx(s)), clock, ctx(s));
                e_bribe::bribe(&mut e_bribe, mint<USDT>(setup::usdc_100K(), ctx(s)), clock, ctx(s));
                e_bribe::bribe(&mut e_bribe, mint_sdb(&mut minter, setup::sui_100K(), ctx(s)), clock, ctx(s));
                e_bribe::bribe(&mut e_bribe, mint<sui::sui::SUI>(setup::sui_100K(), ctx(s)), clock, ctx(s));
            };

            test::return_shared(voter);
            test::return_shared(minter);
            test::return_shared(vsdb_reg);
            test::return_shared(pool);
            test::return_shared(gauge);
            test::return_shared(i_bribe);
            test::return_shared(e_bribe);
            test::return_to_sender(s, lp);
        };

        next_tx(s,a);{ // VSDB A holder voting
            let voter = test::take_shared<Voter>(s);
            let vsdb = test::take_from_sender<Vsdb>(s);
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

                {   // Potato
                    assert!(vsdb::voting_weight(&vsdb, clock) == 755952312048497141, 404);
                    let weights = vec::singleton(50000);
                    vec::push_back(&mut weights, 50000);
                    let pools = vec::singleton(object::id_to_address(&pool_id_a));
                    vec::push_back(&mut pools, object::id_to_address(&pool_id_b));

                    let potato = voter::voting_entry(&mut vsdb, clock);
                    let potato = voter::reset_(potato, &mut voter, &mut vsdb, &mut gauge_a, &mut i_bribe_a, &mut e_bribe_a, clock);
                    let potato =  voter::reset_(potato, &mut voter, &mut vsdb, &mut gauge_b, &mut i_bribe_b, &mut e_bribe_b, clock);
                    potato = voter::vote_entry(potato,&mut voter, pools, weights);
                    potato = voter::vote_(potato, &mut voter, &mut vsdb, &mut gauge_a, &mut i_bribe_a, &mut e_bribe_a, clock);
                    potato = voter::vote_(potato, &mut voter, &mut vsdb, &mut gauge_b, &mut i_bribe_b, &mut e_bribe_b, clock);
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

        next_tx(s,a);{ // Assertion: Rewards is unavailable to withdraw
            let e_bribe = test::take_shared<ExternalBribe<USDC, USDT>>(s);
            let vsdb = test::take_from_sender<Vsdb>(s);
            let vsdb_1 = test::take_from_sender<Vsdb>(s);

            // vsdb_1
            assert!(e_bribe::earned<USDC, USDT, USDC>(&e_bribe, &vsdb_1, clock) == 0, 404);
            assert!(e_bribe::earned<USDC, USDT, USDT>(&e_bribe, &vsdb_1, clock) == 0, 404);
            assert!(e_bribe::earned<USDC, USDT, SDB>(&e_bribe, &vsdb_1, clock) == 0, 404);
            assert!(e_bribe::earned<USDC, USDT, SUI>(&e_bribe, &vsdb_1, clock) == 0, 404);
            // vsdb
            assert!(e_bribe::earned<USDC, USDT, USDC>(&e_bribe, &vsdb, clock) == 0, 404);
            assert!(e_bribe::earned<USDC, USDT, USDT>(&e_bribe, &vsdb, clock) == 0, 404);
            assert!(e_bribe::earned<USDC, USDT, SDB>(&e_bribe, &vsdb, clock) == 0, 404);
            assert!(e_bribe::earned<USDC, USDT, SUI>(&e_bribe, &vsdb, clock) == 0, 404);

            test::return_to_sender<Vsdb>(s, vsdb_1);
            test::return_to_sender<Vsdb>(s, vsdb);
            test::return_shared(e_bribe);
        };

        // Next epoch start, thereby we are allowed to withdraw external_bribes rewards
        add_time(clock, setup::week() * 1000 + 1);

        next_tx(s, a);{ // Withdraw weekly emissions after expiry
            let voter = test::take_shared<Voter>(s);
            let minter = test::take_shared<Minter>(s);
            let vsdb_reg = test::take_shared<VSDBRegistry>(s);
            let pool = test::take_shared<Pool<USDC, USDT>>(s);
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
            let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);
            let lp = test::take_from_sender<LP<USDC, USDT>>(s);

            {
                voter::claim_rewards(&mut voter, &mut minter, &mut gauge, &mut i_bribe, &mut pool, &mut vsdb_reg, clock, ctx(s));
                gauge::unstake(&mut gauge, &pool, &mut lp, setup::stake_1(), clock, ctx(s));
                add_time(clock, 1);
            };

            test::return_shared(voter);
            test::return_shared(minter);
            test::return_shared(vsdb_reg);
            test::return_shared(pool);
            test::return_shared(gauge);
            test::return_shared(i_bribe);
            test::return_to_sender(s, lp);
        };

        next_tx(s,a);{ // Assertion: received the reward
            let sdb = test::take_from_sender<Coin<SDB>>(s);
            assert!(coin::value(&sdb) == 19246888256400000, 404);
            burn(sdb);
        };

        next_tx(s,a);{ // Vsdb holder internal_bribe ( tx fees )
            let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);
            let vsdb = test::take_from_sender<Vsdb>(s);

            assert!(i_bribe::earned<USDC, USDT, USDC>(&i_bribe, &vsdb, clock) == 911851118, 404);
            assert!(i_bribe::earned<USDC, USDT, USDT>(&i_bribe, &vsdb, clock) == 911851118, 404);
            voter::claim_fees(&mut i_bribe, &vsdb, clock, ctx(s));

            test::return_to_sender<Vsdb>(s, vsdb);
            test::return_shared(i_bribe);
        };

        next_tx(s,a);{
            let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);
            let vsdb = test::take_from_sender<Vsdb>(s);
            let usdc = test::take_from_sender<Coin<USDC>>(s);
            let usdt = test::take_from_sender<Coin<USDT>>(s);

            assert!(coin::value(&usdc) == 911851118, 404);
            assert!(coin::value(&usdt) == 911851118, 404);
            assert!(i_bribe::earned<USDC, USDT, USDC>(&i_bribe, &vsdb, clock) == 0, 404);
            assert!(i_bribe::earned<USDC, USDT, USDT>(&i_bribe, &vsdb, clock) == 0, 404);

            burn(usdc);
            burn(usdt);
            test::return_shared(i_bribe);
            test::return_to_sender<Vsdb>(s, vsdb);
        };

        next_tx(s,a);{ // Vsdb holder withdraw extenal_bribes ( bribes )
            let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);
            let e_bribe = test::take_shared<ExternalBribe<USDC, USDT>>(s);
            let vsdb = test::take_from_sender<Vsdb>(s);
            assert!(e_bribe::earned<USDC, USDT, USDC>(&e_bribe, &vsdb, clock) == 7878411871, 404);
            assert!(e_bribe::earned<USDC, USDT, USDT>(&e_bribe, &vsdb, clock) == 7878411871, 404);
            assert!(e_bribe::earned<USDC, USDT, SUI>(&e_bribe, &vsdb, clock) == 7878411871378, 404);
            assert!(e_bribe::earned<USDC, USDT, SDB>(&e_bribe, &vsdb, clock) == 7878411871378, 404);

            voter::claim_bribes(&mut e_bribe, &vsdb, clock, ctx(s));

            test::return_to_sender<Vsdb>(s, vsdb);
            test::return_shared(i_bribe);
            test::return_shared(e_bribe);
        };
        next_tx(s,a);{
            let e_bribe = test::take_shared<ExternalBribe<USDC, USDT>>(s);
            let vsdb = test::take_from_sender<Vsdb>(s);
            assert!(e_bribe::earned<USDC, USDT, USDC>(&e_bribe, &vsdb, clock) == 0, 404);
            assert!(e_bribe::earned<USDC, USDT, USDT>(&e_bribe, &vsdb, clock) == 0, 404);
            assert!(e_bribe::earned<USDC, USDT, SDB>(&e_bribe, &vsdb, clock) == 0, 404);
            assert!(e_bribe::earned<USDC, USDT, SUI>(&e_bribe, &vsdb, clock) == 0, 404);

            test::return_to_sender<Vsdb>(s, vsdb);
            test::return_shared(e_bribe);
        };
        next_tx(s,a);{ // succesfully receive the bribes
            let usdc = test::take_from_sender<Coin<USDC>>(s);
            let usdt = test::take_from_sender<Coin<USDT>>(s);
            let sui = test::take_from_sender<Coin<sui::sui::SUI>>(s);
            let sdb = test::take_from_sender<Coin<SDB>>(s);

            assert!(coin::value(&usdc) == 7878411871, 404);
            assert!(coin::value(&usdt) == 7878411871, 404);
            assert!(coin::value(&sui) == 7878411871378, 404);
            assert!(coin::value(&sdb) == 7878411871378, 404);

            burn(usdc);
            burn(usdt);
            burn(sui);
            burn(sdb);
        };

        next_tx(s,a);
        let prev_usdc = { // Action: unused Vsdb can't withdraw
            let e_bribe = test::take_shared<ExternalBribe<USDC, USDT>>(s);
            let _vsdb = test::take_from_sender<Vsdb>(s);
            let vsdb = test::take_from_sender<Vsdb>(s);

            let usdc = test::take_from_sender<Coin<USDC>>(s);
            let value = coin::value(&usdc);
            test::return_to_sender(s, usdc);
            voter::claim_bribes(&mut e_bribe, &vsdb, clock, ctx(s));

            test::return_to_sender(s, vsdb);
            test::return_to_sender(s, _vsdb);
            test::return_shared(e_bribe);

            value
        };

        next_tx(s,a);{
            let usdc = test::take_from_sender<Coin<USDC>>(s);
            let value = coin::value(&usdc);
            assert!(value == prev_usdc, 404);
            test::return_to_sender(s, usdc);
        }
    }
}