#[test_only]
module test::setup{
    use coin_list::mock_usdt::{Self as usdt, MOCK_USDT as USDT};
    use coin_list::mock_usdc::{Self as usdc, MOCK_USDC as USDC};
    use suiDouBashi_amm::pool::{Pool};
    use suiDouBashi_vsdb::sdb::{Self, SDB};

    use sui::math;
    use sui::clock::{Clock};
    use sui::transfer;
    use sui::coin::{Self, TreasuryCap};
    use std::vector as vec;
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};

    // 6 decimals
    public fun usdc_1(): u64 { math::pow(10, 6) }
    public fun usdc_100K(): u64 { math::pow(10, 11) }
    public fun usdc_1M(): u64 { math::pow(10, 12) }
    public fun usdc_100M(): u64 { math::pow(10, 14)}
    public fun usdc_1B(): u64 { math::pow(10, 15) }
    public fun usdc_10B(): u64 { math::pow(10, 16) }
    // 9 decimals, max coin supply: 18.44B
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
    public fun week(): u64 { 7 * 86400 }
    public fun day(): u64 { 86400 }

    public fun deploy_coins(s: &mut Scenario){
        usdc::deploy_coin(ctx(s));
        usdt::deploy_coin(ctx(s));
        sdb::deploy_coin(ctx(s));
    }

    /// Mint USDC & USDT
    public fun mint_stable(s: &mut Scenario){
        let (a, b, c) = people();
        let owners = vec::singleton(a);
        vec::push_back(&mut owners, b);
        vec::push_back(&mut owners, c);

        let ctx = ctx(s);
        let (i, len) = (0, vec::length(&owners));
        while( i < len ){
            let owner = vec::pop_back(&mut owners);
            let v = math::pow(10, 9);
            let usdc = coin::mint_for_testing<USDC>( v * usdc_1(), ctx);
            let usdt = coin::mint_for_testing<USDT>( v * usdc_1(), ctx);

            transfer::public_transfer(usdc, owner);
            transfer::public_transfer(usdt, owner);

            i = i + 1;
        };

        vec::destroy_empty(owners);
    }

    use suiDouBashi_vote::minter::{Self, Minter, mint_sdb};
    use suiDouBashi_vsdb::vsdb::VSDBRegistry;

    public fun deploy_minter(clock: &mut Clock, s: &mut Scenario){
        let ( a, _, c) = people();
        next_tx(s,a);{
            let vsdb_reg = test::take_shared<VSDBRegistry>(s);
            let sdb_cap = test::take_from_sender<TreasuryCap<SDB>>(s);
            let claimants = vec::empty<address>();
            let claim_amounts = vec::empty<u64>();
            // maxL 20M
            minter::initialize(sdb_cap, &mut vsdb_reg, 20 * sui_1M(), claimants, claim_amounts, clock, ctx(s));
            test::return_shared(vsdb_reg);
        };
        next_tx(s,a);{
            let minter = test::take_shared<Minter>(s);
            minter::set_team(&mut minter, c, ctx(s));
            test::return_shared(minter);
        };

        next_tx(s, a);{
            let minter = test::take_shared<Minter>(s);
            transfer::public_transfer(mint_sdb(&mut minter, 18 * sui_1B(), ctx(s)), a);
            test::return_shared(minter);
        }
    }

    use suiDouBashi_vote::voter::{Self, Voter, VSDB};
    use suiDouBashi_vsdb::vsdb::{Self,VSDBCap};
    public fun deploy_voter(s: &mut Scenario){
        let ( a, _, _ ) = people();

        voter::init_for_testing(ctx(s));

        next_tx(s,a);{
            let voter = test::take_shared<Voter>(s);

            assert!(voter::total_weight(&voter) == 0, 0);

            test::return_shared(voter);
        };
        next_tx(s,a);{ // Action: register module
            let reg_cap = test::take_from_sender<VSDBCap>(s);
            let reg = test::take_shared<VSDBRegistry>(s);

            vsdb::register_module<VSDB>(&reg_cap, &mut reg, true);

            test::return_shared(reg);
            test::return_to_sender(s, reg_cap);
        };
        next_tx(s, a);{
            let reg = test::take_shared<VSDBRegistry>(s);
            assert!(vsdb::whitelisted<VSDB>(&reg), 404);
            test::return_shared(reg);
        }
    }

    use suiDouBashi_vote::gauge::{Self, Gauge};
    use suiDouBashi_vote::bribe::{Self, Bribe};
    use suiDouBashi_vote::voter::VoterCap;
    public fun deploy_gauge(s: &mut Scenario){
        let ( a, _, _ ) = people();

        next_tx(s,a);{ // Action: create gauges & I_brbie & E_bribe for given pool
            let voter = test::take_shared<Voter>(s);
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let voter_cap = test::take_from_sender<VoterCap>(s);

            voter::create_gauge(&mut voter, &voter_cap, &pool_a, ctx(s));
            voter::create_gauge(&mut voter, &voter_cap, &pool_b, ctx(s));

            test::return_to_sender(s, voter_cap);
            test::return_shared(voter);
            test::return_shared(pool_a);
            test::return_shared(pool_b);
        };
        next_tx(s,a);{ // Assertion: create gauge, I_birbe & E_bribe successfully
            let voter = test::take_shared<Voter>(s);

            {// pool_a
                let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
                let gauge = test::take_shared<Gauge<USDC,USDT>>(s);
                let bribe = test::take_shared<Bribe<USDC,USDT>>(s);
                assert!(gauge::is_alive(&gauge), 0);
                assert!(bribe::total_votes(&bribe) == 0, 0);
                assert!(voter::pool_weights(&voter, &pool_a) == 0, 0);
                assert!(voter::is_registry(&voter, &pool_a), 0);
                test::return_shared(gauge);
                test::return_shared(bribe);
                test::return_shared(pool_a);
            };

            {// pool_b
                let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
                let gauge = test::take_shared<Gauge<SDB, USDC>>(s);
                let bribe = test::take_shared<Bribe<SDB, USDC>>(s);
                assert!(gauge::is_alive(&gauge), 0);
                assert!(bribe::total_votes(&bribe) == 0, 0);
                // amount of external bribe is at most 4, including pair of coins + SDB + SUI
                assert!(voter::pool_weights(&voter, &pool_b) == 0, 0);
                assert!(voter::is_registry(&voter, &pool_b), 0);
                test::return_shared(gauge);
                test::return_shared(bribe);
                test::return_shared(pool_b);
            };

            test::return_shared(voter);
        }
    }

    public fun people(): (address, address, address) { (@0x000A, @0x000B, @0x000C ) }
}