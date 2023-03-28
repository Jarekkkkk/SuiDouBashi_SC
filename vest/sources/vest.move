module suiDouBashiVest::vest{
    use sui::object::{Self, UID, ID};
    use sui::balance::{Self, Supply, Balance};
    use sui::coin::{Self};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::vector as vec;
    use sui::table::{Self, Table};
    use std::option::{Self, Option};


    use suiDouBashiVest::err;
    use suiDouBashiVest::point::{Self, Point};
    use suiDouBashiVest::sdb::{Self, SDB};
    use suiDouBashiVest::vsdb::{Self, VSDB};
    use suiDouBashi::i128::{Self, I128};
    use suiDouBashi::i256::{Self, I256};

    // mocked time
    use suiDouBashiVest::fake_time;

    const WEEK: u64 = { 7 * 86400 };
    const YEAR: u256 = { 365 * 86400 };
    const MULTIPLIER: u256 = 1_000_000_000_000_000_000;

    // # 1 +        /
    // #   |      /
    // #   |    /
    // #   |  /
    // #   |/
    // # 0 +--------+------> time
    // #  maxtime (4 years)
    const MAX_TIME: u256 = { 4 * 365 * 86400 };


    // ===== OTW =====

    struct VSDBCap has key, store { id: UID }

    struct VSDBRegistry has key {
        id: UID,
        sdb_supply: Supply<SDB>,
        gov: address,
        minted_vsdb:vector<u8>,

        /// this epoch is different from POS
        epoch: u256,
        point_history: Table<u256, Point>, //epoch -> Point
        slope_changes: Table<u64, I128> // ts -> slope
    }


    struct CheckPoint has store {
        timestamp: u256,
        // TODO: dynamic fields to store, if no need of accessing into tokens, we could replaced with
        // Table <ts, token_amounts>
        tokenIds: vector<ID>
    }



    // ===== assertion =====
    fun assert_gov(reg: & VSDBRegistry, ctx: &mut TxContext){
        assert!(reg.gov == tx_context::sender(ctx), err::invalid_guardian());
    }

    // ===== entry =====


    // ===== MAIN_LOGIC =====
    /// This function should be explictly called as we are unable to call init execution in SDB module
    fun create(ctx: &mut TxContext){
        transfer::transfer(VSDBCap { id: object::new(ctx) }, tx_context::sender(ctx));
        transfer::share_object(
            VSDBRegistry {
                id: object::new(ctx),
                sdb_supply: sdb::new(ctx),
                gov: tx_context::sender(ctx),
                minted_vsdb: vec::empty<u8>(),

                epoch:0,
                point_history: table::new<u256, Point>(ctx),
                slope_changes: table::new<u64, I128>(ctx)
            }
        )
    }

    /// None -> update global checkpoint
    /// Some -> update both global & player's checkpoint
    fun checkpoint_(reg: &mut VSDBRegistry, vsdb: &mut Option<VSDB>){
        // let old_dslope = i128::zero();
        // let new_dslope = i128::zero();

        // let slope_0 = 0;
        // let bias_0 = 0;
        // let slope_1 = 0;
        // let bias_1 = 0;

        let time_stamp =  fake_time::ts();
        let block_num =  fake_time::bn();
        let epoch = reg.epoch;

        // // update calculate repsecitve slope & bias
        // if(option::is_some(vsdb)){
        //     if(locked_0.end > time_stamp && balance::value(&locked_0.balance) > 0){
        //         slope_0 = locked_0.end /  (balance::value(&locked_0.balance) as u256);
        //         bias_0 = slope_0 * (locked_0.end -( fake_time::ts() as u256)); // i256
        //     };

        //     if(locked_1.end > time_stamp && balance::value(&locked_1.balance) > 0){
        //         slope_1 = locked_1.end /  (balance::value(&locked_1.balance) as u256);
        //         bias_1 = slope_0 * (locked_1.end - (fake_time::ts() as u256)); //i256
        //     };

        //     dslope_0 = *table::borrow(&reg.slope_per_ts, locked_0.end);
        //     if(locked_1.end != 0){
        //         if(locked_1.end == locked_0.end){
        //             dslope_1 = dslope_0;
        //         }else{
        //             dslope_1 = *table::borrow(&reg.slope_per_ts, locked_1.end);
        //         }
        //     };
        // };


        // get the latest point
        let last_point = if(reg.epoch > 0){
            // copy the value in table
            *table::borrow(& reg.point_history, reg.epoch)
        }else{
            point::empty()
        };

        let last_checkpoint = point::ts(&last_point);
        let initial_last_point = last_point;

        //calculate dblock/ dt
        let block_slope = if(time_stamp > point::ts(&last_point)){
            MULTIPLIER * ((block_num - point::blk(&last_point)) as u256) / (( time_stamp - point::ts(&last_point)) as u256)
        }else{
            0
        };

        // If last point is already recorded in this block, slope=0

        // But that's ok b/c we know the block in such case

        // Go over weeks to fill history and calculate what the current point is

        let t_i = (last_checkpoint / WEEK) * WEEK; // make sure t_i is multiply of WEEK
        let last_point_bias = point::bias(&last_point);
        let last_point_slope = point::slope(&last_point);

        // update the weekly point
        let i = 0;
        while( i < 255 ){
            t_i = t_i + WEEK;

            let d_slope = i128::zero();
            if( t_i > time_stamp ){
                //latest
                t_i =  time_stamp;
            }else{
                // obsolete point
                d_slope = *table::borrow(&reg.slope_changes, t_i);
            };
            let diff = i128::from(((t_i - last_checkpoint) as u128));
            last_point_bias = i128::sub(&last_point_bias, &i128::mul(&last_point_slope, &diff));
            last_point_slope = i128::add(&last_point_slope, &d_slope);

            let compare_bias = i128::compare(last_point_bias, i128::zero());
            // if last_point_bais <= 0
            if(compare_bias == 1 || compare_bias == 0){
                last_point_bias = I128::zero();
            };
            let compare_slope = i128::compare(last_point_slope, i128::zero());
            // if last_point_slope <= 0
            if(compare_slope == 1 || compare_slope == 0){
                last_point_slope = I128::zero();
            };

            last_checkpoint = t_i;
            latest_point.ts = t_i;
            latest_point.blk = init_latest_point.blk + ( block_slope * (t_i - init_latest_point.ts)) / SCLAE_FACTOR;

            epoch = epoch + 1;
            if(t_i == time_stamp){
                latest_point.blk = block_num;
                break
            }else{
                let point = table::borrow_mut(&mut reg.point_per_epoch, epoch);
                *point = latest_point;
            };

            i = i + 1;
        };

        reg.epoch = epoch;
        // Now point_history is filled until t=now

        // if (option::is_some(&token_id)) {
        //     // If last point was in this block, the slope change has been applied already
        //     // But in such case we have 0 slope(s)
        //     latest_point.slope = latest_point.slope + (slope_1 - slope_0);
        //     latest_point.bias = latest_point.bias + (bias_1 - bias_0);
        //     if (latest_point.slope < 0) {
        //         latest_point.slope = 0;
        //     };
        //     if (latest_point.bias < 0) {
        //         latest_point.bias = 0;
        //     };
        // };

        // if(option::is_some(&token_id)){
        //     // Schedule the slope changes (slope is going down)
        //     // We subtract new_user_slope from [new_locked.end]
        //     // and add old_user_slope to [old_locked.end]
        //     if (locked_0.end > time_stamp) {
        //         // old_dslope was <something> - u_old.slope, so we cancel that
        //         dslope_0 = dslope_0 + slope_0;
        //         if (locked_1.end == locked_0.end) {
        //             dslope_0 = dslope_0 - slope_1; // It was a new deposit, not extension
        //         };
        //         let slope = table::borrow_mut(&mut reg.slope_per_ts, locked_0.end);
        //         *slope = dslope_0;
        //     };

        //     if (locked_1.end > time_stamp) {
        //         if (locked_1.end > locked_0.end) {
        //             dslope_1 = dslope_1 - slope_1; // old slope disappeared at this point
        //             let slope = table::borrow_mut(&mut reg.slope_per_ts, locked_1.end);
        //             *slope = dslope_1;
        //         };
        //         // else: we recorded it already in old_dslope
        //     };
        //     // Now handle user history
        //     let user_epoch = table::borrow_mut(&mut reg.user_point_epoch, option::extract(&mut token_id));


        //     user_point_epoch[_tokenId] = user_epoch;
        //     u_new.ts = block.timestamp;
        //     u_new.blk = block.number;
        //     user_point_history[_tokenId][user_epoch] = u_new;
        // };
    }
}