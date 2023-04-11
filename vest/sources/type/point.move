module suiDouBashiVest::point{
    use suiDouBashi::i128::{ I128};

    struct Point has store, copy, drop{
        bias: I128,
        slope: I128, // # -dweight / dt
        ts: u64, // t_i (week_based)
    }

    public fun from(bias: I128, slope: I128, ts: u64): Point{
        Point{
            bias,
            slope,
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