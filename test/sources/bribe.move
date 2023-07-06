module test::bribe_test{
    use suiDouBashi_vest::internal_bribe::{InternalBribe};
    use suiDouBashi_vest::external_bribe::{Self as e_bribe, ExternalBribe};
    use suiDouBashi_vest::gauge::{Self, Gauge};
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use test::setup;
    use suiDouBashi_vsdb::sdb::SDB;
    use coin_list::mock_usdt::{MOCK_USDT as USDT};
    use coin_list::mock_usdc::{MOCK_USDC as USDC};
    use suiDouBashi_vest::checkpoints;
    use suiDouBashi_vest::minter::{mint_sdb, Minter};
    use sui::clock::{timestamp_ms as get_time, increment_for_testing as add_time, Clock};
    use sui::table_vec;
    use sui::coin::{ Self, Coin, burn_for_testing as burn};
    use suiDouBashi_amm::pool::{Self, Pool, LP};
    use sui::table;

    public fun bribe_(clock: &mut Clock, s: &mut Scenario){
        let (a,_,_) = setup::people();

        next_tx(s,a);{ // Action: distribute weekly emissions & deposit bribes
            let minter = test::take_shared<Minter>(s);
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
            gauge::distribute_emissions(&mut gauge_a, &mut i_bribe_a, &mut pool_a, mint_sdb(&mut minter, setup::stake_1(), ctx), clock, ctx);
            gauge::distribute_emissions(&mut gauge_b, &mut i_bribe_b, &mut pool_b, mint_sdb(&mut minter, setup::stake_1(), ctx), clock, ctx);
            // bribe SDB
            e_bribe::bribe(&mut e_bribe_a, mint_sdb(&mut minter, setup::stake_1(), ctx), clock, ctx);
            e_bribe::bribe(&mut e_bribe_b, mint_sdb(&mut minter, setup::stake_1(), ctx), clock, ctx);

            test::return_shared(gauge_a);
            test::return_shared(gauge_b);
            test::return_shared(i_bribe_a);
            test::return_shared(i_bribe_b);
            test::return_shared(e_bribe_a);
            test::return_shared(e_bribe_b);
            test::return_shared(pool_a);
            test::return_shared(pool_b);
            test::return_shared(minter);
        };
        next_tx(s,a);{ // Assertion: successfully deposit weekly emissions, pool_fees, external_ bribes
                let reward_index = setup::stake_1() / setup::week();
            {// gauge_a
                let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
                let reward = gauge::borrow_reward(&gauge);
                assert!( gauge::get_reward_rate(reward) == reward_index, 0);
                assert!( gauge::get_reward_per_token_stored(reward) == 0, 0);
                assert!( gauge::get_period_finish(reward) == get_time(clock) / 1000 + setup::week(), 0);
                assert!( gauge::get_reward_balance(reward) == setup::stake_1(), 0);
                assert!( table_vec::length(gauge::reward_checkpoints_borrow(reward)) == reward_index, 0);
                assert!( gauge::reward_per_token(&gauge, clock) == 0, 404);
                test::return_shared(gauge);
            };
            {// gauge_b
                let gauge = test::take_shared<Gauge<SDB, USDC>>(s);
                let reward = gauge::borrow_reward(&gauge);
                assert!( gauge::get_reward_rate(reward) == reward_index, 0);
                assert!( gauge::get_reward_per_token_stored(reward) == 0, 0);
                assert!( gauge::get_period_finish(reward) == get_time(clock)/ 1000 + setup::week(), 0);
                assert!( gauge::get_reward_balance(reward) == setup::stake_1(), 0);
                assert!( table_vec::length(gauge::reward_checkpoints_borrow(reward)) == reward_index, 0);
                assert!( gauge::reward_per_token(&gauge, clock) == 0, 404);
                test::return_shared(gauge);
            };
            {// e_bribe_a
                let e_bribe = test::take_shared<ExternalBribe<USDC, USDT>>(s);
                let reward = e_bribe::borrow_reward<USDC, USDT, SDB>(&e_bribe);
                let epoch_start = e_bribe::get_epoch_start(get_time(clock)/ 1000);
                assert!( *table::borrow(e_bribe::get_reward_per_token_stored(reward), epoch_start) == setup::stake_1(), 0);
                assert!( table::length(e_bribe::get_reward_per_token_stored(reward)) == 1, 0);
                assert!( e_bribe::get_period_finish(reward) == epoch_start + setup::week(), 0);
                assert!( e_bribe::get_reward_balance<USDC, USDT, SDB>(&e_bribe) == setup::stake_1(), 0);
                test::return_shared(e_bribe);
            };
            {// e_bribe_a
                let e_bribe = test::take_shared<ExternalBribe<SDB, USDC>>(s);
                let reward = e_bribe::borrow_reward<SDB, USDC, SDB>(&e_bribe);
                let epoch_start = e_bribe::get_epoch_start(get_time(clock)/ 1000);
                assert!( *table::borrow(e_bribe::get_reward_per_token_stored(reward), epoch_start) == setup::stake_1(), 0);
                assert!( table::length(e_bribe::get_reward_per_token_stored(reward)) == 1, 0);
                assert!( e_bribe::get_period_finish(reward) == epoch_start + setup::week(), 0);
                assert!( e_bribe::get_reward_balance<SDB, USDC, SDB>(&e_bribe) == setup::stake_1(), 0);
                test::return_shared(e_bribe);
            };
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

            assert!(gauge::earned(&gauge_a, a, clock) == 86400 , 404);
            assert!(gauge::earned(&gauge_b, a, clock) == 86400 , 404);

            gauge::unstake(&mut gauge_a, &pool_a, &mut lp_a, setup::stake_1(), clock, ctx(s));
            gauge::unstake(&mut gauge_b, &pool_b, &mut lp_b, setup::stake_1(), clock, ctx(s));

            gauge::get_reward(&mut gauge_a, clock, ctx(s));
            gauge::get_reward(&mut gauge_b, clock, ctx(s));

            assert!(gauge::earned(&gauge_a, a, clock) == 0 , 404);
            assert!(gauge::earned(&gauge_b, a, clock) == 0 , 404);

            test::return_shared(gauge_a);
            test::return_shared(gauge_b);
            test::return_to_sender(s, lp_a);
            test::return_to_sender(s, lp_b);
            test::return_shared(pool_a);
            test::return_shared(pool_b);
        };
        next_tx(s,a);{// Assetion: nobody stake & LP successfully withdraw the rewards
            {   // gauge_a
                let lp = test::take_from_sender<LP<USDC, USDT>>(s);
                let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
                let reward = gauge::borrow_reward(&gauge);
                let sdb_reward = test::take_from_sender<Coin<SDB>>(s);
                assert!(pool::get_lp_balance(&lp) == 1999000 , 404);
                // LP position record in Gauge
                assert!(gauge::get_balance_of(&gauge, a) == 0, 404);
                // index at 1
                assert!(checkpoints::balance_ts(table_vec::borrow(gauge::checkpoints_borrow(&gauge, a), 1)) == get_time(clock)/ 1000, 404);
                assert!(checkpoints::balance(table_vec::borrow(gauge::checkpoints_borrow(&gauge, a), 1)) ==  0, 404);
                // supply points index at 1
                assert!(checkpoints::supply_ts(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 3)) == get_time(clock)/ 1000, 404);
                assert!(checkpoints::supply(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 3)) ==  0, 404);
                // total staked lp
                assert!(pool::get_lp_balance(gauge::total_supply_borrow(&gauge)) ==  0, 404);
                // receeive accumulated rewards
                assert!(coin::value(&sdb_reward) == 86400, 404);
                assert!(*table::borrow(gauge::user_reward_per_token_stored_borrow(reward), a) == 86400000000000000, 404);
                assert!(*table::borrow(gauge::last_earn_borrow(reward), a) == get_time(clock)/ 1000, 404);

                test::return_shared(gauge);
                burn(sdb_reward);
                test::return_to_sender(s, lp);
            };
            {   // guage_b
                let lp = test::take_from_sender<LP<SDB, USDC>>(s);
                let gauge = test::take_shared<Gauge<SDB, USDC>>(s);
                let reward = gauge::borrow_reward(&gauge);
                let sdb_reward = test::take_from_sender<Coin<SDB>>(s);
                assert!(pool::get_lp_balance(&lp) ==  63244552, 404);
                // LP position record in Gauge
                assert!(gauge::get_balance_of(&gauge, a) == 0, 404);
                // index at 1
                assert!(checkpoints::balance_ts(table_vec::borrow(gauge::checkpoints_borrow(&gauge, a), 1)) == get_time(clock)/ 1000, 404);
                assert!(checkpoints::balance(table_vec::borrow(gauge::checkpoints_borrow(&gauge, a), 1)) == 0, 404);
                // supply points index at 1
                assert!(checkpoints::supply_ts(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 3)) == get_time(clock)/ 1000, 404);
                assert!(checkpoints::supply(table_vec::borrow(gauge::supply_checkpoints_borrow(&gauge), 3)) ==   0, 404);
                // total staked lp
                assert!(pool::get_lp_balance(gauge::total_supply_borrow(&gauge)) == 0 , 404);
                // receeive accumulated rewards
                assert!(coin::value(&sdb_reward) == 86400, 404);
                assert!(*table::borrow(gauge::user_reward_per_token_stored_borrow(reward), a) == 86400000000000000, 404);
                assert!(*table::borrow(gauge::last_earn_borrow(reward), a) == get_time(clock)/ 1000, 404);

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

        add_time(clock, setup::week() * 1000);
    }
}