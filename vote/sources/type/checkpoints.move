/// Checkpoints for any kinds of balance, supply, rewards
/// useful when contract requires massive interactions and rewards calculations
/// All the checkpoints don't have copy ability to protect each checkpoint
module suiDouBashi_vote::checkpoints{

    ///checkpoint for marking reward rate
    struct RewardPerTokenCheckpoint has store {
        timestamp: u64,
        reward_per_token: u256
    }

    ///checkpoint for marking supply
    struct SupplyCheckpoint has store {
        timestamp: u64,
        supply: u64
    }

    ///checkpoint for marking balance
    struct BalanceCheckpoint has store {
        timestamp: u64,
        balance: u64
    }

    public fun new_rp(timestamp: u64, reward_per_token: u256):RewardPerTokenCheckpoint{
        RewardPerTokenCheckpoint{
            timestamp,
            reward_per_token
        }
    }
    public fun reward_ts(r: &RewardPerTokenCheckpoint):u64 { r.timestamp }
    public fun reward(r: &RewardPerTokenCheckpoint):u256 { r.reward_per_token }


    public fun new_sp(timestamp: u64, supply: u64):SupplyCheckpoint{
        SupplyCheckpoint{
            timestamp,
            supply
        }
    }
    public fun supply_ts(s: &SupplyCheckpoint):u64 { s.timestamp }
    public fun supply(s: &SupplyCheckpoint):u64 { s.supply }


    public fun new_cp(timestamp: u64, balance: u64):BalanceCheckpoint{
        BalanceCheckpoint{
            timestamp,
            balance
        }
    }
    public fun balance_ts(c: &BalanceCheckpoint):u64 { c.timestamp }
    public fun balance(c: &BalanceCheckpoint):u64 { c.balance }


    // ===== Setter =====
    public fun update_reward(r: &mut RewardPerTokenCheckpoint, v: u256){
        r.reward_per_token = v;
    }

    public fun update_supply(s: &mut SupplyCheckpoint, v: u64){
        s.supply = v;
    }

    public fun update_balance(c: &mut BalanceCheckpoint, v: u64){
        c.balance = v
    }

}