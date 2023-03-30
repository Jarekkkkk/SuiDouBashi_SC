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

    const WEEK: u64 = { 7 * 86400 };
    const YEAR: u256 = { 365 * 86400 };

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
    fun assert_gov(self: & VSDBRegistry, ctx: &mut TxContext){
        assert!(self.gov == tx_context::sender(ctx), err::invalid_guardian());
    }

    // ===== entry =====
    fun init(ctx: &mut TxContext){
        transfer::transfer(VSDBCap { id: object::new(ctx)}, tx_context::sender(ctx));
        let point_history = table::new<u256, Point>(ctx);
        let slope_changes = table::new<u64, I128>(ctx);
        table::add(&mut point_history, 0, point::from(i128::zero(), i128::zero(), tx_context::epoch_timestamp_ms(ctx)));
        table::add(&mut slope_changes, 0, i128::zero());

        transfer::share_object(
            VSDBRegistry {
                id: object::new(ctx),
                // coin supply
                // sdb_supply: sdb::new(ctx),
                gov: tx_context::sender(ctx),
                minted_vsdb: 0,
                locked_total: 0,
                epoch:0,
                point_history,
                slope_changes
            }
        )
    }


    // Question: everyone would only have single NFT ?
    public entry fun lock(self: &mut VSDBRegistry, sdb:Coin<SDB>, duration: u64, clock: &Clock, ctx: &mut TxContext){
        // 1. assert
        let ts = clock::timestamp_ms(clock);
        let unlock_time = (duration + ts) / WEEK;

        assert!( coin::value(&sdb) > 0 ,err::zero_input());
        assert!( unlock_time > ts && unlock_time <= ts + vsdb::max_time(), err::invalid_lock_time());

        // 2. create vsdb & update registry

        let amount = coin::value(&sdb);
        let vsdb = vsdb::new( sdb, unlock_time, ts, ctx);
        self.minted_vsdb = self.minted_vsdb + 1;
        self.locked_total = self.locked_total + (amount as u256);

        // 3. udpate global checkpoint
        checkpoint_(true, self, &vsdb, 0, 0, ts);

        let id = object::id(&vsdb);

        // 4. object transfer
        transfer::public_transfer(vsdb, tx_context::sender(ctx));

        // 5. event
        event::deposit(id, amount, unlock_time);
    }

    public entry fun increase_unlock_time(
        self: &mut VSDBRegistry,
        vsdb: &mut VSDB,
        extended_duration: u64,
        clock: &Clock,
        _ctx: &mut TxContext
    ){
        // 1. assert
        let ts = clock::timestamp_ms(clock);
        let unlock_time = ( (ts + extended_duration ) / WEEK) * WEEK;
        let locked_bal = vsdb::locked_balance(vsdb);
        let locked_end = vsdb::locked_balance(vsdb);

        assert!(locked_end > ts, err::expired_escrow());
        // TODO: destroy expired SDB when it is fully withdrawed
        assert!(locked_bal > 0, err::empty_locked_balance());
        assert!(unlock_time > ts && unlock_time < ts + vsdb::max_time(), err::invalid_lock_time());

        // 2. update vsdb state
        let prev_bal = vsdb::locked_balance(vsdb);
        let prev_end = vsdb::locked_end(vsdb);
        vsdb::extend(vsdb, option::none<Coin<SDB>>(), extended_duration, ts);

        // 2. global state
        checkpoint_(true, self, vsdb, prev_bal, prev_end, ts);


        event::deposit(object::id(vsdb), vsdb::locked_balance(vsdb), unlock_time);
    }

    public entry fun increase_unlock_balance(
        self: &mut VSDBRegistry,
        vsdb: &mut VSDB,
        coin: Coin<SDB>,
        clock: &Clock,
        _ctx: &mut TxContext
    ){
        let ts = clock::timestamp_ms(clock);
        let locked_bal = vsdb::locked_balance(vsdb);
        let locked_end = vsdb::locked_balance(vsdb);

        assert!(locked_end > ts, err::expired_escrow());
        // TODO: destroy expired SDB when it is fully withdrawed
        assert!(locked_bal > 0, err::empty_locked_balance());
        assert!(coin::value(&coin) > 0 , err::emptry_coin());

        // 2. update vsdb state
        vsdb::extend(vsdb, option::some(coin), 0, ts);

        // 2. global state
        checkpoint_(true, self, vsdb, locked_bal, locked_end, ts);


        event::deposit(object::id(vsdb), vsdb::locked_balance(vsdb), locked_end);
    }

    // /// Withdraw all the unlocked coin only when the due date is attained
    public entry fun unlock(self: &mut VSDBRegistry, vsdb: VSDB, clock: &Clock, ctx: &mut TxContext){
        let locked_bal = vsdb::locked_balance(&vsdb);
        let locked_end = vsdb::locked_balance(&vsdb);
        let ts = clock::timestamp_ms(clock);

        assert!(ts >= locked_end , err::expired_escrow());
        assert!(locked_bal > 0, err::empty_locked_balance());

        let coin = vsdb::withdraw(&mut vsdb, ctx);
        let withdrawl = coin::value(&coin);
        let id = object::id(&vsdb);

        checkpoint_(true, self, &vsdb, locked_bal, locked_end, ts);

        vsdb::destroy(vsdb);
        transfer::public_transfer(coin, tx_context::sender(ctx));

        event::withdraw(id, withdrawl, ts);
    }


    // ===== Main Logic =====
    fun checkpoint_(
        user_checkpoint: bool,
        self: &mut VSDBRegistry,
        vsdb: &VSDB, // option is not allowed to wrap referenced obj
        old_locked_amount: u64,
        old_locked_end: u64 ,
        time_stamp: u64,
    ){
        let new_locked_amount = vsdb::locked_balance(vsdb);
        let new_locked_end = vsdb::locked_end(vsdb);
        let old_dslope = i128::zero();
        let new_dslope = i128::zero();

        let u_old_slope = i128::zero();
        let u_old_bias = i128::zero();
        let u_new_slope = i128::zero();
        let u_new_bias = i128::zero();

        let epoch = self.epoch;

        // update calculate repsecitve slope & bias
        if(user_checkpoint){
            // Calculate slopes and biases
            // Kept at zero when they have to
            if(old_locked_end > time_stamp && old_locked_amount > 0){
                u_old_slope = i128::div( &i128::from((old_locked_amount as u128)), &i128::from((vsdb::max_time() as u128)));
                u_old_bias = i128::mul(&u_old_slope, &i128::from((old_locked_end as u128) - (time_stamp as u128)) );
            };

             if(new_locked_end > time_stamp && new_locked_amount > 0){
                u_new_slope = i128::div( &i128::from((new_locked_amount as u128)), &i128::from((vsdb::max_time() as u128)));
                u_new_bias = i128::mul(&u_old_slope, &i128::from((old_locked_end as u128) - (time_stamp as u128)) );
            };

            // Read values of scheduled changes in the slope
            // old_locked.end can be in the past and in the future
            // new_locked.end can ONLY by in the FUTURE unless everything expired: than zeros
            old_dslope = *table::borrow(&self.slope_changes, old_locked_end);
            if(new_locked_end != 0){
                if(new_locked_end == old_locked_end){
                    new_dslope = old_dslope;
                }else{
                    new_dslope = *table::borrow(&self.slope_changes, new_locked_end);
                }
            };
        };


        // get the latest point
        let last_point = if(self.epoch > 0){
            // copy the value in table
            *table::borrow(& self.point_history, self.epoch)
        }else{
            point::empty()
        };

        // If last point is already recorded in this block, slope=0

        // But that's ok b/c we know the block in such case


        // Go over weeks to fill history and calculate what the current point is

        // things get easier if we copy all the fields value first
        let last_checkpoint = point::ts(&last_point); // make sure checkpoint is multiply of WEEK

        let last_point_bias = point::bias(&last_point);
        let last_point_slope = point::slope(&last_point);
        let last_point_ts = point::ts(&last_point);

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
                d_slope = *table::borrow(&self.slope_changes, t_i);
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


            epoch = epoch + 1;
            if(t_i == time_stamp){
                break
            }else{
                // new version update
                let point = point::from(last_point_bias, last_point_slope, last_point_ts);
                table::add(&mut self.point_history, epoch, point);
            };

            i = i + 1;
        };

        self.epoch = epoch;
        // Now point_history is filled until t=now

        if (user_checkpoint) {
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
        *table::borrow_mut(&mut self.point_history, epoch) = point::from(last_point_bias, last_point_slope, last_point_ts);

        if(user_checkpoint){
            // Schedule the slope changes (slope is going down)
            // We subtract new_user_slope from [new_locked.end]
            // and add old_user_slope to [old_locked.end]
            if (old_locked_end > time_stamp) {
                // old_dslope was <something> - u_old.slope, so we cancel that
                old_dslope = i128::add(&old_dslope, &u_old_slope);
                if (new_locked_end == old_locked_end) {
                    old_dslope = i128::sub( &old_dslope, &u_new_slope);  // It was a new deposit, not extension
                };
                *table::borrow_mut(&mut self.slope_changes, old_locked_end) = old_dslope;
            };

            if (new_locked_end > time_stamp) {
                if (new_locked_end > old_locked_end) {
                    new_dslope =  i128::sub(&new_dslope, &u_new_slope);// old slope disappeared at this point
                    *table::borrow_mut(&mut self.slope_changes, new_locked_end) = new_dslope;
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


    public fun total_voting_weight(self: &VSDBRegistry, ts: u64){
        // index at block
    }
}