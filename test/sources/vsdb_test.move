#[test_only]
module test::vasdb_test{
    use sui::coin::{ Self, Coin, mint_for_testing as mint};
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::clock::{Self, timestamp_ms as get_time, increment_for_testing as add_time};
    use sui::math;
    use suiDouBashiVest::vsdb;
    use suiDouBashiVest::sdb::{ Self, SDB};
    use suiDouBashiVest::vsdb::{ VSDBRegistry,VSDB};

    #[test]
    fun test_lock(){
        let scenario = test::begin(@0x1);
        let value = 1_000 * math::pow(10, sdb::decimals());
        let coin = mint<SDB>(value, ctx(&mut scenario));
        test_lock_(coin, (2 * vsdb::week()), &mut scenario);
        test::end(scenario);
    }

    fun test_lock_( sdb: Coin<SDB>, duration: u64, s: &mut Scenario){
        let jarek = person();
        let locked_value = coin::value(&sdb);
        let _locked_end = 0;
        let _g_t = 0;  // published at 2023/01/01 00:00
        let clock = clock::create_for_testing(ctx(s));


        next_tx(s, jarek);{ // test init
            add_time(&mut clock, 1672531200);
            _g_t = get_time(&clock);
            vsdb::init_for_testing(ctx(s));
        };
        next_tx(s, jarek);
        { // test create
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::lock(&mut reg, sdb, duration, &clock, ctx(s));
            test::return_shared(reg);
        };
        next_tx(s, jarek);{
            let vsdb = test::take_from_sender<VSDB>(s);
            let end = vsdb::round_down_week(_g_t + duration);
            _locked_end = end;
            let slope = vsdb::calculate_slope(locked_value, vsdb::max_time());
            let bias = vsdb::calculate_bias(locked_value, vsdb::max_time(), end, _g_t);
            assert!( vsdb::get_latest_slope(&vsdb) == slope, 0);
            assert!( vsdb::get_version(&vsdb) == 1, 0);
            assert!( vsdb::get_latest_bias(&vsdb) == bias , 0);
            assert!( vsdb::locked_end(&vsdb) == end, 0);
            test::return_to_sender(s, vsdb);
        };
        next_tx(s, jarek);{ // test extend unlocked time
            let vsdb = test::take_from_sender<VSDB>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            let extended = 2 * vsdb::week();
            _locked_end  = _locked_end + extended;
            vsdb::increase_unlock_time(&mut reg, &mut vsdb, extended, &clock, ctx(s));
            test::return_shared(reg);
            test::return_to_sender(s, vsdb);
        };
     next_tx(s, jarek);{
            let vsdb = test::take_from_sender<VSDB>(s);
            let slope = vsdb::calculate_slope(locked_value, vsdb::max_time()); // slope is unchanged
            let bias = vsdb::calculate_bias(locked_value, vsdb::max_time(), _locked_end, _g_t);
            assert!( vsdb::locked_end(&vsdb) == _locked_end, 0);
            assert!( vsdb::get_version(&vsdb) == 2, 0);
            assert!( vsdb::get_latest_slope(&vsdb) == slope, 0);
            assert!( vsdb::get_latest_bias(&vsdb) == bias , 0);
            test::return_to_sender(s, vsdb);
        };
         next_tx(s, jarek);{ // test extend unlocked amount
            let vsdb = test::take_from_sender<VSDB>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            let extended = mint<SDB>(2_000 * math::pow(10, sdb::decimals()), ctx(s));
            let value = coin::value(&extended);
            locked_value = locked_value + value;
            vsdb::increase_unlock_amount(&mut reg, &mut vsdb, extended, &clock, ctx(s));
            test::return_shared(reg);
            test::return_to_sender(s, vsdb);
        };
        next_tx(s, jarek);{
            let vsdb = test::take_from_sender<VSDB>(s);
            let slope = vsdb::calculate_slope(locked_value, vsdb::max_time()); // slope is unchanged
            let bias = vsdb::calculate_bias(locked_value, vsdb::max_time(), _locked_end, _g_t);
                     assert!( vsdb::locked_end(&vsdb) == _locked_end, 0);
            assert!( vsdb::get_version(&vsdb) == 3, 0);
            assert!( vsdb::get_latest_slope(&vsdb) == slope, 0);
            assert!( vsdb::get_latest_bias(&vsdb) == bias , 0);
            test::return_to_sender(s, vsdb);
        };
        next_tx(s, jarek);{
            add_time(&mut clock, 8 * vsdb::week());
        };
        next_tx(s, jarek);{
            let vsdb = test::take_from_sender<VSDB>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::unlock(&mut reg, vsdb, &clock, ctx(s));
            test::return_shared(reg);
        };

        clock::destroy_for_testing(clock);
    }
    fun person(): address{ ( @0xABCD ) }
}