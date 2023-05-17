module test::gauge_test{
    use suiDouBashi_vest::gauge::{Self, Gauge};
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use test::setup;
    use suiDouBashi_vsdb::sdb::SDB;
    use suiDouBashi_amm::usdc::USDC;
    use suiDouBashi_amm::usdt::USDT;
    use suiDouBashi_vest::checkpoints;
    use sui::clock::{timestamp_ms as get_time, increment_for_testing as add_time, Clock};
    use sui::table_vec;
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
                assert!(checkpoints::balance_ts(table_vec::borrow(gauge::checkpoints_borrow(&gauge, a), 0)) == 1673136000, 0);
                assert!(checkpoints::balance(table_vec::borrow(gauge::checkpoints_borrow(&gauge, a), 0)) ==  setup::stake_1(), 0);
                // supply points
                assert!(checkpoints::supply_ts(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 0)) == 1673136000, 0);
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
                assert!(checkpoints::balance_ts(table_vec::borrow(gauge::checkpoints_borrow(&gauge, a), 0)) == 1673136000, 0);
                assert!(checkpoints::balance(table_vec::borrow(gauge::checkpoints_borrow(&gauge, a), 0)) ==  setup::stake_1(), 0);
                // supply points
                assert!(checkpoints::supply_ts(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 0)) == 1673136000, 0);
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
        add_time(clock, 1);
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
                // supply points index at 2
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
                // supply points index at 2
                assert!(checkpoints::supply_ts(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 2)) == get_time(clock), 404);
                assert!(checkpoints::supply(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 2)) ==   setup::stake_1(), 404);
                // total staked lp
                assert!(pool::get_lp_balance(gauge::total_supply_borrow(&gauge)) == setup::stake_1() , 404);
                test::return_shared(gauge);
                test::return_to_sender(s, lp);
            };
        }
    }
}