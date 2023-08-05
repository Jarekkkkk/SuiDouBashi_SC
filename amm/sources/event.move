module suiDouBashi_amm::event{
    use sui::event::emit;
    use sui::object::{ID};

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
        lp_token: u64
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
    struct Fee<phantom T> has copy, drop{
        amount: u64
    }
    struct Claim<phantom X, phantom Y> has copy, drop{
        from: address,
        amount_x: u64,
        amount_y: u64
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
    public fun liquidity_removed <X, Y>(withdrawl_x: u64, withdrawl_y: u64, lp_token: u64){
        emit(
            LiquidityRemoved<X, Y>{
                withdrawl_x,
                withdrawl_y,
                lp_token
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
    public fun fee<T>( amount: u64){
        emit(
            Fee<T>{
                amount
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