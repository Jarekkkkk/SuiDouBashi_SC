module coin_list::mock_btc {
    use sui::coin::{Self, TreasuryCap};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::option;

    struct MOCK_BTC has drop {}

    fun init(witness: MOCK_BTC, ctx: &mut TxContext)
    {
        let (treasury_cap, metadata) = coin::create_currency<MOCK_BTC>(
            witness,
            8,
            b"BTC",
            b"Bitcoin",
            b"https://cryptototem.com/wp-content/uploads/2022/08/SUI-logo.jpg",
            option::none(),
            ctx
        );
        transfer::public_transfer(coin::mint(&mut treasury_cap, 1_000_000 * sui::math::pow(10, 8), ctx), tx_context::sender(ctx));
        transfer::public_freeze_object(metadata);
        transfer::public_share_object(treasury_cap)
    }

    public entry fun mint(treasury_cap: &mut TreasuryCap<MOCK_BTC>, amount: u64, ctx: &mut TxContext)
    {
        let coin = coin::mint<MOCK_BTC>(treasury_cap, amount, ctx);
        transfer::public_transfer(coin, tx_context::sender(ctx));
    }

    public entry fun transfer(treasury_cap: TreasuryCap<MOCK_BTC>, recipient: address)
    {
        transfer::public_transfer(treasury_cap, recipient);
    }

    #[test_only]
    public fun deploy_coin(ctx: &mut TxContext)
    {
        init(MOCK_BTC {}, ctx)
    }
}