module suiDouBashi_vest::err{
    const Prefix: u64 = 000000;

    // - Reg
    public fun already_reigster(): u64 { Prefix + 201 }
    public fun OTW(): u64 { Prefix + 202 }
    public fun invalid_module(): u64 { Prefix + 203 }
    // - VSDB
    public fun invalid_guardian(): u64 { Prefix + 200 }

    public fun zero_input(): u64{ Prefix + 201 }

    public fun invalid_lock_time(): u64 { Prefix + 202 }

    public fun locked(): u64 { Prefix + 203 }

    public fun empty_locked_balance(): u64{ Prefix + 204 }

    public fun empty_coin(): u64{ Prefix + 205 }

    public fun invalid_owner(): u64{ Prefix + 206 }

    public fun invalid_type_argument(): u64{ Prefix + 206 }

    public fun reward_not_exist(): u64 { Prefix + 207 }

    public fun pure_vsdb(): u64 { Prefix + 208 }

    // - Reward
    public fun max_reward(): u64 { Prefix + 209 }
    public fun invalid_reward_rate(): u64 { Prefix + 210 }

    // -Bribe
    public fun insufficient_bribes(): u64 { Prefix + 211 }
    public fun insufficient_voting(): u64 { Prefix + 212 }
    // - Gauge
    public fun already_stake(): u64 { Prefix + 211 }
    public fun invalid_staker(): u64 { Prefix + 212 }

    public fun empty_lp(): u64 { Prefix + 212 }
    public fun dead_gauge(): u64 { Prefix + 211 }
    public fun zero_fees(): u64 { Prefix + 212 }
    public fun insufficient_lp(): u64{ Prefix + 212 }

    // - Vote
    public fun already_voted(): u64 { Prefix + 212 }
    public fun invalid_voter(): u64 { Prefix + 213 }
    public fun invalid_governor(): u64 { Prefix + 213 }
    public fun invalid_emergency(): u64 { Prefix + 214 }
    public fun invalid_team(): u64 { Prefix + 215 }
    public fun non_whitelist(): u64 { Prefix + 215 }
    public fun invalid_weight(): u64 { Prefix + 216 }

    // - Minter
    public fun max_rate(): u64{ Prefix + 217 }

    // - Distributor
    public fun invalid_depositor(): u64{ Prefix + 218 }

}