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

    struct Attach<phantom X, phantom Y> has copy, drop{
        id: ID,
        from: address,
    }
    public fun attach<X,Y>(id: ID, from: address){
        emit(
            Attach<X,Y>{
                id,
                from
            }
        )
    }

    struct Detach<phantom X, phantom Y> has copy, drop{
        id: ID,
        from: address,
    }
    public fun detach<X,Y>(id: ID, from: address){
        emit(
            Detach<X,Y>{
                id,
                from
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

    // - Voter
    struct GaugeCreated<phantom X, phantom Y> has copy, drop{
        pool:ID,
        gauge:ID,
        internal_bribe: ID,
        external_bribe: ID
    }
    public fun gauge_created<X,Y>(pool: ID, gauge: ID, internal_bribe: ID, external_bribe: ID){
       emit(
            GaugeCreated<X,Y>{
                pool,
                gauge,
                internal_bribe,
                external_bribe
            }
       )
    }

    struct Abstain<phantom X, phantom Y, phantom T> has copy, drop{
        vsdb: ID,
        amount: u64
    }
    public fun abstain<X,Y,T>(vsdb: ID, amount:u64){
        emit(
            Abstain<X,Y,T>{
                vsdb,
                amount
            }
        )
    }

    struct Voted<phantom X, phantom Y, phantom T> has copy, drop{
        vsdb: ID,
        amount: u64
    }
    public fun voted<X,Y,T>(vsdb: ID, amount:u64){
        emit(
            Abstain<X,Y,T>{
                vsdb,
                amount
            }
        )
    }

    struct DistributeReward<phantom X, phantom Y> has copy, drop{
        from: address,
        amount: u64
    }
    public fun distribute_reward<X,Y>(from: address, amount: u64){
        emit(
            DistributeReward<X,Y>{
                from,
                amount
            }
        )
    }

    // - Mint
    struct Mint has copy, drop{
        from: address,
        weekly: u64,
        circulating_supply: u64,
        circulating_emission: u64
    }
    public fun mint(from: address, weekly: u64, circulating_supply: u64, circulating_emission: u64){
        emit(
            Mint{
                from,
                weekly,
                circulating_supply,
                circulating_emission
            }
        )
    }

    // - Distribute Fee
    struct VoterNotifyReward has copy, drop{
        amount: u64
    }
    public fun voter_notify_reward(amount: u64){
        emit(
            VoterNotifyReward{
                amount
            }
        )
    }

    // - Distributor
    struct CheckPointToken has copy, drop{
        ts: u64,
        amount: u64
    }
    public fun checkopint_token(ts: u64, amount: u64){
        emit(
            CheckPointToken{
                ts,
                amount
            }
        )
    }

    struct RewardClaimed has copy, drop{
        vsdb: ID,
        to_distribute: u64,
        user_epoch: u64,
        max_user_epoch: u64
    }
    public fun reward_claimed(vsdb: ID, to_distribute: u64, user_epoch: u64, max_user_epoch: u64){
        emit(
            RewardClaimed{
                vsdb,
                to_distribute,
                user_epoch,
                max_user_epoch,
            }
        )
    }

}