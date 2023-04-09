module suiDouBashiVest::event{
    use sui::event::emit;
    use sui::object::{ID};

    // - VSDB
    struct Deposit has copy, drop{
        id: ID,
        locked_value: u64,
        unlock_time: u64
    }

    public fun deposit(id: ID, locked_value: u64, unlock_time: u64){
        emit(
           Deposit{
                id,
                locked_value,
                unlock_time
           }
        )
    }
     struct Withdraw has copy, drop{
        id: ID,
        unlocked_value: u64,
        ts: u64
    }

    public fun withdraw(id: ID, unlocked_value: u64, ts: u64){
        emit(
           Withdraw{
                id,
                unlocked_value,
                ts
           }
        )
    }


    // - Bribe
    struct ClaimRewards has copy, drop{
        claimer: address,
        value: u64
    }

    public fun claim_reward(claimer: address, value: u64){
        emit(
            ClaimRewards{
                claimer,
                value
            }
        )
    }

    struct NotifyRewards<phantom T> has copy, drop{
        from: address,
        value: u64
    }

    public fun notify_reward<T>(from: address, value: u64){
        emit(
            NotifyRewards<T>{
                from,
                value
            }
        )
    }

    // - Gague
    struct ClaimFees has copy, drop{
        from: address,
        claimed_x: u64,
        claimed_y: u64
    }

    public fun claim_fees(from: address, claimed_x: u64, claimed_y: u64){
        emit(
            ClaimFees{
                from,
                claimed_x,
                claimed_y
            }
        )
    }

    struct DepositLP<phantom X, phantom Y> has copy, drop{
        from: address,
        token_id: ID,
        amount: u64
    }

    public fun deposit_lp<X,Y>(from: address, token_id: ID, amount: u64){
        emit(
            DepositLP<X,Y>{
                from,
                token_id,
                amount
            }
        )
    }
    struct WithdrawLP<phantom X, phantom Y> has copy, drop{
        from: address,
        token_id: ID,
        amount: u64
    }

    public fun withdraw_lp<X,Y>(from: address, token_id: ID, amount: u64){
        emit(
            WithdrawLP<X,Y>{
                from,
                token_id,
                amount
            }
        )
    }
}