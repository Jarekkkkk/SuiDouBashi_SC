module coin_list::mock_eth {
    use sui::coin::{Self, TreasuryCap};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::option;

    struct MOCK_ETH has drop {}

    fun init(witness: MOCK_ETH, ctx: &mut TxContext)
    {
        let (treasury_cap, metadata) = coin::create_currency<MOCK_ETH>(
            witness,
            8,
            b"ETH",
            b"Etherum",
            b"https://assets.coingecko.com/coins/images/279/small/ethereum.png?1595348880",
            option::none(),
            ctx
        );
        transfer::public_freeze_object(metadata);
        transfer::public_share_object(treasury_cap)
    }

    public entry fun mint(treasury_cap: &mut TreasuryCap<MOCK_ETH>, amount: u64, ctx: &mut TxContext)
    {
        let coin = coin::mint<MOCK_ETH>(treasury_cap, amount, ctx);
        transfer::public_transfer(coin, tx_context::sender(ctx));
    }

    public entry fun transfer(treasury_cap: TreasuryCap<MOCK_ETH>, recipient: address)
    {
        transfer::public_transfer(treasury_cap, recipient);
    }

    #[test_only]
    public fun deploy_coin(ctx: &mut TxContext)
    {
        init(MOCK_ETH {}, ctx)
    }
}