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

    use suiDouBashi::i128::{Self, I128};
    use suiDouBashi::i256::{Self, I256};

    // mocked time
    use suiDouBashi::fake_time;

    const WEEK: u256 = { 7 * 86400 };
    const YEAR: u256 = { 365 * 86400 };
    const SCLAE_FACTOR: u256 = 1_000_000_000_000_000_000;

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

        epoch: u256,
        user_point_epoch: Table<ID, u256>,
        user_point_history: Table<u256, Point>,
        slope_changes: Table<u256, u256>
    }

    struct Point has store, copy, drop{
        bias: I128,
        slope: I128, // # -dweight / dt
        ts: u256,
        blk: u256 // block
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
                user_point_epoch: table::new<ID, u256>(ctx),
                user_point_history: table::new<u256, Point>(ctx),
                slope_changes: table::new<u256, u256>(ctx)
            }
        )
    }
    /// locked_0: old
    /// locked_1: new
    fun checkpoint_(reg: &mut VSDBRegistry, token_id: Option<ID>, locked_0: &LockedSDB, locked_1: &LockedSDB){
        let dslope_0 = 0;
        let dslope_1 = 0;


        let slope_0 = 0;
        let bias_0 = 0;
        let slope_1 = 0;
        let bias_1 = 0;

        let time_stamp = ( fake_time::ts() as u256 );
        let block_num = ( fake_time::block_num() as u256);
        let epoch = reg.epoch;

        // update calculate repsecitve slope & bias
        if(option::is_some(&token_id)){
            if(locked_0.end > time_stamp && balance::value(&locked_0.balance) > 0){
                slope_0 = locked_0.end /  (balance::value(&locked_0.balance) as u256);
                bias_0 = slope_0 * (locked_0.end -( fake_time::ts() as u256)); // i256
            };

            if(locked_1.end > time_stamp && balance::value(&locked_1.balance) > 0){
                slope_1 = locked_1.end /  (balance::value(&locked_1.balance) as u256);
                bias_1 = slope_0 * (locked_1.end - (fake_time::ts() as u256)); //i256
            };

            dslope_0 = *table::borrow(&reg.slope_per_ts, locked_0.end);
            if(locked_1.end != 0){
                if(locked_1.end == locked_0.end){
                    dslope_1 = dslope_0;
                }else{
                    dslope_1 = *table::borrow(&reg.slope_per_ts, locked_1.end);
                }
            };
        };


        let latest_point = if(time_stamp > 1){
            *table::borrow(&reg.point_per_epoch, epoch)
        }else{
            Point {
                bias: 0,
                slope: 0,
                ts: time_stamp,
                blk: block_num
            }
        };

        let init_latest_point = latest_point;
        //calculate created_block / time
        let block_slope = if(time_stamp > latest_point.ts){
            SCLAE_FACTOR * (block_num - latest_point.blk) / ( time_stamp - latest_point.ts) // i256
        }else{
            0
        };

        let last_checkpoint = latest_point.ts;
        let t_i = (last_checkpoint / WEEK) / WEEK;

        let i = 0;
        while( i < 255 ){
            t_i = t_i + WEEK;

            let d_slope = 0;
            if( t_i > time_stamp ){
                t_i = time_stamp ;
            }else{
                d_slope = *table::borrow(&reg.slope_per_ts, t_i);
            };
            latest_point.bias = latest_point.bias - latest_point.slope * (t_i - last_checkpoint); //i256
            latest_point.slope = latest_point.slope + d_slope;
            if(latest_point.bias < 0){
                latest_point.bias = 0;
            };
            if(latest_point.slope < 0){
                latest_point.slope = 0;
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

        if (option::is_some(&token_id)) {
            // If last point was in this block, the slope change has been applied already
            // But in such case we have 0 slope(s)
            latest_point.slope = latest_point.slope + (slope_1 - slope_0);
            latest_point.bias = latest_point.bias + (bias_1 - bias_0);
            if (latest_point.slope < 0) {
                latest_point.slope = 0;
            };
            if (latest_point.bias < 0) {
                latest_point.bias = 0;
            };
        };

        if(option::is_some(&token_id)){
            // Schedule the slope changes (slope is going down)
            // We subtract new_user_slope from [new_locked.end]
            // and add old_user_slope to [old_locked.end]
            if (locked_0.end > time_stamp) {
                // old_dslope was <something> - u_old.slope, so we cancel that
                dslope_0 = dslope_0 + slope_0;
                if (locked_1.end == locked_0.end) {
                    dslope_0 = dslope_0 - slope_1; // It was a new deposit, not extension
                };
                let slope = table::borrow_mut(&mut reg.slope_per_ts, locked_0.end);
                *slope = dslope_0;
            };

            if (locked_1.end > time_stamp) {
                if (locked_1.end > locked_0.end) {
                    dslope_1 = dslope_1 - slope_1; // old slope disappeared at this point
                    let slope = table::borrow_mut(&mut reg.slope_per_ts, locked_1.end);
                    *slope = dslope_1;
                };
                // else: we recorded it already in old_dslope
            };
            // Now handle user history
            let user_epoch = table::borrow_mut(&mut reg.user_point_epoch, option::extract(&mut token_id));


            user_point_epoch[_tokenId] = user_epoch;
            u_new.ts = block.timestamp;
            u_new.blk = block.number;
            user_point_history[_tokenId][user_epoch] = u_new;
        };
    }
}