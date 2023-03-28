module suiDouBashi::err{
    const Prefix: u64 = 000000;

    public fun OTW(): u64{
        // it's likely we could create protocol's OTW in high level way to secure all of our created objects to make sure only we have access to modification
        Prefix + 000
    }
    public fun protocol_locked(): u64{
        Prefix + 001
    }



    // === Profile ===
    public fun invalid_name(): u64{
        Prefix + 100
    }
    public fun invalid_img_url(): u64{
        Prefix + 101
    }
    // === Registry ===
    public fun alreday_registered(): u64{
        Prefix + 102
    }


    // === AMM_v1 ===
    public fun invalid_guardian():u64{
        Prefix + 200
    }
    public fun pool_unlocked():u64{
        Prefix + 201
    }
    public fun zero_amount():u64{
        Prefix + 202
    }
    public fun pool_max_value():u64{
        Prefix + 203
    }
    public fun invalid_fee():u64{
        Prefix + 204
    }
    public fun insufficient_input(): u64{
        Prefix + 205
    }
    public fun slippage(): u64{
        Prefix + 206
    }
    public fun insufficient_liquidity(): u64{
        Prefix + 207
    }
    public fun empty_reserve():u64{
        Prefix + 208
    }
    public fun same_type():u64{
        Prefix + 209
    }
    public fun wrong_pair_ordering():u64{
        Prefix + 210
    }
    public fun below_minimum():u64{
        Prefix + 211
    }
    public fun k_value():u64{
        Prefix + 212
    }
}
