module suiDouBashi_vote::event{
    use sui::event::emit;
    use sui::object::{ID};

    // - Bribe
    struct ClaimReward has copy, drop{
        claimer: address,
        value: u64
    }
    public fun claim_reward(claimer: address, value: u64){
        emit(
            ClaimReward{
                claimer,
                value
            }
        )
    }

    struct NotifyRewards<phantom T> has copy, drop{
        value: u64
    }
    public fun notify_reward<T>(value: u64){
        emit(
            NotifyRewards<T>{
                value
            }
        )
    }

    struct DepositLP<phantom X, phantom Y> has copy, drop{
        from: address,
        amount: u64
    }
    public fun deposit_lp<X,Y>(from: address, amount: u64){
        emit(
            DepositLP<X,Y>{
                from,
                amount
            }
        )
    }

    struct WithdrawLP<phantom X, phantom Y> has copy, drop{
        from: address,
        amount: u64
    }
    public fun withdraw_lp<X,Y>(from: address, amount: u64){
        emit(
            WithdrawLP<X,Y>{
                from,
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

    struct Voted<phantom X, phantom Y> has copy, drop{
        vsdb: ID,
        amount: u64
    }
    public fun voted<X,Y>(vsdb: ID, amount:u64){
        emit(
            Voted<X,Y>{
                vsdb,
                amount
            }
        )
    }

    struct Abstain<phantom X, phantom Y> has copy, drop{
        vsdb: ID,
        amount: u64
    }

    public fun abstain<X,Y>(vsdb: ID, amount:u64){
        emit(
            Abstain<X,Y>{
                vsdb,
                amount
            }
        )
    }

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
}