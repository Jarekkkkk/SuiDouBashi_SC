module suiDouBashiVest::vsdb{
    use sui::url::{Self, Url};
    use std::type_name::{Self, TypeName};
    use std::string::{Self};
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID};
    use sui::transfer;
    use std::vector as vec;
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};
    use sui::table_vec::{Self, TableVec};
    use sui::coin::{Self, Coin};
    use std::option::{Self, Option};
    use sui::clock::{Self, Clock};
    use std::ascii::{Self, String};
    use sui::dynamic_field as df;
    use sui::dynamic_object_field as dof;

    use suiDouBashiVest::sdb::SDB;
    use suiDouBashiVest::point::{Self, Point};
    use suiDouBashiVest::err;
    use suiDouBashiVest::event;

    use suiDouBashi::string::to_string;
    use suiDouBashi::encode::base64_encode as encode;
    use suiDouBashi::i128::{Self, I128};

    const MAX_TIME: u64 = { 4 * 365 * 86400 };
    const WEEK: u64 = { 7 * 86400 };
    const YEAR: u256 = { 365 * 86400 };
    const SVG_PREFIX: vector<u8> = b"data:image/svg+xml;base64,";

    // Error
    const E_INVALID_UNLOCK_TIME: u64 =  001 ;
    const E_LOCK: u64 =  002 ;

    // modules
    const E_NOT_REGISTERED: u64 = 004;


    // ===== assertion =====


    // TODO: display pkg format rule
    struct VSDB has key, store {
        id: UID,
        url: Url,
        // TODO: last updated
        player_epoch: u64,
        player_point_history: Table<u64, Point>, // epoch -> point_history
        locked_balance: LockedSDB,
        modules: vector<String>,
    }
    struct LockedSDB has store{
        balance: Balance<SDB>,
        end: u64 // week-based
    }

    struct VSDBCap has key, store { id: UID }

    struct VSDBRegistry has key {
        id: UID,
        whitelist_modules: Table<TypeName, bool>,
        minted_vsdb: u64,
        locked_total: u64,
        epoch: u64,
        point_history: TableVec<Point>, // epoch -> Point
        slope_changes: Table<u64, I128> // week_ts -> d_slope
    }

    public fun get_minted(reg: &VSDBRegistry): u64 { reg.minted_vsdb }

    public fun epoch(reg: &VSDBRegistry ): u64 { reg.epoch }

    public fun get_global_point_history(reg: &VSDBRegistry, epoch: u64): &Point{ table_vec::borrow(&reg.point_history, epoch) }

    public fun total_VeSDB(reg: &VSDBRegistry, clock: &Clock): u64{
        total_VeSDB_at(reg, clock::timestamp_ms(clock))
    }

    public fun total_VeSDB_at(self: &VSDBRegistry, ts: u64): u64{
        // calculate by latest epoch
        let point = table_vec::borrow(&self.point_history, self.epoch);
        let last_point_bias = point::bias(point);
        let last_point_slope = point::slope(point);
        let last_point_ts = point::ts(point);
        let t_i = round_down_week(last_point_ts);

        let i = 0;
        while( i < 255){
            t_i = t_i + WEEK;

            let d_slope = i128::zero();
            if(t_i > ts){
                t_i = ts ;
            }else{
                d_slope = if(table::contains(&self.slope_changes, t_i)){
                    *table::borrow(&self.slope_changes, t_i)
                }else{
                    i128::zero()
                };
            };
            let time_left_unlock = i128::sub(&i128::from(((t_i as u128))), &i128::from((last_point_ts as u128)));
            last_point_bias = i128::sub(&last_point_bias, &i128::mul(&last_point_slope, &time_left_unlock));

            if (t_i == ts) {
                break
            };
            last_point_slope = i128::add(&last_point_slope, &d_slope);
            last_point_ts = t_i;

            i = i +1 ;
        };

        if(i128::is_neg(&last_point_bias)){
            last_point_bias = i128::zero();
        };

        return ((i128::as_u128(&last_point_bias)) as u64)
    }

    /// register whitelisted module
    public entry fun register_module<T>(_cap: &VSDBCap, reg: &mut VSDBRegistry){
        let type = type_name::get<T>();
        assert!(!table::contains(&reg.whitelist_modules, type), err::already_reigster());
        table::add(&mut reg.whitelist_modules, type, true);
    }
    public fun whitelisted<T: copy + store + drop>(reg: &VSDBRegistry):bool {
        table::contains(&reg.whitelist_modules, type_name::get<T>())
    }
    public entry fun remove_module<T>(_cap: &VSDBCap, reg: &mut VSDBRegistry){
        table::remove(&mut reg.whitelist_modules, type_name::get<T>());
    }
    /// check if module successfully register fields in SDB
    public fun module_exists(self: &VSDB, name: vector<u8>):bool{
        vec::contains(&self.modules, &ascii::string(name))
    }

    // ===== entry =====
    fun init(ctx: &mut TxContext){
        let point_history = table_vec::singleton<Point>(point::new(i128::zero(), i128::zero(), tx_context::epoch_timestamp_ms(ctx)), ctx);
        let slope_changes = table::new<u64, I128>(ctx);

        transfer::transfer(VSDBCap { id: object::new(ctx)}, tx_context::sender(ctx));
        transfer::share_object(
            VSDBRegistry {
                id: object::new(ctx),
                whitelist_modules: table::new<TypeName, bool>(ctx),
                minted_vsdb: 0,
                locked_total: 0,
                epoch:0,
                point_history,
                slope_changes
            }
        )
    }
    public entry fun lock(
        reg: &mut VSDBRegistry,
        sdb:Coin<SDB>,
        duration: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        lock_for(reg, sdb, duration, tx_context::sender(ctx),clock, ctx);
    }
    public entry fun lock_for(
        reg: &mut VSDBRegistry,
        sdb:Coin<SDB>,
        duration: u64,
        recipient: address,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        let ts = clock::timestamp_ms(clock);
        let unlock_time = round_down_week(duration + ts);

        assert!(coin::value(&sdb) > 0 ,err::zero_input());
        assert!(unlock_time > ts && unlock_time <= ts + MAX_TIME, E_INVALID_UNLOCK_TIME);
        let amount = coin::value(&sdb);
        let vsdb = new( sdb,unlock_time, clock, ctx);
        reg.minted_vsdb = reg.minted_vsdb + 1;
        reg.locked_total = reg.locked_total + amount;
        checkpoint_(true, reg, locked_balance(&vsdb), locked_end(&vsdb), 0, 0, clock);
        let id = object::id(&vsdb);
        transfer::public_transfer(vsdb, recipient);

        event::deposit(id, amount, unlock_time);
    }
    /// extended from current time_stamp
    public entry fun increase_unlock_time(
        reg: &mut VSDBRegistry,
        self: &mut VSDB,
        extended_duration: u64,
        clock: &Clock,
    ){
        let ts = clock::timestamp_ms(clock);
        let locked_bal = locked_balance(self);
        let locked_end = locked_end(self);
        let unlock_time = round_down_week(ts + extended_duration );

        assert!(locked_end > ts, E_LOCK);
        assert!(locked_bal > 0, err::empty_locked_balance());
        assert!(unlock_time > locked_end, E_INVALID_UNLOCK_TIME);
        assert!(unlock_time > ts && unlock_time <= ts + MAX_TIME, E_INVALID_UNLOCK_TIME);

        extend(self, option::none<Coin<SDB>>(), unlock_time, clock);

        checkpoint_(true, reg, locked_balance(self), locked_end(self), locked_bal, locked_end, clock);

        event::deposit(object::id(self), locked_balance(self), unlock_time);
    }

    public entry fun increase_unlock_amount(
        reg: &mut VSDBRegistry,
        self: &mut VSDB,
        sdb: Coin<SDB>,
        clock: &Clock,
    ){
        let locked_bal = locked_balance(self);
        let locked_end = locked_end(self);
        let value = coin::value(&sdb);

        assert!(locked_end > clock::timestamp_ms(clock), E_LOCK);
        assert!(locked_bal > 0, err::empty_locked_balance());
        assert!(value > 0 , err::empty_coin());

        extend(self, option::some(sdb), 0, clock);

        reg.locked_total = reg.locked_total + value;
        checkpoint_(true, reg, locked_balance(self), locked_end(self), locked_bal, locked_end, clock);

        event::deposit(object::id(self), locked_balance(self), locked_end);
    }

    public entry fun merge(
        reg: &mut VSDBRegistry,
        self: &mut VSDB,
        vsdb:VSDB,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(vec::length(&self.modules) == 0, err::pure_vsdb());
        let locked_bal = locked_balance(self);
        let locked_end = locked_end(self);
        let locked_bal_ = locked_balance(&vsdb);
        let locked_end_ = locked_end(&vsdb);
        let ts = clock::timestamp_ms(clock);

        assert!(locked_end_ >= ts , E_LOCK);
        assert!(locked_bal_ > 0, err::empty_locked_balance());
        assert!(locked_end_ >= ts , E_LOCK);
        assert!(locked_bal_ > 0, err::empty_locked_balance());

        // empty the old vsdb
        let coin = withdraw(&mut vsdb, ctx);
        vsdb.locked_balance.end = 0;
        checkpoint_(true, reg, locked_balance(&vsdb), locked_end(&vsdb), locked_bal_, locked_end_, clock);

        destroy(vsdb);

        let end_ = if(locked_end > locked_end_){
            locked_end
        }else{
            locked_end_
        };
        reg.minted_vsdb = reg.minted_vsdb - 1 ;
        extend(self, option::some(coin), end_, clock);
        checkpoint_(true, reg, locked_balance(self), locked_end(self), locked_bal, locked_end, clock);

        event::deposit(object::id(self), locked_balance(self), end_);
    }

    /// Withdraw all the unlocked coin only when due date is expired
    public entry fun unlock(reg: &mut VSDBRegistry, self: VSDB, clock: &Clock, ctx: &mut TxContext){
        let locked_bal = locked_balance(&self);
        let locked_end = locked_end(&self);
        let ts = clock::timestamp_ms(clock);

        assert!(ts >= locked_end , E_LOCK);
        assert!(locked_bal > 0, err::empty_locked_balance());

        let coin = withdraw(&mut self, ctx);
        self.locked_balance.end = 0;
        let withdrawl = coin::value(&coin);
        let id = object::id(&self);

        checkpoint_(true, reg, locked_balance(&self), locked_end(&self), locked_bal, locked_end, clock);

        reg.locked_total = reg.locked_total - withdrawl;

        destroy(self);
        transfer::public_transfer(coin, tx_context::sender(ctx));

        event::withdraw(id, withdrawl, ts);
    }

    // ===== Display & Transfer =====

    public fun token_id(self: &VSDB): &UID {
        &self.id
    }
    public fun url(self: &VSDB): &Url {
        &self.url
    }
    public fun locked_balance(self: &VSDB): u64{ balance::value(&self.locked_balance.balance) }

    public fun locked_end(self: &VSDB):u64{ self.locked_balance.end }

    public fun player_epoch(self: &VSDB): u64{ self.player_epoch }

    public fun player_point_history(self: &VSDB, epoch: u64):&Point{
        table::borrow(&self.player_point_history, epoch)
    }

    public fun voting_weight(self: &VSDB, clock: &Clock):u64{
        voting_weight_at(self, clock::timestamp_ms(clock))
    }

    public fun voting_weight_at(self: &VSDB, ts: u64): u64{
        if(self.player_epoch == 0){
            // useless
            return 0
        }else{
            let last_point = *table::borrow(&self.player_point_history, self.player_epoch);
            let last_point_bias = point::bias(&last_point);
            let diff = i128::mul(&point::slope(&last_point), &i128::from(((ts - point::ts(&last_point)) as u128)));

            last_point_bias = i128::sub(&last_point_bias, &diff);

            if(i128::compare(&last_point_bias, &i128::zero()) == 1){
                last_point_bias = i128::zero();
            };
            return ((i128::as_u128(&last_point_bias))as u64)
        }
    }

    // - point
    public fun get_user_epoch(self: &VSDB): u64 { self.player_epoch }

    public fun get_latest_bias(self: &VSDB): I128{ get_bias(self, self.player_epoch) }

    public fun get_bias(self: &VSDB, epoch: u64): I128{
        point::bias(table::borrow(&self.player_point_history, epoch))
    }

    public fun get_latest_slope(self: &VSDB): I128{ get_slope(self, self.player_epoch) }

    public fun get_slope(self: &VSDB, epoch: u64): I128{
        point::slope( table::borrow(&self.player_point_history, epoch) )
    }

    public fun get_latest_ts(self: &VSDB): u64{ get_ts(self, self.player_epoch) }

    public fun get_ts(self: &VSDB, epoch: u64): u64{
        point::ts(table::borrow(&self.player_point_history, epoch))
    }

    fun update_user_point_(self: &mut VSDB, clock: &Clock){
        let ts = clock::timestamp_ms(clock);
        let amount = balance::value(&self.locked_balance.balance);
        let slope = calculate_slope(amount);
        let bias = calculate_bias(amount, self.locked_balance.end, ts);

        self.player_epoch = self.player_epoch + 1;

        let point = point::new(bias, slope, ts);
        table::add(&mut self.player_point_history, self.player_epoch, point);
    }

    // ===== Utils =====

    public fun calculate_slope( amount: u64 ): I128{
        i128::div( &i128::from((amount as u128)), &i128::from( (MAX_TIME as u128)))
    }

    public fun calculate_bias( amount: u64, end: u64, ts: u64): I128{
        let slope = calculate_slope(amount);
        i128::mul(&slope, &i128::from((end as u128) - (ts as u128)))
    }
    public fun round_down_week(t: u64):u64{ t / WEEK * WEEK}

    // ===== Main =====
    fun new(locked_sdb: Coin<SDB>, unlock_time: u64, clock: &Clock, ctx: &mut TxContext): VSDB {
        let uid = object::new(ctx);
        let id = object::uid_to_inner(&uid);
        let amount = coin::value(&locked_sdb);
        let voting_weight = i128::as_u128(&calculate_bias(amount, unlock_time, clock::timestamp_ms(clock)));
        let player_point_history = table::new<u64, Point>(ctx);

        let vsdb = VSDB {
            id: uid,
            url: img_url_(object::id_to_bytes(&id),(voting_weight as u256) , (unlock_time as u256), (amount as u256)),
            player_epoch: 0,
            player_point_history,
            locked_balance: LockedSDB{
                balance: coin::into_balance(locked_sdb),
                end: unlock_time
            },
            modules: vec::empty<String>(),
        };

        update_user_point_(&mut vsdb, clock);

        vsdb
    }
    /// TWO SCENARIO:
    /// 1. extend the amount
    /// 2. extend the locked_time
    /// 3. merge: extend both amount & locked_time
    fun extend(
        self: &mut VSDB,
        coin: Option<Coin<SDB>>,
        unlock_time: u64,
        clock: &Clock,
    ){
        if(option::is_some<Coin<SDB>>(&coin)){
            coin::put(&mut self.locked_balance.balance, option::extract(&mut coin));
        };
        if(unlock_time != 0){
            self.locked_balance.end = unlock_time;
        };

        option::destroy_none(coin);

        update_user_point_(self, clock);
    }

    fun withdraw(self: &mut VSDB, ctx: &mut TxContext): Coin<SDB>{
        let bal = balance::withdraw_all(&mut self.locked_balance.balance);
        self.locked_balance.end = 0;
        coin::from_balance(bal, ctx)
    }

    fun destroy(self: VSDB){
        let VSDB{
            id,
            url: _,
            player_epoch: _,
            player_point_history,
            locked_balance,
            modules,
        } = self;

        let LockedSDB{
            balance,
            end: _
        } = locked_balance;

        table::drop<u64, Point>(player_point_history);
        balance::destroy_zero(balance);
        vec::destroy_empty(modules);
        object::delete(id);
    }

    fun checkpoint_(
        user_checkpoint: bool,
        self: &mut VSDBRegistry,
        new_locked_amount: u64,
        new_locked_end: u64,
        old_locked_amount: u64,
        old_locked_end: u64 ,
        clock: &Clock
    ){
        let time_stamp = clock::timestamp_ms(clock);
        let old_dslope = i128::zero();
        let new_dslope = i128::zero();

        let u_old_slope = i128::zero();
        let u_old_bias = i128::zero();
        let u_new_slope = i128::zero();
        let u_new_bias = i128::zero();

        let epoch = self.epoch;

        // calculate slope & bias
        if(user_checkpoint){
            if(old_locked_end > time_stamp && old_locked_amount > 0){
                u_old_slope = calculate_slope(old_locked_amount);
                u_old_bias = calculate_bias(old_locked_amount,  old_locked_end, time_stamp);
            };
            if(new_locked_end > time_stamp && new_locked_amount > 0){
                u_new_slope = calculate_slope(new_locked_amount);
                u_new_bias = calculate_bias(new_locked_amount, new_locked_end, time_stamp);
            };

            // Read values of scheduled changes in the slope
            // old_locked.end can be in the past and in the future
            // new_locked.end can ONLY by in the FUTURE unless everything expired: than zeros
            if(table::contains(&self.slope_changes, old_locked_end)){
                old_dslope = *table::borrow(&self.slope_changes, old_locked_end);
            };

            if(new_locked_end != 0){ // exclude withdraw action
                if(new_locked_end == old_locked_end){
                    // update dslope: depoisit & minted
                    new_dslope = old_dslope;
                }else{
                    // extend locking duration
                    if(table::contains(&self.slope_changes, new_locked_end)){
                        new_dslope = *table::borrow(&self.slope_changes, new_locked_end);
                    };
                }
            };
        };

        // get the latest point
        let last_point = if(self.epoch > 0){
            *table_vec::borrow(&self.point_history, self.epoch)
        }else{
            point::new( i128::zero(), i128::zero(), time_stamp )
        };

        // Go over weeks to fill history and calculate what the current point is

        // things get easier we copy all the fields value first
        let last_point_bias = point::bias(&last_point);
        let last_point_slope = point::slope(&last_point);
        let last_point_ts = point::ts(&last_point);

        let t_i = round_down_week(last_point_ts);
        let i = 0;
        while( i < 255 ){ // broken when never used over 5 years
            t_i = t_i + WEEK; // endpoint of interval where checkpoint at
            let d_slope = i128::zero();

            if( t_i > time_stamp ){
                //latest, all histroy has been filled, no need of recording point_history
                t_i = time_stamp;
            }else{
                // get the d_slope of this interval, only update when the period is passed
                if(table::contains(&self.slope_changes, t_i)){
                    d_slope = *table::borrow(&self.slope_changes, t_i);
                };
            };

            let time_left = i128::sub(&i128::from(((t_i as u128))), &i128::from((last_point_ts as u128)));

            // update new bias & slope as we insert new checkpoint
            last_point_bias = i128::sub(&last_point_bias, &i128::mul(&last_point_slope, &time_left));
            last_point_slope = i128::add(&last_point_slope, &d_slope);

            let compare_bias = i128::compare(&last_point_bias, &i128::zero());
            // if last_point_bais <= 0
            if(compare_bias == 1 || compare_bias == 0){
                // this could be negative as current interval of 2 checkpoint is larger than previous interval
                last_point_bias = i128::zero();
            };
            let compare_slope = i128::compare(&last_point_slope, &i128::zero());
            // if last_point_slope <= 0
            if(compare_slope == 1 || compare_slope == 0){
                // this won't happen, just make sure
                last_point_slope = i128::zero();
            };

            last_point_ts = t_i;

            epoch = epoch + 1;
            if(t_i == time_stamp){
                break
            }else{
                // update obsolete checkpoints
                let point = point::new(last_point_bias, last_point_slope, last_point_ts);
                table_vec::push_back(&mut self.point_history, point);
            };

            i = i + 1;
        };

        // Now point_history is filled until t=now
        if (user_checkpoint) {
            // If last point was in this block, the slope change has been applied already
            // But in such case we have 0 slope(s)
            last_point_slope = i128::add(&last_point_slope, &i128::sub(&u_new_slope, &u_old_slope));
            last_point_bias = i128::add(&last_point_bias, &i128::sub(&u_new_bias, &u_old_bias));
            //  if last_point_slope < 0
            if (i128::compare(&last_point_slope, &i128::zero()) == 1) {
                last_point_slope = i128::zero();
            };
            //  if last_point_bias < 0
            if (i128::compare(&last_point_bias, &i128::zero()) == 1) {
                last_point_bias = i128::zero();
            };
        };

        // prevent infinitely creating checkpoints
        // Record the changed point into history
        let latest_point =  table_vec::borrow(&self.point_history, self.epoch);
        if(point::ts(latest_point) != last_point_ts || !i128::is_zero(&last_point_slope) || !i128::is_zero(&last_point_bias)){
            self.epoch = epoch;
            // Record the changed point into history
            let last_point = point::new(last_point_bias, last_point_slope, last_point_ts);
            // update latest epoch
            table_vec::push_back(&mut self.point_history, last_point);
        };

        if(user_checkpoint){
            // Schedule the slope changes (slope is going down)
            // We subtract new_user_slope from [new_locked.end]
            // and add old_user_slope to [old_locked.end]
            if (old_locked_end > time_stamp) {
                // old_dslope was <something> - u_old.slope, so we cancel that
                old_dslope = i128::add(&old_dslope, &u_old_slope);

                if (new_locked_end == old_locked_end) { // extend_amount
                    old_dslope = i128::sub( &old_dslope, &u_new_slope);  // It was a new deposit, not extension
                };
                // update old_locked.end in slope_changes
                if(table::contains(&self.slope_changes, old_locked_end)){
                    *table::borrow_mut(&mut self.slope_changes, old_locked_end) = old_dslope;
                }else{
                    table::add(&mut self.slope_changes, old_locked_end, old_dslope);
                }
            };

            if (new_locked_end > time_stamp) {
                // else: we recorded it already in old_dslope
                if (new_locked_end > old_locked_end) { // lock & extend locked_time
                    new_dslope =  i128::sub(&new_dslope, &u_new_slope);// old slope disappeared at this point

                    // update new_locked.end in slope_changes
                     if(table::contains(&self.slope_changes, new_locked_end)){
                        *table::borrow_mut(&mut self.slope_changes, new_locked_end) = new_dslope;
                    }else{
                        table::add(&mut self.slope_changes, new_locked_end, new_dslope);
                    }
                    // else: we recorded it already in old_dslope
                };
            };
        };
    }

    public fun global_checkpoint(
        self: &mut VSDBRegistry,
        clock: &Clock
    ){
        checkpoint_(false, self, 0, 0, 0, 0, clock);
    }

     // - df

    /// Authorized module can add dynamic fields into VSDB
    /// Witness is the entry of dyanmic fields , being careful of your generated witness, otherwise your registered state is exposed to public
    public fun df_add<T: copy + store + drop, V: store>(
        witness: &T, // Witness stands for Entry point
        reg: & VSDBRegistry,
        vsdb: &mut VSDB,
        value: V
    ){
        // retrieve address from witness
        let type = type_name::get<T>();
        assert!(table::contains(&reg.whitelist_modules, type) && *table::borrow(&reg.whitelist_modules, type), err::invalid_module());

        vec::push_back(&mut vsdb.modules, type_name::into_string(type));
        df::add(&mut vsdb.id, *witness, value);
    }
    public fun df_exists<T: copy + drop + store>(
        vsdb: &VSDB,
        witness: T,
    ): bool{
        df::exists_(&vsdb.id, witness)
    }
    public fun df_exists_with_type<T: copy + store + drop, V: store>(
        vsdb: &VSDB,
        witness: T,
    ):bool{
        df::exists_with_type<T, V>(&vsdb.id, witness)
    }
    public fun df_borrow<T: copy + drop + store, V: store>(
        vsdb: &VSDB,
        witness: T,
    ): &V{
        df::borrow(&vsdb.id, witness)
    }
    /// registered module should check borrow_mut reference
    public fun df_borrow_mut<T: copy + drop + store, V: store>(
        vsdb: &mut VSDB,
        witness: T,
    ): &mut V{
        df::borrow_mut(&mut vsdb.id, witness)
    }
    public fun df_remove_if_exists<T: copy + store + drop, V: store>(
        vsdb: &mut VSDB,
        witness: &T,
    ):Option<V>{
        let (success, idx) = vec::index_of(&vsdb.modules, &type_name::into_string(type_name::get<T>()));
        assert!(success, E_NOT_REGISTERED);
        vec::remove(&mut vsdb.modules, idx);
        df::remove_if_exists(&mut vsdb.id, *witness)
    }
    public fun df_remove<T: copy + store + drop, V: store>(
        witness: &T,
        vsdb: &mut VSDB,
    ):V{
        let (success, idx) = vec::index_of(&vsdb.modules, &type_name::into_string(type_name::get<T>()));
        assert!(success, E_NOT_REGISTERED);
        vec::remove(&mut vsdb.modules, idx);
        df::remove(&mut vsdb.id, *witness)
    }

    // - dof
    public fun dof_add<T: copy + store + drop, V: key + store>(
        witness: &T, // Witness stands for Entry point
        reg: & VSDBRegistry,
        vsdb: &mut VSDB,
        value: V
    ){
        // retrieve address from witness
        let type = type_name::get<T>();
        assert!(table::contains(&reg.whitelist_modules, type) && *table::borrow(&reg.whitelist_modules, type), err::invalid_module());

        vec::push_back(&mut vsdb.modules, type_name::into_string(type));
        dof::add(&mut vsdb.id, *witness, value);
    }
    public fun dof_exists<T: copy + drop + store>(
        vsdb: &VSDB,
        witness: T,
    ): bool{
        dof::exists_(&vsdb.id, witness)
    }
    public fun dof_exists_with_type<T: copy + store + drop, V: key + store>(
        vsdb: &VSDB,
        witness: T,
    ):bool{
        dof::exists_with_type<T, V>(&vsdb.id, witness)
    }
    public fun dof_borrow<T: copy + drop + store, V: key + store>(
        vsdb: &VSDB,
        witness: T,
    ): &V{
        dof::borrow(&vsdb.id, witness)
    }
    public fun dof_borrow_mut<T: copy + drop + store, V: key + store>(
        vsdb: &mut VSDB,
        witness: T,
    ): &mut V{
        dof::borrow_mut(&mut vsdb.id, witness)
    }
    public fun dof_remove<T: copy + store + drop, V: key + store>(
        witness: &T,
        vsdb: &mut VSDB,
    ):V{
        let (success, idx) = vec::index_of(&vsdb.modules, &type_name::into_string(type_name::get<T>()));
        assert!(success, E_NOT_REGISTERED);
        vec::remove(&mut vsdb.modules, idx);
        dof::remove(&mut vsdb.id, *witness)
    }

    fun img_url_(_id: vector<u8>, voting_weight: u256, locked_end: u256, locked_amount: u256): Url {
        let vesdb = SVG_PREFIX;
        let encoded_b = vec::empty<u8>();

        vec::append(&mut encoded_b, b"<svg xmlns='http://www.w3.org/2000/svg' preserveAspectRatio='xMinYMin meet' viewBox='0 0 350 350'><style>.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width='100%' height='100%' fill='#93c5fd' /><text x='10' y='20' class='base'>SuiDouBashi VeSDB ");
        // gas consuming if we loop 32 bytes ID to string
        //vec::append(&mut encoded_b,*string::bytes(&string::utf8(_id)));
        vec::append(&mut encoded_b,b"</text><text x='10' y='40' class='base'>Voting Weight: ");
        vec::append(&mut encoded_b,*string::bytes(&to_string(voting_weight)));
        vec::append(&mut encoded_b,b"</text><text x='10' y='60' class='base'>Locked end: ");
        vec::append(&mut encoded_b,*string::bytes(&to_string(locked_end)));
        vec::append(&mut encoded_b,b"</text><text x='10' y='80' class='base'>Locked_amount: ");
        vec::append(&mut encoded_b,*string::bytes(&to_string(locked_amount)));
        vec::append(&mut encoded_b,b"</text></svg>");
        vec::append(&mut vesdb,encode(encoded_b));
        url::new_unsafe_from_bytes(vesdb)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}