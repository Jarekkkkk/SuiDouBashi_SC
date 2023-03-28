// handling binary fixed point numbers, highly inspired by Uniswap's UQ112 X UQ112
//https://github.com/Uniswap/solidity-lib/blob/master/contracts/libraries/FixedPoint.sol
module suiDouBashi::uq128x128{
    const MAX_U128:u128 = 340282366920938463463374607431768211455_u128;
    const MAX_U256: u256 = 115792089237316195423570985008687907853269984665640564039457584007913129639935_u256;

    // range: [0, 2**128 - 1]
    // resolution: 1 / 2**128

    const ERR_DIVIDE_BY_ZERO: u64 = 0;
    const ERR_EQUAL: u8 = 1;
    const ERR_LESS_THAN: u8 = 2;
    const ERR_GREATER_THAN: u8 = 3;

    const Q128: u256 = 340282366920938463463374607431768211455;
    struct UQ128x128 has store, drop{
        v: u256
    }

    public fun encode(x: u128): UQ128x128{
        let v = ( x as u256 ) * Q128;
        UQ128x128{
            v
        }
    }
    spec encode {
        ensures Q128 == MAX_U128;
        ensures result.v == x * Q128;
        ensures result.v <= MAX_U128;
    }

    public fun decode(uq: UQ128x128): u128 {
        ((uq.v / Q128) as u128)
    }
    spec decode {
        ensures result == uq.v / Q128;
    }


    public fun to_u256(uq: UQ128x128): u256 {
        uq.v
    }
    spec to_u256{
        ensures result == uq.v;
    }

    /// Multiply a `UQ128x128` by a `u128`, returning a `UQ128x128`
    public fun mul(uq: UQ128x128, y: u128): UQ128x128 {
        // vm would direct abort when overflow occured
        let v = uq.v * (y as u256);

        UQ128x128{ v }
    }
    spec mul {
        ensures result.v == uq.v * y;
        ensures result.v <= MAX_U256;
    }

    /// Divide a `UQ128x128` by a `u128`, returning a `UQ128x128`.
    public fun div(uq: UQ128x128, y: u128): UQ128x128 {
        assert!(y != 0, ERR_DIVIDE_BY_ZERO);

        let v = uq.v / (y as u256);
        UQ128x128{ v }
    }
    spec div {
        aborts_if y == 0 with ERR_DIVIDE_BY_ZERO;
        ensures result.v == uq.v / y;
    }

    /// Returns a `UQ128x128` which represents the ratio of the numerator to the denominator.
    public fun fraction(numerator: u128, denominator: u128): UQ128x128 {
        assert!(denominator != 0, ERR_DIVIDE_BY_ZERO);

        let r = (numerator as u256) * Q128;
        let v = r / (denominator as u256);

        UQ128x128{ v }
    }
    spec fraction {
        aborts_if denominator == 0 with ERR_DIVIDE_BY_ZERO;
        ensures result.v == numerator * Q128 / denominator;
    }

    /// Compare two `UQ128x128` numbers.
    public fun compare(left: &UQ128x128, right: &UQ128x128): u8 {
        if (left.v == right.v) {
            return ERR_EQUAL
        } else if (left.v < right.v) {
            return ERR_LESS_THAN
        } else {
            return ERR_GREATER_THAN
        }
    }
    spec compare {
        ensures left.v == right.v ==> result == ERR_EQUAL;
        ensures left.v < right.v ==> result == ERR_LESS_THAN;
        ensures left.v > right.v ==> result == ERR_GREATER_THAN;
    }

    /// Check if `UQ128x128` is zero
    public fun is_zero(uq: &UQ128x128): bool {
        uq.v == 0
    }
    spec is_zero {
        ensures uq.v == 0 ==> result == true;
        ensures uq.v > 0 ==> result == false;
    }


    fun test(numerator: u64, denominator: u64){
        let u_128 = (numerator as u128);
        let d_128 = (denominator as u128);

        let uq_fraction = fraction(u_128, d_128);
        let _uq_256 = to_u256(uq_fraction);
    }


    #[test]
    fun test_uq128(){
        let numerator:u64 = 100;
        let denominator:u64 = 400;

        test(numerator, denominator);
    }
}