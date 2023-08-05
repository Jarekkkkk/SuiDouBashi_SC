module coin_list::mock_usdt {
    use sui::coin;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::option;
    use sui::url::{Self, Url};

    struct MOCK_USDT has drop {}

    fun init(witness: MOCK_USDT, ctx: &mut TxContext)
    {
        let (treasury_cap, metadata) = coin::create_currency<MOCK_USDT>(
            witness,
            6,
            b"USDT",
            b"Tether",
            b"desc",
            option::some<Url>(url::new_unsafe_from_bytes(b"https://assets.coingecko.com/coins/images/325/small/Tether-logo.png?1598003707")),
            ctx
        );
        transfer::public_transfer(coin::mint(&mut treasury_cap, 1_000_000 * sui::math::pow(10, 6), ctx), tx_context::sender(ctx));
        transfer::public_freeze_object(metadata);
        transfer::public_share_object(treasury_cap)
    }


    #[test_only]
    public fun deploy_coin(ctx: &mut TxContext)
    {
        init(MOCK_USDT {}, ctx)
    }
}