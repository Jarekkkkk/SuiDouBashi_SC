module suiDouBashi_vsdb::sdb{
    use std::option;
    use sui::coin::{Self};
    use sui::transfer;
    use sui::tx_context::{TxContext};
    use sui::url::{Self, Url};
    use sui::tx_context;


    struct SDB has drop {}

    const DECIMALS: u8 = 9;
    const SDB_SVG: vector<u8> = b"https://ucarecdn.com/0b5e3467-eaeb-411b-a232-53f523bcfb6b/Coin_SDB.svg";

    fun init(otw: SDB, ctx: &mut TxContext){
        let (treasury, metadata) = coin::create_currency(
            otw,
            DECIMALS,
            b"SDB",
            b"SuiDouBashi",
            b"SuiDouBashi's Utility Token",
            option::some<Url>(url::new_unsafe_from_bytes(SDB_SVG)),
            ctx
        );

        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, tx_context::sender(ctx));
    }

    public fun decimals():u8 { DECIMALS }

    #[test_only] public fun deploy_coin(ctx: &mut TxContext){
        init(SDB{}, ctx);
    }
    #[test_only] public fun mint(value:u64, ctx: &mut TxContext):sui::coin::Coin<SDB>{
        sui::coin::mint_for_testing(value, ctx)
    }

    #[test]
    fun test_flip(){
        let input = b"[241,167,233,150,236,67,156,221,55,59,249,128,170,46,83,193]";
        let messageVector = sui::bcs::to_bytes(&b"0x4cf97e8371690dfd80d4a0c1ad09e063f4377f4e71e2b3ce72732632d87bca84");
        std::vector::append(&mut messageVector, input);
       std::debug::print(&messageVector);
    }
}
