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

}