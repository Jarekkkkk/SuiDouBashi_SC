module suiDouBashiVest::point{
    use suiDouBashi::i128::{Self, I128};
    use suiDouBashi::i256::{Self, I256};


    struct Point has store, copy, drop{
        bias: I128,
        slope: I128, // # -dweight / dt
        ts: u256,
        blk: u256 // block
    }

    public fun bias(self: &Point): I128{
        self.bias
    }
    public fun slope(self: &Point): I128{
        self.slope
    }
}