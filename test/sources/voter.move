module test::voter_test{
    use std::vector as vec;
    use suiDouBashi::pool::Pool;

    use suiDouBashiVest::sdb::SDB;
    use suiDouBashi::usdc::USDC;
    use suiDouBashi::usdt::USDT;

    use test::setup;
    use sui::coin::{ Self, Coin};
    use sui::object;
    use sui::vec_map;

    use sui::clock::{increment_for_testing as add_time, Clock};

    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use suiDouBashiVest::internal_bribe::{Self as i_bribe, InternalBribe};
    use suiDouBashiVest::external_bribe::{Self as e_bribe, ExternalBribe};
    use suiDouBashiVest::gauge::{Self, Gauge};
    use suiDouBashiVest::voter::{Self, Voter};
    use suiDouBashiVest::vsdb::{Self, VSDB, VSDBRegistry};

    public fun vote_(clock: &mut Clock, s: &mut Scenario){
        let ( a, _, _ ) = setup::people();

        next_tx(s,a);{
            let voter = test::take_shared<Voter>(s);
            let vsdb = test::take_from_sender<VSDB>(s);
            let reg = test::take_shared<VSDBRegistry>(s);

            assert!(!voter::initialized(&vsdb), 404);
            voter::initialize_voting(&voter, &reg, &mut vsdb);

            test::return_shared(voter);
            test::return_shared(reg);
            test::return_to_sender(s, vsdb);
        };
        next_tx(s,a);{
            let vsdb = test::take_from_sender<VSDB>(s);
            assert!(voter::initialized(&vsdb), 404);
            test::return_to_sender(s, vsdb);
        };

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
                    potato = voter::poke_entry(potato, &mut voter, &mut vsdb);
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
            let voter = test::take_shared<Voter>(s);
            assert!(voting >= 998630128940296005, 404);
            assert!(vsdb::locked_balance(&vsdb) == setup::sui_1B(),404);
            assert!(vsdb::total_supply(&reg, clock) == 11878082096488896050, 404);
            assert!(vsdb::total_minted(&reg) == 2, 404);
            assert!( vsdb::get_user_epoch(&vsdb) == 1, 404);
            // intialize
            voter::initialize_voting(&voter, &reg, &mut vsdb);
            test::return_to_sender(s, vsdb);
            test::return_shared(voter);
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
                    potato = voter::vote_entry(potato, &mut voter, vec::singleton(object::id_to_address(&pool_id)), vec::singleton(weights));
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
                assert!(voter::pool_votes_by_pool(&vsdb, &pool_id) == 998630128940296005, 404);
                assert!(voter::used_weights(&vsdb) == 998630128940296005, 404);
                assert!(voter::voted(&vsdb), 404);

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
                let pool_votes_borrow = voter::pool_votes(&vsdb);
                assert!(vec_map::try_get(pool_votes_borrow, &pool_id) == std::option::none<u64>(), 404);
                assert!(voter::used_weights(&vsdb) == 0, 404);
                assert!(!voter::voted(&vsdb), 404);

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
            let vsdb = test::take_from_sender<VSDB>(s);
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
                    potato = voter::vote_entry(potato, &mut voter, pools, weights);
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
            let vsdb = test::take_from_sender<VSDB>(s);
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
                assert!(voter::pool_votes_by_pool(&vsdb, &pool_id) == vsdb_voting / 2, 404);

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
                assert!(voter::pool_votes_by_pool(&vsdb, &pool_id) == vsdb_voting / 2, 404);

                test::return_shared(gauge);
                test::return_shared(i_bribe);
                test::return_shared(e_bribe);
                test::return_shared(pool);
            };
            //voter
            assert!(voter::get_total_weight(&voter) == vsdb_voting / 2 * 2, 404);
            // vsdb
            assert!(voter::used_weights(&vsdb) == vsdb_voting / 2 * 2, 404);
            assert!(voter::voted(&vsdb), 404);

            test::return_shared(voter);
            test::return_to_sender(s, vsdb);
        };
        next_tx(s,a);{ // Action: VSDB holder B voting
            let voter = test::take_shared<Voter>(s);
            let _vsdb = test::take_from_sender<VSDB>(s);
            let vsdb = test::take_from_sender<VSDB>(s);
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
                    assert!( vsdb::latest_voting_weight(&vsdb, clock) == 10773972515494232045, 404);
                    let weights = vec::singleton(50000);
                    vec::push_back(&mut weights, 50000);
                    let pools = vec::singleton(object::id_to_address(&pool_id_a));
                    vec::push_back(&mut pools, object::id_to_address(&pool_id_b));

                    let potato = voter::voting_entry(&mut vsdb, clock);
                    potato = voter::vote_entry(potato,&mut voter, pools, weights);
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
            test::return_to_sender(s, _vsdb);
        };
        next_tx(s,a);{ // Assertion: VSDB B  holder voting successfully
            let voter = test::take_shared<Voter>(s);
            let _vsdb = test::take_from_sender<VSDB>(s);
            let vsdb = test::take_from_sender<VSDB>(s);

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
                assert!(voter::pool_votes_by_pool(&vsdb, &pool_id) == vsdb_voting / 2, 404);

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
                assert!(voter::pool_votes_by_pool(&vsdb, &pool_id) == vsdb_voting / 2, 404);

                test::return_shared(gauge);
                test::return_shared(i_bribe);
                test::return_shared(e_bribe);
                test::return_shared(pool);
            };
            // voter
            assert!(voter::get_total_weight(&voter) == 989041087845544004 + vsdb_voting / 2 * 2, 404);
            // vsdb
            assert!(voter::used_weights(&vsdb) == vsdb_voting / 2 * 2, 404);
            assert!(voter::voted(&vsdb), 404);

            test::return_shared(voter);
            test::return_to_sender(s, vsdb);
            test::return_to_sender(s, _vsdb);
        };
    }
}