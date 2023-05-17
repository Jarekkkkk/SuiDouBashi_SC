#[test_only]
module suiDouBashi_vsdb::vsdb_test{
    use sui::coin::{ mint_for_testing as mint};
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::clock::{Self, timestamp_ms as get_time, increment_for_testing as add_time, Clock};
    use suiDouBashi_vsdb::vsdb;
    use suiDouBashi_vsdb::sdb::SDB;
    use suiDouBashi_vsdb::vsdb::{ VSDBRegistry,VSDB};


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
    #[expected_failure(abort_code = suiDouBashi_vsdb::vsdb::E_INVALID_UNLOCK_TIME)]
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
            vsdb::lock(&mut reg, mint<SDB>(sui_100M(), ctx(s)), week(), &clock, ctx(s));
            test::return_shared(reg);
        };
        next_tx(s, a);{ // extend 2 weeks duration
            let vsdb = test::take_from_sender<VSDB>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::increase_unlock_time(&mut reg, &mut vsdb, four_years() + week(), &clock);
            test::return_shared(reg);
            test::return_to_sender(s, vsdb);
        };

        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = suiDouBashi_vsdb::vsdb::E_LOCK)]
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
            vsdb::lock(&mut reg, mint<SDB>(sui_100M(), ctx(s)), week(), &clock, ctx(s));
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
            vsdb::lock(&mut reg, mint<SDB>(sui_100M(), ctx(s)), week(), clock, ctx(s));
            test::return_shared(reg);
        };
        next_tx(s, a);{
            let vsdb = test::take_from_sender<VSDB>(s);
            let slope = vsdb::calculate_slope(sui_100M());
            let end = vsdb::round_down_week(get_time(clock) + week());
            let bias = vsdb::calculate_bias(sui_100M(), end, get_time(clock));
            assert!( vsdb::get_latest_slope(&vsdb) == slope, 0);
            assert!( vsdb::get_user_epoch(&vsdb) == 1, 0);
            assert!( vsdb::get_latest_bias(&vsdb) == bias , 0);
            assert!( vsdb::locked_end(&vsdb) == end, 0);
            test::return_to_sender(s, vsdb);
        };
        next_tx(s, a);{ // extend 2 weeks duration
            let vsdb = test::take_from_sender<VSDB>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::increase_unlock_time(&mut reg, &mut vsdb, 2 * week(), clock);
            test::return_shared(reg);
            test::return_to_sender(s, vsdb);
        };
        next_tx(s, a);{
            let vsdb = test::take_from_sender<VSDB>(s);
            let slope = vsdb::calculate_slope(sui_100M()); // slope is unchanged
            let end = vsdb::round_down_week(get_time(clock) + 2 * week());
            let bias = vsdb::calculate_bias(sui_100M(), end, get_time(clock));
            assert!( vsdb::locked_end(&vsdb) == end, 0);
            assert!( vsdb::get_user_epoch(&vsdb) == 2, 0);
            assert!( vsdb::get_latest_slope(&vsdb) == slope, 0);
            assert!( vsdb::get_latest_bias(&vsdb) == bias , 0);
            test::return_to_sender(s, vsdb);
        };
         next_tx(s, a);{ // extend amount
            let vsdb = test::take_from_sender<VSDB>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::increase_unlock_amount(&mut reg, &mut vsdb, mint<SDB>(sui_1B(), ctx(s)), clock);
            test::return_shared(reg);
            test::return_to_sender(s, vsdb);
        };
        next_tx(s, a);{
            let vsdb = test::take_from_sender<VSDB>(s);
            let value = sui_1B() + sui_100M();
            let end = vsdb::round_down_week(get_time(clock) + 2 * week());
            let slope = vsdb::calculate_slope(value);
            let bias = vsdb::calculate_bias(value, end, get_time(clock));
            assert!( vsdb::locked_end(&vsdb) == end, 0);
            assert!( vsdb::get_user_epoch(&vsdb) == 3, 0);
            assert!( vsdb::get_latest_slope(&vsdb) == slope, 0);
            assert!( vsdb::get_latest_bias(&vsdb) == bias , 0);
            test::return_to_sender(s, vsdb);
        };
        add_time(clock, 3 * week());
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

    use suiDouBashi_vsdb::test_whitelist::{Self as white, MOCK, Foo};
    use suiDouBashi_vsdb::vsdb::{VSDBCap};
    fun test_whitelisted_module(clock: &mut Clock, s: &mut Scenario){
        let ( a, _, _ ) = people();

        next_tx(s, a);{
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::lock(&mut reg, mint<SDB>(sui_100M(), ctx(s)), week(), clock, ctx(s));
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
    use sui::math;

    public fun people(): (address, address, address) { (@0x000A, @0x000B, @0x000C ) }
    public fun usdc_1(): u64 { math::pow(10, 6) }
    public fun usdc_100K(): u64 { math::pow(10, 11) }
    public fun usdc_1M(): u64 { math::pow(10, 12) }
    public fun usdc_100M(): u64 { math::pow(10, 14)}
    public fun usdc_1B(): u64 { math::pow(10, 15) }
    public fun usdc_10B(): u64 { math::pow(10, 16) }
    // 9 decimals, max value: 18.44B
    public fun sui_1(): u64 { math::pow(10, 9) }
    public fun sui_100K(): u64 { math::pow(10, 14) }
    public fun sui_1M(): u64 { math::pow(10, 15) }
    public fun sui_100M(): u64 { math::pow(10, 17) }
    public fun sui_1B(): u64 { math::pow(10, 18) }
    public fun sui_10B(): u64 { math::pow(10, 19) }
    // stake
    public fun stake_1(): u64 { math::pow(10, 6)}
    // time utility
    public fun start_time(): u64 { 1672531200 }
    public fun four_years(): u64 { 4 * 365 * 86400 }
    public fun week(): u64 { 7 * 86400 }
    public fun day(): u64 { 86400 }
}