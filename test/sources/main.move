#[test_only]
module test::main{
    use sui::clock::{Self, Clock, increment_for_testing as add_time, timestamp_ms as get_time};
    use sui::test_scenario::{Self as test, Scenario, ctx};

    use test::setup;
    use test::vsdb_test;

    use suiDouBashi_vsdb::vsdb;



    #[test] fun main(){
        let (a,_,_) = setup::people();
        let s = test::begin(a);
        let clock = clock::create_for_testing(ctx(&mut s));

        setup_(&mut clock, &mut s);
        // VSDB
        vsdb_test::vest_(&mut clock, &mut s);
        // AMM
        test::pool_test::pool_(&mut clock, &mut s);
        // VeModel
        setup::deploy_voter(&mut s);
        setup::deploy_gauge(&mut s);
        test::gauge_test::gauge_(&mut clock, &mut s);
        test::voter_test::vote_(&mut clock, &mut s);
        test::gauge_test::distribute_emissions_(&mut clock, &mut s);
        test::bribe_test::internal_bribe_(&mut clock, &mut s);
        test::bribe_test::external_bribe_(&mut clock, &mut s); // gas cost high
        test::vsdb_test::vsdb_decay(&mut clock, &mut s);

        clock::destroy_for_testing(clock);
        test::end(s);
    }

    fun setup_(clock: &mut Clock, test: &mut Scenario){
        add_time(clock, setup::start_time() * 1000);
        std::debug::print(&std::ascii::string(b"start time: "));
        std::debug::print(&(get_time(clock)/1000));

        setup::deploy_coins(test);
        setup::mint_stable(test);

        vsdb::init_for_testing(ctx(test));

        setup::deploy_minter(clock, test);
    }
}
