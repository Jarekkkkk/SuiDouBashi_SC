//stable curve: X^3Y + X*Y^3 = k
module suiDouBashi::formula{
    const SCALE_FACTOR: u256 = 1_000_000_000_000_000_000;

    use suiDouBashi::math;
    //use suiDouBashi::amm_v1::swap_output as swap;
        /// Action: Swap: swap X for Y
    /// dy = (dx * y) / (dx + x), at dx' = dx(1 - fee)

    public fun variable_swap_output(dx:u256, res_x:u256, res_y:u256): u256{
        let n = dx * res_y ;
        let d = dx + res_x;
         n / d
    }

    public fun k_(res_x: u256, res_y: u256, scale_x: u256, scale_y: u256): u256 {
        // x^3y + xy^3 = k
        let _x = res_x * SCALE_FACTOR / scale_x;
        let _y = res_y * SCALE_FACTOR / scale_y;

        let _a = (_x * _y ) / SCALE_FACTOR;
        let _b =(( _x * _x) / SCALE_FACTOR) + (( _y * _y) / SCALE_FACTOR) ;

        (_a * _b / SCALE_FACTOR)
    }

    public fun stable_swap_output(input_x: u256, res_x: u256, res_y: u256, scale_x: u256, scale_y: u256 ): u256 {
        let xy = k_(res_x, res_y, scale_x, scale_y);

        let res_x_ = (res_x  * SCALE_FACTOR) / scale_x ;
        let res_y_ = (res_y  * SCALE_FACTOR) / scale_y ;

        let input_x_ = (input_x  * SCALE_FACTOR ) / scale_x ;

        let output_y = res_y_ -  get_y(input_x_ + res_x_, xy, res_y_);

        let output_y_ = output_y * scale_y  / SCALE_FACTOR;

        output_y_
    }

    /// calculate splited amount for zapping, functino should be calculated in front end
    public fun zap_optimized_output(res_x: u256, input_x: u256, fee_percentage: u64, scaling: u64):u256{
        let fee_ = ( fee_percentage as u256 );
        let scaling_ = ( scaling as u256);

        let var_1 = ( 4 * scaling_ * scaling_ - 4 * fee_ * scaling_ + fee_ * fee_);
        let var_2 =  4 * scaling_ * scaling_ -  4 * fee_ * scaling_ ;
        let var_3 = ( 2 * scaling_ - fee_);
        let var_4 = 2 * ( scaling_ - fee_);

        (math::sqrt_u256( res_x * ( res_x *  var_1 + input_x * var_2)) - res_x * var_3 ) / var_4
    }

    fun get_y(x0: u256, xy: u256, y: u256): u256 {
        let i = 0;

        while (i < 255) {
            let k = f(x0, y);
            let prev_y = y;

            if( k < xy ){
                let dy = ((xy - k)* SCALE_FACTOR / d(x0, y)) ;
                y = y + dy;
            }else{
                let dy = ((k - xy) * SCALE_FACTOR / d(x0, y));
                y = y - dy;
            };

            if (y > prev_y) {
                if (y - prev_y <= 1) {
                    return y
                }
            } else {
                if (prev_y - y <= 1) {
                    return y
                }
            };

            i = i + 1;
        };

        y
    }

    fun f(x0: u256, y: u256): u256 {
        x0 * (y * y / SCALE_FACTOR * y / SCALE_FACTOR) / SCALE_FACTOR + (x0 * x0 / SCALE_FACTOR * x0 / SCALE_FACTOR) * y / SCALE_FACTOR
        //x0*y^3 + x0^3*y
    }

    fun d(x0: u256, y: u256): u256 {
        3 * x0 * (y * y/ SCALE_FACTOR) / SCALE_FACTOR + (x0 * x0 / SCALE_FACTOR * x0 / SCALE_FACTOR)
        //3*x0*y^2 + x0^3
    }
    #[test]
    fun test_varable_swap_output(){
        let input_x = 1200000000;
        let res_x = 4196187624;
        let res_y = 841532386;
        let dx = input_x - input_x * 3 / (10000 as u256);
        let _out = variable_swap_output(dx, res_x, res_y);



        assert!(_out == 187095656, 1);
    }
    #[test]
    fun test_zap(){
        let _foo = zap_optimized_output(1_000_000, 70_000, 3, 10000);
    }
    #[test]
    fun test_coin_out() {
        let out = stable_swap_output(
            2513_058000,
            25582858_050757,
            25582858_05075712,
            1000000,
            100000000
        );
        assert!(out == 2513_05799999, 0);

    }

    #[test]
    fun test_coin_out_vise_vera() {
        let out = stable_swap_output(
            251305800000,
            2558285805075701,
            25582858050757,
            100000000,
            1000000
        );
        assert!(out == 2513057999, 0);
    }

    // #[test]
    // fun test_f() {
    //     let x0 = 10000518365287;
    //     let y = 2520572000001255;

    //     let r = f(x0 , y );
    //     std::debug::print(&r);
    //     assert!(r == 160149899619106589403934712464197979, 0);

    //     let r = (f(0, 0) as u128 );
    //     assert!(r == 0, 1);
    // }

    // #[test]
    // fun test_d() {
    //     let x0 = 10000518365287;
    //     let y = 2520572000001255;

    //     let z = d(x0, y);
    //     let r = (( z / 100_000_000 ) as u128 );

    //     assert!(r == 1906093763356467088703995764640866982, 0);

    //     let x0 = 5000000000;
    //     let y = 10000000000000000;

    //     let z = d(x0, y);
    //     let r = ( ( z / 100000000) as u128);

    //     assert!(r == 15000000000001250000000000000000000, 1);

    //     let x0 = 1;
    //     let y = 2;

    //     let z = d(x0, y);
    //     let r = (z as u128);
    //     assert!(r == 13, 2);
    // }

    // #[test]
    // fun test_k__compute() {
    //     // 0.3 ^ 3 * 0.5 + 0.5 ^ 3 * 0.3 = 0.051 (12 decimals)
    //     let k_ = k_(300000, 1000000, 500000, 1000000);

    //     assert!(
    //         (k_ as u128 ) == 5100000000000000000000000000000,
    //         0
    //     );

    //     k_ = k_(
    //         500000899318256,
    //         1000000,
    //         25000567572582123,
    //         1000000000000
    //     );

    //     k_ = k_ /  1000000000000000000000000;
    //     assert!((k_ as u128) == 312508781701599715772756132553838833260, 1);
    // }
}