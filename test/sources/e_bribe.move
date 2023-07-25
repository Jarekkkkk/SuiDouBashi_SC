module test::e_bribe_test{
    use std::vector as vec;
    use test::setup;

    use sui::clock::{increment_for_testing as add_time, Clock};
    use sui::coin::{ Self, mint_for_testing as mint, Coin, burn_for_testing as burn};
    use sui::sui::SUI;
    use sui::object;
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};

    use suiDouBashi_vsdb::vsdb::{Self, Vsdb, VSDBRegistry};
    use suiDouBashi_vsdb::sdb::SDB;
    use suiDouBashi_vote::bribe::{Self,Bribe,Rewards};
    use suiDouBashi_vote::gauge::{Self, Gauge};
    use suiDouBashi_vote::voter::{Self, Voter};
    use suiDouBashi_vote::minter::{ mint_sdb, Minter};
    use suiDouBashi_amm::pool::{LP};
    use suiDouBashi_amm::pool::Pool;

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
            let rewards = test::take_shared<Rewards<USDC, USDT>>(s);
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
            let lp = test::take_from_sender<LP<USDC, USDT>>(s);

            voter::distribute(&mut voter, &mut minter, &mut gauge, &mut rewards, &mut pool, &mut vsdb_reg, clock, ctx(s));

            { // bribing 100K for gauge_a
                bribe::bribe(&mut rewards, mint<USDC>(setup::usdc_100K(), ctx(s)), clock);
                bribe::bribe(&mut rewards, mint<USDT>(setup::usdc_100K(), ctx(s)), clock);
                bribe::bribe(&mut rewards, mint_sdb(&mut minter, setup::sui_100K(), ctx(s)), clock);
                bribe::bribe(&mut rewards, mint<sui::sui::SUI>(setup::sui_100K(), ctx(s)), clock);
            };

            test::return_shared(voter);
            test::return_shared(minter);
            test::return_shared(vsdb_reg);
            test::return_shared(pool);
            test::return_shared(gauge);
            test::return_shared(rewards);
            test::return_to_sender(s, lp);
        };

        next_tx(s,a);{ // VSDB A holder voting
            let voter = test::take_shared<Voter>(s);
            let minter = test::take_shared<Minter>(s);
            let vsdb = test::take_from_sender<Vsdb>(s);
            {
                // pool_a
                let gauge_a = test::take_shared<Gauge<USDC, USDT>>(s);
                let pool_id_a = gauge::pool_id(&gauge_a);
                let bribe_a = test::take_shared<Bribe<USDC, USDT>>(s);
                // pool_b
                let gauge_b = test::take_shared<Gauge<SDB, USDC>>(s);
                let pool_id_b = gauge::pool_id(&gauge_b);
                let bribe_b = test::take_shared<Bribe<SDB, USDC>>(s);

                {   // Potato
                    assert!(vsdb::voting_weight(&vsdb, clock) == 755952312048497141, 404);
                    let weights = vec::singleton(50000);
                    vec::push_back(&mut weights, 50000);
                    let pools = vec::singleton(object::id_to_address(&pool_id_a));
                    vec::push_back(&mut pools, object::id_to_address(&pool_id_b));

                    let potato = voter::voting_entry(&mut vsdb, clock);
                    let potato = voter::reset_(potato, &mut voter, &mut minter, &mut vsdb, &mut gauge_a, &mut bribe_a, clock);
                    let potato =  voter::reset_(potato, &mut voter, &mut minter, &mut vsdb, &mut gauge_b, &mut bribe_b, clock);
                    potato = voter::vote_entry(potato,&mut voter, pools, weights);
                    potato = voter::vote_(potato, &mut voter, &mut minter, &mut vsdb, &mut gauge_a, &mut bribe_a, clock);
                    potato = voter::vote_(potato, &mut voter, &mut minter, &mut vsdb, &mut gauge_b, &mut bribe_b, clock);
                    voter::vote_exit(potato, &mut voter, &mut vsdb);
                };

                test::return_shared(gauge_a);
                test::return_shared(bribe_a);

                test::return_shared(gauge_b);
                test::return_shared(bribe_b);
            };
            test::return_shared(voter);
            test::return_shared(minter);
            test::return_to_sender(s, vsdb);
        };

        next_tx(s,a);{ // accumulating rewards
            let bribe = test::take_shared<Bribe<USDC, USDT>>(s);
            let rewards = test::take_shared<Rewards<USDC, USDT>>(s);
            let vsdb = test::take_from_sender<Vsdb>(s);
            let vsdb_1 = test::take_from_sender<Vsdb>(s);

            // vsdb_1
            assert!(bribe::earned<USDC, USDT, USDC>(&bribe, &rewards, &vsdb_1, clock) == 9088127288, 404);
            assert!(bribe::earned<USDC, USDT, USDT>(&bribe, &rewards, &vsdb_1, clock) == 9088127288, 404);
            assert!(bribe::earned<USDC, USDT, SDB>(&bribe, &rewards, &vsdb_1, clock) == 0, 404);
            assert!(bribe::earned<USDC, USDT, SUI>(&bribe, &rewards, &vsdb_1, clock) == 0, 404);
            // vsdb
            assert!(bribe::earned<USDC, USDT, USDC>(&bribe, &rewards, &vsdb, clock) == 911872711, 404);
            assert!(bribe::earned<USDC, USDT, USDT>(&bribe, &rewards, &vsdb, clock) == 911872711, 404);
            assert!(bribe::earned<USDC, USDT, SDB>(&bribe, &rewards, &vsdb, clock) == 0, 404);
            assert!(bribe::earned<USDC, USDT, SUI>(&bribe, &rewards, &vsdb, clock) == 0, 404);

            test::return_to_sender<Vsdb>(s, vsdb_1);
            test::return_to_sender<Vsdb>(s, vsdb);
            test::return_shared(bribe);
            test::return_shared(rewards);
        };

        // Next epoch start, thereby we are allowed to withdraw external_bribes rewards
        add_time(clock, setup::week() * 1000 + 1);

        next_tx(s, a);{ // Withdraw weekly emissions after expiry
            let voter = test::take_shared<Voter>(s);
            let minter = test::take_shared<Minter>(s);
            let vsdb_reg = test::take_shared<VSDBRegistry>(s);
            let pool = test::take_shared<Pool<USDC, USDT>>(s);
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
            let rewards = test::take_shared<Rewards<USDC, USDT>>(s);
            let lp = test::take_from_sender<LP<USDC, USDT>>(s);

            {
                voter::claim_rewards(&mut voter, &mut gauge, clock, ctx(s));
                gauge::unstake(&mut gauge, &pool, &mut lp, setup::stake_1(), clock, ctx(s));
                add_time(clock, 1);
            };

            test::return_shared(voter);
            test::return_shared(minter);
            test::return_shared(vsdb_reg);
            test::return_shared(pool);
            test::return_shared(gauge);
            test::return_shared(rewards);
            test::return_to_sender(s, lp);
        };

        next_tx(s,a);{ // Assertion: received the reward
            let sdb = test::take_from_sender<Coin<SDB>>(s);
            assert!(coin::value(&sdb) == 19246888256796093, 404);
            burn(sdb);
        };

        next_tx(s,a);{ // Vsdb holder internal_bribe ( tx fees )
            let bribe = test::take_shared<Bribe<USDC, USDT>>(s);
            let rewards = test::take_shared<Rewards<USDC, USDT>>(s);
            let vsdb = test::take_from_sender<Vsdb>(s);

            assert!(bribe::earned<USDC, USDT, USDC>(&bribe, &rewards, &vsdb, clock) == 8790284582, 404);
            assert!(bribe::earned<USDC, USDT, USDT>(&bribe, &rewards, &vsdb, clock) == 8790284582, 404);
            assert!(bribe::earned<USDC, USDT, SDB>(&bribe, &rewards, &vsdb, clock) == 7878411871378, 404);
            assert!(bribe::earned<USDC, USDT, SUI>(&bribe, &rewards, &vsdb, clock) == 7878411871378, 404);
            voter::claim_bribes(&mut bribe, &mut rewards, &vsdb, clock, ctx(s));

            test::return_to_sender<Vsdb>(s, vsdb);
            test::return_shared(bribe);
            test::return_shared(rewards);
        };

        next_tx(s,a);{
            let bribe = test::take_shared<Bribe<USDC, USDT>>(s);
            let rewards = test::take_shared<Rewards<USDC, USDT>>(s);
            let vsdb = test::take_from_sender<Vsdb>(s);
            let usdc = test::take_from_sender<Coin<USDC>>(s);
            let usdt = test::take_from_sender<Coin<USDT>>(s);
            let sdb = test::take_from_sender<Coin<SDB>>(s);
            let sui = test::take_from_sender<Coin<SUI>>(s);

            assert!(coin::value(&usdc) == 8790284582, 404);
            assert!(coin::value(&usdt) == 8790284582, 404);
            assert!(coin::value(&sdb) == 7878411871378, 404);
            assert!(coin::value(&sui) == 7878411871378, 404);
            assert!(bribe::earned<USDC, USDT, USDC>(&bribe, &rewards, &vsdb, clock) == 0, 404);
            assert!(bribe::earned<USDC, USDT, USDC>(&bribe, &rewards, &vsdb, clock) == 0, 404);
            assert!(bribe::earned<USDC, USDT, USDT>(&bribe, &rewards, &vsdb, clock) == 0, 404);
            assert!(bribe::earned<USDC, USDT, USDT>(&bribe, &rewards, &vsdb, clock) == 0, 404);

            burn(usdc);
            burn(usdt);
            burn(sdb);
            burn(sui);
            test::return_shared(bribe);
            test::return_shared(rewards);
            test::return_to_sender<Vsdb>(s, vsdb);
        };

        next_tx(s,a);{ // Assertion: unvoted votes get carried over
            let voter = test::take_shared<Voter>(s);
            let _vsdb = test::take_from_sender<Vsdb>(s);
            let vsdb = test::take_from_sender<Vsdb>(s);
            {
                {   // pool_a
                    let bribe = test::take_shared<Bribe<USDC, USDT>>(s);
                    let rewards = test::take_shared<Rewards<USDC, USDT>>(s);
                    assert!(bribe::vsdb_votes(&bribe, &vsdb) == 4419642478226148670, 404);
                    assert!(bribe::earned<USDC, USDT, USDC>(&bribe, &rewards, &vsdb, clock) == 101209715416, 404);
                    assert!(bribe::earned<USDC, USDT, USDT>(&bribe, &rewards, &vsdb, clock) == 101209715416, 404);
                    assert!(bribe::earned<USDC, USDT, SDB>(&bribe, &rewards, &vsdb, clock) == 92121588128621, 404);
                    assert!(bribe::earned<USDC, USDT, SUI>(&bribe, &rewards, &vsdb, clock) == 92121588128621, 404);
                    test::return_shared(bribe);
                    test::return_shared(rewards);
                };
                {   // pool_b
                    let bribe = test::take_shared<Bribe<SDB, USDC>>(s);
                    let rewards = test::take_shared<Rewards<SDB, USDC>>(s);
                    assert!(bribe::vsdb_votes(&bribe, &vsdb) == 4419642478226148670, 404);
                    // no accumulating bribes from previous week
                    assert!(bribe::earned<SDB, USDC, USDC>(&bribe, &rewards, &vsdb, clock) == 0, 404);
                    assert!(bribe::earned<SDB, USDC, SDB>(&bribe, &rewards, &vsdb, clock) == 0, 404);
                    assert!(bribe::earned<SDB, USDC, SUI>(&bribe, &rewards, &vsdb, clock) == 0, 404);
                    test::return_shared(bribe);
                    test::return_shared(rewards);
                };
            };
            test::return_to_sender(s, vsdb);
            test::return_to_sender(s, _vsdb);
            test::return_shared(voter);
        };

        next_tx(s,a);{
            let _vsdb = test::take_from_sender<Vsdb>(s);
            let vsdb = test::take_from_sender<Vsdb>(s);

            let bribe = test::take_shared<Bribe<USDC, USDT>>(s);
            let rewards = test::take_shared<Rewards<USDC, USDT>>(s);
            voter::claim_bribes(&mut bribe, &mut rewards, &vsdb, clock, ctx(s));

            test::return_to_sender<Vsdb>(s, vsdb);
            test::return_to_sender<Vsdb>(s, _vsdb);
            test::return_shared(bribe);
            test::return_shared(rewards);
        };

        next_tx(s,a);{
            let _vsdb = test::take_from_sender<Vsdb>(s);
            let vsdb = test::take_from_sender<Vsdb>(s);
            {
                {   // pool_a
                    let gauge_a = test::take_shared<Gauge<USDC, USDT>>(s);
                    let bribe = test::take_shared<Bribe<USDC, USDT>>(s);
                    let rewards = test::take_shared<Rewards<USDC, USDT>>(s);

                    assert!(bribe::vsdb_votes(&bribe, &vsdb) == 4419642478226148670, 404);
                    assert!(bribe::earned<USDC, USDT, USDC>(&bribe, &rewards, &vsdb, clock) == 0, 404);
                    assert!(bribe::earned<USDC, USDT, USDT>(&bribe, &rewards, &vsdb, clock) == 0, 404);

                    test::return_shared(gauge_a);
                    test::return_shared(bribe);
                    test::return_shared(rewards);
                };
                {   // pool_b
                    let gauge_b = test::take_shared<Gauge<SDB, USDC>>(s);
                    let bribe = test::take_shared<Bribe<SDB, USDC>>(s);
                    let rewards = test::take_shared<Rewards<SDB, USDC>>(s);

                    assert!(bribe::vsdb_votes(&bribe, &vsdb) == 4419642478226148670, 404);
                    // no accumulating bribes from previous week
                    assert!(bribe::earned<SDB, USDC, USDC>(&bribe, &rewards, &vsdb, clock) == 0, 404);
                    assert!(bribe::earned<SDB, USDC, SDB>(&bribe, &rewards, &vsdb, clock) == 0, 404);

                    test::return_shared(gauge_b);
                    test::return_shared(bribe);
                    test::return_shared(rewards);
                };
            };
            test::return_to_sender(s, vsdb);
            test::return_to_sender(s, _vsdb);
        }
    }
}