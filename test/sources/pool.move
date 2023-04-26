#[test_only]
module test::pool{
    use suiDouBashiVest::sdb::{SDB};
    use suiDouBashiVest::vsdb::{Self, VSDB, VSDBRegistry};

    use test::setup;
    use sui::coin::{ Self, mint_for_testing as mint, Coin};
    use sui::object;

    use sui::clock::{Self, timestamp_ms as get_time, increment_for_testing as add_time, Clock};
    use sui::transfer;

    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};

    #[test] fun main(){
        let (a,_,_) = setup::people();
        let scenario = test::begin(a);
        let clock = clock::create_for_testing(ctx(&mut scenario));

        setup_(&mut clock, &mut scenario);
        create_lock_(&mut clock, &mut scenario);

        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    fun setup_(clock: &mut Clock, test: &mut Scenario){
        let (a,_,_) = setup::people();
        add_time(clock, 1672531200);

        setup::deploy_coins(test);
        setup::mint_stable(test);

        vsdb::init_for_testing(ctx(test));
        transfer::public_transfer(mint<SDB>(18 * setup::sui_1B(), ctx(test)), a);
    }

    fun create_lock_(clock: &mut Clock, s: &mut Scenario){
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

           assert!(voting > vsdb::voting_weight(&vsdb, get_time(clock) + setup::day()), 1);
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

            assert!(voting > vsdb::voting_weight(&vsdb, get_time(clock) + setup::day()), 1);
            assert!(vsdb::locked_balance(&vsdb) == 10 * setup::sui_1B(),1);
            assert!(vsdb::total_supply(&reg) == 10 * setup::sui_1B(), 1);
            assert!(vsdb::total_minted(&reg) == 1, 1);
            assert!( vsdb::get_user_epoch(&vsdb) == 3, 0);

            test::return_to_sender(s, vsdb);
            test::return_shared(reg);
        };

        next_tx(s,a);{ // create new VeSDB
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

            assert!(voting > vsdb::voting_weight(&vsdb, get_time(clock) + setup::day()), 1);
            assert!(vsdb::locked_balance(&vsdb) == 5 * setup::sui_100M(),1);
            assert!(vsdb::total_supply(&reg) == 110 * setup::sui_100M(), 1);
            assert!(vsdb::total_minted(&reg) == 3, 1);
            assert!( vsdb::get_user_epoch(&vsdb) == 1, 0);

            test::return_to_sender(s, vsdb);
            test::return_shared(reg);
        };

        next_tx(s,a);
        let (id, id_1) = {
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

            assert!(voting > vsdb::voting_weight(&vsdb, get_time(clock) + setup::day()), 1);
            assert!(vsdb::locked_balance(&vsdb) == 110 * setup::sui_100M(),1);
            assert!( vsdb::get_user_epoch(&vsdb) == 3, 0);
            assert!(!test::was_taken_from_address(a, id),1); // not exist
            assert!(!test::was_taken_from_address(a, id_1),1); // not exist
            assert!(vsdb::total_supply(&reg) == 110 * setup::sui_100M(), 1);
            assert!(vsdb::total_minted(&reg) == 1, 1);

            test::return_to_sender(s, vsdb);
            test::return_shared(reg);
        }
    }
}