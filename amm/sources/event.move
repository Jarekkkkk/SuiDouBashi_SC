module suiDouBashi::event{
    use sui::event::emit;
    use sui::object::{ID};

    // == event ==

    // - Profile
    struct ItemAdded<phantom T> has copy, drop {
        profile_id: ID,
        did_id: ID
    }
    struct ItemRemoved<phantom T> has copy, drop {
        profile_id: ID,
        did_id: ID,
    }
    // - AMM
    struct GuardianAdded has copy, drop{
        guardian: address
    }
    struct PoolCreated<phantom V, phantom X, phantom Y> has copy, drop{
        pool_id: ID,
        creator: address
    }
    struct LiquidityAdded<phantom V, phantom X, phantom Y> has copy, drop{
        deposit_x: u64,
        deposit_y: u64,
        lp_token: u64
    }
    struct LiquidityRemoved<phantom V, phantom X, phantom Y> has copy, drop{
        withdrawl_x: u64,
        withdrawl_y: u64,
        burned_lp: u64
    }
    struct Swap<phantom V, phantom X, phantom Y> has copy, drop{
        input: u64,
        output: u64,
    }
    struct OracleUpdated<phantom V, phantom X, phantom Y> has copy, drop {
        last_price_cumulative_x: u128,
        last_price_cumulative_y: u128,
    }

    // - ESCROW
    struct Deposit {}
    struct Withdraw {}
    struct Supply {}

    // - Profile
    public fun item_added<T>(profile_id:ID, did_id: ID){
        emit(
            ItemAdded<T>{
                profile_id,
                did_id
            }
        );
    }
    public fun item_removed<T>(profile_id:ID, did_id: ID){
        emit(
            ItemRemoved<T>{
                profile_id,
                did_id
            }
        );
    }

    // - AMM_v1
    public fun guardian_added(guardian: address){
        emit(
            GuardianAdded{
                guardian
            }
        )
    }
    public fun pool_created<V, X, Y>(pool_id: ID, creator: address){
        emit(
            PoolCreated<V, X, Y>{
                pool_id,
                creator
            }
        )
    }
    public fun liquidity_added<V, X, Y>(deposit_x:u64, deposit_y:u64, lp_token:u64 ){
        emit(
            LiquidityAdded<V, X, Y>{
                deposit_x,
                deposit_y,
                lp_token
            }
        )
    }
    public fun liquidity_removed<V, X, Y>(withdrawl_x: u64, withdrawl_y: u64, burned_lp: u64){
        emit(
            LiquidityRemoved<V, X, Y>{
                withdrawl_x,
                withdrawl_y,
                burned_lp
            }
        )
    }
    public fun swap<V, X, Y>(input: u64, output: u64){
        emit(
            Swap<V, X, Y>{
                input,
                output
            }
        )
    }

    // - ESCROW

}