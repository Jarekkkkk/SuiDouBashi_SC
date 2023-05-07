module suiDouBashi::amm_math{
    /// Maximum of u128 number.
    const MAX_U128: u128 = 340282366920938463463374607431768211455_u128;

    const ERR_DIVIDE_BY_ZERO: u64 = 0;

    public fun mul_div(x: u64, y: u64, z: u64): u64 {
        assert!(z != 0, ERR_DIVIDE_BY_ZERO);
        let r = (x as u128) * (y as u128) / (z as u128);
        (r as u64)
    }

    public fun mul_to_u128(x: u64, y: u64): u128 {
        (x as u128) * (y as u128)
    }

    public fun mul_sqrt(x:u64, y:u64): u64{
        (sqrt_u128( (x as u128) * (y as u128)) as u64)
    }
    /// Get square root of `y`.
    /// Babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    public fun sqrt_u128(y: u128): u128 {
        if (y < 4) {
            if (y == 0) {
                0u128
            } else {
                1u128
            }
        } else {
            let z = y;
            let x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            };
            z
        }
    }

     public fun overflow_add(a: u128, b: u128): u128 {
        let r = MAX_U128 - b;
        if (r < a) {
            return a - r - 1
        };
        r = MAX_U128 - a;
        if (r < b) {
            return b - r - 1
        };

        a + b
    }

}