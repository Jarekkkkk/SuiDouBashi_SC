#[test_only]
module test::vasdb_test{
    use sui::coin::{ Self, Coin, mint_for_testing as mint};
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::clock::{Self, Clock, timestamp_ms as ts};
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
    fun setup(scenario: &mut Scenario){
        clock::create_for_testing(ctx(scenario));
        tran
    }
    fun test_lock_( sdb: Coin<SDB>, duration: u64, s: &mut Scenario){
        let jarek = person();
        let locked_value = coin::value(&sdb);
        let _locked_end = 0;
        let _g_t = 0;  // published at 2023/01/01 00:00
        next_tx(s, jarek);{
            setup(s);
        };
        next_tx(s, jarek);{ // test init
            _g_t = add_time(s, 1672531200);
            vsdb::init_for_testing(ctx(s));
        };
        next_tx(s, jarek);
        { // test create
            let clock = test::take_shared<Clock>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::lock(&mut reg, sdb, duration, &clock, ctx(s));
            test::return_shared(reg);
            test::return_shared(clock);
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
            let clock = test::take_shared<Clock>(s);
            let vsdb = test::take_from_sender<VSDB>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            let extended = 2 * vsdb::week();
            _locked_end  = _locked_end + extended;
            vsdb::increase_unlock_time(&mut reg, &mut vsdb, extended, &clock, ctx(s));
            test::return_shared(reg);
            test::return_shared(clock);
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
            let clock = test::take_shared<Clock>(s);
            let vsdb = test::take_from_sender<VSDB>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            let extended = mint<SDB>(2_000 * math::pow(10, sdb::decimals()), ctx(s));
            let value = coin::value(&extended);
            locked_value = locked_value + value;
            vsdb::increase_unlock_amount(&mut reg, &mut vsdb, extended, &clock, ctx(s));
            test::return_shared(reg);
            test::return_shared(clock);
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
            add_time(s, 8 * vsdb::week());
        };
        next_tx(s, jarek);{
            let clock = test::take_shared<Clock>(s);
            let vsdb = test::take_from_sender<VSDB>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::unlock(&mut reg, vsdb, &clock, ctx(s));
            test::return_shared(reg);
            test::return_shared(clock);
        };
    }
    fun get_time(s: &mut Scenario): u64{
        let clock = test::take_shared<Clock>(s);
        let ts = ts(&clock);
        test::return_shared(clock);
        ts
    }
    fun add_time(s: &mut Scenario, increment: u64): u64{
        let clock = test::take_shared<Clock>(s);
        clock::increment_for_testing(&mut clock, increment);
        let ts = ts(&clock);
        test::return_shared(clock);
        ts
    }
    fun person(): address{ ( @0xABCD ) }
}