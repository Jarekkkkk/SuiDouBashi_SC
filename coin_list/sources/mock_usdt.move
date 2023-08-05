module coin_list::mock_usdt {
    use sui::coin::{Self, TreasuryCap};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::option;


    struct MOCK_USDT has drop {}

    fun init(witness: MOCK_USDT, ctx: &mut TxContext)
    {
        let (treasury_cap, metadata) = coin::create_currency<MOCK_USDT>(
            witness,
            6,
            b"USDT",
            b"Tether",
            b"https://assets.coingecko.com/coins/images/325/small/Tether-logo.png?1598003707",
            option::none(),
            ctx
        );
        transfer::public_transfer(coin::mint(&mut treasury_cap, 1_000_000 * sui::math::pow(10, 6), ctx), tx_context::sender(ctx));
        transfer::public_freeze_object(metadata);
        transfer::public_share_object(treasury_cap)
    }

    public entry fun mint(treasury_cap: &mut TreasuryCap<MOCK_USDT>, amount: u64, ctx: &mut TxContext)
    {
        let coin = coin::mint<MOCK_USDT>(treasury_cap, amount, ctx);
        transfer::public_transfer(coin, tx_context::sender(ctx));
    }

    public entry fun transfer(treasury_cap: TreasuryCap<MOCK_USDT>, recipient: address)
    {
        transfer::public_transfer(treasury_cap, recipient);
    }

    #[test_only]
    public fun deploy_coin(ctx: &mut TxContext)
    {
        init(MOCK_USDT {}, ctx)
    }
}