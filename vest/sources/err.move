module suiDouBashiVest::err{
    const Prefix: u64 = 000000;


    public fun invalid_guardian():u64{
        Prefix + 200
    }

}