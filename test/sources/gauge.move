module test::gauge_test{
    use suiDouBashi_vote::gauge::{Self, Gauge, Stake};
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::transfer;
    use test::setup;
    use suiDouBashi_vsdb::sdb::SDB;
    use coin_list::mock_usdt::{MOCK_USDT as USDT};
    use coin_list::mock_usdc::{MOCK_USDC as USDC};
    use sui::clock::{increment_for_testing as add_time, Clock};
    use suiDouBashi_amm::pool::{Self, Pool, LP};

    public fun gauge_(clock: &mut Clock, s: &mut Scenario){
        let ( a, b, _ ) = setup::people();

        next_tx(s,a);{ // Action: LP A stake LP
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let lp_b = test::take_from_sender<LP<SDB, USDC>>(s);
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let gauge_a = test::take_shared<Gauge<USDC, USDT>>(s);
            let gauge_b = test::take_shared<Gauge<SDB, USDC>>(s);

            let stake_a = gauge::new_stake(&gauge_a, ctx(s));
            let stake_b = gauge::new_stake(&gauge_b, ctx(s));
            gauge::stake(&mut gauge_a, &mut stake_a, &pool_a, &mut lp_a, setup::stake_1(), clock, ctx(s));
            gauge::stake(&mut gauge_b, &mut stake_b, &pool_b, &mut lp_b, setup::stake_1(), clock, ctx(s));
            transfer::public_transfer(stake_a, a);
            transfer::public_transfer(stake_b, a);

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
                let stake = test::take_from_sender<Stake<USDC, USDT>>(s);
                let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
                assert!(pool::lp_balance(&lp) == 1999000 - setup::stake_1(), 0);
                // LP position record in Gauge
                assert!(gauge::lp_stakes(&stake) == setup::stake_1(), 0);
                // total staked lp
                assert!(pool::lp_balance(gauge::total_stakes(&gauge)) ==  setup::stake_1() , 1);
                test::return_shared(gauge);
                test::return_to_sender(s, lp);
                test::return_to_sender(s, stake);
            };
            {// guage_b
                let lp = test::take_from_sender<LP<SDB, USDC>>(s);
                let stake = test::take_from_sender<Stake<SDB, USDC>>(s);
                let gauge = test::take_shared<Gauge<SDB, USDC>>(s);
                assert!(pool::lp_balance(&lp) ==  63244552 - setup::stake_1(), 0);
                // LP position record in Gauge
                assert!(gauge::lp_stakes(&stake) == setup::stake_1(), 0);
                // total staked lp
                assert!(pool::lp_balance(gauge::total_stakes(&gauge)) ==  setup::stake_1() , 1);
                test::return_shared(gauge);
                test::return_to_sender(s, lp);
                test::return_to_sender(s, stake);
            }
        };

        add_time(clock, setup::day() * 1000);

        next_tx(s,b);{ // Action: LP B stake LP
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let lp_b = test::take_from_sender<LP<SDB, USDC>>(s);
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let gauge_a = test::take_shared<Gauge<USDC, USDT>>(s);
            let gauge_b = test::take_shared<Gauge<SDB, USDC>>(s);

            let stake_a = gauge::new_stake(&gauge_a, ctx(s));
            let stake_b = gauge::new_stake(&gauge_b, ctx(s));
            gauge::stake(&mut gauge_a, &mut stake_a, &pool_a, &mut lp_a,  setup::stake_1(), clock, ctx(s));
            gauge::stake(&mut gauge_b, &mut stake_b, &pool_b, &mut lp_b,  setup::stake_1(), clock, ctx(s));
            transfer::public_transfer(stake_a, b);
            transfer::public_transfer(stake_b, b);

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
                let stake = test::take_from_sender<Stake<USDC, USDT>>(s);
                let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
                assert!(pool::lp_balance(&lp) == 1000000 - setup::stake_1(), 0);
                // LP position record in Gauge
                assert!(gauge::lp_stakes(&stake) == setup::stake_1(), 0);
                // total staked lp
                assert!(pool::lp_balance(gauge::total_stakes(&gauge)) ==  2 * setup::stake_1() , 1);
                test::return_shared(gauge);
                test::return_to_sender(s, lp);
                test::return_to_sender(s, stake);
            };
            {// guage_b
                let lp = test::take_from_sender<LP<SDB, USDC>>(s);
                let stake = test::take_from_sender<Stake<SDB, USDC>>(s);
                let gauge = test::take_shared<Gauge<SDB, USDC>>(s);
                assert!(pool::lp_balance(&lp) ==  31622776 - setup::stake_1(), 0);
                // LP position record in Gauge
                assert!(gauge::lp_stakes(&stake) == setup::stake_1(), 0);
                // total staked lp
                assert!(pool::lp_balance(gauge::total_stakes(&gauge)) == 2 * setup::stake_1() , 1);
                test::return_shared(gauge);
                test::return_to_sender(s, lp);
                test::return_to_sender(s, stake);
            }
        };
        add_time(clock, 1000);
        next_tx(s,b);{ // Action: LP B unstake
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let lp_b = test::take_from_sender<LP<SDB, USDC>>(s);
            let stake_a = test::take_from_sender<Stake<USDC, USDT>>(s);
            let stake_b = test::take_from_sender<Stake<SDB, USDC>>(s);
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let gauge_a = test::take_shared<Gauge<USDC, USDT>>(s);
            let gauge_b = test::take_shared<Gauge<SDB, USDC>>(s);

            gauge::unstake(&mut gauge_a, &mut stake_a, &pool_a, &mut lp_a, setup::stake_1(), clock, ctx(s));
            gauge::unstake(&mut gauge_b, &mut stake_b, &pool_b, &mut lp_b, setup::stake_1(), clock, ctx(s));

            test::return_shared(gauge_a);
            test::return_shared(gauge_b);
            test::return_to_sender(s, lp_a);
            test::return_to_sender(s, lp_b);
            test::return_to_sender(s, stake_a);
            test::return_to_sender(s, stake_b);
            test::return_shared(pool_a);
            test::return_shared(pool_b);
        };
        next_tx(s,b);{ // Assertion: LP B successfully unstake
             { // gauge_a
                let lp = test::take_from_sender<LP<USDC, USDT>>(s);
                let stake = test::take_from_sender<Stake<USDC, USDT>>(s);
                let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
                assert!(pool::lp_balance(&lp) == 1000000 , 404);
                // LP position record in Gauge
                assert!(gauge::lp_stakes(&stake) == 0, 404);
                // index at 1
                // total staked lp
                assert!(pool::lp_balance(gauge::total_stakes(&gauge)) ==  setup::stake_1() , 404);
                test::return_shared(gauge);
                test::return_to_sender(s, lp);
                test::return_to_sender(s, stake);
            };
            {// guage_b
                let lp = test::take_from_sender<LP<SDB, USDC>>(s);
                let stake = test::take_from_sender<Stake<SDB, USDC>>(s);
                let gauge = test::take_shared<Gauge<SDB, USDC>>(s);
                assert!(pool::lp_balance(&lp) ==  31622776 , 404);
                // LP position record in Gauge
                assert!(gauge::lp_stakes(&stake) == 0, 404);
                // index at 1
                // total staked lp
                assert!(pool::lp_balance(gauge::total_stakes(&gauge)) == setup::stake_1() , 404);
                test::return_shared(gauge);
                test::return_to_sender(s, lp);
                test::return_to_sender(s, stake);
            };
        }
    }
}