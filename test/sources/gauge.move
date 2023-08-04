module test::gauge_test{
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::clock::{increment_for_testing as add_time, timestamp_ms as get_time, Clock};

    use test::setup;

    use suiDouBashi_vote::gauge::{Self, Gauge};
    use suiDouBashi_vsdb::sdb::SDB;
    use suiDouBashi_vote::minter::{mint_sdb, Minter};
    use suiDouBashi_vote::bribe::{Self, Rewards};
    use suiDouBashi_amm::pool::{Self, Pool, LP};

    use coin_list::mock_usdt::{MOCK_USDT as USDT};
    use coin_list::mock_usdc::{MOCK_USDC as USDC};

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
                assert!(pool::lp_balance(&lp) == 1999000 - setup::stake_1(), 0);
                // LP position record in Gauge
                assert!(gauge::lp_stakes(&gauge, &lp) == setup::stake_1(), 0);
                // total staked lp
                assert!(pool::lp_balance(gauge::total_stakes(&gauge)) ==  setup::stake_1() , 1);
                test::return_shared(gauge);
                test::return_to_sender(s, lp);
            };
            {// guage_b
                let lp = test::take_from_sender<LP<SDB, USDC>>(s);
                let gauge = test::take_shared<Gauge<SDB, USDC>>(s);
                assert!(pool::lp_balance(&lp) ==  63244552 - setup::stake_1(), 0);
                // LP position record in Gauge
                assert!(gauge::lp_stakes(&gauge, &lp) == setup::stake_1(), 0);
                // total staked lp
                assert!(pool::lp_balance(gauge::total_stakes(&gauge)) ==  setup::stake_1() , 1);
                test::return_shared(gauge);
                test::return_to_sender(s, lp);
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
                assert!(pool::lp_balance(&lp) == 1000000 - setup::stake_1(), 0);
                // LP position record in Gauge
                assert!(gauge::lp_stakes(&gauge, &lp) == setup::stake_1(), 0);
                // total staked lp
                assert!(pool::lp_balance(gauge::total_stakes(&gauge)) ==  2 * setup::stake_1() , 1);
                test::return_shared(gauge);
                test::return_to_sender(s, lp);
            };
            {// guage_b
                let lp = test::take_from_sender<LP<SDB, USDC>>(s);
                let gauge = test::take_shared<Gauge<SDB, USDC>>(s);
                assert!(pool::lp_balance(&lp) ==  31622776 - setup::stake_1(), 0);
                // LP position record in Gauge
                assert!(gauge::lp_stakes(&gauge, &lp) == setup::stake_1(), 0);
                // total staked lp
                assert!(pool::lp_balance(gauge::total_stakes(&gauge)) == 2 * setup::stake_1() , 1);
                test::return_shared(gauge);
                test::return_to_sender(s, lp);
            }
        };

        add_time(clock, 1000);

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
                assert!(pool::lp_balance(&lp) == 1000000 , 404);
                // LP position record in Gauge
                assert!(gauge::lp_stakes(&gauge, &lp) == 0, 404);
                // index at 1
                // total staked lp
                assert!(pool::lp_balance(gauge::total_stakes(&gauge)) ==  setup::stake_1() , 404);
                test::return_shared(gauge);
                test::return_to_sender(s, lp);
            };
            {// guage_b
                let lp = test::take_from_sender<LP<SDB, USDC>>(s);
                let gauge = test::take_shared<Gauge<SDB, USDC>>(s);
                assert!(pool::lp_balance(&lp) ==  31622776 , 404);
                // LP position record in Gauge
                assert!(gauge::lp_stakes(&gauge, &lp) == 0, 404);
                // index at 1
                // total staked lp
                assert!(pool::lp_balance(gauge::total_stakes(&gauge)) == setup::stake_1() , 404);
                test::return_shared(gauge);
                test::return_to_sender(s, lp);
            };
        };

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


    use suiDouBashi_vote::voter::{Self, Voter};
    use sui::coin::{ Self, mint_for_testing as mint, Coin, burn_for_testing as burn};
    use suiDouBashi_vsdb::vsdb::VSDBRegistry;

    const SCALE_FACTOR: u256 = 1_000_000_000_000_000_000;

    public fun distribute_emissions_(clock: &mut Clock, s: &mut Scenario){
        let ( a, _, c ) = setup::people();

        next_tx(s,a);{ // Action: protocol distribute weekly emissions
            let voter = test::take_shared<Voter>(s);
            let minter = test::take_shared<Minter>(s);
            let gauge_a = test::take_shared<Gauge<USDC, USDT>>(s);
            let gauge_b = test::take_shared<Gauge<SDB, USDC>>(s);

            voter::deposit_sdb(&mut voter, mint<SDB>(setup::stake_1(), ctx(s)));
            voter::update_for(&mut voter, &mut gauge_b, &mut minter);
            voter::update_for(&mut voter, &mut gauge_a, &mut minter);

            test::return_shared(gauge_a);
            test::return_shared(gauge_b);
            test::return_shared(voter);
            test::return_shared(minter);
        };
        next_tx(s,a);{ // Assertion: voter state is successfully updated
            let voter = test::take_shared<Voter>(s);
            let total_voting_weight = voter::total_weight(&voter);
            let index = (setup::stake_1() as u256) * SCALE_FACTOR / (total_voting_weight as u256);
            // voter
            assert!(voter::index(&voter) == index, 404);
            assert!(voter::sdb_balance(&voter) == setup::stake_1(), 404);
            {// pool_a
                let pool = test::take_shared<Pool<USDC, USDT>>(s);
                let gauge= test::take_shared<Gauge<USDC, USDT>>(s);
                let gauge_weights =( voter::pool_weights(&voter, &pool) as u256);
                assert!(gauge::voting_index(&gauge) == index, 404);
                assert!(gauge::claimable(&gauge) == ((index * gauge_weights / SCALE_FACTOR )as u64), 404);

                test::return_shared(pool);
                test::return_shared(gauge);
            };
            {// pool_b
                let pool = test::take_shared<Pool<SDB, USDC>>(s);
                let gauge= test::take_shared<Gauge<SDB, USDC>>(s);
                let gauge_weights =( voter::pool_weights(&voter, &pool) as u256);

                assert!(gauge::voting_index(&gauge) == index, 404);
                assert!(gauge::claimable(&gauge) == ((index * gauge_weights / SCALE_FACTOR )as u64), 404);
                test::return_shared(pool);
                test::return_shared(gauge);
            };
            test::return_shared(voter);
        };
        next_tx(s,a);{ // Actions: distribute weekly emissions
            let voter = test::take_shared<Voter>(s);
            let minter = test::take_shared<Minter>(s);
            let vsdb_reg = test::take_shared<VSDBRegistry>(s);
            let pool = test::take_shared<Pool<USDC, USDT>>(s);
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
            let rewards = test::take_shared<Rewards<USDC, USDT>>(s);

            voter::distribute(&mut voter, &mut minter, &mut gauge, &mut rewards, &mut pool, &mut vsdb_reg, clock, ctx(s));
            test::return_shared(voter);
            test::return_shared(minter);
            test::return_shared(vsdb_reg);
            test::return_shared(pool);
            test::return_shared(gauge);
            test::return_shared(rewards);
        };

        next_tx(s,c);{ // Assertion: first time distribution
            let voter = test::take_shared<Voter>(s);
            let minter = test::take_shared<Minter>(s);
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
            let sdb_team = test::take_from_sender<Coin<SDB>>(s);

            assert!(coin::value(&sdb_team) == 513019197003257 , 404);
            assert!(voter::sdb_balance(&voter) == 8293810352052660, 404);
            assert!(gauge::sdb_balance(&gauge) == 8293810352793456, 404);
            assert!(gauge::claimable(&gauge) == 0, 404);

            burn(sdb_team);
            test::return_shared(voter);
            test::return_shared(gauge);
            test::return_shared(minter);
        };

        next_tx(s,a);{ // Action: staker A withdraw weekly emissions
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
            let lp = test::take_from_sender<LP<USDC, USDT>>(s);

            gauge::get_reward(&mut gauge, &lp, clock, ctx(s));

            test::return_shared(gauge);
            test::return_to_sender(s, lp);
        };

        next_tx(s,a);{ // Assertion:
            let sdb = test::take_from_sender<Coin<SDB>>(s);
            let voter = test::take_shared<Voter>(s);
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);

            // staked for 6 days, previous epoch rate stay at 1
            assert!(coin::value(&sdb) == 518397, 404);
            assert!( gauge::sdb_balance(&gauge) == 8293810352793456 - coin::value(&sdb), 404);
            // reward
            assert!(gauge::period_finish(&gauge) == gauge::epoch_end(get_time(clock) / 1000) , 404);

            burn(sdb);
            test::return_shared(voter);
            test::return_shared(gauge);
        };

        add_time(clock, setup::week() * 1000);

        next_tx(s,a);
        let opt_emission = { // Action: staker A withdraw weekly emissions after a week
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
            let lp = test::take_from_sender<LP<USDC, USDT>>(s);

            let earned = gauge::pending_sdb(&gauge, &lp, clock);
            gauge::get_reward(&mut gauge, &lp, clock, ctx(s));

            test::return_to_sender(s, lp);
            test::return_shared(gauge);

            earned
        };

        next_tx(s,a);{
            let sdb = test::take_from_sender<Coin<SDB>>(s);
            assert!(coin::value(&sdb) == opt_emission, 404);
            burn(sdb);
        };
    }
}