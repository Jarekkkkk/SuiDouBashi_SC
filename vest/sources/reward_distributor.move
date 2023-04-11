module suiDouBashiVest::reward_distributor{
    use sui::vec_map::{Self, VecMap};
    use std::vector as vec;
    use sui::clock::{Self, Clock};
    use sui::balance::{Self, Balance};

    use sui::tx_context::{Self, TxContext};
    use sui::transfer;

    use suiDouBashiVest::event;
    use suiDouBashiVest::err;
    use suiDouBashiVest::sdb::SDB;
    use suiDouBashiVest::vsdb::{Self, VSDB,VSDBRegistry};
    use suiDouBashiVest::point;

    friend suiDouBashiVest::minter;

    const WEEK: u64 = {7 * 86400};


    struct Distributor has key{
        balance: Balance<SDB>,
        start_time: u64,
        time_cursor: u64,

        time_cursor_of: VecMap<u64, u64>,
        user_epoch_of: VecMap<u64, u64>,

        last_token_time: u64,

        tokens_per_week: VecMap<u64, u64>, // ts -> distribute tokens

        token_last_balance: u64,

        ve_supply: vector<u64>,

        depositor: address
    }

    public (friend) fun new(ctx: &mut TxContext){
        let ts = tx_context::epoch_timestamp_ms(ctx) / WEEK * WEEK;

        let distributor = Distributor{
            balance: balance::zero<SDB>(),

            start_time: ts,
            time_cursor: ts,

            time_cursor_of: vec_map::empty<u64, u64>(),
            user_epoch_of: vec_map::empty<u64, u64>(),

            last_token_time: ts,

            tokens_per_week: vec_map::empty<u64, u64>(),

            token_last_balance: 0,

            ve_supply: vec::empty<u64>(),

            depositor: tx_context::sender(ctx)
        };

        transfer::share_object(distributor);
    }

    fun timestamp(clock: &Clock): u64{
        return clock::timestamp_ms(clock) * WEEK / WEEK
    }

    // ===== Entry =====
    public entry fun checkopint_token(self: &mut Distributor, clock: &Clock, ctx: &mut TxContext){
        assert!(tx_context::sender(ctx) == self.depositor, err::invalid_depositor());
        checkpoint_token_(self, clock);
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
                        vec_map::insert(&mut self.tokens_per_week, this_week,  to_distribute * ( ts - t ) / since_last);
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
    ): u256{
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
        vsdb_reg: &VSDBRegistry,
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
}


