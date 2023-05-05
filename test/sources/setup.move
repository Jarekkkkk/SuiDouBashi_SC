#[test_only]
module test::setup{
    use suiDouBashi::usdc::{Self, USDC};
    use suiDouBashi::usdt::{Self, USDT};
    use suiDouBashi::pool::{Self, Pool, LP};
    use suiDouBashiVest::sdb::{Self, SDB};

    use sui::math;
    use sui::clock::{Self, Clock};
    use sui::transfer;
    use sui::coin::{Self, CoinMetadata, mint_for_testing as mint, TreasuryCap};
    use std::vector as vec;

    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    // 6 decimals
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

    #[test] fun test_setup(){
        let (a,_,_) = people();
        let scenario = test::begin(a);
        let clock = clock::create_for_testing(ctx(&mut scenario));

        deploy_coins(&mut scenario);
        mint_stable(&mut scenario);
        deploy_pools(&mut scenario, &mut clock);

        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    public fun deploy_coins(s: &mut Scenario){
        usdc::deploy_coin(ctx(s));
        usdt::deploy_coin(ctx(s));
        sdb::deploy_coin(ctx(s));
    }

    public fun mint_stable(s: &mut Scenario){
        let (a, b, c) = people();
        let owners = vec::singleton(a);
        vec::push_back(&mut owners, b);
        vec::push_back(&mut owners, c);

        let ctx = ctx(s);
        let (i, len) = (0, vec::length(&owners));
        while( i < len ){
            let owner = vec::pop_back(&mut owners);
            // 1B for each owner
            let v = math::pow(10, 9);
            let usdc = coin::mint_for_testing<USDC>( v * usdc_1(), ctx);
            let usdt = coin::mint_for_testing<USDT>( v * usdc_1(), ctx);

            transfer::public_transfer(usdc, owner);
            transfer::public_transfer(usdt, owner);

            i = i + 1;
        };

        vec::destroy_empty(owners);
    }

    use suiDouBashi::pool_reg::{Self, PoolReg};
    public fun deploy_pools(s: &mut Scenario, clock: &mut Clock){
        let (a,_,_) = people();

        pool_reg::init_for_testing(ctx(s));

        next_tx(s, a); { // Action: create pool
            let meta_usdc = test::take_immutable<CoinMetadata<USDC>>(s);
            let meta_usdt = test::take_immutable<CoinMetadata<USDT>>(s);
            let meta_sdb = test::take_immutable<CoinMetadata<SDB>>(s);

            let pool_gov = test::take_shared<PoolReg>(s);
            pool_reg::create_pool(
                &mut pool_gov,
                true,
                &meta_usdc,
                &meta_usdt,
                3,
                ctx(s)
            );
            pool_reg::create_pool(
                &mut pool_gov,
                false,
                &meta_sdb,
                &meta_usdc,
                5,
                ctx(s)
            );

            test::return_shared(pool_gov);
            test::return_immutable(meta_usdc);
            test::return_immutable(meta_sdb);
            test::return_immutable(meta_usdt);
        };
        next_tx(s,a);{ // Action: add liquidity
            let pool_gov = test::take_shared<PoolReg>(s);
            assert!(pool_reg::pools_length(&pool_gov) == 2, 0);

            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let ctx = ctx(s);
            let lp_a = pool::create_lp(&pool_a, ctx);
            let lp_b = pool::create_lp(&pool_b, ctx);

            pool::add_liquidity(&mut pool_a, mint<USDC>(usdc_1(), ctx), mint<USDT>(usdc_1(), ctx), &mut lp_a, 0, 0, clock, ctx);
            pool::add_liquidity(&mut pool_b, mint<SDB>(sui_1(), ctx), mint<USDC>(usdc_1(), ctx), &mut lp_b, 0, 0, clock, ctx);

            transfer::public_transfer(lp_a, a);
            transfer::public_transfer(lp_b, a);

            test::return_shared(pool_gov);
            test::return_shared(pool_a);
            test::return_shared(pool_b);
        };
        next_tx(s,a);{ // Assertion: swap amount, lp_balance
            let pool_gov = test::take_shared<PoolReg>(s);
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let lp_b = test::take_from_sender<LP<SDB, USDC>>(s);
            let _ctx = ctx(s);

            assert!(pool_reg::pools_length(&pool_gov) == 2, 0);
            let (_, _, res_lp_a) = pool::get_reserves(&pool_a);
            let (_, _, res_lp_b) = pool::get_reserves(&pool_b);

            // pool_a
            assert!(pool::get_stable(&pool_a) == true, 0);
            assert! (res_lp_a == 1000000, 0);
            assert!(pool::get_lp_balance(&lp_a) == res_lp_a - 1000, 0);
            assert!(pool::get_output<USDC, USDT, USDC>(&pool_a, usdc_1()) == 753_627, 0);
            assert!(pool::get_output<USDC, USDT, USDT>(&pool_a, usdc_1()) == 753_627, 0);

            // pool_b
            assert!(pool::get_stable(&pool_b) == false, 0);
            assert!(res_lp_b == 31622776, 0);
            assert!(pool::get_lp_balance(&lp_b) == res_lp_b - 1000, 0);
            assert!(pool::get_output<SDB, USDC, SDB>(&pool_b, sui_1()) == 499_874, 0);
            assert!(pool::get_output<SDB, USDC, USDC>(&pool_b, usdc_1()) == 499_874_968, 0);

            test::return_shared(pool_gov);
            test::return_shared(pool_a);
            test::return_shared(pool_b);
            test::return_to_sender(s, lp_a);
            test::return_to_sender(s, lp_b);
        };
    }

    use suiDouBashiVest::minter::{Self, Minter};
    use suiDouBashiVest::reward_distributor;
    use suiDouBashiVest::vsdb::VSDBRegistry;
    public fun deploy_minter(clock: &mut Clock, s: &mut Scenario){
        let ( a, _, c) = people();
        next_tx(s,a);{
            let vsdb_reg = test::take_shared<VSDBRegistry>(s);
            let sdb_cap = test::take_from_sender<TreasuryCap<SDB>>(s);
            let claimants = vec::empty<address>();
            let claim_amounts = vec::empty<u64>();
            // maxL 20M
            minter::initialize(sdb_cap, &mut vsdb_reg, 20 * sui_1M(), claimants, claim_amounts, clock, ctx(s));
            reward_distributor::init_for_testing(ctx(s));

            test::return_shared(vsdb_reg);
        };
        next_tx(s,a);{
            let minter = test::take_shared<Minter>(s);
            minter::set_team(&mut minter, c, ctx(s));
            test::return_shared(minter);
        };
    }

    use suiDouBashiVest::voter::{Self, Voter};
    public fun deploy_voter(s: &mut Scenario){
        let ( a, _, _ ) = people();

        voter::init_for_testing(ctx(s));

        next_tx(s,a);{
            let voter = test::take_shared<Voter>(s);

            assert!(voter::get_registry_length(&voter) == 0, 0);
            assert!(voter::get_governor(&voter) == a, 0);
            assert!(voter::get_emergency(&voter) == a, 0);
            assert!(voter::get_total_weight(&voter) == 0, 0);

            test::return_shared(voter);
        }
    }

    use suiDouBashiVest::gauge::{Self, Gauge};
    use suiDouBashiVest::internal_bribe::{Self as i_bribe, InternalBribe};
    use suiDouBashiVest::external_bribe::{Self as e_bribe, ExternalBribe};
    public fun deploy_gauge(s: &mut Scenario){
        let ( a, _, _ ) = people();

        next_tx(s,a);{ // Action: create gauges & I_brbie & E_bribe for given pool
            let voter = test::take_shared<Voter>(s);
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);

            voter::create_gauge(&mut voter, &pool_a, ctx(s));
            voter::create_gauge(&mut voter, &pool_b, ctx(s));

            test::return_shared(voter);
            test::return_shared(pool_a);
            test::return_shared(pool_b);
        };
        next_tx(s,a);{ // Assertion: create gauge, I_birbe & E_bribe successfully
            let voter = test::take_shared<Voter>(s);

            assert!(voter::get_registry_length(&voter) == 2, 0);

            {// pool_a
                let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
                let gauge = test::take_shared<Gauge<USDC,USDT>>(s);
                let i_bribe = test::take_shared<InternalBribe<USDC,USDT>>(s);
                let e_bribe = test::take_shared<ExternalBribe<USDC, USDT>>(s);
                assert!(gauge::is_alive(&gauge), 0);
                assert!(i_bribe::total_voting_weight(&i_bribe) == 0, 0);
                assert!(e_bribe::total_voting_weight(&e_bribe) == 0, 0);
                assert!(e_bribe::total_rewwards_length(&e_bribe) == 4, 0);
                assert!(voter::get_weights_by_pool(&voter, &pool_a) == 0, 0);
                assert!(voter::get_pool_exists(&voter, &pool_a), 0);
                test::return_shared(gauge);
                test::return_shared(i_bribe);
                test::return_shared(e_bribe);
                test::return_shared(pool_a);
            };

            {// pool_b
                let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
                let gauge = test::take_shared<Gauge<SDB, USDC>>(s);
                let i_bribe = test::take_shared<InternalBribe<SDB, USDC>>(s);
                let e_bribe = test::take_shared<ExternalBribe<SDB, USDC>>(s);
                assert!(gauge::is_alive(&gauge), 0);
                assert!(i_bribe::total_voting_weight(&i_bribe) == 0, 0);
                assert!(e_bribe::total_voting_weight(&e_bribe) == 0, 0);
                // amount of external bribe is at most 4, including pair of coins + SDB + SUI
                assert!(e_bribe::total_rewwards_length(&e_bribe) == 3, 0);
                assert!(voter::get_weights_by_pool(&voter, &pool_b) == 0, 0);
                assert!(voter::get_pool_exists(&voter, &pool_b), 0);
                test::return_shared(gauge);
                test::return_shared(i_bribe);
                test::return_shared(e_bribe);
                test::return_shared(pool_b);
            };
            test::return_shared(voter);
        }
    }

    public fun people(): (address, address, address) { (@0x000A, @0x000B, @0x000C ) }
}