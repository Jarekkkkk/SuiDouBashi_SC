module suiDouBashiVest::point{
    use suiDouBashi::i128::{Self, I128};



    struct Point has store, copy, drop{
        bias: I128,
        slope: I128, // # -dweight / dt
        ts: u64,
    }

    public fun empty (): Point{
        Point {
            bias: i128::zero(),
            slope: i128::zero(),
            ts: 0
        }
    }

    public fun from(bias: I128, slope: I128, ts: u64): Point{
        Point{
            bias,
            slope,
            ts,
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