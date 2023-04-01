module suiDouBashi::amm_v1_oracle{
    use sui::clock::{Self, Clock};
    use suiDouBashi::amm_v1::{Self, Pool};
    use suiDouBashi::uq128x128;

    public fun current_block_timestamp(clock: &Clock):u32{
        (clock::timestamp_ms(clock) % ( 2^32 ) as u32)
    }

    public fun current_cumulative_price<V,X,Y>
    (pool: &Pool<X,Y>,
    clock: &Clock
    ):(u256, u256)
    {
        let timestamp = current_block_timestamp(clock);
        let last_timestamp = amm_v1::get_last_timestamp(pool);
        let (cumulative_price_x, cumulative_price_y) = amm_v1::get_cumulative_prices(pool);
        let (_res_x, _res_y, _) = amm_v1::get_reserves(pool);
        let res_x = ( _res_x as u128 );
        let res_y = ( _res_y as u128 );

        if(timestamp != last_timestamp ){
            let elapsed = ((timestamp - last_timestamp) as u256);
            let p_0 = uq128x128::to_u256(uq128x128::div(uq128x128::encode(res_y), res_x));
            let p_1 = uq128x128::to_u256(uq128x128::div(uq128x128::encode(res_x), res_y));
            cumulative_price_x = cumulative_price_x + cumulative_price_x + p_0 * elapsed;
            cumulative_price_y = cumulative_price_y + cumulative_price_y + p_1 * elapsed;
        };

        (cumulative_price_x, cumulative_price_y)
    }
}