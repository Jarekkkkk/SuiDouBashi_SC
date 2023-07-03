module suiDouBashi_amm::amm_math{
    use std::type_name;
    use sui::math;

    const SCALE_FACTOR: u256 = 1_000_000_000_000_000_000;

    const ERR_INVALD_FEE:u64 = 001;

    public fun k_(res_x: u64, res_y: u64, scale_x: u64, scale_y: u64): u256 {
        // x^3y + xy^3 = k
        let _x = (res_x as u256) * SCALE_FACTOR / (scale_x as u256);
        let _y = (res_y as u256) * SCALE_FACTOR / (scale_y as u256);
        let _a = (_x * _y ) / SCALE_FACTOR;
        let _b =(( _x * _x) / SCALE_FACTOR) + (( _y * _y) / SCALE_FACTOR) ;

        (_a * _b / SCALE_FACTOR)
    }

    public fun get_output_<X,Y,T>(
        stable: bool,
        dx: u64,
        reserve_x: u64,
        reserve_y: u64,
        decimal_x: u8,
        decimal_y: u8
    ):u64{
        if(type_name::get<X>() == type_name::get<T>()){
            if(stable){
            (stable_swap_output(
                    dx,
                    reserve_x,
                    reserve_y,
                    math::pow(10, decimal_x),
                    math::pow(10, decimal_y)
                ) as u64)
            }else{
                (variable_swap_output( dx, reserve_x, reserve_y) as u64)
            }
        }else{
            if(stable){
            (stable_swap_output(
                    dx,
                    reserve_y,
                    reserve_x,
                    math::pow(10, decimal_y),
                    math::pow(10, decimal_x)
                ) as u64)
            }else{
                (variable_swap_output( dx, reserve_y, reserve_x) as u64)
            }
        }
    }

    /// Action: Swap: swap X for Y
    /// dy = (dx * y) / (dx + x), at dx' = dx(1 - fee)
    public fun variable_swap_output( _dx: u64, _res_x: u64, _res_y: u64): u128{
        let dx = ( _dx as u128 );
         dx * (_res_y as u128) / ( dx + (_res_x as u128))
    }

    public fun stable_swap_output(dx: u64, _res_x: u64, _res_y: u64, _scale_x: u64, _scale_y: u64 ): u256 {
        let scale_x = ( _scale_x as u256);
        let scale_y = ( _scale_y as u256);
        let xy = k_(_res_x, _res_y, _scale_x, _scale_y);

        let res_x_ = (( _res_x as u256)  * SCALE_FACTOR) / scale_x ;
        let res_y_ = (( _res_y as u256)  * SCALE_FACTOR) / scale_y ;

        let input_x_ = (( dx as u256)  * SCALE_FACTOR ) / scale_x ;
        let output_y = res_y_ -  get_y(input_x_ + res_x_, xy, res_y_);

        output_y * scale_y  / SCALE_FACTOR
    }

    /// Calculate optimized one-side adding liquidity ( Variable Pool )
    public fun zap_optimized_input(res_x: u256, input_x: u256, fee: u8):u64{
        assert!(fee >= 10 && fee <= 50, ERR_INVALD_FEE);
        // let var_1 = ( 4 * scaling_ * scaling_ - 4 * fee_ * scaling_ + fee_ * fee_);
        // let var_2 =  4 * scaling_ * scaling_ -  4 * fee_ * scaling_ ;
        // let var_3 = ( 2 * scaling_ - fee_);
        // let var_4 = 2 * ( scaling_ - fee_);
        let (var_1, var_2, var_3, var_4) = if(fee == 10){
            (399_600_100, 399_600_000, 19_990, 19_980)
        }else if(fee == 20){
            (399_200_400, 399_200_000, 19_980, 19_960)
        }else if(fee == 30){
            (398_880_900, 398_800_000, 19_970, 19_940)
        }else if(fee == 40){
            (398_401_600, 398_400_000, 19_960, 19_920)
        }else{ // 0.5%
            (398_002_500, 398_000_000, 19_950, 19_900)
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

    public fun max_u128(x: u128, y: u128): u128 {
        if (x > y) {
            x
        } else {
            y
        }
    }

    public fun max_u256(x: u256, y: u256): u256 {
        if (x > y) {
            x
        } else {
            y
        }
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