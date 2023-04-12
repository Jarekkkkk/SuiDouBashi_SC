#[test_only]
module test::bribe_test{
    // use sui::test_scenario::{Self as test, next_tx, ctx};
    // use sui::coin::{mint_for_testing as mint};

    // use suiDouBashiVest::internal_bribe::{Self};

    // // fake
    // struct JRK {}

    // #[test]
    // fun test_bribe(){
    //     let s = test::begin(@0x1);

    //     let (sender, _) = people();

    //     next_tx(&mut s, sender);{
    //         internal_bribe::mock_init(ctx(&mut s));
    //     };

    //     next_tx(&mut s, sender);{
    //         let coin  = mint<JRK>(500, ctx(&mut s));
    //         let reg = test::take_shared<Reg>(&mut s);
    //         internal_bribe::deposit(&mut reg, coin, ctx(&mut s));

    //         test::return_shared(reg);
    //     };

    //     next_tx(&mut s, sender);{
    //         let reg = test::take_shared<Reg>(&mut s);
    //         assert!(internal_bribe::get_balance_value<JRK>(&mut reg) == 500, 1);
    //         test::return_shared(reg);
    //     };


    //     test::end(s);
    // }


    fun people(): (address, address) { (@0xABCD, @0x1234 ) }
}