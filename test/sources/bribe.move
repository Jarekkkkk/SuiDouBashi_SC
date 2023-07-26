module test::bribe_test{
    use suiDouBashi_vote::bribe::{Self, Rewards};
    use suiDouBashi_vote::gauge::{Self, Gauge};
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use test::setup;
    use suiDouBashi_vsdb::sdb::SDB;
    use sui::coin::{Self, Coin, burn_for_testing as burn};
    use coin_list::mock_usdt::{MOCK_USDT as USDT};
    use coin_list::mock_usdc::{MOCK_USDC as USDC};
    use suiDouBashi_vote::minter::{mint_sdb, Minter};
    use sui::clock::{timestamp_ms as get_time, increment_for_testing as add_time, Clock};
    use suiDouBashi_amm::pool::{Pool, LP};

    public fun bribe_(clock: &mut Clock, s: &mut Scenario){
        let (a,_,_) = setup::people();

        next_tx(s,a);{ // Action: distribute weekly emissions & deposit bribes
            let minter = test::take_shared<Minter>(s);
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let gauge_a = test::take_shared<Gauge<USDC, USDT>>(s);
            let gauge_b = test::take_shared<Gauge<SDB, USDC>>(s);
            let rewards_a = test::take_shared<Rewards<USDC, USDT>>(s);
            let rewards_b = test::take_shared<Rewards<SDB, USDC>>(s);
            let ctx = ctx(s);

            // tx fee
            gauge::distribute_emissions(&mut gauge_a, &mut rewards_a, &mut pool_a, mint_sdb(&mut minter, setup::stake_1(), ctx), clock, ctx);
            gauge::distribute_emissions(&mut gauge_b, &mut rewards_b, &mut pool_b, mint_sdb(&mut minter, setup::stake_1(), ctx), clock, ctx);
            // bribe
            bribe::bribe(&mut rewards_a, mint_sdb(&mut minter, setup::stake_1(), ctx), clock);
            bribe::bribe(&mut rewards_b, mint_sdb(&mut minter, setup::stake_1(), ctx), clock);

            test::return_shared(gauge_a);
            test::return_shared(gauge_b);
            test::return_shared(rewards_a);
            test::return_shared(rewards_b);
            test::return_shared(pool_a);
            test::return_shared(pool_b);
            test::return_shared(minter);
        };
        next_tx(s,a);
        let idx = { // Assertion: successfully deposit weekly emissions, pool_fees, external
            let ts = get_time(clock) / 1000;
            let reward_index = setup::stake_1() / ( gauge::epoch_end(ts) - ts );
            {// gauge_a
                let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
                assert!( gauge::reward_rate(&gauge) == reward_index, 0);
                assert!( gauge::gauge_staking_index(&gauge) == 0, 0);
                assert!( gauge::sdb_balance(&gauge) == setup::stake_1(), 0);
                test::return_shared(gauge);
            };
            {// gauge_b
                let gauge = test::take_shared<Gauge<SDB, USDC>>(s);
                assert!( gauge::reward_rate(&gauge) == reward_index, 0);
                assert!( gauge::gauge_staking_index(&gauge) == 0, 0);
                assert!( gauge::sdb_balance(&gauge) == setup::stake_1(), 0);
                test::return_shared(gauge);
            };
            {   // e_bribe_a
                let rewards_a = test::take_shared<Rewards<USDC, USDT>>(s);
                assert!( bribe::rewards_per_epoch<USDC, USDT, SDB>(&rewards_a, get_time(clock)/ 1000) == setup::stake_1(), 0);
                assert!( bribe::rewards_per_epoch<USDC, USDT, SDB>(&rewards_a, get_time(clock)/ 1000) == setup::stake_1(), 0);
                test::return_shared(rewards_a);
            };
            {   // e_bribe_
                let rewards_b = test::take_shared<Rewards<SDB, USDC>>(s);
                assert!( bribe::rewards_per_epoch<SDB, USDC, SDB>(&rewards_b, get_time(clock)/ 1000) == setup::stake_1(), 0);
                assert!( bribe::rewards_per_epoch<SDB, USDC, SDB>(&rewards_b, get_time(clock)/ 1000) == setup::stake_1(), 0);
                test::return_shared(rewards_b);
            };
            reward_index
        };
        // stake for a day
        add_time(clock, setup::day() * 1000);

        next_tx(s,a);{ // Action: LP A unstake & claim rewards
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let lp_b = test::take_from_sender<LP<SDB, USDC>>(s);
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let gauge_a = test::take_shared<Gauge<USDC, USDT>>(s);
            let gauge_b = test::take_shared<Gauge<SDB, USDC>>(s);

            assert!(gauge::pending_sdb(&gauge_a, &lp_a, clock) == idx * setup::day() , 404);
            assert!(gauge::pending_sdb(&gauge_b, &lp_b, clock) == idx * setup::day() , 404);

            gauge::unstake(&mut gauge_a, &pool_a, &mut lp_a, setup::stake_1(), clock, ctx(s));
            gauge::unstake(&mut gauge_b, &pool_b, &mut lp_b, setup::stake_1(), clock, ctx(s));

            gauge::get_reward(&mut gauge_a, &lp_a, clock, ctx(s));
            gauge::get_reward(&mut gauge_b, &lp_b, clock, ctx(s));

            assert!(gauge::pending_sdb(&gauge_a, &lp_a, clock) == 0 , 404);
            assert!(gauge::pending_sdb(&gauge_b, &lp_b, clock) == 0 , 404);

            test::return_shared(gauge_a);
            test::return_shared(gauge_b);
            test::return_to_sender(s, lp_a);
            test::return_to_sender(s, lp_b);
            test::return_shared(pool_a);
            test::return_shared(pool_b);
        };

        next_tx(s,a);{ // Assertion: successfully recieve the coin SDB
            let sdb = test::take_from_sender<Coin<SDB>>(s);
            let sdb_1 = test::take_from_sender<Coin<SDB>>(s);
            assert!(coin::value(&sdb) == 259200, 404);
            assert!(coin::value(&sdb_1) == 259200, 404);
            burn(sdb);
            burn(sdb_1);
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

        add_time(clock, setup::week() * 1000);
    }
}