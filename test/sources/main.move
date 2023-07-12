#[test_only]
module test::main{
    use suiDouBashi_vsdb::sdb::SDB;

    use suiDouBashi_amm::pool::Pool;
    use coin_list::mock_usdt::{MOCK_USDT as USDT};
    use coin_list::mock_usdc::{MOCK_USDC as USDC};

    use suiDouBashi_vest::minter::{mint_sdb, Minter};

    use test::setup;
    use sui::coin::{ Self, mint_for_testing as mint, Coin, burn_for_testing as burn};
    use sui::object;

    use sui::clock::{Self, timestamp_ms as get_time, increment_for_testing as add_time, Clock};
    use sui::transfer;
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};


    #[test] fun main(){
        let (a,_,_) = setup::people();
        let s = test::begin(a);
        let clock = clock::create_for_testing(ctx(&mut s));

        setup_(&mut clock, &mut s);
        // VSDB
        vest_(&mut clock, &mut s);

        // AMM
        test::pool_test::pool_(&mut clock, &mut s);
        // VeModel
        setup::deploy_voter(&mut s);
        setup::deploy_gauge(&mut s);
        test::gauge_test::gauge_(&mut clock, &mut s);
        test::bribe_test::bribe_(&mut clock, &mut s);
        test::voter_test::vote_(&mut clock, &mut s);
        distribute_fees_(&mut clock, &mut s);
        internal_bribe_(&mut clock, &mut s);
        test::e_bribe_test::external_bribe_(&mut clock, &mut s); // gas cost high
        vsdb_decay(&mut clock, &mut s);

        clock::destroy_for_testing(clock);
        test::end(s);
    }

    fun setup_(clock: &mut Clock, test: &mut Scenario){
        let (a, _, _ ) = setup::people();

        add_time(clock, setup::start_time() * 1000);
        std::debug::print(&get_time(clock));

        setup::deploy_coins(test);
        setup::mint_stable(test);

        vsdb::init_for_testing(ctx(test));

        setup::deploy_minter(clock, test);

        next_tx(test, a);{
            let minter = test::take_shared<Minter>(test);
            transfer::public_transfer(mint_sdb(&mut minter, 18 * setup::sui_1B(), ctx(test)), a);
            test::return_shared(minter);
        }
    }

    use suiDouBashi_vsdb::vsdb::{Self, Vsdb, VSDBRegistry};
    fun vest_(clock: &mut Clock, s: &mut Scenario){
        let (a,_,_) = setup::people();

        next_tx(s, a);{ // create lock
            let reg = test::take_shared<VSDBRegistry>(s);
            let sdb = test::take_from_sender<Coin<SDB>>(s);
            vsdb::lock(&mut reg, coin::split(&mut sdb, 5 * setup::sui_1B(), ctx(s)), vsdb::max_time(), clock, ctx(s));

            test::return_to_sender(s, sdb);
            test::return_shared(reg);
        };
        next_tx(s, a);{
            let vsdb = test::take_from_sender<Vsdb>(s);
            let voting = vsdb::voting_weight(&vsdb, clock);
            let reg = test::take_shared<VSDBRegistry>(s);
            assert!(voting >=  4910714285702544000, 1);
            assert!(vsdb::locked_balance(&vsdb) == 5 * setup::sui_1B(),1);

            assert!(vsdb::total_VeSDB(&reg, clock) == 4910714285702544000, 1);
            assert!(vsdb::minted_vsdb(&reg) == 1, 1);
            assert!( vsdb::player_epoch(&vsdb) == 0, 0);

            test::return_to_sender(s, vsdb);
            test::return_shared(reg);
        };

        add_time(clock, setup::week() * 1000);

        next_tx(s, a);{ // increase lock amount & time
            let sdb = test::take_from_sender<Coin<SDB>>(s);
            let vsdb = test::take_from_sender<Vsdb>(s);
            let reg = test::take_shared<VSDBRegistry>(s);

            vsdb::increase_unlock_amount(&mut reg, &mut vsdb, coin::split(&mut sdb, 5 * setup::sui_1B(), ctx(s)), clock);
              vsdb::increase_unlock_time(&mut reg, &mut vsdb, vsdb::max_time(), clock);

            test::return_to_sender(s, sdb);
            test::return_to_sender(s, vsdb);
            test::return_shared(reg);
        };
        next_tx(s, a);{
            let vsdb = test::take_from_sender<Vsdb>(s);
            let voting = vsdb::voting_weight(&vsdb, clock);
            let reg = test::take_shared<VSDBRegistry>(s);
            assert!(voting >= 9821428571419344000, 1);
            assert!(vsdb::locked_balance(&vsdb) == 10 * setup::sui_1B(),1);

            assert!(vsdb::total_VeSDB(&reg, clock) == 9821428571419344000, 1);
            assert!(vsdb::minted_vsdb(&reg) == 1, 1);
            assert!( vsdb::player_epoch(&vsdb) == 2, 0);

            test::return_to_sender(s, vsdb);
            test::return_shared(reg);
        };
        next_tx(s,a);{ // create 2 additional new VeSDB
            let reg = test::take_shared<VSDBRegistry>(s);
            let sdb = test::take_from_sender<Coin<SDB>>(s);
            vsdb::lock(&mut reg, coin::split(&mut sdb, 5 * setup::sui_100M(), ctx(s)), vsdb::max_time(), clock, ctx(s));
            vsdb::lock(&mut reg, coin::split(&mut sdb, 5 * setup::sui_100M(), ctx(s)), vsdb::max_time(), clock, ctx(s));

            test::return_to_sender(s, sdb);
            test::return_shared(reg);
        };
        next_tx(s, a);{
            let vsdb = test::take_from_sender<Vsdb>(s);
            let voting = vsdb::voting_weight(&vsdb, clock);
            let reg = test::take_shared<VSDBRegistry>(s);
            assert!(voting >= 491071428557424000, 1);
            assert!(vsdb::locked_balance(&vsdb) == 5 * setup::sui_100M(), 404);
            assert!(vsdb::total_VeSDB(&reg, clock) == 10803571428534192000, 404);
            assert!(vsdb::minted_vsdb(&reg) == 3, 1);
            assert!( vsdb::player_epoch(&vsdb) == 0, 0);

            test::return_to_sender(s, vsdb);
            test::return_shared(reg);
        };
        next_tx(s,a);
        let (id, id_1) = { // Action: Merge 3 vsdb into single
            let vsdb = test::take_from_sender<Vsdb>(s);
            let vsdb_merged = test::take_from_sender<Vsdb>(s);
            let vsdb_merged_1 = test::take_from_sender<Vsdb>(s);
            let id = object::id(&vsdb_merged);
            let id_1 = object::id(&vsdb_merged_1);
            let reg = test::take_shared<VSDBRegistry>(s);
            vsdb::merge(&mut reg, &mut vsdb, vsdb_merged, clock, ctx(s));
            vsdb::merge(&mut reg, &mut vsdb, vsdb_merged_1, clock, ctx(s));

            test::return_to_sender(s, vsdb);
            test::return_shared(reg);
            (id, id_1)
        };
        next_tx(s,a);{
            let vsdb = test::take_from_sender<Vsdb>(s);
            let voting = vsdb::voting_weight(&vsdb, clock);
            let reg = test::take_shared<VSDBRegistry>(s);

            assert!(voting >= 10803571428562704000, 1);
            assert!(vsdb::locked_balance(&vsdb) == 110 * setup::sui_100M(),1);
            assert!( vsdb::player_epoch(&vsdb) == 2, 0);
            // check NFTs are removed from global storage
            assert!(!test::was_taken_from_address(a, id),1); // not exist
            assert!(!test::was_taken_from_address(a, id_1),1); // not exist
            assert!(vsdb::total_VeSDB(&reg, clock) == 10803571428562704000, 1);
            assert!(vsdb::minted_vsdb(&reg) == 1, 1);

            test::return_to_sender(s, vsdb);
            test::return_shared(reg);
        }
    }

    use suiDouBashi_vest::internal_bribe::{InternalBribe};
    use suiDouBashi_vest::gauge::{Self, Gauge};
    use suiDouBashi_vest::voter::{Self, Voter};
    use suiDouBashi_amm::pool::{Self, LP};
    use sui::table;
    const SCALE_FACTOR: u256 = 1_000_000_000_000_000_000; // 10e18

    fun distribute_fees_(clock: &mut Clock, s: &mut Scenario){
        let ( a, _, c ) = setup::people();

        next_tx(s,a);{ // Action: protocol distribute weekly emissions
            let voter = test::take_shared<Voter>(s);
            let gauge_a = test::take_shared<Gauge<USDC, USDT>>(s);
            let gauge_b = test::take_shared<Gauge<SDB, USDC>>(s);

            voter::notify_reward_amount_(&mut voter, mint<SDB>(setup::stake_1(), ctx(s)));
            voter::update_for(&voter, &mut gauge_a);
            voter::update_for(&voter, &mut gauge_b);

            test::return_shared(gauge_a);
            test::return_shared(gauge_b);
            test::return_shared(voter);
        };
        next_tx(s,a);{ // Assertion: voter state is successfully updated
            let voter = test::take_shared<Voter>(s);
            let total_voting_weight = voter::get_total_weight(&voter);
            let index = (setup::stake_1() as u256) * SCALE_FACTOR / (total_voting_weight as u256);
            // voter
            assert!(voter::get_index(&voter) == index, 404);
            assert!(voter::get_balance(&voter) == setup::stake_1(), 404);
            {// pool_a
                let pool = test::take_shared<Pool<USDC, USDT>>(s);
                let gauge= test::take_shared<Gauge<USDC, USDT>>(s);
                let gauge_weights =( voter::get_weights_by_pool(&voter, &pool) as u256);
                assert!(gauge::get_supply_index(&gauge) == index, 404);
                assert!(gauge::get_claimable(&gauge) == ((index * gauge_weights / SCALE_FACTOR )as u64), 404);

                test::return_shared(pool);
                test::return_shared(gauge);
            };
            {// pool_b
                let pool = test::take_shared<Pool<SDB, USDC>>(s);
                let gauge= test::take_shared<Gauge<SDB, USDC>>(s);
                let gauge_weights =( voter::get_weights_by_pool(&voter, &pool) as u256);

                assert!(gauge::get_supply_index(&gauge) == index, 404);
                assert!(gauge::get_claimable(&gauge) == ((index * gauge_weights / SCALE_FACTOR )as u64), 404);
                test::return_shared(pool);
                test::return_shared(gauge);
            };
            test::return_shared(voter);
        };
        next_tx(s,a);{ // Actions: distribute weekly emissions
            let voter = test::take_shared<Voter>(s);
            let minter = test::take_shared<Minter>(s);
            let vsdb_reg = test::take_shared<VSDBRegistry>(s);
            let pool = test::take_shared<Pool<USDC, USDT>>(s);
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
            let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);

            voter::distribute(&mut voter, &mut minter, &mut gauge, &mut i_bribe, &mut pool, &mut vsdb_reg, clock, ctx(s));

            test::return_shared(voter);
            test::return_shared(minter);
            test::return_shared(vsdb_reg);
            test::return_shared(pool);
            test::return_shared(gauge);
            test::return_shared(i_bribe);
        };
        next_tx(s,c);{ // Assertion: first time distribution
            let voter = test::take_shared<Voter>(s);
            let minter = test::take_shared<Minter>(s);
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
            let reward = gauge::borrow_reward(&gauge);
            let sdb_team = test::take_from_sender<Coin<SDB>>(s);

          // { // new weekly index
          //      let _weekly = 15071747136074714; // locked ratio is too low
          //      let prev_idx = 95382;
          //      let total_voting_weight = voter::get_total_weight(&voter);
          //      let index = prev_idx + (_weekly as u256) * SCALE_FACTOR / (total_voting_weight as u256);
          //      assert!(voter::get_index(&voter) == index && index == gauge::get_supply_index(&gauge), 404);
          //  };
            //let _new_claiabe = 7535873568537349; // have to hard-coded, we had reset it in the distribute function
            //assert!(gauge::get_reward_rate(reward) == _new_claiabe / (7 * 86400), 404);

            assert!(coin::value(&sdb_team) == 513019197003257 , 404);
            assert!(voter::get_balance(&voter) == 8293810352052660, 404);
            assert!(gauge::get_reward_balance(reward) == 8293810352966256, 404);
            assert!(gauge::get_claimable(&gauge) == 0, 404);

            burn(sdb_team);
            test::return_shared(voter);
            test::return_shared(gauge);
            test::return_shared(minter);
        };
        next_tx(s,a);{ // Action: staker A withdraw weekly emissions
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
            gauge::get_reward(&mut gauge, clock, ctx(s));
            test::return_shared(gauge);
        };
        next_tx(s,a);{ // Assertion:
            let sdb = test::take_from_sender<Coin<SDB>>(s);
            let voter = test::take_shared<Voter>(s);
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
            let reward = gauge::borrow_reward(&gauge);

            // staked for 6 days, previous epoch rate stay at 1
            assert!(coin::value(&sdb) == 1 * 6 * 86400, 404);
            assert!( gauge::get_reward_balance(reward) == 8293810352966256 - coin::value(&sdb), 404);
            // reward
            assert!(gauge::get_period_finish(reward) == get_time(clock) / 1000 + setup::week() , 404);
            assert!(*table::borrow(gauge::last_earn_borrow(reward), a) == get_time(clock)/1000 , 404);

            burn(sdb);
            test::return_shared(voter);
            test::return_shared(gauge);
        };

        add_time(clock, setup::week() * 1000);

        next_tx(s,a);
        let opt_emission = { // Action: staker A withdraw weekly emissions after a week
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
            let earned = gauge::earned(&gauge, a, clock);
            gauge::get_reward(&mut gauge, clock, ctx(s));
            test::return_shared(gauge);

            earned
        };
        next_tx(s,a);{
            let sdb = test::take_from_sender<Coin<SDB>>(s);
            assert!(coin::value(&sdb) == opt_emission, 404);
            burn(sdb);
        };
    }
    use suiDouBashi_vest::internal_bribe::{Self as i_bribe};
    public fun internal_bribe_(clock: &mut Clock, s: &mut Scenario){
        let ( a, _, _ ) = setup::people();

        next_tx(s, a);
        let opt_sdb = { // Action: swap
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let pool_b = test::take_shared<Pool<SDB, USDC>>(s);
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let lp_b = test::take_from_sender<LP<SDB, USDC>>(s);
            let ctx = ctx(s);

            let opt_output = pool::get_output<USDC,USDT,USDC>(&pool_a, setup::usdc_100M());
            pool::swap_for_y(&mut pool_a, mint<USDC>(setup::usdc_100M(), ctx), opt_output, clock, ctx);
            let opt_output = pool::get_output<USDC,USDT,USDT>(&pool_a, setup::usdc_100M());
            pool::swap_for_x(&mut pool_a, mint<USDT>(setup::usdc_100M(), ctx), opt_output, clock, ctx);

            let opt_output = pool::get_output<SDB, USDC, SDB>(&pool_b, setup::sui_100M());
            pool::swap_for_y(&mut pool_b, mint<SDB>(setup::sui_100M(), ctx), opt_output, clock, ctx);
            let opt_output = pool::get_output<SDB, USDC, USDC>(&pool_b, setup::usdc_100M());
            pool::swap_for_x(&mut pool_b, mint<USDC>(setup::usdc_100M(), ctx), opt_output, clock, ctx);

            test::return_shared(pool_a);
            test::return_shared(pool_b);
            test::return_to_sender(s, lp_a);
            test::return_to_sender(s, lp_b);

            opt_output
        };
        next_tx(s,a);{
            let sdb = test::take_from_sender<Coin<SDB>>(s);
            assert!(coin::value(&sdb) == opt_sdb, 404);
            burn(sdb);
        };

        add_time(clock, setup::week() * 1000 + setup::day() * 1000);

        next_tx(s,a);{ // LP holders withdraw LP fees when pool is empty
            let vsdb = test::take_from_sender<Vsdb>(s);
            let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);
            assert!( i_bribe::reward_per_token<USDC, USDT, USDC>(&i_bribe, clock) == 0, 404);
            assert!( i_bribe::reward_per_token<USDC, USDT, USDT>(&i_bribe, clock) == 0, 404);
            i_bribe::get_all_rewards(&mut i_bribe, &vsdb, clock, ctx(s));

            test::return_to_sender(s, vsdb);
            test::return_shared(i_bribe);
        };

        // next_tx(s, a);{
        //     let usdc = test::take_from_sender<Coin<USDC>>(s);
        //     let usdt = test::take_from_sender<Coin<USDT>>(s);

        //     assert!(coin::value(&usdc) == 911851118, 404);
        //     assert!(coin::value(&usdt) == 911851118, 404);

        //     test::return_to_sender(s, usdc);
        //     test::return_to_sender(s, usdt);
        // };
        next_tx(s,a);{ // distribute fees
            let pool = test::take_shared<Pool<USDC, USDT>>(s);
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
            let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);

            voter::distribute_fees(&mut gauge, &mut i_bribe, &mut pool, clock, ctx(s));

            test::return_shared(pool);
            test::return_shared(gauge);
            test::return_shared(i_bribe);
        };
        next_tx(s, a);{ // I_bribe receive the rewards
            let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);
            assert!(i_bribe::get_reward_balance<USDC,USDT,USDC>(&i_bribe) == 10_000_000_000, 404);
            assert!(i_bribe::get_reward_balance<USDC,USDT,USDT>(&i_bribe) == 10_000_000_000, 404);

            test::return_shared(i_bribe);
        };
        next_tx(s,a);{
            let voter = test::take_shared<Voter>(s);
            let minter = test::take_shared<Minter>(s);
            let vsdb_reg = test::take_shared<VSDBRegistry>(s);
            let pool = test::take_shared<Pool<USDC, USDT>>(s);
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
            let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);

            voter::distribute(&mut voter, &mut minter, &mut gauge, &mut i_bribe, &mut pool, &mut vsdb_reg, clock, ctx(s));

            test::return_shared(voter);
            test::return_shared(minter);
            test::return_shared(vsdb_reg);
            test::return_shared(pool);
            test::return_shared(gauge);
            test::return_shared(i_bribe);
        };
        next_tx(s,a);{ // LP holders withdraw LP fees when pool is empty
            let vsdb = test::take_from_sender<Vsdb>(s);
            let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);
            assert!( i_bribe::reward_per_token<USDC, USDT, USDC>(&i_bribe, clock) == 0, 404);
            assert!( i_bribe::reward_per_token<USDC, USDT, USDT>(&i_bribe, clock) == 0, 404);

            test::return_to_sender(s, vsdb);
            test::return_shared(i_bribe);
        };
        next_tx(s,a);{
            let lp_a = test::take_from_sender<LP<USDC, USDT>>(s);
            let pool_a = test::take_shared<Pool<USDC, USDT>>(s);
            let gauge_a = test::take_shared<Gauge<USDC, USDT>>(s);

            gauge::unstake(&mut gauge_a, &pool_a, &mut lp_a, setup::stake_1(), clock, ctx(s));
            add_time(clock, 1);
            gauge::stake(&mut gauge_a, &pool_a, &mut lp_a, setup::stake_1(), clock, ctx(s));

            test::return_shared(gauge_a);
            test::return_to_sender(s, lp_a);
            test::return_shared(pool_a);
        };

        next_tx(s,a);{ // Action: Batch reward per token
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
            let prev_len = {
                let reward = gauge::borrow_reward(&gauge);
                let rps = gauge::reward_checkpoints_borrow(reward);
                sui::table_vec::length(rps)
            };

            add_time(clock, 1);
            gauge::batch_reward_per_token(&mut gauge, 200, clock);
            add_time(clock, 1);
            gauge::batch_reward_per_token(&mut gauge, 200, clock);
            add_time(clock, 1);
            gauge::batch_reward_per_token(&mut gauge, 200, clock);
            add_time(clock, 1);
            gauge::batch_reward_per_token(&mut gauge, 200, clock);
            add_time(clock, 1);
            gauge::batch_reward_per_token(&mut gauge, 200, clock);
            add_time(clock, 1);
            gauge::batch_reward_per_token(&mut gauge, 200, clock);
            add_time(clock, 1);
            gauge::batch_reward_per_token(&mut gauge, 200, clock);
            add_time(clock, 1);

            let post_len = {
                let reward = gauge::borrow_reward(&gauge);
                let rps = gauge::reward_checkpoints_borrow(reward);
                sui::table_vec::length(rps)
            };

            assert!(prev_len == post_len, 404);
            test::return_shared(gauge);
        };

        next_tx(s,a);{ // Staker claim the rewards
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
            let lp = test::take_from_sender<LP<USDC, USDT>>(s);
            let pool = test::take_shared<Pool<USDC, USDT>>(s);

            gauge::get_reward(&mut gauge, clock, ctx(s));
            gauge::unstake(&mut gauge, &pool, &mut lp, setup::stake_1(), clock, ctx(s));
            add_time(clock, 1);
            let prev_earned = gauge::earned(&gauge, a, clock);
            assert!(prev_earned == 0, 404);

            test::return_shared(gauge);
            test::return_to_sender(s, lp);
            test::return_shared(pool);
        };

        next_tx(s,a);
        let prev_sdb = { // Action: repeated exploitative behavior
            let voter = test::take_shared<Voter>(s);
            let minter = test::take_shared<Minter>(s);
            let vsdb_reg = test::take_shared<VSDBRegistry>(s);
            let pool = test::take_shared<Pool<USDC, USDT>>(s);
            let gauge = test::take_shared<Gauge<USDC, USDT>>(s);
            let i_bribe = test::take_shared<InternalBribe<USDC, USDT>>(s);
            let lp = test::take_from_sender<LP<USDC, USDT>>(s);

            {
                gauge::stake(&mut gauge, &pool, &mut lp, setup::stake_1(), clock, ctx(s));
                voter::claim_rewards(&mut voter, &mut minter, &mut gauge, &mut i_bribe, &mut pool, &mut vsdb_reg, clock, ctx(s));
                gauge::unstake(&mut gauge, &pool, &mut lp, setup::stake_1(), clock, ctx(s));
                add_time(clock, 1);
            };
            {
                gauge::stake(&mut gauge, &pool, &mut lp, setup::stake_1(), clock, ctx(s));
                voter::claim_rewards(&mut voter, &mut minter, &mut gauge, &mut i_bribe, &mut pool, &mut vsdb_reg, clock, ctx(s));
                gauge::unstake(&mut gauge, &pool, &mut lp, setup::stake_1(), clock, ctx(s));
                add_time(clock, 1);
            };
            {
                gauge::stake(&mut gauge, &pool, &mut lp, setup::stake_1(), clock, ctx(s));
                voter::claim_rewards(&mut voter, &mut minter, &mut gauge, &mut i_bribe, &mut pool, &mut vsdb_reg, clock, ctx(s));
                gauge::unstake(&mut gauge, &pool, &mut lp, setup::stake_1(), clock, ctx(s));
                add_time(clock, 1);
            };
            {
                gauge::stake(&mut gauge, &pool, &mut lp, setup::stake_1(), clock, ctx(s));
                voter::claim_rewards(&mut voter, &mut minter, &mut gauge, &mut i_bribe, &mut pool, &mut vsdb_reg, clock, ctx(s));
                gauge::unstake(&mut gauge, &pool, &mut lp, setup::stake_1(), clock, ctx(s));
                add_time(clock, 1);
            };
            {
                gauge::stake(&mut gauge, &pool, &mut lp, setup::stake_1(), clock, ctx(s));
                voter::claim_rewards(&mut voter, &mut minter, &mut gauge, &mut i_bribe, &mut pool, &mut vsdb_reg, clock, ctx(s));
                gauge::unstake(&mut gauge, &pool, &mut lp, setup::stake_1(), clock, ctx(s));
                add_time(clock, 1);
            };
            {
                gauge::stake(&mut gauge, &pool, &mut lp, setup::stake_1(), clock, ctx(s));
                voter::claim_rewards(&mut voter, &mut minter, &mut gauge, &mut i_bribe, &mut pool, &mut vsdb_reg, clock, ctx(s));
                add_time(clock, 1);
            };

            let post_sdb = {
                let sdb = test::take_from_sender<Coin<SDB>>(s);
                let id = object::id(&sdb);
                test::return_to_sender(s, sdb);
                id
            };

            test::return_shared(voter);
            test::return_shared(minter);
            test::return_shared(vsdb_reg);
            test::return_shared(pool);
            test::return_shared(gauge);
            test::return_shared(i_bribe);
            test::return_to_sender(s, lp);

            post_sdb
        };

        next_tx(s,a);{ // Assertion: check sdb is balance is unchanged
            let sdb = test::take_from_sender<Coin<SDB>>(s);
            assert!(object::id(&sdb) == prev_sdb, 404);
            test::return_to_sender(s, sdb);
        };
    }
    fun vsdb_decay(clock: &mut Clock, s: &mut Scenario){
        let ( a, _, _ ) = setup::people();
        add_time(clock, 122255982 * 1000);

        next_tx(s,a);{ // Decay the vsdb
            let vsdb = test::take_from_sender<Vsdb>(s);
            let vsdb_1 = test::take_from_sender<Vsdb>(s);
            let vsdb_reg = test::take_shared<VSDBRegistry>(s);
            assert!(vsdb::voting_weight(&vsdb, clock) == 0, 404);
            vsdb::total_VeSDB(&vsdb_reg, clock);
            assert!(vsdb::total_VeSDB(&vsdb_reg, clock) == 0, 404); //9589041094752000
            test::return_to_sender(s, vsdb);
            test::return_to_sender(s, vsdb_1);
            test::return_shared(vsdb_reg);
        };
    }
}
