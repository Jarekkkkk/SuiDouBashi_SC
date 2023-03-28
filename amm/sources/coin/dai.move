module suiDouBashi::dai{
    use std::option;
    use sui::coin;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::url::{Self, Url};
    use sui::math;

    struct DAI has drop {}

    const DAI_SVG: vector<u8> = b"data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMzIiIGhlaWdodD0iMzIiIHZpZXdCb3g9IjAgMCAzMiAzMiIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB4bWxuczp4bGluaz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94bGluayI+PGRlZnM+PGZpbHRlciB4PSItNS44JSIgeT0iLTQuMiUiIHdpZHRoPSIxMTEuNyUiIGhlaWdodD0iMTExLjclIiBmaWx0ZXJVbml0cz0ib2JqZWN0Qm91bmRpbmdCb3giIGlkPSJhIj48ZmVPZmZzZXQgZHk9Ii41IiBpbj0iU291cmNlQWxwaGEiIHJlc3VsdD0ic2hhZG93T2Zmc2V0T3V0ZXIxIi8+PGZlR2F1c3NpYW5CbHVyIHN0ZERldmlhdGlvbj0iLjUiIGluPSJzaGFkb3dPZmZzZXRPdXRlcjEiIHJlc3VsdD0ic2hhZG93Qmx1ck91dGVyMSIvPjxmZUNvbXBvc2l0ZSBpbj0ic2hhZG93Qmx1ck91dGVyMSIgaW4yPSJTb3VyY2VBbHBoYSIgb3BlcmF0b3I9Im91dCIgcmVzdWx0PSJzaGFkb3dCbHVyT3V0ZXIxIi8+PGZlQ29sb3JNYXRyaXggdmFsdWVzPSIwIDAgMCAwIDAgMCAwIDAgMCAwIDAgMCAwIDAgMCAwIDAgMCAwLjE5OTQ3MzUwNSAwIiBpbj0ic2hhZG93Qmx1ck91dGVyMSIvPjwvZmlsdGVyPjxmaWx0ZXIgeD0iLTkuMiUiIHk9Ii03LjglIiB3aWR0aD0iMTE4LjQlIiBoZWlnaHQ9IjEyMS45JSIgZmlsdGVyVW5pdHM9Im9iamVjdEJvdW5kaW5nQm94IiBpZD0iZCI+PGZlT2Zmc2V0IGR5PSIuNSIgaW49IlNvdXJjZUFscGhhIiByZXN1bHQ9InNoYWRvd09mZnNldE91dGVyMSIvPjxmZUdhdXNzaWFuQmx1ciBzdGREZXZpYXRpb249Ii41IiBpbj0ic2hhZG93T2Zmc2V0T3V0ZXIxIiByZXN1bHQ9InNoYWRvd0JsdXJPdXRlcjEiLz48ZmVDb2xvck1hdHJpeCB2YWx1ZXM9IjAgMCAwIDAgMCAwIDAgMCAwIDAgMCAwIDAgMCAwIDAgMCAwIDAuMjA0MjU3MjQ2IDAiIGluPSJzaGFkb3dCbHVyT3V0ZXIxIi8+PC9maWx0ZXI+PGxpbmVhckdyYWRpZW50IHgxPSI1MCUiIHkxPSIwJSIgeDI9IjUwJSIgeTI9IjEwMCUiIGlkPSJjIj48c3RvcCBzdG9wLWNvbG9yPSIjRkZGIiBzdG9wLW9wYWNpdHk9Ii41IiBvZmZzZXQ9IjAlIi8+PHN0b3Agc3RvcC1vcGFjaXR5PSIuNSIgb2Zmc2V0PSIxMDAlIi8+PC9saW5lYXJHcmFkaWVudD48Y2lyY2xlIGlkPSJiIiBjeD0iMTYiIGN5PSIxNSIgcj0iMTUiLz48cGF0aCBkPSJNMTUuODI5IDdjMy45ODUgMCA3LjAwNiAyLjExNiA4LjEzIDUuMTk0SDI2djEuODYxaC0xLjYxMWMuMDMxLjI5NC4wNDcuNTk0LjA0Ny44OTh2LjA0NmMwIC4zNDItLjAyLjY4LS4wNiAxLjAxSDI2djEuODZoLTIuMDhDMjIuNzY3IDIwLjkwNSAxOS43NyAyMyAxNS44MyAyM0g5LjI3N3YtNS4xMzFIN3YtMS44NmgyLjI3N3YtMS45NTRIN3YtMS44NmgyLjI3N1Y3aDYuNTUyem02LjA4NCAxMC44NjlIMTEuMTA4djMuNDYyaDQuNzJjMi45MTQgMCA1LjA3OC0xLjM4NyA2LjA4NS0zLjQ2MnptLjU2NC0zLjgxNEgxMS4xMDh2MS45NTNoMTEuMzY2Yy4wNDQtLjMxMy4wNjctLjYzNS4wNjctLjk2NFYxNWE2Ljk2IDYuOTYgMCAwMC0uMDY0LS45NDR6TTE1LjgzIDguNjY2aC00LjcydjMuNTI4aDEwLjgxOGMtMS4wMDEtMi4xMDQtMy4xNzItMy41MjgtNi4wOTgtMy41Mjh6IiBpZD0iZSIvPjwvZGVmcz48ZyBmaWxsPSJub25lIiBmaWxsLXJ1bGU9ImV2ZW5vZGQiPjx1c2UgZmlsbD0iIzAwMCIgZmlsdGVyPSJ1cmwoI2EpIiB4bGluazpocmVmPSIjYiIvPjx1c2UgZmlsbD0iI0Y0QjczMSIgeGxpbms6aHJlZj0iI2IiLz48dXNlIGZpbGw9InVybCgjYykiIHN0eWxlPSJtaXgtYmxlbmQtbW9kZTpzb2Z0LWxpZ2h0IiB4bGluazpocmVmPSIjYiIvPjxjaXJjbGUgc3Ryb2tlLW9wYWNpdHk9Ii4wOTciIHN0cm9rZT0iIzAwMCIgc3Ryb2tlLWxpbmVqb2luPSJzcXVhcmUiIGN4PSIxNiIgY3k9IjE1IiByPSIxNC41Ii8+PGcgZmlsbC1ydWxlPSJub256ZXJvIj48dXNlIGZpbGw9IiMwMDAiIGZpbHRlcj0idXJsKCNkKSIgeGxpbms6aHJlZj0iI2UiLz48dXNlIGZpbGw9IiNGRkYiIHhsaW5rOmhyZWY9IiNlIi8+PC9nPjwvZz48L3N2Zz4=";


    fun init(witness: DAI, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            18, // original decimals for DAI is 18, which is overload for prmitive u64 value
            b"DAI",
            b"DAI",
            b"Test StableCoin DAI",
            option::some<Url>(url::new_unsafe_from_bytes(DAI_SVG)),
            ctx
        );
        let coin = coin::mint<DAI>(&mut treasury, 10000*math::pow(10, 8), ctx);
        transfer::public_transfer(coin, tx_context::sender(ctx));

        transfer::public_freeze_object(metadata);
        transfer::public_share_object(treasury)
    }
    entry fun mint (cap: &mut coin::TreasuryCap<DAI>, value:u64, ctx: &mut TxContext){
        let coin = coin::mint<DAI>(cap, value, ctx);
        transfer::public_transfer(
            coin,
            tx_context::sender(ctx)
        )
    }
}