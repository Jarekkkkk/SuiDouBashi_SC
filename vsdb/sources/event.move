module suiDouBashi_vsdb::event{
    use sui::event::emit;
    use sui::object::{ID};
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
}