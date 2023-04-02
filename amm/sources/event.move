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
    struct PoolCreated<phantom X, phantom Y> has copy, drop{
        pool_id: ID,
        creator: address
    }
    struct LiquidityAdded<phantom X, phantom Y> has copy, drop{
        deposit_x: u64,
        deposit_y: u64,
        lp_token: u64
    }
    struct LiquidityRemoved<phantom X, phantom Y> has copy, drop{
        withdrawl_x: u64,
        withdrawl_y: u64,
        burned_lp: u64
    }
    struct Swap<phantom X, phantom Y> has copy, drop{
        input: u64,
        output: u64,
    }
    struct OracleUpdated<phantom X, phantom Y> has copy, drop {
        last_price_cumulative_x: u128,
        last_price_cumulative_y: u128,
    }
    struct Sync<phantom X, phantom Y> has copy, drop{
        res_x: u64,
        res_y: u64
    }
    struct Fee<phantom X, phantom Y> has copy, drop{
        to: address,
        amount_x: u64,
        amount_y: u64
    }
    struct Claim<phantom X, phantom Y> has copy, drop{
        from: address,
        amount_x: u64,
        amount_y: u64
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
    public fun pool_created <X, Y>(pool_id: ID, creator: address){
        emit(
            PoolCreated<X,Y>{
                pool_id,
                creator
            }
        )
    }
    public fun liquidity_added <X, Y>(deposit_x:u64, deposit_y:u64, lp_token:u64 ){
        emit(
            LiquidityAdded<X, Y>{
                deposit_x,
                deposit_y,
                lp_token
            }
        )
    }
    public fun liquidity_removed <X, Y>(withdrawl_x: u64, withdrawl_y: u64, burned_lp: u64){
        emit(
            LiquidityRemoved<X, Y>{
                withdrawl_x,
                withdrawl_y,
                burned_lp
            }
        )
    }
    public fun swap<X, Y>(input: u64, output: u64){
        emit(
            Swap<X,Y>{
                input,
                output
            }
        )
    }
    public fun sync<X, Y>(res_x: u64, res_y: u64){
        emit(
            Sync<X,Y>{
                res_x,
                res_y
            }
        )
    }
    public fun fee<X, Y>(to: address, amount_x: u64, amount_y: u64){
        emit(
            Fee<X,Y>{
                to,
                amount_x,
                amount_y
            }
        )
    }
    public fun claim<X, Y>(from: address, amount_x: u64, amount_y: u64){
        emit(
            Claim<X,Y>{
                from,
                amount_x,
                amount_y
            }
        )
    }


}