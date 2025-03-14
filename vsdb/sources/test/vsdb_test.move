#[test_only]
module suiDouBashi_vsdb::vsdb_test{
    use sui::coin::{mint_for_testing as mint};
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::clock::{Self, timestamp_ms as get_time, increment_for_testing as add_time, Clock};
    use suiDouBashi_vsdb::vsdb;
    use suiDouBashi_vsdb::sdb::SDB;
    use suiDouBashi_vsdb::vsdb::{ VSDBRegistry, Vsdb, VSDBCap};


    #[test]
    fun test_create_lock(){
        let (a, _, _) = people();
        let scenario = test::begin(a);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        add_time(&mut clock, 1672531200  * 1000);

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
        add_time(&mut clock, 1672531200  * 1000);

        // main
        vsdb::init_for_testing(ctx(s));
        next_tx(s,a);{ // add image_url
            let cap = test::take_from_sender<VSDBCap>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            let art = vector[b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b""];
            vsdb::add_art(&cap, &mut reg, 0, art);
            test::return_to_sender(s, cap);
            test::return_shared(reg);
        };
        next_tx(s, a);{
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::lock(&mut reg, mint<SDB>(sui_100M(), ctx(s)), week(), &clock, ctx(s));
            test::return_shared(reg);
        };
        next_tx(s, a);{ // extend 2 weeks duration
            let vsdb = test::take_from_sender< Vsdb>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::increase_unlock_time(&mut reg, &mut vsdb, vsdb::max_time() + week(), &clock);
            test::return_shared(reg);
            test::return_to_sender(s, vsdb);
        };

        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[allow(unused_function)]
    fun test_art(){
        let (a, _, _) = people();
        let scenario = test::begin(a);
        let clock = clock::create_for_testing(ctx(&mut scenario));


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
        add_time(&mut clock, 1672531200 * 1000);

        // main
        next_tx(s,a);{
            vsdb::init_for_testing(ctx(s));
        };
        next_tx(s,a);{ // add image_url
            let cap = test::take_from_sender<VSDBCap>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            let art = vector[b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b""];
            vsdb::add_art(&cap, &mut reg, 0, art);
            test::return_to_sender(s, cap);
            test::return_shared(reg);
        };
        next_tx(s, a);{
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::lock(&mut reg, mint<SDB>(sui_100M(), ctx(s)), week(), &clock, ctx(s));
            test::return_shared(reg);
        };
        next_tx(s, a);{ // early unlock
            let vsdb = test::take_from_sender< Vsdb>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::unlock(&mut reg, vsdb, &clock, ctx(s));
            test::return_shared(reg);
        };

        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    public fun test_create_lock_(clock: &mut Clock, s: &mut Scenario){
        let (a, _, _) = people();

        next_tx(s,a);{
            vsdb::init_for_testing(ctx(s));
        };

        next_tx(s,a);{ // add image_url
            let cap = test::take_from_sender<VSDBCap>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            let art = vector[b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b"",b""];
            vsdb::add_art(&cap, &mut reg, 0, art);
            test::return_to_sender(s, cap);
            test::return_shared(reg);
        };

         next_tx(s, a);
        {
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::lock(&mut reg, mint<SDB>(sui_100M(), ctx(s)), week(), clock, ctx(s));
            test::return_shared(reg);
        };
        next_tx(s, a);{
            let vsdb = test::take_from_sender< Vsdb>(s);
            let slope = vsdb::calculate_slope(sui_100M());
            let end = vsdb::round_down_week(get_time(clock) / 1000 + week());
            let bias = vsdb::calculate_bias(sui_100M(), end, get_time(clock) / 1000);
            assert!( vsdb::get_latest_slope(&vsdb) == slope, 0);
            assert!( vsdb::player_epoch(&vsdb) == 0, 0);
            assert!( vsdb::get_latest_bias(&vsdb) == bias , 0);
            assert!( vsdb::locked_end(&vsdb) == end, 0);
            test::return_to_sender(s, vsdb);
        };
        next_tx(s, a);{ // extend 2 weeks duration
            let vsdb = test::take_from_sender< Vsdb>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::increase_unlock_time(&mut reg, &mut vsdb, 2 * week(), clock);
            test::return_shared(reg);
            test::return_to_sender(s, vsdb);
        };
        next_tx(s, a);{
            let vsdb = test::take_from_sender< Vsdb>(s);
            let slope = vsdb::calculate_slope(sui_100M()); // slope is unchanged
            let end = vsdb::round_down_week(get_time(clock)/1000 + 2 * week());
            let bias = vsdb::calculate_bias(sui_100M(), end, get_time(clock) / 1000);
            assert!( vsdb::locked_end(&vsdb) == end, 0);
            assert!( vsdb::player_epoch(&vsdb) == 1, 0);
            assert!( vsdb::get_latest_slope(&vsdb) == slope, 0);
            assert!( vsdb::get_latest_bias(&vsdb) == bias , 0);
            test::return_to_sender(s, vsdb);
        };
         next_tx(s, a);{ // extend amount
            let vsdb = test::take_from_sender< Vsdb>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::increase_unlock_amount(&mut reg, &mut vsdb, mint<SDB>(sui_1B(), ctx(s)), clock);
            test::return_shared(reg);
            test::return_to_sender(s, vsdb);
        };
        next_tx(s, a);{
            let vsdb = test::take_from_sender< Vsdb>(s);
            let value = sui_1B() + sui_100M();
            let end = vsdb::round_down_week(get_time(clock) / 1000 + 2 * week());
            let slope = vsdb::calculate_slope(value);
            let bias = vsdb::calculate_bias(value, end, get_time(clock) / 1000);
            assert!( vsdb::locked_end(&vsdb) == end, 0);
            assert!( vsdb::player_epoch(&vsdb) == 2, 0);
            assert!( vsdb::get_latest_slope(&vsdb) == slope, 0);
            assert!( vsdb::get_latest_bias(&vsdb) == bias , 0);
            test::return_to_sender(s, vsdb);
        };
        add_time(clock, 3 * week() * 1000);
        next_tx(s, a);{ // unlock
            let vsdb = test::take_from_sender< Vsdb>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::unlock(&mut reg, vsdb, clock, ctx(s));
            let len_prev = sui::table_vec::length(vsdb::point_history(&reg));
            vsdb::global_checkpoint(&mut reg, clock);
            vsdb::global_checkpoint(&mut reg, clock);
            vsdb::global_checkpoint(&mut reg, clock);
            vsdb::global_checkpoint(&mut reg, clock);
            vsdb::global_checkpoint(&mut reg, clock);
            let len_post = sui::table_vec::length(vsdb::point_history(&reg));
            assert!(len_prev == len_post, 404);
            test::return_shared(reg);
        };
        next_tx(s, a);{ // vsdb been burnt
            assert!(!test::has_most_recent_for_sender< Vsdb>(s), 0);
        };
        next_tx(s,a);{
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::lock(&mut reg, mint<SDB>(sui_100M(), ctx(s)), vsdb::max_time(), clock, ctx(s));
            test::return_shared(reg);
        };
    }

    use suiDouBashi_vsdb::test_whitelist::{Self as white, MOCK, Foo};
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

            vsdb::register_module<MOCK>(&reg_cap, &mut reg, false);
            white::init_for_testing(ctx(s));

            test::return_shared(reg);
            test::return_to_sender(s, reg_cap);
        };

        next_tx(s,a);{
            let foo = test::take_shared<Foo>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            let vsdb = test::take_from_sender< Vsdb>(s);

            white::add_pool_votes(&foo, &reg, &mut vsdb);
            let _registered = vsdb::module_exists<MOCK>(&vsdb);

            test::return_shared(foo);
            test::return_shared(reg);
            test::return_to_sender(s, vsdb);
        };

        next_tx(s,a) ;{
            let vsdb = test::take_from_sender< Vsdb>(s);
            let foo = test::take_shared<Foo>(s);

            white::update_pool_votes(&foo, &mut vsdb);

            test::return_to_sender(s, vsdb);
            test::return_shared(foo);
        };

        next_tx(s,a);{
            let vsdb = test::take_from_sender< Vsdb>(s);
            white::add_experience(&mut vsdb);
            test::return_to_sender(s, vsdb);
        };
        next_tx(s,a);{
            let vsdb = test::take_from_sender< Vsdb>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            assert!(vsdb::experience(&vsdb) ==25, 404);
            let level = vsdb::level(&vsdb);
            assert!(vsdb::required_xp(level + 1, level) == 25, 404);
            vsdb::upgrade(&reg, &mut vsdb);
            test::return_to_sender(s, vsdb);
            test::return_shared(reg);
        };
        next_tx(s,a);{
            let vsdb = test::take_from_sender< Vsdb>(s);
            let level = vsdb::level(&vsdb);
            assert!(vsdb::required_xp(level + 1, level) == 75, 404);
            assert!(vsdb::experience(&vsdb) == 0, 404);
            assert!(vsdb::level(&vsdb)== 1, 404);
            test::return_to_sender(s, vsdb);
        };

        add_time(clock, week() * 1000);

        next_tx(s,a);{ // revive the expired NFT
            let vsdb = test::take_from_sender< Vsdb>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::revive(&mut reg, &mut vsdb, vsdb::max_time(), clock);
            test::return_shared(reg);
            test::return_to_sender(s, vsdb);
        };

        next_tx(s,a);{
            let vsdb = test::take_from_sender<Vsdb>(s);
            let _end = vsdb::round_down_week(get_time(clock)/1000 + vsdb::max_time());

            assert!(vsdb::locked_end(&vsdb) == _end, 404);
            assert!(vsdb::locked_balance(&vsdb) == sui_100M(), 404);
            test::return_to_sender(s, vsdb);

        };
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
    public fun start_time(): u64 { 1672531200  * 1000}
    public fun week(): u64 { 7 * 86400 }
    public fun day(): u64 { 86400 }
}