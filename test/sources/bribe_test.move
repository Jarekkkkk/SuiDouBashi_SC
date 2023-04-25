#[test_only]
module test::setup{
    use suiDouBashi::usdc::{Self, USDC};
    use suiDouBashi::usdt::{Self, USDT};
    use suiDouBashiVest::sdb::{Self, SDB};

    use sui::math;
    use sui::transfer;
    use sui::tx_context;
    use sui::coin::{Self, CoinMetadata};
    use std::vector as vec;

    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    // 6 decimals
    public fun usdc_1(): u64 { math::pow(10, 6) }
    public fun usdc_100K(): u64 { math::pow(10, 11) }
    public fun usdc_1M(): u64 { math::pow(10, 12) }
    public fun usdc_100M(): u64 { math::pow(10, 14) }
    public fun usdc_1B(): u64 { math::pow(10, 15) }
    public fun usdc_10B(): u64 { math::pow(10, 16) }
    // 9 decimals, max value: 184B
    public fun sui_1(): u64 { math::pow(10, 9) }
    public fun sui_100K(): u64 { math::pow(10, 14) }
    public fun sui_1M(): u64 { math::pow(10, 15) }
    public fun sui_100M(): u64 { math::pow(10, 17) }
    public fun sui_1B(): u64 { math::pow(10, 18) }
    public fun sui_10B(): u64 { math::pow(10, 19) }

    public fun deploy_coins(test: &mut Scenario){
        usdc::deploy_coin(ctx(test));
        usdt::deploy_coin(ctx(test));
        sdb::deploy_coin(ctx(test));
    }

    public fun mint_stable(t: &mut Scenario){
        let (a, b, c) = people();
        let owners = vec::singleton(a);
        vec::push_back(&mut owners, b);
        vec::push_back(&mut owners, c);

        let ctx = ctx(t);
        let i = 0;
        while( i < vec::length(&owners) ){
            // 1B for each owner
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

    use suiDouBashi::pool_reg::{Self, PoolReg};
    public fun deploy_pools(t: &mut Scenario){
        let (a,_,_) = people();

        pool_reg::init_for_testing(ctx(t));

        next_tx(t, a); {
            let meta_usdc = test::take_immutable<CoinMetadata<USDC>>(t);
            let meta_usdt = test::take_immutable<CoinMetadata<USDT>>(t);
            let meta_sdb = test::take_immutable<CoinMetadata<SDB>>(t);

            let pool_gov = test::take_shared<PoolReg>(t);
            pool_reg::create_pool(
                &mut pool_gov,
                true,
                &meta_usdc,
                &meta_usdt,
                3,
                ctx(t)
            );
            pool_reg::create_pool(
                &mut pool_gov,
                false,
                &meta_sdb,
                &meta_usdc,
                5,
                ctx(t)
            );

            test::return_shared(pool_gov);
            test::return_immutable(meta_usdc);
            test::return_immutable(meta_usdt);
        };
        next_tx(t,a);{
            let pool_gov = test::take_shared<PoolReg>(t);
            assert!(pool_reg::pools_length(&pool_gov) == 2, 0);
            test::return_shared(pool_gov);
        }
    }


    public fun people(): (address, address, address) { (@0x000A, @0x000B, @0x000C ) }
}