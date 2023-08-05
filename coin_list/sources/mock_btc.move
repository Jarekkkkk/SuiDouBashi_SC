module coin_list::mock_btc {
    use sui::coin;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::option;
    use sui::url::{Self, Url};

    struct MOCK_BTC has drop {}

    fun init(witness: MOCK_BTC, ctx: &mut TxContext)
    {
        let (treasury_cap, metadata) = coin::create_currency<MOCK_BTC>(
            witness,
            8,
            b"BTC",
            b"Bitcoin",
            b"descripition",
            option::some<Url>(url::new_unsafe_from_bytes(b"https://assets.coingecko.com/coins/images/1/small/bitcoin.png?1547033579")),
            ctx
        );
        transfer::public_transfer(coin::mint(&mut treasury_cap, 1_000_000 * sui::math::pow(10, 8), ctx), tx_context::sender(ctx));
        transfer::public_freeze_object(metadata);
        transfer::public_share_object(treasury_cap)
    }

    #[test_only]
    public fun deploy_coin(ctx: &mut TxContext)
    {
        init(MOCK_BTC {}, ctx)
    }
}