module suiDouBashiVest::reward_distributor{
    use sui::vec_map::{Self, VecMap};
    use std::vector as vec;
    use sui::clock::{Self, Clock};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::math;
    use sui::object::{Self, ID, UID};
    use sui::table::{Self, Table};

    use sui::tx_context::{Self, TxContext};
    use sui::transfer;

    use suiDouBashiVest::event;
    use suiDouBashiVest::sdb::SDB;
    use suiDouBashiVest::vsdb::{Self, VSDB, VSDBRegistry};
    use suiDouBashiVest::point;
    use suiDouBashi::i128;

    friend suiDouBashiVest::minter;

    const WEEK: u64 = {7 * 86400};

    struct Distributor has key{
        id: UID,
        balance: Balance<SDB>,
        start_time: u64,
        time_cursor: u64, // weekly countdown

        time_cursor_of: Table<ID, u64>,
        user_epoch_of: Table<ID, u64>,

        last_token_time: u64,

        tokens_per_week: VecMap<u64, u64>, // week_epoch -> distribute tokens

        token_last_balance: u64,

        ve_supply: VecMap<u64, u64>, // time-cursor -> veSDB supply
    }

     fun init(ctx: &mut TxContext){
        let ts = tx_context::epoch_timestamp_ms(ctx) / WEEK * WEEK;

        let distributor = Distributor{
            id: object::new(ctx),
            balance: balance::zero<SDB>(),

            start_time: ts,
            time_cursor: ts,

            time_cursor_of: table::new<ID, u64>(ctx),
            user_epoch_of: table::new<ID, u64>(ctx),

            last_token_time: ts,

            tokens_per_week: vec_map::empty<u64, u64>(),

            token_last_balance: 0,

            ve_supply: vec_map::empty<u64, u64>(),
        };

        transfer::share_object(distributor);
    }

    fun timestamp(clock: &Clock): u64{
        return clock::timestamp_ms(clock) * WEEK / WEEK
    }

    // ===== Entry =====
    public (friend) fun deposit_reward(self: &mut Distributor, coin: Coin<SDB>){
        coin::put(&mut self.balance, coin);
    }
    public(friend) fun checkpoint_token(self: &mut Distributor, clock: &Clock){
        checkpoint_token_(self, clock);
    }

    public entry fun checkpoint_total_supply(
        self: &mut Distributor,
        vsdb_reg: &mut VSDBRegistry,
        clock: &Clock,
    ){
        checkpoint_total_supply_(self, vsdb_reg, clock);
    }

    /// VSDB holder to rebase voting weight
    public entry fun claim(
        self: &mut Distributor,
        vsdb_reg: &mut VSDBRegistry,
        vsdb: &mut VSDB,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        if(clock::timestamp_ms(clock) >= self.time_cursor){
            checkpoint_total_supply_(self, vsdb_reg, clock);
        };

        let last_token_time_ = self.last_token_time;
        last_token_time_ = last_token_time_ / WEEK * WEEK;

        let amount = claim_(self, vsdb, last_token_time_);
        if(amount != 0){
             // extend the rebased amount for VeSDB holders
            let coin_sdb = coin::take(&mut self.balance, amount, ctx);
            vsdb::increase_unlock_amount(vsdb_reg, vsdb, coin_sdb, clock, ctx);
            self.token_last_balance = self.token_last_balance - amount;
        };
    }

    public entry fun claimable(
        self: & Distributor,
        vsdb: & VSDB,
    ){
        let last_token_time_ = self.last_token_time / WEEK * WEEK;
        claimable_(self, vsdb, last_token_time_);
    }

    public entry fun claim_many(
        self: &mut Distributor,
        vsdb_reg: &mut VSDBRegistry,
        vsdbs: vector<VSDB>, // watch out any argument with vector wrapping object, since it doesn't protect underlying objects by reference
        clock: &Clock,
        ctx: &mut TxContext
    ){
        if(clock::timestamp_ms(clock) >= self.time_cursor){
            checkpoint_total_supply_(self, vsdb_reg, clock);
        };

        let last_token_time_ = self.last_token_time;
        last_token_time_ = last_token_time_ / WEEK * WEEK;

        let total = 0;
        let i = 0;
        while( i < vec::length(&vsdbs)){
            let vsdb = vec::pop_back(&mut vsdbs);
            let amount = claim_(self, &vsdb, last_token_time_);
            if(amount != 0){
                let coin_sdb = coin::take(&mut self.balance, amount, ctx);
                vsdb::increase_unlock_amount(vsdb_reg, &mut vsdb, coin_sdb, clock, ctx);
                self.token_last_balance = self.token_last_balance - amount;
                total = total + amount;
            };
            transfer::public_transfer(vsdb, tx_context::sender(ctx));

            i = i + 1;
        };

        if(total != 0) self.token_last_balance = self.token_last_balance - total;
        vec::destroy_empty(vsdbs)
    }



    // ===== Internal =====
    fun checkpoint_token_(self: &mut Distributor, clock: &Clock){
        let ts = clock::timestamp_ms(clock);

        let token_balance = balance::value(&self.balance);
        let to_distribute = token_balance - self.token_last_balance;
        self.token_last_balance = token_balance;

        let t = self.last_token_time;
        let since_last = ts - t;

        self.last_token_time = ts;
        let this_week = t / WEEK * WEEK;

        let i = 0;
        while( i < 20 ){
            let next_week = this_week + WEEK;

            if( ts < next_week ){ // in latest epoch
                if( since_last == 0 && ts == t ){ // same block
                    if(vec_map::contains(&self.tokens_per_week, &this_week)){
                        *vec_map::get_mut(&mut self.tokens_per_week, &this_week) = *vec_map::get(&self.tokens_per_week, &this_week) + to_distribute;
                    }else{
                        vec_map::insert(&mut self.tokens_per_week, this_week, to_distribute);
                    }
                }else{
                    if(vec_map::contains(&self.tokens_per_week, &this_week)){
                        *vec_map::get_mut(&mut self.tokens_per_week, &this_week) = *vec_map::get(&self.tokens_per_week, &this_week) + to_distribute * ( ts - t ) / since_last;
                    }else{
                        vec_map::insert(&mut self.tokens_per_week, this_week,  to_distribute * ( ts - t ) / since_last);
                    }
                };
                break
            } else { // obsolete epoch
                if( since_last == 0 && next_week == t ){ // same block
                    if(vec_map::contains(&self.tokens_per_week, &this_week)){
                        *vec_map::get_mut(&mut self.tokens_per_week, &this_week) = *vec_map::get(&self.tokens_per_week, &this_week) + to_distribute;
                    }else{
                        vec_map::insert(&mut self.tokens_per_week, this_week, to_distribute);
                    }
                }else{
                    if(vec_map::contains(&self.tokens_per_week, &this_week)){
                        *vec_map::get_mut(&mut self.tokens_per_week, &this_week) = *vec_map::get(&self.tokens_per_week, &this_week) + to_distribute * ( next_week - t ) / since_last;
                    }else{
                        vec_map::insert(&mut self.tokens_per_week, this_week, to_distribute * ( next_week - t ) / since_last);
                    }
                };
            };
            t = next_week;
            this_week = next_week;

            i = i + 1 ;
        };

        event::checkopint_token(ts, to_distribute);
    }

    fun find_timestamp_epoch_(
        vsdb_reg: &VSDBRegistry,
        timestamp: u64
    ): u64{
        let min_ = 0;
        let max_ = vsdb::epoch(vsdb_reg);

        let i = 0 ;
        while( i < 128 ){
            if( min_ > max_ ) break;

            let mid_ = ( min_ + max_  + 2) / 2;
            let point = *vsdb::get_global_point_history(vsdb_reg, mid_);
            if(point::ts(&point) <= timestamp){
                min_ = mid_;
            }else{
                max_ = mid_ - 1;
            };

            i = i + 1;
        };

        return min_
    }

    fun find_timestamp_user_epoch_(
        vsdb: &VSDB,
        timestamp: u64,
        max_user_epoch: u64
    ): u64{
        let min_ = 0;
        let max_ = max_user_epoch;

        let i = 0 ;
        while( i < 128 ){
            if( min_ > max_ ) break;

            let mid_ = ( min_ + max_  + 2) / 2;
            let point = *vsdb::user_point_history(vsdb, mid_);

            if(point::ts(&point) <= timestamp){
                min_ = mid_;
            }else{
                max_ = mid_ - 1;
            };

            i = i + 1;
        };

        return min_
    }

    fun ve_for_at_(
        vsdb: &VSDB,
        timestamp: u64,
    ):u64{
        let max_user_epoch = vsdb::user_epoch(vsdb);
        let epoch = find_timestamp_user_epoch_(vsdb, timestamp, max_user_epoch);
        let pt = *vsdb::user_point_history(vsdb, epoch);

        let time_left_unlock = i128::sub(&i128::from(((timestamp as u128))), &i128::from((point::ts(&pt) as u128)));
        let ts = i128::sub(&point::bias(&pt), &i128::mul(&point::slope(&pt), &time_left_unlock));

        return math::max((i128::as_u128(&ts) as u64), 0)
    }

    /// Alert: globally checkpoint global histroy of vsdb registry
    fun checkpoint_total_supply_(
        self: &mut Distributor,
        vsdb_reg: &mut VSDBRegistry,
        clock: &Clock,
    ){
        let ts = clock::timestamp_ms(clock);

        let t = self.time_cursor;
        let rounded_timestamp = ts / WEEK * WEEK;
        vsdb::global_checkpoint_(vsdb_reg, clock);

        let i = 0;
        while( i < 20 ){
            if( t > rounded_timestamp ){
                break
            }else{
                let epoch = find_timestamp_epoch_(vsdb_reg, t);
                let pt = *vsdb::get_global_point_history(vsdb_reg, epoch);
                let dt = i128::zero();
                if( t > point::ts(&pt)){
                    dt = i128::sub(&i128::from(((t as u128))), &i128::from((point::ts(&pt) as u128)));
                };

                let bias = i128::sub(&point::bias(&pt), &i128::mul(&point::slope(&pt), &dt));
                let new_ve_supply = math::max((i128::as_u128(&bias) as u64), 0);

                if(vec_map::contains(&self.ve_supply, &t)){
                    *vec_map::get_mut(&mut self.ve_supply, &t) = new_ve_supply;
                }else{
                    vec_map::insert(&mut self.ve_supply, t, new_ve_supply);
                };
            };

            t = t + WEEK;
            i = i + 1;
        };

        self.time_cursor = t;
    }

    fun claim_(
        self: &mut Distributor,
        vsdb: &VSDB,
        last_token_time: u64
    ): u64{
        let id = object::id(vsdb);

        let to_distribute = 0;

        let max_user_epoch = vsdb::user_epoch(vsdb);
        if (max_user_epoch == 0) return 0;

        let start_time_ = self.start_time;

        let week_cursor = if(table::contains(&self.time_cursor_of, id)){
            *table::borrow(&self.time_cursor_of, id)
        }else{
            0
        };

        let user_epoch = if(week_cursor == 0){
            find_timestamp_user_epoch_(vsdb, start_time_, max_user_epoch)
        }else{
            if(table::contains(&self.user_epoch_of, id)){
                *table::borrow(&self.user_epoch_of, id)
            }else{
                0
            }
        };

        if(user_epoch == 0) user_epoch = 1;

        let user_point = *vsdb::user_point_history(vsdb, user_epoch);

        if(week_cursor == 0){
            week_cursor = ( point::ts(&user_point) + WEEK - 1 ) / WEEK * WEEK;
        };

        if(week_cursor >= last_token_time) return 0;

        if(week_cursor < start_time_) week_cursor = start_time_;

        let old_user_point = point::new(i128::zero(), i128::zero(), 0);

        let i = 0;
        while( i < 50 ){
            if(week_cursor >= last_token_time) break;

            if( week_cursor >= point::ts(&user_point) && user_epoch <= max_user_epoch){
                user_epoch = user_epoch + 1;
                old_user_point = user_point;

                if(user_epoch > max_user_epoch){
                    user_point = point::new(i128::zero(), i128::zero(), 0);
                }else{
                    user_point = *vsdb::user_point_history(vsdb, user_epoch);
                }
            }else{
                let dt = i128::sub(&i128::from(((week_cursor as u128))), &i128::from((point::ts(&old_user_point) as u128)));
                let ts = i128::sub(&point::bias(&old_user_point), &i128::mul(&point::slope(&old_user_point), &dt));
                let balance_of = math::max((i128::as_u128(&ts) as u64), 0);
                if( balance_of == 0 && user_epoch > max_user_epoch) break;
                if(balance_of != 0){
                    to_distribute = to_distribute + balance_of * *vec_map::get(&self.tokens_per_week, &week_cursor) / *vec_map::get(&self.ve_supply, &week_cursor);
                };

                week_cursor = week_cursor + WEEK;
            };

            i = i + 1;
        };

        user_epoch = math::min(max_user_epoch, user_epoch - 1);

        if(table::contains(&self.user_epoch_of, id)){
            *table::borrow_mut(&mut self.user_epoch_of, id) = user_epoch;
        }else{
            table::add(&mut self.user_epoch_of, id, user_epoch);
        };

        if(table::contains(&self.time_cursor_of, id)){
            *table::borrow_mut(&mut self.time_cursor_of, id) = week_cursor;
        }else{
            table::add(&mut self.time_cursor_of, id, week_cursor);
        };

        event::reward_claimed(id, to_distribute, user_epoch, max_user_epoch);

        to_distribute
    }

    fun claimable_(
        self: &Distributor,
        vsdb: &VSDB,
        last_token_time: u64
    ): u64{
        let id = object::id(vsdb);
        let to_distribute = 0;

        let max_user_epoch = vsdb::user_epoch(vsdb);
        let start_time_ = self.start_time;

        if (max_user_epoch == 0) return 0;

        let week_cursor = if(table::contains(&self.time_cursor_of, id)){
            *table::borrow(&self.time_cursor_of, id)
        }else{
            0
        };

        let user_epoch = if(week_cursor == 0){
            find_timestamp_user_epoch_(vsdb, start_time_, max_user_epoch)
        }else{
            if(table::contains(&self.user_epoch_of, id)){
                *table::borrow(&self.user_epoch_of, id)
            }else{
                0
            }
        };

        if(user_epoch == 0) user_epoch = 1;

        let user_point = *vsdb::user_point_history(vsdb, user_epoch);

        if(week_cursor == 0){
            week_cursor = ( point::ts(&user_point) + WEEK - 1 ) / WEEK * WEEK;
        };

        if(week_cursor >= last_token_time) return 0;

        if(week_cursor < start_time_) week_cursor = start_time_;

        let old_user_point = point::new(i128::zero(), i128::zero(), 0);

        let i = 0;
        while( i < 50 ){
            if(week_cursor >= last_token_time) break;

            if( week_cursor >= point::ts(&user_point) && user_epoch <= max_user_epoch){
                user_epoch = user_epoch + 1;
                old_user_point = user_point;

                if(user_epoch > max_user_epoch){
                    user_point = point::new(i128::zero(), i128::zero(), 0);
                }else{
                    user_point = *vsdb::user_point_history(vsdb, user_epoch);
                }
            }else{
                let dt = i128::sub(&i128::from(((week_cursor as u128))), &i128::from((point::ts(&old_user_point) as u128)));
                let ts = i128::sub(&point::bias(&old_user_point), &i128::mul(&point::slope(&old_user_point), &dt));
                let balance_of = math::max((i128::as_u128(&ts) as u64), 0);
                if( balance_of == 0 && user_epoch > max_user_epoch) break;
                if(balance_of != 0){
                    to_distribute = to_distribute + balance_of * *vec_map::get(&self.tokens_per_week, &week_cursor) / *vec_map::get(&self.ve_supply, &week_cursor);
                };

                week_cursor = week_cursor + WEEK;
            };

            i = i + 1;
        };

        to_distribute
    }
     #[test_only]
     public fun init_for_testing(ctx: &mut TxContext){
        init(ctx);
     }
}