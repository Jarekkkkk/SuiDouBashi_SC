module suiDouBashi::math{

    /// babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
     public fun sqrt_u256(y: u256):u256 {
        let z = 0;
        if (y > 3) {
            z = y;
            let x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        };
        z
    }

    #[test] fun test_sqrt256(){
        let foo = sqrt_u256(3);
        let bar = sqrt_u256(100);

        let baz = sqrt_u256(289465520400);

        assert!(foo == 1, 0);
        assert!(bar == 10, 0);
        assert!(baz == 538020, 1);
    }
}