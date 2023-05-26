module suiDouBashi_amm::formula{
    const SCALE_FACTOR: u256 = 1_000_000_000_000_000_000;

    public fun k_(res_x: u64, res_y: u64, scale_x: u64, scale_y: u64): u256 {
        // x^3y + xy^3 = k
        let _x = (res_x as u256) * SCALE_FACTOR / (scale_x as u256);
        let _y = (res_y as u256) * SCALE_FACTOR / (scale_y as u256);

        let _a = (_x * _y ) / SCALE_FACTOR;
        let _b =(( _x * _x) / SCALE_FACTOR) + (( _y * _y) / SCALE_FACTOR) ;

        (_a * _b / SCALE_FACTOR)
    }

    /// Action: Swap: swap X for Y
    /// dy = (dx * y) / (dx + x), at dx' = dx(1 - fee)
    public fun variable_swap_output( _dx: u64, _res_x: u64, _res_y: u64): u128{
        let dx = ( _dx as u128 );
        let n = dx * (_res_y as u128) ;
        let d = dx + (_res_x as u128);
         n / d
    }

    public fun stable_swap_output(dx: u64, _res_x: u64, _res_y: u64, _scale_x: u64, _scale_y: u64 ): u256 {
        let input_x = ( dx as u256);
        let res_x = ( _res_x as u256);
        let res_y = ( _res_y as u256);
        let scale_x = ( _scale_x as u256);
        let scale_y = ( _scale_y as u256);
        let xy = k_(_res_x, _res_y, _scale_x, _scale_y);

        let res_x_ = (res_x  * SCALE_FACTOR) / scale_x ;
        let res_y_ = (res_y  * SCALE_FACTOR) / scale_y ;

        let input_x_ = (input_x  * SCALE_FACTOR ) / scale_x ;

        let output_y = res_y_ -  get_y(input_x_ + res_x_, xy, res_y_);

        let output_y_ = output_y * scale_y  / SCALE_FACTOR;

        output_y_
    }

    /// Calculate optimized one-side adding liquidity
    public fun zap_optimized_input(res_x: u256, input_x: u256, fee_percentage: u8):u64{
        // let var_1 = ( 4 * scaling_ * scaling_ - 4 * fee_ * scaling_ + fee_ * fee_);
        // let var_2 =  4 * scaling_ * scaling_ -  4 * fee_ * scaling_ ;
        // let var_3 = ( 2 * scaling_ - fee_);
        // let var_4 = 2 * ( scaling_ - fee_);
        let (var_1, var_2, var_3, var_4) = if(fee_percentage == 1){
            (399_960_001, 399_960_000, 19_999, 19_998)
        }else if(fee_percentage == 2){
            (399_920_004, 399_920_000, 19_998, 19_996)
        }else if(fee_percentage == 3){
            (399_880_009, 399_880_000, 19_997, 19_994)
        }else if(fee_percentage == 4){
            (399_840_016, 399_840_000, 19_996, 19_992)
        }else{ // 0.05%
            (399_800_025, 399_800_000, 19_995, 19_990)
        };

        (((sqrt_u256( res_x * ( res_x *  var_1 + input_x * var_2)) - res_x * var_3 ) / var_4 ) as u64 )
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
    #[test]
    fun test_varable_swap_output(){
        let input_x = 1200000000;
        let res_x = 4196187624;
        let res_y = 841532386;
        let dx = input_x - input_x * 3 / (10000 as u64);
        let _out = variable_swap_output(dx, res_x, res_y);
        assert!(_out == 187095656, 1);
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
}