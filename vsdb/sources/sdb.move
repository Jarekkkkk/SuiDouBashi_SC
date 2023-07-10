module suiDouBashi_vsdb::sdb{
    use std::option;
    use sui::coin::{Self};
    use sui::transfer;
    use sui::tx_context::{TxContext};
    use sui::url::{Self, Url};
    use sui::tx_context;


    struct SDB has drop {}

    const DECIMALS: u8 = 9;
    const SDB_SVG: vector<u8> = b"data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA1MTIgNTEyIiBzdHlsZT0iZW5hYmxlLWJhY2tncm91bmQ6bmV3IDAgMCA1MTIgNTEyIiB4bWw6c3BhY2U9InByZXNlcnZlIj4KICA8cGF0aCBzdHlsZT0iZmlsbDojOTNjNWZkIiBkPSJNMjU2IDUxMkMxMTQuODM5IDUxMiAwIDM5Ny4xNjEgMCAyNTZTMTE0LjgzOSAwIDI1NiAwczI1NiAxMTQuODM5IDI1NiAyNTYtMTE0LjgzOSAyNTYtMjU2IDI1NnoiLz4KICA8cGF0aCBzdHlsZT0iZmlsbDojZmZmIiBkPSJNNTEyIDI1NkM1MTIgMTE0LjgzOSAzOTcuMTYxIDAgMjU2IDB2NTEyYzE0MS4xNjEgMCAyNTYtMTE0LjgzOSAyNTYtMjU2eiIvPgogIDxwYXRoIHN0eWxlPSJmaWxsOiNmZmYiIGQ9Ik0zNTYuMTk2IDMzOS40OTZjLTkuMjA4IDAtMTYuNjk5LTcuNDkxLTE2LjY5OS0xNi42OTlWMTcyLjUwNGgxNi42OTljOS4yMjUgMCAxNi42OTktNy40NzUgMTYuNjk5LTE2LjY5OSAwLTkuMjI1LTcuNDc1LTE2LjY5OS0xNi42OTktMTYuNjk5SDE1NS44MDRjLTkuMjI1IDAtMTYuNjk5IDcuNDc1LTE2LjY5OSAxNi42OTkgMCA5LjIyNSA3LjQ3NSAxNi42OTkgMTYuNjk5IDE2LjY5OWgxNi42OTl2MTgzLjY5MmMwIDkuMjI1IDcuNDc1IDE2LjY5OSAxNi42OTkgMTYuNjk5IDkuMjI1IDAgMTYuNjk5LTcuNDc1IDE2LjY5OS0xNi42OTlWMTcyLjUwNGgxMDAuMTk3djE1MC4yOTRjMCAyNy42MjUgMjIuNDczIDUwLjA5OCA1MC4wOTggNTAuMDk4IDkuMjI1IDAgMTYuNjk5LTcuNDc1IDE2LjY5OS0xNi42OTkgMC05LjIyNi03LjQ3NS0xNi43MDEtMTYuNjk5LTE2LjcwMXoiLz4KICA8cGF0aCBzdHlsZT0iZmlsbDojOTNjNWZkIiBkPSJNMzU2LjE5NiAzMzkuNDk2Yy05LjIwOCAwLTE2LjY5OS03LjQ5MS0xNi42OTktMTYuNjk5VjE3Mi41MDRoMTYuNjk5YzkuMjI1IDAgMTYuNjk5LTcuNDc1IDE2LjY5OS0xNi42OTkgMC05LjIyNS03LjQ3NS0xNi42OTktMTYuNjk5LTE2LjY5OUgyNTZ2MzMuMzk5aDUwLjA5OHYxNTAuMjk0YzAgMjcuNjI1IDIyLjQ3MyA1MC4wOTggNTAuMDk4IDUwLjA5OCA5LjIyNSAwIDE2LjY5OS03LjQ3NSAxNi42OTktMTYuNjk5IDAtOS4yMjctNy40NzUtMTYuNzAyLTE2LjY5OS0xNi43MDJ6Ii8+Cjwvc3ZnPgo=";

    // TODO: First Minted Coin
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
}