module suiDouBashiVest::point{
    use suiDouBashi::i128::{Self, I128};
    use suiDouBashi::i256::{Self, I256};

    use suiDouBashiVest::fake_time;

    struct Point has store, copy, drop{
        bias: I128,
        slope: I128, // # -dweight / dt
        ts: u64,
        blk: u64 // block_num assume u64
    }

    public fun empty (): Point{
        Point {
            bias: i128::zero(),
            slope: i128::zero(),
            ts: fake_time::ts(),
            blk: fake_time::bn()
        }
    }

    public fun new(bias: I128, slope: I128, ts: u64, blk: u64): Point{
        Point{
            bias,
            slope,
            ts,
            blk
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
     public fun blk(self: &Point): u64{
        self.blk
    }
}