#[test_only]
module test::vsdb_test{
    use sui::coin::{Self, Coin};
    use sui::object;
    use sui::clock::{increment_for_testing as add_time, Clock};
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};

    use test::setup;
    use suiDouBashi_vsdb::sdb::SDB;
    use suiDouBashi_vsdb::vsdb::{Self, Vsdb, VSDBRegistry, VSDBCap};


    public fun vest_(clock: &mut Clock, s: &mut Scenario){
        let (a,_,_) = setup::people();

        next_tx(s,a);{ // add image_url
            let cap = test::take_from_sender<VSDBCap>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            let art = vector[b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b""];
            vsdb::add_art(&cap, &mut reg, 0, art);
            test::return_to_sender(s, cap);
            test::return_shared(reg);
        };

        next_tx(s, a);{ // create lock
            let reg = test::take_shared<VSDBRegistry>(s);
            let sdb = test::take_from_sender<Coin<SDB>>(s);

            vsdb::lock(&mut reg, coin::split(&mut sdb, 5 * setup::sui_1B(), ctx(s)), vsdb::max_time(), clock, ctx(s));

            test::return_to_sender(s, sdb);
            test::return_shared(reg);
        };
        next_tx(s, a);{
            let vsdb = test::take_from_sender<Vsdb>(s);
            let reg = test::take_shared<VSDBRegistry>(s);

            assert!(vsdb::voting_weight(&vsdb, clock) >=  4910714285702544000, 1);
            assert!(vsdb::locked_balance(&vsdb) == 5 * setup::sui_1B(),1);
            assert!(vsdb::total_VeSDB(&reg, clock) == 4910714285702544000, 1);
            assert!(vsdb::minted_vsdb(&reg) == 1, 1);
            assert!( vsdb::player_epoch(&vsdb) == 0, 0);

            test::return_to_sender(s, vsdb);
            test::return_shared(reg);
        };

        add_time(clock, setup::week() * 1000);

        next_tx(s, a);{ // increase lock amount & time
            let sdb = test::take_from_sender<Coin<SDB>>(s);
            let vsdb = test::take_from_sender<Vsdb>(s);
            let reg = test::take_shared<VSDBRegistry>(s);

            vsdb::increase_unlock_amount(&mut reg, &mut vsdb, coin::split(&mut sdb, 5 * setup::sui_1B(), ctx(s)), clock);
            vsdb::increase_unlock_time(&mut reg, &mut vsdb, vsdb::max_time(), clock);

            test::return_to_sender(s, sdb);
            test::return_to_sender(s, vsdb);
            test::return_shared(reg);
        };
        next_tx(s, a);{
            let vsdb = test::take_from_sender<Vsdb>(s);
            let voting = vsdb::voting_weight(&vsdb, clock);
            let reg = test::take_shared<VSDBRegistry>(s);

            assert!(voting >= 9821428571419344000, 1);
            assert!(vsdb::locked_balance(&vsdb) == 10 * setup::sui_1B(),1);
            assert!(vsdb::total_VeSDB(&reg, clock) == 9821428571419344000, 1);
            assert!(vsdb::minted_vsdb(&reg) == 1, 1);
            assert!( vsdb::player_epoch(&vsdb) == 2, 0);

            test::return_to_sender(s, vsdb);
            test::return_shared(reg);
        };
        next_tx(s,a);{ // create 2 additional new VeSDB
            let reg = test::take_shared<VSDBRegistry>(s);
            let sdb = test::take_from_sender<Coin<SDB>>(s);

            vsdb::lock(&mut reg, coin::split(&mut sdb, 5 * setup::sui_100M(), ctx(s)), vsdb::max_time(), clock, ctx(s));
            vsdb::lock(&mut reg, coin::split(&mut sdb, 5 * setup::sui_100M(), ctx(s)), vsdb::max_time(), clock, ctx(s));

            test::return_to_sender(s, sdb);
            test::return_shared(reg);
        };
        next_tx(s, a);{
            let vsdb = test::take_from_sender<Vsdb>(s);
            let voting = vsdb::voting_weight(&vsdb, clock);
            let reg = test::take_shared<VSDBRegistry>(s);

            assert!(voting >= 491071428557424000, 1);
            assert!(vsdb::locked_balance(&vsdb) == 5 * setup::sui_100M(), 404);
            assert!(vsdb::total_VeSDB(&reg, clock) == 10803571428534192000, 404);
            assert!(vsdb::minted_vsdb(&reg) == 3, 1);
            assert!( vsdb::player_epoch(&vsdb) == 0, 0);

            test::return_to_sender(s, vsdb);
            test::return_shared(reg);
        };
        next_tx(s,a);
        let (id, id_1) = { // Action: Merge 3 vsdb into single
            let vsdb = test::take_from_sender<Vsdb>(s);
            let vsdb_merged = test::take_from_sender<Vsdb>(s);
            let vsdb_merged_1 = test::take_from_sender<Vsdb>(s);
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
            let vsdb = test::take_from_sender<Vsdb>(s);
            let voting = vsdb::voting_weight(&vsdb, clock);
            let reg = test::take_shared<VSDBRegistry>(s);

            assert!(voting >= 10803571428562704000, 1);
            assert!(vsdb::locked_balance(&vsdb) == 110 * setup::sui_100M(),1);
            assert!( vsdb::player_epoch(&vsdb) == 2, 0);
            // check NFTs are removed from global storage
            assert!(!test::was_taken_from_address(a, id),1); // not exist
            assert!(!test::was_taken_from_address(a, id_1),1); // not exist
            assert!(vsdb::total_VeSDB(&reg, clock) == 10803571428562704000, 1);
            assert!(vsdb::minted_vsdb(&reg) == 1, 1);

            test::return_to_sender(s, vsdb);
            test::return_shared(reg);
        }
    }

    public fun vsdb_decay(clock: &mut Clock, s: &mut Scenario){
        let ( a, _, _ ) = setup::people();

        add_time(clock, vsdb::max_time() * 1000);

        next_tx(s,a);{ // Decay the vsdb
            let vsdb = test::take_from_sender<Vsdb>(s);
            let vsdb_1 = test::take_from_sender<Vsdb>(s);
            let vsdb_reg = test::take_shared<VSDBRegistry>(s);
            assert!(vsdb::voting_weight(&vsdb, clock) == 0, 404);
            vsdb::total_VeSDB(&vsdb_reg, clock);
            assert!(vsdb::total_VeSDB(&vsdb_reg, clock) == 0, 404);
            test::return_to_sender(s, vsdb);
            test::return_to_sender(s, vsdb_1);
            test::return_shared(vsdb_reg);
        };
    }
}