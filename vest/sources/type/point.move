module suiDouBashiVest::point{
    use suiDouBashi::i128::{ I128};

    struct Point has store, copy, drop{
        slope: I128, // # -dweight / dt
        bias: I128,
        ts: u64, // week_ts
    }

    public fun new(bias: I128, slope: I128, ts: u64): Point{
        Point{
            slope,
            bias,
            ts, // at which this Point created
        }
    }

    public fun bias(self: &Point): I128{
        self.bias
    }
    public fun slope(self: &Point): I128{
        self.slope
    }
     public fun ts(self: &Point): u64{
        self.ts
    }
}