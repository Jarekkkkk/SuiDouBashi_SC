/// Test usage
module suiDouBashi_amm::usdc{
    use std::option;
    use sui::coin;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::url::{Self, Url};
    use sui::math;

    struct USDC has drop {}

    const USDC_SVG: vector<u8> = b"data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMzIiIGhlaWdodD0iMzIiIHZpZXdCb3g9IjAgMCAzMiAzMiIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB4bWxuczp4bGluaz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94bGluayI+PGRlZnM+PGxpbmVhckdyYWRpZW50IHgxPSI1MCUiIHkxPSIwJSIgeDI9IjUwJSIgeTI9IjEwMCUiIGlkPSJjIj48c3RvcCBzdG9wLWNvbG9yPSIjRkZGIiBzdG9wLW9wYWNpdHk9Ii41IiBvZmZzZXQ9IjAlIi8+PHN0b3Agc3RvcC1vcGFjaXR5PSIuNSIgb2Zmc2V0PSIxMDAlIi8+PC9saW5lYXJHcmFkaWVudD48ZmlsdGVyIHg9Ii01LjglIiB5PSItNC4yJSIgd2lkdGg9IjExMS43JSIgaGVpZ2h0PSIxMTEuNyUiIGZpbHRlclVuaXRzPSJvYmplY3RCb3VuZGluZ0JveCIgaWQ9ImEiPjxmZU9mZnNldCBkeT0iLjUiIGluPSJTb3VyY2VBbHBoYSIgcmVzdWx0PSJzaGFkb3dPZmZzZXRPdXRlcjEiLz48ZmVHYXVzc2lhbkJsdXIgc3RkRGV2aWF0aW9uPSIuNSIgaW49InNoYWRvd09mZnNldE91dGVyMSIgcmVzdWx0PSJzaGFkb3dCbHVyT3V0ZXIxIi8+PGZlQ29tcG9zaXRlIGluPSJzaGFkb3dCbHVyT3V0ZXIxIiBpbjI9IlNvdXJjZUFscGhhIiBvcGVyYXRvcj0ib3V0IiByZXN1bHQ9InNoYWRvd0JsdXJPdXRlcjEiLz48ZmVDb2xvck1hdHJpeCB2YWx1ZXM9IjAgMCAwIDAgMCAwIDAgMCAwIDAgMCAwIDAgMCAwIDAgMCAwIDAuMTk5NDczNTA1IDAiIGluPSJzaGFkb3dCbHVyT3V0ZXIxIi8+PC9maWx0ZXI+PGNpcmNsZSBpZD0iYiIgY3g9IjE2IiBjeT0iMTUiIHI9IjE1Ii8+PC9kZWZzPjxnIGZpbGw9Im5vbmUiIGZpbGwtcnVsZT0iZXZlbm9kZCI+PHVzZSBmaWxsPSIjMDAwIiBmaWx0ZXI9InVybCgjYSkiIHhsaW5rOmhyZWY9IiNiIi8+PHVzZSBmaWxsPSIjM0U3M0M0IiB4bGluazpocmVmPSIjYiIvPjx1c2UgZmlsbD0idXJsKCNjKSIgc3R5bGU9Im1peC1ibGVuZC1tb2RlOnNvZnQtbGlnaHQiIHhsaW5rOmhyZWY9IiNiIi8+PGNpcmNsZSBzdHJva2Utb3BhY2l0eT0iLjA5NyIgc3Ryb2tlPSIjMDAwIiBzdHJva2UtbGluZWpvaW49InNxdWFyZSIgY3g9IjE2IiBjeT0iMTUiIHI9IjE0LjUiLz48ZyBmaWxsPSIjRkZGIiBmaWxsLXJ1bGU9Im5vbnplcm8iPjxwYXRoIGQ9Ik0yMC4wMjIgMTcuMTI0YzAtMi4xMjQtMS4yOC0yLjg1Mi0zLjg0LTMuMTU2LTEuODI4LS4yNDMtMi4xOTMtLjcyOC0yLjE5My0xLjU3OCAwLS44NS42MS0xLjM5NiAxLjgyOC0xLjM5NiAxLjA5NyAwIDEuNzA3LjM2NCAyLjAxMSAxLjI3NWEuNDU4LjQ1OCAwIDAwLjQyNy4zMDNoLjk3NWEuNDE2LjQxNiAwIDAwLjQyNy0uNDI1di0uMDZhMy4wNCAzLjA0IDAgMDAtMi43NDMtMi40ODlWOC4xNDJjMC0uMjQzLS4xODMtLjQyNS0uNDg3LS40ODZoLS45MTVjLS4yNDMgMC0uNDI2LjE4Mi0uNDg3LjQ4NnYxLjM5NmMtMS44MjkuMjQyLTIuOTg2IDEuNDU2LTIuOTg2IDIuOTc0IDAgMi4wMDIgMS4yMTggMi43OTEgMy43NzggMy4wOTUgMS43MDcuMzAzIDIuMjU1LjY2OCAyLjI1NSAxLjYzOSAwIC45Ny0uODUzIDEuNjM4LTIuMDExIDEuNjM4LTEuNTg1IDAtMi4xMzMtLjY2Ny0yLjMxNi0xLjU3OC0uMDYtLjI0Mi0uMjQ0LS4zNjQtLjQyNy0uMzY0aC0xLjAzNmEuNDE2LjQxNiAwIDAwLS40MjYuNDI1di4wNmMuMjQzIDEuNTE4IDEuMjE5IDIuNjEgMy4yMyAyLjkxNHYxLjQ1N2MwIC4yNDIuMTgzLjQyNS40ODcuNDg1aC45MTVjLjI0MyAwIC40MjYtLjE4Mi40ODctLjQ4NVYyMC4zNGMxLjgyOS0uMzAzIDMuMDQ3LTEuNTc4IDMuMDQ3LTMuMjE3eiIvPjxwYXRoIGQ9Ik0xMi44OTIgMjMuNDk3Yy00Ljc1NC0xLjctNy4xOTItNi45OC01LjQyNC0xMS42NTMuOTE0LTIuNTUgMi45MjUtNC40OTEgNS40MjQtNS40MDIuMjQ0LS4xMjEuMzY1LS4zMDMuMzY1LS42MDd2LS44NWMwLS4yNDItLjEyMS0uNDI0LS4zNjUtLjQ4NS0uMDYxIDAtLjE4MyAwLS4yNDQuMDZhMTAuODk1IDEwLjg5NSAwIDAwLTcuMTMgMTMuNzE3YzEuMDk2IDMuNCAzLjcxNyA2LjAxIDcuMTMgNy4xMDIuMjQ0LjEyMS40ODggMCAuNTQ4LS4yNDMuMDYxLS4wNi4wNjEtLjEyMi4wNjEtLjI0M3YtLjg1YzAtLjE4Mi0uMTgyLS40MjQtLjM2NS0uNTQ2em02LjQ2LTE4LjkzNmMtLjI0NC0uMTIyLS40ODggMC0uNTQ4LjI0Mi0uMDYxLjA2MS0uMDYxLjEyMi0uMDYxLjI0M3YuODVjMCAuMjQzLjE4Mi40ODUuMzY1LjYwNyA0Ljc1NCAxLjcgNy4xOTIgNi45OCA1LjQyNCAxMS42NTMtLjkxNCAyLjU1LTIuOTI1IDQuNDkxLTUuNDI0IDUuNDAyLS4yNDQuMTIxLS4zNjUuMzAzLS4zNjUuNjA3di44NWMwIC4yNDIuMTIxLjQyNC4zNjUuNDg1LjA2MSAwIC4xODMgMCAuMjQ0LS4wNmExMC44OTUgMTAuODk1IDAgMDA3LjEzLTEzLjcxN2MtMS4wOTYtMy40Ni0zLjc3OC02LjA3LTcuMTMtNy4xNjJ6Ii8+PC9nPjwvZz48L3N2Zz4=";


    fun init(witness: USDC, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            6,
            b"USDC",
            b"USDC",
            b"Test StableCoin USDC",
            option::some<Url>(url::new_unsafe_from_bytes(USDC_SVG)),
            ctx
        );
        let coin = coin::mint<USDC>(&mut treasury, 10000*math::pow(10, 6), ctx);
        transfer::public_transfer(coin, tx_context::sender(ctx));
        transfer::public_freeze_object(metadata);
        transfer::public_share_object(treasury)
    }

    entry fun mint (cap: &mut coin::TreasuryCap<USDC>, value:u64, ctx: &mut TxContext){
        let coin = coin::mint<USDC>(cap, value, ctx);
        transfer::public_transfer(
            coin,
            tx_context::sender(ctx)
        )
    }

    #[test_only] public fun deploy_coin(ctx: &mut TxContext){
        init(USDC{}, ctx);
    }

    //TODO: add high level mint function
}