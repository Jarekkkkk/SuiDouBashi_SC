#[test_only]
module farm::farm_test{
    use sui::clock::{Self, Clock, timestamp_ms as get_time,set_for_testing as set_time, increment_for_testing as add_time};
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::coin::mint_for_testing as mint;
    use sui::math;

    use suiDouBashi::amm_test;
    use suiDouBashi::usdt::{USDT};
    use suiDouBashi::usdc::{USDC};
    use suiDouBashiVest::sdb::{SDB};
    use suiDouBashiVest::vsdb::{Self, VSDB, VSDBRegistry};
    use suiDouBashi::pool::{Pool,LP};


    use test::setup;
    use farm::farm::{Self, Reg, Farm};

    #[test]
    fun main(){
        let (a,_,_) = people();
        let s = test::begin(a);
        let clock = clock::create_for_testing(ctx(&mut s));

        setup::deploy_coins(&mut s);
        // pool
        pool_setup(&mut clock, &mut s);
        // vsdb
        vsdb::init_for_testing(ctx(&mut s));

        // farm
        create_reg(&mut s);
        add_farm(&mut clock, &mut s);

        clock::destroy_for_testing(clock);
        test::end(s);
    }

    fun pool_setup(clock: &mut Clock, s: &mut Scenario){
        // deploy sdb
        let ( a, _, _ ) = people();
        next_tx(s,a);{
            amm_test::add_liquidity_<USDC, USDT>(setup::usdc_100M(), setup::usdc_100M(), clock, s);
            amm_test::add_liquidity_<SDB, USDT>(setup::sui_100M(), setup::usdc_100M(), clock, s);
            amm_test::add_liquidity_<SDB, USDC>(setup::sui_100M(), setup::usdc_100M(), clock, s);
        };
        // time
        set_time(clock, 1684040292);
        add_time(clock, 0);
    }

    fun create_reg(s: &mut Scenario){
        let ( a, _, _ ) = people();

        next_tx(s,a);{
            farm::init_for_testing(ctx(s));
        };
    }

    fun add_farm(clock: &mut Clock, s: &mut Scenario){
        let ( a, _, _ ) = people();

        std::debug::print(&get_time(clock));

        next_tx(s,a);{ // Action: initialize reg
            let reg = test::take_shared<Reg>(s);
            let start_time = get_time(clock) + setup::week();
            let duration = 4 * 7 * 86400;
            let sdb = mint<SDB>(625_000 * math::pow(10, 9), ctx(s)); // 625K SDB with 9 decimals

            farm::initialize(&mut reg, start_time, duration, sdb, clock, ctx(s));

            test::return_shared(reg);
        };

        next_tx(s,a);{ // Assertion: validate reg state
            let reg = test::take_shared<Reg>(s);

            assert!(farm::get_sdb_balance(&reg) == 625_000 * math::pow(10, 9), 404);
            assert!(farm::get_start_time(&reg) == 1684645092, 404);
            assert!(farm::get_end_time(&reg) == 1687064292, 404);
            assert!(farm::sdb_per_second(&reg) == 258349867, 404);
            test::return_shared(reg);
        };

        next_tx(s,a);{
            let reg = test::take_shared<Reg>(s);
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let pool_c = test::take_shared<Pool<SDB, USDT>>(s);
            let ctx = ctx(s);
            // 20/ 30/ 50 bps
            farm::add_farm(&mut reg, &pool_a, 20, clock, ctx);
            farm::add_farm(&mut reg, &pool_b, 30, clock, ctx);
            farm::add_farm(&mut reg, &pool_c, 50, clock, ctx);

            test::return_shared(pool_a);
            test::return_shared(pool_b);
            test::return_shared(pool_c);
            test::return_shared(reg);
        };

        next_tx(s,a);{
            let reg = test::take_shared<Reg>(s);
           { // pool_a
                let lp = test::take_from_sender<LP<USDC, USDT>>(s);
                let pool = test::take_shared<Pool<USDC, USDT>>(s);
                let farm = test::take_shared<Farm<USDC, USDT>>(s);
                let ctx = ctx(s);
                farm::stake(&reg, &mut farm, &pool, &mut lp, 50 * setup::usdc_1M(), clock, ctx);

                test::return_to_sender(s, lp);
                test::return_shared(pool);
                test::return_shared(farm);
           };
           { // pool_b
                let lp = test::take_from_sender<LP<SDB, USDC>>(s);
                let pool = test::take_shared<Pool<SDB, USDC>>(s);
                let farm = test::take_shared<Farm<SDB, USDC>>(s);
                let ctx = ctx(s);
                farm::stake(&reg, &mut farm, &pool, &mut lp, 50 * setup::usdc_1M(), clock, ctx);

                test::return_to_sender(s, lp);
                test::return_shared(pool);
                test::return_shared(farm);
           };
           { // pool_c
                let lp = test::take_from_sender<LP<SDB, USDT>>(s);
                let pool = test::take_shared<Pool<SDB, USDT>>(s);
                let farm = test::take_shared<Farm<SDB, USDT>>(s);
                let ctx = ctx(s);
                farm::stake(&reg, &mut farm, &pool, &mut lp, 50 * setup::usdc_1M(), clock, ctx);

                test::return_to_sender(s, lp);
                test::return_shared(pool);
                test::return_shared(farm);
           };

           test::return_shared(reg);
        };

        next_tx(s,a);{
            let reg = test::take_shared<Reg>(s);

            {
                let farm = test::take_shared<Farm<USDC, USDT>>(s);
                assert!(farm::get_farm_lp(&farm) == 50 * setup::usdc_1M(), 404);
                assert!(farm::pending_rewards(&farm, &reg, a, clock) == 0, 404);
                test::return_shared(farm);
            };
            {
                let farm = test::take_shared<Farm<SDB, USDT>>(s);
                assert!(farm::get_farm_lp(&farm) == 50 * setup::usdc_1M(), 404);
                assert!(farm::pending_rewards(&farm, &reg, a, clock) == 0, 404);
                test::return_shared(farm);
            };
            {
                let farm = test::take_shared<Farm<SDB, USDC>>(s);
                assert!(farm::get_farm_lp(&farm) == 50 * setup::usdc_1M(), 404);
                assert!(farm::pending_rewards(&farm, &reg, a, clock) == 0, 404);
                test::return_shared(farm);
            };

            test::return_shared(reg);
        };

        add_time(clock, 4 * setup::day());

        next_tx(s,a);{ // still zero rewards when stake before start time
            let reg = test::take_shared<Reg>(s);

            {
                let farm = test::take_shared<Farm<USDC, USDT>>(s);
                assert!(farm::pending_rewards(&farm, &reg, a, clock) == 0, 404);
                test::return_shared(farm);
            };
            {
                let farm = test::take_shared<Farm<SDB, USDT>>(s);
                assert!(farm::pending_rewards(&farm, &reg, a, clock) == 0, 404);
                test::return_shared(farm);
            };
            {
                let farm = test::take_shared<Farm<SDB, USDC>>(s);
                assert!(farm::pending_rewards(&farm, &reg, a, clock) == 0, 404);
                test::return_shared(farm);
            };

            test::return_shared(reg);
        };

        add_time(clock, setup::week());

        next_tx(s,a);{ // accumulating rewards when staking, 4 days after start_time
             let reg = test::take_shared<Reg>(s);
             let duration = 4 * setup::day();
            { // Unstake pool A
                let rewards = duration * 258349867 * 2 / 10;
                let farm = test::take_shared<Farm<USDC, USDT>>(s);
                let pool = test::take_shared<Pool<USDC, USDT>>(s);
                let lp = test::take_from_sender<LP<USDC, USDT>>(s);
                assert!(farm::pending_rewards(&farm, &reg, a, clock) == rewards, 404);
                farm::unstake(&reg, &mut farm, &pool, &mut lp, 50 * setup::usdc_1M(), clock, ctx(s));

                test::return_shared(farm);
                test::return_shared(pool);
                test::return_to_sender(s, lp);
            };
            {
                let rewards = duration * 258349867 * 3 /10;
                let farm = test::take_shared<Farm<SDB, USDC>>(s);
                assert!(farm::pending_rewards(&farm, &reg, a, clock) == rewards, 404);
                test::return_shared(farm);
            };
            {
                let rewards = duration * 258349867 * 5 /10;
                let farm = test::take_shared<Farm<SDB, USDT>>(s);
                assert!(farm::pending_rewards(&farm, &reg, a, clock) == rewards, 404);
                test::return_shared(farm);
            };
            test::return_shared(reg);
        };

        add_time(clock, 3 * setup::day());

        next_tx(s,a);{
            let reg = test::take_shared<Reg>(s);
            {   // stake for specific duration
                let rewards = 4 * setup::day() * 258349867 * 2 / 10;
                let farm = test::take_shared<Farm<USDC, USDT>>(s);
                assert!(farm::pending_rewards(&farm, &reg, a, clock) == rewards, 404);
                let pool = test::take_shared<Pool<USDC, USDT>>(s);
                let lp = test::take_from_sender<LP<USDC, USDT>>(s);
                farm::stake(&reg, &mut farm, &pool, &mut lp, 50 * setup::usdc_1M(), clock, ctx(s));
                test::return_shared(farm);
                test::return_shared(pool);
                test::return_to_sender(s, lp);
            };
            {   // still staking
                let rewards = setup::week() * 258349867 * 3 /10;
                let farm = test::take_shared<Farm<SDB, USDC>>(s);
                assert!(farm::pending_rewards(&farm, &reg, a, clock) == rewards, 404);
                test::return_shared(farm);
            };
            {   // still staking
                let rewards = setup::week() * 258349867 * 5 /10;
                let farm = test::take_shared<Farm<SDB, USDT>>(s);
                assert!(farm::pending_rewards(&farm, &reg, a, clock) == rewards, 404);
                test::return_shared(farm);
            };
            test::return_shared(reg);
        };

        add_time(clock, setup::week());

        next_tx(s,a);
        let harvest = {
            let reg = test::take_shared<Reg>(s);
            let acc = 0;
            {   // stake for specific duration
                let farm = test::take_shared<Farm<USDC, USDT>>(s);
                acc = acc + farm::pending_rewards(&farm, &reg, a, clock);
                farm::harvest(&mut reg, &mut farm, clock, ctx(s));
                test::return_shared(farm);
            };
            {
                let farm = test::take_shared<Farm<SDB, USDC>>(s);
                acc = acc + farm::pending_rewards(&farm, &reg, a, clock);
                farm::harvest(&mut reg, &mut farm, clock, ctx(s));
                test::return_shared(farm);
            };
            {
                let farm = test::take_shared<Farm<SDB, USDT>>(s);
                acc = acc + farm::pending_rewards(&farm, &reg, a, clock);
                farm::harvest(&mut reg, &mut farm, clock, ctx(s));
                test::return_shared(farm);
            };

            test::return_shared(reg);
            acc
        };

        next_tx(s,a);{
            let reg = test::take_shared<Reg>(s);
            assert!(farm::total_pending(&reg, a) == harvest, 404);
            {
                let farm = test::take_shared<Farm<USDC, USDT>>(s);
                assert!(farm::pending_rewards(&farm, &reg, a, clock) == 0, 404);
                test::return_shared(farm);
            };
            {
                let farm = test::take_shared<Farm<SDB, USDC>>(s);
                assert!(farm::pending_rewards(&farm, &reg, a, clock) == 0, 404);
                test::return_shared(farm);
            };
            {
                let farm = test::take_shared<Farm<SDB, USDT>>(s);
                assert!(farm::pending_rewards(&farm, &reg, a, clock) == 0, 404);
                test::return_shared(farm);
            };

            test::return_shared(reg);
        };

        add_time(clock, 2 * setup::week());

        next_tx(s,a);{
            let reg = test::take_shared<Reg>(s);
            assert!(farm::total_pending(&reg, a) == harvest, 404);
            let duration = 2 * setup::week();
            {
                let farm = test::take_shared<Farm<USDC, USDT>>(s);
                let rewards = duration * 258349867 * 2 / 10;
                assert!(farm::pending_rewards(&farm, &reg, a, clock) == rewards, 404);
                farm::harvest(&mut reg, &mut farm, clock, ctx(s));
                assert!(farm::pending_rewards(&farm, &reg, a, clock) == 0, 404);
                test::return_shared(farm);
            };
            {
                let farm = test::take_shared<Farm<SDB, USDC>>(s);
                let rewards = duration * 258349867 * 3 / 10;
                assert!(farm::pending_rewards(&farm, &reg, a, clock) == rewards, 404);
                farm::harvest(&mut reg, &mut farm, clock, ctx(s));
                assert!(farm::pending_rewards(&farm, &reg, a, clock) == 0, 404);
                test::return_shared(farm);
            };
            {
                let farm = test::take_shared<Farm<SDB, USDT>>(s);
                let rewards = duration * 258349867 * 5 / 10;
                assert!(farm::pending_rewards(&farm, &reg, a, clock) == rewards, 404);
                farm::harvest(&mut reg, &mut farm, clock, ctx(s));
                assert!(farm::pending_rewards(&farm, &reg, a, clock) == 0, 404);
                test::return_shared(farm);
            };
            test::return_shared(reg);
        };

        next_tx(s,a);{
            let reg = test::take_shared<Reg>(s);
            let vsdb_reg = test::take_shared<VSDBRegistry>(s);
            farm::claim_vsdb(&mut reg, &mut vsdb_reg, clock, ctx(s));
            // removed from table
            test::return_shared(vsdb_reg);
            test::return_shared(reg);
        };

        next_tx(s,a);{
            let vsdb = test::take_from_sender<VSDB>(s);

            let reward_a = ( 28 - 3 ) * 86400 * 258349867 * 2 / 10;
            let reward_b = ( 28 - 0 ) * 86400 * 258349867 * 3 / 10;
            let reward_c = ( 28 - 0 ) * 86400 * 258349867 * 5 / 10;
            assert!(vsdb::locked_balance(&vsdb) == reward_a + reward_b + reward_c, 404);
            let time = vsdb::round_down_week(get_time(clock) + 36 * 7 * 86400);
            assert!(vsdb::locked_end(&vsdb) == time, 404);

            test::return_to_sender(s, vsdb);
        }

    }

    public fun people(): (address, address, address) { (@0x000A, @0x000B, @0x000C) }
}