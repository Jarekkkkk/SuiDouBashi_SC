module suiDouBashiVest::err{
    const Prefix: u64 = 000000;

    public fun invalid_guardian():u64 { Prefix + 200 }

    public fun zero_input(): u64{ Prefix + 201 }

    public fun invalid_lock_time():u64 { Prefix + 202 }

    public fun locked():u64 { Prefix + 203 }

    public fun empty_locked_balance():u64{ Prefix + 204 }

    public fun emptry_coin(): u64{ Prefix + 205 }

    public fun invalid_owner(): u64{ Prefix + 206 }

}