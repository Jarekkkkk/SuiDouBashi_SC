module suiDouBashiVest::vest{
    use sui::object::{Self, UID, ID};
    //use sui::balance::{Self, Supply, Balance};
    use sui::coin::{Self,Coin};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    //use std::vector as vec;
    use sui::table::{Self, Table};
    use std::option::{Self, Option};
    use sui::clock::{Self, Clock};


    use suiDouBashiVest::err;
    use suiDouBashiVest::event;
    use suiDouBashiVest::point::{Self, Point};
    use suiDouBashiVest::sdb::{ SDB};
    use suiDouBashiVest::vsdb::{Self, VSDB};

    use suiDouBashi::i128::{Self, I128};
    //use suiDouBashi::i256::{Self};

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



    // ===== OTW =====

    struct VSDBCap has key, store { id: UID }

    struct VSDBRegistry has key {
        id: UID,
        //sdb_supply: Supply<SDB>,
        gov: address,

        minted_vsdb: u64,
        locked_total: u256,

        /// acts like version, count down the times of checktime execution
        epoch: u256,
        point_history: Table<u256, Point>, //epoch -> Point
        slope_changes: Table<u64, I128> // ts -> d_slope
    }


    /// TODO: wrapped into Table<u64, vector<ID>>
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
    /// This function should be explictly called as we are unable to call init execution in SDB module
    fun create(ctx: &mut TxContext){
        transfer::transfer(VSDBCap { id: object::new(ctx)}, tx_context::sender(ctx));
        transfer::share_object(
            VSDBRegistry {
                id: object::new(ctx),
                // coin supply
                // sdb_supply: sdb::new(ctx),
                gov: tx_context::sender(ctx),
                minted_vsdb: 0,
                locked_total: 0,
                epoch:0,
                point_history: table::new<u256, Point>(ctx),
                slope_changes: table::new<u64, I128>(ctx)
            }
        )
    }



    // first time lock
    // Question: everyone would only have single NFT ?
    public entry fun create_lock(reg: &mut VSDBRegistry, sdb:Coin<SDB>, duration: u64, clock: &Clock, ctx: &mut TxContext){
        // 1. assert
        let ts = clock::timestamp_ms(clock);
        let bn = fake_time::bn();
        let unlock_time = (duration + ts) / WEEK;

        assert!( coin::value(&sdb) > 0 ,err::zero_input());
        assert!( unlock_time > ts && unlock_time <= ts + vsdb::max_time(), err::invalid_lock_time());

        // 2. create vsdb & update registry

        let amount = coin::value(&sdb);
        let vsdb_ = option::some(vsdb::new( sdb, unlock_time, ts, bn, ctx));
        reg.minted_vsdb = reg.minted_vsdb + 1;
        reg.locked_total = reg.locked_total + (amount as u256);

        // 3. udpate global checkpoint
        checkpoint_(reg, &vsdb_, 0, unlock_time, ts);

        let vsdb = option::destroy_some<VSDB>(vsdb_);
        let id = object::id(&vsdb);

        // 4. object transfer
        transfer::public_transfer(vsdb, tx_context::sender(ctx));

        // 5. event
        event::deposit(id, amount, duration);
    }

    public entry fun increase_unlock_time(_reg: &mut VSDBRegistry, vsdb: &mut VSDB, extended_duration: u64, clock: &Clock, _ctx: &mut TxContext){
        // 1. assert
        let ts = clock::timestamp_ms(clock);
        let unlock_time = ( (ts + extended_duration ) / WEEK) * WEEK;
        let locked_bal = vsdb::locked_balance(vsdb);
        let locked_end = vsdb::locked_balance(vsdb);

        assert!(locked_end > ts, err::expired_escrow());
        // TODO: destroy expired SDB when it is fully withdrawed
        assert!(locked_bal > 0, err::empty_locked_balance());
        assert!(unlock_time > ts && unlock_time < ts + vsdb::max_time(), err::invalid_lock_time());

        // 2.
    }

    // /// Withdraw all the unlocked coin only when the due date is attained
    // public entry fun unlock(reg: &mut VSDBRegistry, _vsdb: VSDB, ctx: &mut TxContext){}



    // ===== Utils =====



    // ===== Main Logic =====

    /// None -> update global checkpoint
    /// Some -> update both global & player's checkpoint
    /// VSDB's balance has been updated
    fun checkpoint_(reg: &mut VSDBRegistry, vsdb: &Option<VSDB>, old_locked_amount: u64, old_locked_end: u64 , time_stamp: u64){
        let old_dslope = i128::zero();
        let new_dslope = i128::zero();

        let u_old_slope = i128::zero();
        let u_old_bias = i128::zero();
        let u_new_slope = i128::zero();
        let u_new_bias = i128::zero();

        let block_num =  fake_time::bn();
        let epoch = reg.epoch;

        // update calculate repsecitve slope & bias
        if(option::is_some(vsdb)){
            let new_locked_amount = vsdb::locked_balance(option::borrow(vsdb));
            let new_locked_end = vsdb::locked_end(option::borrow(vsdb));
            // Calculate slopes and biases
            // Kept at zero when they have to
            if(old_locked_end > time_stamp && old_locked_amount > 0){
                u_old_slope = i128::div( &i128::from((old_locked_amount as u128)), &i128::from((vsdb::max_time() as u128)));
                u_old_bias = i128::mul(&u_old_slope, &i128::from((old_locked_end as u128) - (fake_time::ts() as u128)) );
            };

             if(new_locked_end > time_stamp && new_locked_amount > 0){
                u_new_slope = i128::div( &i128::from((new_locked_amount as u128)), &i128::from((vsdb::max_time() as u128)));
                u_new_bias = i128::mul(&u_old_slope, &i128::from((old_locked_end as u128) - (fake_time::ts() as u128)) );
            };

            // Read values of scheduled changes in the slope
            // old_locked.end can be in the past and in the future
            // new_locked.end can ONLY by in the FUTURE unless everything expired: than zeros
            old_dslope = *table::borrow(&reg.slope_changes, old_locked_end);
            if(new_locked_end != 0){
                if(new_locked_end == old_locked_end){
                    new_dslope = old_dslope;
                }else{
                    new_dslope = *table::borrow(&reg.slope_changes, new_locked_end);
                }
            };
        };


        // get the latest point
        let last_point = if(reg.epoch > 0){
            // copy the value in table
            *table::borrow(& reg.point_history, reg.epoch)
        }else{
            point::empty()
        };

        let initial_last_point = last_point;


        //calculate dblock/ dt if latest point is obsolete
        let block_slope: u256 = if(time_stamp > point::ts(&last_point)){
            MULTIPLIER * ((block_num - point::blk(&last_point)) as u256) / (( time_stamp - point::ts(&last_point)) as u256)
        }else{
            0
        };

        // If last point is already recorded in this block, slope=0

        // But that's ok b/c we know the block in such case


        // Go over weeks to fill history and calculate what the current point is

        // things get easier if we copy all the fields value first
        let last_checkpoint = point::ts(&last_point); // make sure checkpoint is multiply of WEEK

        let last_point_bias = point::bias(&last_point);
        let last_point_slope = point::slope(&last_point);
        let last_point_ts = point::ts(&last_point);
        let last_point_blk = point::blk(&last_point);

        // incremntal period by week
        let t_i = (last_checkpoint / WEEK) * WEEK; // make sure t_i is multiply of WEEK

        // update the weekly checkpoint
        let i = 0;
        while( i < 255 ){
            t_i = t_i + WEEK;

            let d_slope = i128::zero();
            if( t_i > time_stamp ){
                //latest, --> the loop will only execute once
                t_i =  time_stamp;
            }else{
                // obsolete point to update
                d_slope = *table::borrow(&reg.slope_changes, t_i);
            };
            let time_left_unlock = i128::from(((t_i - last_checkpoint) as u128));
            // calculate next week;s bias
            last_point_bias = i128::sub(&last_point_bias, &i128::mul(&last_point_slope, &time_left_unlock));
            last_point_slope = i128::add(&last_point_slope, &d_slope);

            let compare_bias = i128::compare(&last_point_bias, &i128::zero());
            // if last_point_bais <= 0
            if(compare_bias == 1 || compare_bias == 0){
                last_point_bias = i128::zero();
            };
            let compare_slope = i128::compare(&last_point_slope, &i128::zero());
            // if last_point_slope <= 0
            if(compare_slope == 1 || compare_slope == 0){
                last_point_slope = i128::zero();
            };

            last_checkpoint = t_i;
            last_point_ts = t_i;

            let last_point_blk_ = ((point::blk(&initial_last_point) as u256) + (block_slope * ((t_i - point::ts(&initial_last_point)) as u256)) / MULTIPLIER );
            last_point_blk = (last_point_blk_ as u64);

            epoch = epoch + 1;
            if(t_i == time_stamp){
                last_point_blk = block_num;
                break
            }else{
                let point = table::borrow_mut(&mut reg.point_history, epoch);
                *point = point::new(last_point_bias, last_point_slope, last_point_ts, last_point_blk);
            };

            i = i + 1;
        };

        reg.epoch = epoch;
        // Now point_history is filled until t=now

        if (option::is_some(vsdb)) {
            // If last point was in this block, the slope change has been applied already
            // But in such case we have 0 slope(s)
            last_point_slope = i128::add(&last_point_slope, &i128::sub(&u_new_slope, &u_old_slope));
            last_point_bias = i128::add(&last_point_bias, &i128::sub(&u_new_bias, &u_old_bias));
            if (i128::compare(&last_point_slope, &i128::zero()) == 1) {
                last_point_slope = i128::zero();
            };
            if (i128::compare(&last_point_bias, &i128::zero()) == 1) {
                last_point_bias = i128::zero();
            };
        };

        // Record the changed point into history

        table::add(&mut reg.point_history, epoch, point::new(last_point_bias, last_point_slope, last_point_ts, last_point_blk)); // create new one after value manipulation

        if(option::is_some(vsdb)){
            let new_locked_end = vsdb::locked_end(option::borrow(vsdb));
            // Schedule the slope changes (slope is going down)
            // We subtract new_user_slope from [new_locked.end]
            // and add old_user_slope to [old_locked.end]
            if (old_locked_end > time_stamp) {
                // old_dslope was <something> - u_old.slope, so we cancel that
                old_dslope = i128::add(&old_dslope, &u_old_slope);
                if (new_locked_end == old_locked_end) {
                    old_dslope = i128::sub( &old_dslope, &u_new_slope);  // It was a new deposit, not extension
                };
                *table::borrow_mut(&mut reg.slope_changes, old_locked_end) = old_dslope;
            };

            if (new_locked_end > time_stamp) {
                if (new_locked_end > old_locked_end) {
                    new_dslope =  i128::sub(&new_dslope, &u_new_slope);// old slope disappeared at this point
                    *table::borrow_mut(&mut reg.slope_changes, new_locked_end) = new_dslope;
                };
                // else: we recorded it already in old_dslope
            };

            // // Now handle user history
            // let user_vsdb = option::borrow_mut<VSDB>(vsdb);

            // vsdb::update_user_epoch(user_vsdb); // version + 1

            // // update point
            // let user_point_mut = vsdb::user_point_history_mut(user_vsdb, epoch);
            // *user_point_mut = point::new(u_new_bias, u_new_slope, time_stamp, block_num);
        };
    }
}