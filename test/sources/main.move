#[test_only]
module test::main{
    use suiDouBashi::pool::Pool;

    use suiDouBashiVest::sdb::SDB;
    use suiDouBashi::usdc::USDC;
    use suiDouBashi::usdt::USDT;

    use test::setup;
    use sui::coin::{ Self, mint_for_testing as mint, Coin, burn_for_testing as burn};
    use sui::object;

    use sui::clock::{Self, timestamp_ms as get_time, increment_for_testing as add_time, Clock};
    use sui::transfer;

    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};


    #[test] fun main(){
        let (a,_,_) = setup::people();
        let s = test::begin(a);
        let clock = clock::create_for_testing(ctx(&mut s));

        setup_(&mut clock, &mut s);
        vest_(&mut clock, &mut s);
        test::pool_test::pool_(&mut clock, &mut s);
        setup::deploy_minter(&mut clock, &mut s);
        setup::deploy_voter(&mut s);
        setup::deploy_gauge(&mut s);

        test::gauge_test::gauge_(&mut clock, &mut s);
        test::bribe_test::bribe_(&mut clock, &mut s);
        test::voter_test::vote_(&mut clock, &mut s);
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

    use suiDouBashiVest::internal_bribe::{InternalBribe};
    use suiDouBashiVest::gauge::{Self, Gauge};
    use suiDouBashiVest::voter::{Self, Voter};
    use suiDouBashiVest::reward_distributor::{Distributor};
    use suiDouBashiVest::minter::{ Minter};
    const SCALE_FACTOR: u128 = 1_000_000_000_000_000_000; // 10e18

    fun distribute_fees_(clock: &mut Clock, s: &mut Scenario){
        let ( a, _, c ) = setup::people();

        next_tx(s,a);{ // Action: protocol distribute weekly emissions
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
        };
        next_tx(s,a);{ // Actions: distribute weekly emissions
            let voter = test::take_shared<Voter>(s);
            let minter = test::take_shared<Minter>(s);
            let distributor = test::take_shared<Distributor>(s);
            let vsdb_reg = test::take_shared<VSDBRegistry>(s);
            let pool = test::take_shared<Pool<USDC, USDT>>(s);
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
            let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);

            voter::distribute(&mut voter, &mut minter, &mut distributor, &mut gauge, &mut i_bribe, &mut pool, &mut vsdb_reg, clock, ctx(s));

            test::return_shared(voter);
            test::return_shared(minter);
            test::return_shared(distributor);
            test::return_shared(vsdb_reg);
            test::return_shared(pool);
            test::return_shared(gauge);
            test::return_shared(i_bribe);
        };
        next_tx(s,c);{
            let voter = test::take_shared<Voter>(s);
            let minter = test::take_shared<Minter>(s);
            let distributor = test::take_shared<Distributor>(s);
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
            let sdb_team = test::take_from_sender<Coin<SDB>>(s);

            assert!(coin::value(&sdb_team) == 459278350515463 , 404);
            assert!(voter::get_balance(&voter) == 7425000000500008, 404);
            assert!(gauge::get_reward_balance(gauge::borrow_reward(&gauge)) == 7425000001413592, 404);

            burn(sdb_team);
            test::return_shared(voter);
            test::return_shared(gauge);
            test::return_shared(minter);
            test::return_shared(distributor);
        };
        next_tx(s,a);{ // Action: withdraw weekly emissions
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
            gauge::get_reward(&mut gauge, clock, ctx(s));
            test::return_shared(gauge);
        }
    }
}
