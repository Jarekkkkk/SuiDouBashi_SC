module suiDouBashi::i256 {

    // Error
    const INVALID_ARGUMENT:u64 = 1000;

    const MAX_I256_AS_U256: u256 = (1 << 255) - 1;

    const U256_WITH_FIRST_BIT_SET: u256 = 1 << 255;

    /// When both `U256` equal.
    const EQUAL: u8 = 0;

    /// When `a` is less than `b`.
    const LESS_THAN: u8 = 1;

    /// When `b` is greater than `b`.
    const GREATER_THAN: u8 = 2;

    /// @dev When trying to convert from a u256 > MAX_I128_AS_U128 to an I256.
    const ECONVERSION_FROM_U256_OVERFLOW: u64 = 0;

    /// @dev When trying to convert from an negative I256 to a u256.
    const ECONVERSION_TO_U256_UNDERFLOW: u64 = 1;

    /// @notice Struct representing a signed 256-bit integer.
    struct I256 has copy, drop, store {
        bits: u256
    }

    /// @notice Casts a `u256` to an `I256`.
    public fun from(x: u256): I256 {
        assert!(x <= MAX_I256_AS_U256, INVALID_ARGUMENT);
        I256 { bits: x }
    }

    /// @notice Creates a new `I256` with value 0.
    public fun zero(): I256 {
        I256 { bits: 0 }
    }

    /// @notice Casts an `I256` to a `u256`.
    public fun as_u256(x: &I256): u256 {
        assert!(x.bits < U256_WITH_FIRST_BIT_SET, INVALID_ARGUMENT);
        x.bits
    }

    /// @notice Whether or not `x` is equal to 0.
    public fun is_zero(x: &I256): bool {
        x.bits == 0
    }

    /// @notice Whether or not `x` is negative.
    public fun is_neg(x: &I256): bool {
        x.bits > U256_WITH_FIRST_BIT_SET
    }

    /// @notice Flips the sign of `x`.
    public fun neg(x: &I256): I256 {
        if (x.bits == 0) return *x;
        I256 { bits: if (x.bits < U256_WITH_FIRST_BIT_SET) x.bits | (1 << 255) else x.bits - (1 << 255) }
    }

    /// @notice Flips the sign of `x`.
    public fun neg_from(x: u256): I256 {
        let ret = from(x);
        if (ret.bits > 0) *&mut ret.bits = ret.bits | (1 << 255);
        ret
    }

    /// @notice Absolute value of `x`.
    public fun abs(x: &I256): I256 {
        if (x.bits < U256_WITH_FIRST_BIT_SET) *x else I256 { bits: x.bits - (1 << 255) }
    }

    /// @notice Compare `a` and `b`.
    public fun compare(a: &I256, b: &I256): u8 {
        if (a.bits == b.bits) return EQUAL;
        if (a.bits < U256_WITH_FIRST_BIT_SET) {
            // A is positive
            if (b.bits < U256_WITH_FIRST_BIT_SET) {
                // B is positive
                return if (a.bits > b.bits) GREATER_THAN else LESS_THAN
            } else {
                // B is negative
                return GREATER_THAN
            }
        } else {
            // A is negative
            if (b.bits < U256_WITH_FIRST_BIT_SET) {
                // B is positive
                return LESS_THAN
            } else {
                // B is negative
                return if (a.bits > b.bits) LESS_THAN else GREATER_THAN
            }
        }
    }

    /// @notice Add `a + b`.
    public fun add(a: &I256, b: &I256): I256 {
        if (a.bits >> 255 == 0) {
            // A is positive
            if (b.bits >> 255 == 0) {
                // B is positive
                return I256 { bits: a.bits + b.bits }
            } else {
                // B is negative
                if (b.bits - (1 << 255) <= a.bits) return I256 { bits: a.bits - (b.bits - (1 << 255)) }; // Return positive
                return I256 { bits: b.bits - a.bits } // Return negative
            }
        } else {
            // A is negative
            if (b.bits >> 255 == 0) {
                // B is positive
                if (a.bits - (1 << 255) <= b.bits) return I256 { bits: b.bits - (a.bits - (1 << 255)) }; // Return positive
                return I256 { bits: a.bits - b.bits } // Return negative
            } else {
                // B is negative
                return I256 { bits: a.bits + (b.bits - (1 << 255)) }
            }
        }
    }

    /// @notice Subtract `a - b`.
    public fun sub(a: &I256, b: &I256): I256 {
        if (a.bits >> 255 == 0) {
            // A is positive
            if (b.bits >> 255 == 0) {
                // B is positive
                if (a.bits >= b.bits) return I256 { bits: a.bits - b.bits }; // Return positive
                return I256 { bits: (1 << 255) | (b.bits - a.bits) } // Return negative
            } else {
                // B is negative
                return I256 { bits: a.bits + (b.bits - (1 << 255)) } // Return negative
            }
        } else {
            // A is negative
            if (b.bits >> 255 == 0) {
                // B is positive
                return I256 { bits: a.bits + b.bits } // Return negative
            } else {
                // B is negative
                if (b.bits >= a.bits) return I256 { bits: b.bits - a.bits }; // Return positive
                return I256 { bits: a.bits - (b.bits - (1 << 255)) } // Return negative
            }
        }
    }

    /// @notice Multiply `a * b`.
    public fun mul(a: &I256, b: &I256): I256 {
        if (a.bits >> 255 == 0) {
            // A is positive
            if (b.bits >> 255 == 0) {
                // B is positive
                return I256 { bits: a.bits * b.bits } // Return positive
            } else {
                // B is negative
                return I256 { bits: (1 << 255) | (a.bits * (b.bits - (1 << 255))) } // Return negative
            }
        } else {
            // A is negative
            if (b.bits >> 255 == 0) {
                // B is positive
                return I256 { bits: (1 << 255) | (b.bits * (a.bits - (1 << 255))) } // Return negative
            } else {
                // B is negative
                return I256 { bits: (a.bits - (1 << 255)) * (b.bits - (1 << 255)) } // Return positive
            }
        }
    }

    /// @notice Divide `a / b`.
    public fun div(a: &I256, b: &I256): I256 {
        if (a.bits >> 255 == 0) {
            // A is positive
            if (b.bits >> 255 == 0) {
                // B is positive
                return I256 { bits: a.bits / b.bits } // Return positive
            } else {
                // B is negative
                return I256 { bits: (1 << 255) | (a.bits / (b.bits - (1 << 255))) } // Return negative
            }
        } else {
            // A is negative
            if (b.bits >> 255 == 0) {
                // B is positive
                return I256 { bits: (1 << 255) | ((a.bits - (1 << 255)) / b.bits) } // Return negative
            } else {
                // B is negative
                return I256 { bits: (a.bits - (1 << 255)) / (b.bits - (1 << 255)) } // Return positive
            }
        }
    }

    #[test]
    fun test_compare() {
        assert!(compare(&from(123), &from(123)) == EQUAL, 0);
        assert!(compare(&neg_from(123), &neg_from(123)) == EQUAL, 0);
        assert!(compare(&from(234), &from(123)) == GREATER_THAN, 0);
        assert!(compare(&from(123), &from(234)) == LESS_THAN, 0);
        assert!(compare(&neg_from(234), &neg_from(123)) == LESS_THAN, 0);
        assert!(compare(&neg_from(123), &neg_from(234)) == GREATER_THAN, 0);
        assert!(compare(&from(123), &neg_from(234)) == GREATER_THAN, 0);
        assert!(compare(&neg_from(123), &from(234)) == LESS_THAN, 0);
        assert!(compare(&from(234), &neg_from(123)) == GREATER_THAN, 0);
        assert!(compare(&neg_from(234), &from(123)) == LESS_THAN, 0);
    }

    #[test]
    fun test_add() {
        assert!(add(&from(123), &from(234)) == from(357), 0);
        assert!(add(&from(123), &neg_from(234)) == neg_from(111), 0);
        assert!(add(&from(234), &neg_from(123)) == from(111), 0);
        assert!(add(&neg_from(123), &from(234)) == from(111), 0);
        assert!(add(&neg_from(123), &neg_from(234)) == neg_from(357), 0);
        assert!(add(&neg_from(234), &neg_from(123)) == neg_from(357), 0);

        assert!(add(&from(123), &neg_from(123)) == zero(), 0);
        assert!(add(&neg_from(123), &from(123)) == zero(), 0);
    }

    #[test]
    fun test_sub() {
        assert!(sub(&from(123), &from(234)) == neg_from(111), 0);
        assert!(sub(&from(234), &from(123)) == from(111), 0);
        assert!(sub(&from(123), &neg_from(234)) == from(357), 0);
        assert!(sub(&neg_from(123), &from(234)) == neg_from(357), 0);
        assert!(sub(&neg_from(123), &neg_from(234)) == from(111), 0);
        assert!(sub(&neg_from(234), &neg_from(123)) == neg_from(111), 0);

        assert!(sub(&from(123), &from(123)) == zero(), 0);
        assert!(sub(&neg_from(123), &neg_from(123)) == zero(), 0);
    }

    #[test]
    fun test_mul() {
        assert!(mul(&from(123), &from(234)) == from(28782), 0);
        assert!(mul(&from(123), &neg_from(234)) == neg_from(28782), 0);
        assert!(mul(&neg_from(123), &from(234)) == neg_from(28782), 0);
        assert!(mul(&neg_from(123), &neg_from(234)) == from(28782), 0);
    }

    #[test]
    fun test_div() {
        assert!(div(&from(28781), &from(123)) == from(233), 0);
        assert!(div(&from(28781), &neg_from(123)) == neg_from(233), 0);
        assert!(div(&neg_from(28781), &from(123)) == neg_from(233), 0);
        assert!(div(&neg_from(28781), &neg_from(123)) == from(233), 0);
    }
}