module suiDouBashi_amm::amm_math{
    public fun mul_sqrt(x:u64, y:u64): u64{
        (sqrt_u128( (x as u128) * (y as u128)) as u64)
    }
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
}