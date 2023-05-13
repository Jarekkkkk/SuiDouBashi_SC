#[test_only]
module test::vsdb{
    use sui::coin::{ mint_for_testing as mint};
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::clock::{Self, timestamp_ms as get_time, increment_for_testing as add_time, Clock};
    use suiDouBashiVest::vsdb;
    use suiDouBashiVest::sdb::SDB;
    use suiDouBashiVest::vsdb::{ VSDBRegistry,VSDB};

    use test::setup::{Self, people};

    #[test]
    fun test_create_lock(){
        let (a, _, _) = people();
        let scenario = test::begin(a);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        add_time(&mut clock, 1672531200);

        test_create_lock_(&mut clock, &mut scenario);
        test_whitelisted_module(&mut clock, &mut scenario);

        clock::destroy_for_testing(clock);
        test::end(scenario);
    }
    #[test]
    #[expected_failure(abort_code = suiDouBashiVest::vsdb::E_INVALID_UNLOCK_TIME)]
    fun test_error_invalid_time(){
        let (a, _, _) = people();
        let scenario = test::begin(a);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        let s = &mut scenario;
        add_time(&mut clock, 1672531200);

        // main
        vsdb::init_for_testing(ctx(s));
        next_tx(s, a);{
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::lock(&mut reg, mint<SDB>(setup::sui_100M(), ctx(s)), setup::week(), &clock, ctx(s));
            test::return_shared(reg);
        };
        next_tx(s, a);{ // extend 2 weeks duration
            let vsdb = test::take_from_sender<VSDB>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::increase_unlock_time(&mut reg, &mut vsdb, setup::four_years() + vsdb::week(), &clock, ctx(s));
            test::return_shared(reg);
            test::return_to_sender(s, vsdb);
        };

        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = suiDouBashiVest::vsdb::E_LOCK)]
    fun test_error_unlock(){
        let (a, _, _) = people();
        let scenario = test::begin(a);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        let s = &mut scenario;
        add_time(&mut clock, 1672531200);

        // main
        vsdb::init_for_testing(ctx(s));
        next_tx(s, a);{
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::lock(&mut reg, mint<SDB>(setup::sui_100M(), ctx(s)), setup::week(), &clock, ctx(s));
            test::return_shared(reg);
        };
        next_tx(s, a);{ // early unlock
            let vsdb = test::take_from_sender<VSDB>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::unlock(&mut reg, vsdb, &clock, ctx(s));
            test::return_shared(reg);
        };

        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    fun test_create_lock_(clock: &mut Clock, s: &mut Scenario){
        let (a, _, _) = people();

        vsdb::init_for_testing(ctx(s));

         next_tx(s, a);
        {
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::lock(&mut reg, mint<SDB>(setup::sui_100M(), ctx(s)), setup::week(), clock, ctx(s));
            test::return_shared(reg);
        };
        next_tx(s, a);{
            let vsdb = test::take_from_sender<VSDB>(s);
            let slope = vsdb::calculate_slope(setup::sui_100M());
            let end = vsdb::round_down_week(get_time(clock) + setup::week());
            let bias = vsdb::calculate_bias(setup::sui_100M(), end, get_time(clock));
            assert!( vsdb::get_latest_slope(&vsdb) == slope, 0);
            assert!( vsdb::get_user_epoch(&vsdb) == 1, 0);
            assert!( vsdb::get_latest_bias(&vsdb) == bias , 0);
            assert!( vsdb::locked_end(&vsdb) == end, 0);
            test::return_to_sender(s, vsdb);
        };
        next_tx(s, a);{ // extend 2 weeks duration
            let vsdb = test::take_from_sender<VSDB>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::increase_unlock_time(&mut reg, &mut vsdb, 2 * vsdb::week(), clock, ctx(s));
            test::return_shared(reg);
            test::return_to_sender(s, vsdb);
        };
        next_tx(s, a);{
            let vsdb = test::take_from_sender<VSDB>(s);
            let slope = vsdb::calculate_slope(setup::sui_100M()); // slope is unchanged
            let end = vsdb::round_down_week(get_time(clock) + 2 * vsdb::week());
            let bias = vsdb::calculate_bias(setup::sui_100M(), end, get_time(clock));
            assert!( vsdb::locked_end(&vsdb) == end, 0);
            assert!( vsdb::get_user_epoch(&vsdb) == 2, 0);
            assert!( vsdb::get_latest_slope(&vsdb) == slope, 0);
            assert!( vsdb::get_latest_bias(&vsdb) == bias , 0);
            test::return_to_sender(s, vsdb);
        };
         next_tx(s, a);{ // extend amount
            let vsdb = test::take_from_sender<VSDB>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::increase_unlock_amount(&mut reg, &mut vsdb, mint<SDB>(setup::sui_1B(), ctx(s)), clock, ctx(s));
            test::return_shared(reg);
            test::return_to_sender(s, vsdb);
        };
        next_tx(s, a);{
            let vsdb = test::take_from_sender<VSDB>(s);
            let value = setup::sui_1B() + setup::sui_100M();
            let end = vsdb::round_down_week(get_time(clock) + 2 * vsdb::week());
            let slope = vsdb::calculate_slope(value);
            let bias = vsdb::calculate_bias(value, end, get_time(clock));
            assert!( vsdb::locked_end(&vsdb) == end, 0);
            assert!( vsdb::get_user_epoch(&vsdb) == 3, 0);
            assert!( vsdb::get_latest_slope(&vsdb) == slope, 0);
            assert!( vsdb::get_latest_bias(&vsdb) == bias , 0);
            test::return_to_sender(s, vsdb);
        };
        add_time(clock, 3 * setup::week());
        next_tx(s, a);{ // unlock
            let vsdb = test::take_from_sender<VSDB>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::unlock(&mut reg, vsdb, clock, ctx(s));
            vsdb::global_checkpoint(&mut reg, clock);
            vsdb::global_checkpoint(&mut reg, clock);
            vsdb::global_checkpoint(&mut reg, clock);
            vsdb::global_checkpoint(&mut reg, clock);
            vsdb::global_checkpoint(&mut reg, clock);
            test::return_shared(reg);
        };
        next_tx(s, a);{ // vsdb been burnt
            assert!(!test::has_most_recent_for_sender<VSDB>(s), 0);
        }
    }

    use test::test_whitelist::{Self as white, MOCK, Foo};
    use suiDouBashiVest::vsdb::{VSDBCap};
    fun test_whitelisted_module(clock: &mut Clock, s: &mut Scenario){
        let ( a, _, _ ) = setup::people();

        next_tx(s, a);{
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::lock(&mut reg, mint<SDB>(setup::sui_100M(), ctx(s)), setup::week(), clock, ctx(s));
            test::return_shared(reg);
        };

        next_tx(s,a);{
            let reg_cap = test::take_from_sender<VSDBCap>(s);
            let reg = test::take_shared<VSDBRegistry>(s);

            vsdb::register_module<MOCK>(&reg_cap, &mut reg);
            white::init_for_testing(ctx(s));

            test::return_shared(reg);
            test::return_to_sender(s, reg_cap);
        };

        next_tx(s,a);{
            let foo = test::take_shared<Foo>(s);
            let type = std::type_name::into_string(std::type_name::get<MOCK>());
            let reg = test::take_shared<VSDBRegistry>(s);
            let vsdb = test::take_from_sender<VSDB>(s);

            white::add_pool_votes(&foo, &reg, &mut vsdb);
            let _registered = vsdb::module_exists(&vsdb, std::ascii::into_bytes(type));

            test::return_shared(foo);
            test::return_shared(reg);
            test::return_to_sender(s, vsdb);
        };

        next_tx(s,a) ;{
            let vsdb = test::take_from_sender<VSDB>(s);
            let foo = test::take_shared<Foo>(s);

            white::update_pool_votes(&foo, &mut vsdb);

            test::return_to_sender(s, vsdb);
            test::return_shared(foo);
        }
    }
}