module suiDouBashi_vest::checkpoints{

        ///checkpoint for marking reward rate
    struct RewardPerTokenCheckpoint has store {
        timestamp: u64,
        reward_per_token: u128
    }

    ///checkpoint for marking supply
    struct SupplyCheckpoint has store {
        timestamp: u64,
        supply: u64
    }

    ///checkpoint for marking balance
    struct Checkpoint has store {
        timestamp: u64,
        balance: u64
    }

    public fun new_rp(timestamp: u64, reward_per_token: u128):RewardPerTokenCheckpoint{
        RewardPerTokenCheckpoint{
            timestamp,
            reward_per_token
        }
    }
    public fun reward_ts(r: &RewardPerTokenCheckpoint):u64 { r.timestamp }
    public fun reward(r: &RewardPerTokenCheckpoint):u128 { r.reward_per_token }



    public fun new_sp(timestamp: u64, supply: u64):SupplyCheckpoint{
        SupplyCheckpoint{
            timestamp,
            supply
        }
    }
    public fun supply_ts(s: &SupplyCheckpoint):u64 { s.timestamp }
    public fun supply(s: &SupplyCheckpoint):u64 { s.supply }



    public fun new_cp(timestamp: u64, balance: u64):Checkpoint{
        Checkpoint{
            timestamp,
            balance
        }
    }
    public fun balance_ts(c: &Checkpoint):u64 { c.timestamp }
    public fun balance(c: &Checkpoint):u64 { c.balance }


    // ===== Setter =====
    public fun update_reward(r: &mut RewardPerTokenCheckpoint, v: u128){
        r.reward_per_token = v;
    }

    public fun update_supply(s: &mut SupplyCheckpoint, v: u64){
        s.supply = v;
    }

    public fun update_balance(c: &mut Checkpoint, v: u64){
        c.balance = v
    }

}