#[test_only]
module suiDouBashiVest::vasdb_test{
    use sui::coin::{ Self, Coin, mint_for_testing as mint};
    use sui::test_scenario::{Self as test, Scenario, next_tx, next_epoch, ctx};
    use sui::clock::{Clock, timestamp_ms as ts};
    use sui::clock;
    use std::debug::print;
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
    }

    fun test_lock_( sdb: Coin<SDB>, duration: u64, s: &mut Scenario){
        let jarek = person();
        let value = coin::value(&sdb);

        next_tx(s, jarek);{
            setup(s);
        };

        next_epoch(s, jarek);{
            let clock = test::take_shared<Clock>(s);
            clock::increment_for_testing(&mut clock, vsdb::week());
            vsdb::init_for_testing(ctx(s));

            test::return_shared(clock);
        };

        next_tx(s, jarek);
        let ts = {
            let clock = test::take_shared<Clock>(s);
            let reg = test::take_shared<VSDBRegistry>(s);
            let ts = ts(&clock);

            // print(vsdb::point_history(&mut reg, 0));
            // print(vsdb::slope_changes(&mut reg, 0));

            vsdb::lock(&mut reg, sdb, duration, &clock, ctx(s));


            test::return_shared(reg);
            test::return_shared(clock);
            ts
        };

        next_tx(s, jarek);{
            let vsdb = test::take_from_sender<VSDB>(s);
            print(&vsdb::get_latest_bias(&vsdb));

            let end = ts + duration;
            let slope = vsdb::calculate_slope(value, vsdb::max_time());
            let bias = vsdb::calculate_bias(value, vsdb::max_time(), end, ts);

            assert!( vsdb::get_version(&vsdb) == 1, 0);
            assert!( vsdb::get_latest_slope(&vsdb) == slope, 0);
            assert!( vsdb::get_latest_bias(&vsdb) == bias , 0);
            assert!( vsdb::locked_end(&vsdb) == end, 0);

            test::return_to_sender(s, vsdb);
        };
    }

    fun person(): address{ (@0xABCD ) }
}