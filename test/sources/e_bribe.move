module test::e_bribe_test{
    use sui::clock::{increment_for_testing as add_time, Clock};
    use sui::coin::{ Self, mint_for_testing as mint, Coin, burn_for_testing as burn};
    use test::setup;
    use sui::object;
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use std::vector as vec;
    use suiDouBashiVest::internal_bribe::{InternalBribe};
    use suiDouBashiVest::external_bribe::{Self as e_bribe, ExternalBribe};
    use suiDouBashiVest::gauge::{Self, Gauge};
    use suiDouBashiVest::voter::{Self, Voter};
    use suiDouBashiVest::reward_distributor::{Distributor};
    use suiDouBashiVest::vsdb::{VSDB, VSDBRegistry};
    use suiDouBashiVest::minter::{ Minter};
    use suiDouBashi::pool::{LP};
    use suiDouBashi::pool::Pool;
    use suiDouBashiVest::sdb::SDB;
    use suiDouBashi::usdc::USDC;
    use suiDouBashi::usdt::USDT;

    public fun external_bribe_(clock: &mut Clock, s: &mut Scenario){
        let ( a, _, _ ) = setup::people();

        add_time(clock, setup::week());
        next_tx(s,a);{
            let voter = test::take_shared<Voter>(s);
            let minter = test::take_shared<Minter>(s);
            let distributor = test::take_shared<Distributor>(s);
            let vsdb_reg = test::take_shared<VSDBRegistry>(s);
            let pool = test::take_shared<Pool<USDC, USDT>>(s);
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
            let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);
            let e_bribe = test::take_shared<ExternalBribe<USDC, USDT>>(s);
            let lp = test::take_from_sender<LP<USDC, USDT>>(s);

            voter::distribute_(&mut voter, &mut minter, &mut distributor, &mut gauge, &mut i_bribe, &mut pool, &mut vsdb_reg, clock, ctx(s));

            {// bribing 100K for gauge_a
                e_bribe::bribe(&mut e_bribe, mint<USDC>(setup::usdc_100K(), ctx(s)), clock, ctx(s));
                e_bribe::bribe(&mut e_bribe, mint<USDT>(setup::usdc_100K(), ctx(s)), clock, ctx(s));
                e_bribe::bribe(&mut e_bribe, mint<SDB>(setup::sui_100K(), ctx(s)), clock, ctx(s));
                e_bribe::bribe(&mut e_bribe, mint<sui::sui::SUI>(setup::sui_100K(), ctx(s)), clock, ctx(s));
            };

            test::return_shared(voter);
            test::return_shared(minter);
            test::return_shared(distributor);
            test::return_shared(vsdb_reg);
            test::return_shared(pool);
            test::return_shared(gauge);
            test::return_shared(i_bribe);
            test::return_shared(e_bribe);
            test::return_to_sender(s, lp);
        };

        next_tx(s,a);{ // LP holder A Voting
            let voter = test::take_shared<Voter>(s);
            let vsdb = test::take_from_sender_by_id<VSDB>(s, object::id_from_address(@0x84550b111b9b3595f7fc6263993e4f2d368d59e99531c2be9eb89dbc03b1524));
            {
                // pool_a
                let gauge_a = test::take_shared<Gauge<USDC, USDT>>(s);
                let pool_id_a = gauge::pool_id(&gauge_a);
                let i_bribe_a = test::take_shared<InternalBribe<USDC, USDT>>(s);
                let e_bribe_a = test::take_shared<ExternalBribe<USDC, USDT>>(s);
                // pool_b
                let gauge_b = test::take_shared<Gauge<SDB, USDC>>(s);
                let pool_id_b = gauge::pool_id(&gauge_b);
                let i_bribe_b = test::take_shared<InternalBribe<SDB, USDC>>(s);
                let e_bribe_b = test::take_shared<ExternalBribe<SDB, USDC>>(s);

                { // Potato
                    let weights = vec::singleton(50000);
                    vec::push_back(&mut weights, 50000);
                    let pools = vec::singleton(object::id_to_address(&pool_id_a));
                    vec::push_back(&mut pools, object::id_to_address(&pool_id_b));

                    let potato = voter::voting_entry(&mut vsdb, clock);
                    let potato = voter::reset_(potato, &mut voter, &mut vsdb, &mut gauge_a, &mut i_bribe_a, &mut e_bribe_a, clock, ctx(s));
                    let potato =  voter::reset_(potato, &mut voter, &mut vsdb, &mut gauge_b, &mut i_bribe_b, &mut e_bribe_b, clock, ctx(s));
                    potato = voter::vote_entry(potato,&mut voter, pools, weights);
                    potato = voter::vote_(potato, &mut voter, &mut vsdb, &mut gauge_a, &mut i_bribe_a, &mut e_bribe_a, clock, ctx(s));
                    potato = voter::vote_(potato, &mut voter, &mut vsdb, &mut gauge_b, &mut i_bribe_b, &mut e_bribe_b, clock, ctx(s));
                    voter::vote_exit(potato, &mut voter, &mut vsdb);
                };

                test::return_shared(gauge_a);
                test::return_shared(i_bribe_a);
                test::return_shared(e_bribe_a);

                test::return_shared(gauge_b);
                test::return_shared(i_bribe_b);
                test::return_shared(e_bribe_b);
            };
            test::return_shared(voter);
            test::return_to_sender(s, vsdb);
        };

        add_time(clock, setup::week());

        next_tx(s, a);{ // Withdraw weekly emissions after expiry
            let voter = test::take_shared<Voter>(s);
            let minter = test::take_shared<Minter>(s);
            let distributor = test::take_shared<Distributor>(s);
            let vsdb_reg = test::take_shared<VSDBRegistry>(s);
            let pool = test::take_shared<Pool<USDC, USDT>>(s);
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
            let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);
            let lp = test::take_from_sender<LP<USDC, USDT>>(s);

            {
                voter::claim_rewards(&mut voter, &mut minter, &mut distributor, &mut gauge, &mut i_bribe, &mut pool, &mut vsdb_reg, clock, ctx(s));
                gauge::unstake(&mut gauge, &pool, &mut lp, setup::stake_1(), clock, ctx(s));
                add_time(clock, 1);
            };

            test::return_shared(voter);
            test::return_shared(minter);
            test::return_shared(distributor);
            test::return_shared(vsdb_reg);
            test::return_shared(pool);
            test::return_shared(gauge);
            test::return_shared(i_bribe);
            test::return_to_sender(s, lp);
        };

        next_tx(s,a);{ // Assertion: received the reward
            let sdb = test::take_from_sender<Coin<SDB>>(s);
            assert!(coin::value(&sdb) == 14627810189300145, 404);
            burn(sdb);
        };

        next_tx(s,a);{ // VSDB holder withdraw bribes & fees
            let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);
            let e_bribe = test::take_shared<ExternalBribe<USDC, USDT>>(s);
            let vsdb = test::take_from_sender<VSDB>(s);

            voter::claim_fees(&mut i_bribe, &vsdb, clock, ctx(s));
            voter::claim_bribes(&mut e_bribe, &vsdb, clock, ctx(s));

            test::return_to_sender<VSDB>(s, vsdb);
            test::return_shared(i_bribe);
            test::return_shared(e_bribe);
        };
        next_tx(s,a);{ // succesfully receive the bribes
            let usdc = test::take_from_sender<Coin<USDC>>(s);
            let usdt = test::take_from_sender<Coin<USDT>>(s);
            let sui = test::take_from_sender<Coin<sui::sui::SUI>>(s);
            let sdb = test::take_from_sender<Coin<SDB>>(s);

            assert!(coin::value(&usdc) == 91471768403, 404);
            assert!(coin::value(&usdt) == 91471768403, 404);
            assert!(coin::value(&sui) == 91471768403954, 404);
            assert!(coin::value(&sdb) == 91471768403954, 404);

            burn(usdc);
            burn(usdt);
            burn(sui);
            burn(sdb);
        };
    }
}