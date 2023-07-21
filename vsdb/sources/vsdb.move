// SPDX-License-Identifier: MIT
module suiDouBashi_vsdb::vsdb{
    /// Package Version
    const VERSION: u64 = 1;

    use std::vector as vec;
    use std::type_name::{Self, TypeName};
    use std::option::{Self, Option};
    use std::string::utf8;

    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};
    use sui::table_vec::{Self, TableVec};
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::package;
    use sui::display;
    use sui::dynamic_field as df;
    use sui::dynamic_object_field as dof;

    use suiDouBashi_vsdb::sdb::SDB;
    use suiDouBashi_vsdb::point::{Self, Point};
    use suiDouBashi_vsdb::event;
    use suiDouBashi_vsdb::i128::{Self, I128};

    // ====== Constants =======

    const MAX_TIME: u64 = { 24 * 7 * 86400 };
    const WEEK: u64 = { 7 * 86400 };

    // ====== Constants =======

    // ====== Error =======

    const E_WRONG_VERSION: u64 = 001;

    const E_INVALID_UNLOCK_TIME: u64 = 100;
    const E_LOCK: u64 = 101;
    const E_ALREADY_REGISTERED: u64 = 102;
    const E_ZERO_INPUT: u64 = 103;
    const E_EMPTY_BALANCE: u64 = 104;
    const E_NOT_REGISTERED: u64 = 105;
    const E_NOT_PURE: u64 = 106;
    const E_INVALID_LEVEL: u64 = 107;

    // ====== Error =======

    /// One-time witness of Vesting NFT
    struct VSDB has drop {}

    /// Vesting NFT of SuiDoBashi ecosystem. Any SDB holder can lock up their coins for specific duration at most 24 weeks and receive Vsdb NFT in exchange to SuiDoBashi contributor
    /// Additional actions like deposits and extending unlocked period are allowed anytime
    /// The logner the vesting time, the higher the governance power( voting power ) you are granted
    /// As a VSDB holder, you can earn experiences by interacting with DAPPs on SuiDouBashi to enjoy the benefits in SuiDouBashi like fee deduction, or voting bonus
    struct Vsdb has key, store{
        id: UID,
        /// Current level our NFT, corresponding to different images and bonus
        level: u8,
        /// Accrued experiences from interacting with SuiDouBashi ecosystem
        experience: u64,
        /// Locked SDB Coin
        balance: Balance<SDB>,
        /// Unlocked date ( week-based )
        end: u64,
        /// Counts for Vsdb updated times
        player_epoch: u64,
        /// point history
        player_point_history: TableVec<Point>,
        /// registered modules
        modules: vector<TypeName>
    }

    /// Capability of Vsdb package, responsible for whitelisted modules
    struct VSDBCap has key, store { id: UID }

    /// Global Registry object to record down global voting weight for all Vesting NFT
    /// whitelist modules can be registered to join SuiDouBashi ecosystem
    struct VSDBRegistry has key {
        id: UID,
        /// shared object version, used for future upgrade
        version: u64,
        /// Registered modules, verifying which module is allowed to explore dynamic fieilds on our NFT
        modules: Table<TypeName, bool>,
        /// total Vsdb NFT
        minted_vsdb: u64,
        /// Total Locked up SDB Coin
        locked_total: u64,
        /// Count for updated times
        epoch: u64,
        /// point history
        point_history: TableVec<Point>,
        /// Account for unlocked SDB coin amount for each week
        slope_changes: Table<u64, I128>
    }

    public fun minted_vsdb(reg: &VSDBRegistry): u64 { reg.minted_vsdb }

    public fun locked_total(reg: &VSDBRegistry): u64 { reg.locked_total }

    public fun epoch(reg: &VSDBRegistry): u64 { reg.epoch }

    public fun point_history(reg: &VSDBRegistry):&TableVec<Point> { &reg.point_history }

    public fun get_global_point_history(reg: &VSDBRegistry, epoch: u64): &Point{ table_vec::borrow(&reg.point_history, epoch) }

    public fun total_VeSDB(reg: &VSDBRegistry, clock: &Clock): u64{ total_VeSDB_at(reg, unix_timestamp(clock)) }

    /// Total VeSDB ( Voting power ) at time ts
    public fun total_VeSDB_at(reg: &VSDBRegistry, ts: u64): u64{
        // calculate by latest epoch
        let point = table_vec::borrow(&reg.point_history, reg.epoch);
        let last_point_bias = point::bias(point);
        let last_point_slope = point::slope(point);
        let last_point_ts = point::ts(point);
        let t_i = round_down_week(last_point_ts);

        let i = 0;
        while( i < 255){
            t_i = t_i + WEEK;

            let d_slope = i128::zero();
            if(t_i > ts){
                t_i = ts;
            }else{
                if(table::contains(&reg.slope_changes, t_i)){
                    d_slope = *table::borrow(&reg.slope_changes, t_i)
                };
            };

            last_point_bias = i128::sub(&last_point_bias, &i128::mul(&last_point_slope, &i128::sub(&i128::from(((t_i as u128))), &i128::from((last_point_ts as u128)))));

            if (t_i == ts) {
                break
            };
            // slope is going down as some coins are unlocked
            last_point_slope = i128::add(&last_point_slope, &d_slope);
            last_point_ts = t_i;

            i = i + 1 ;
        };

        if(i128::is_neg(&last_point_bias)){
            last_point_bias = i128::zero();
        };

        return ((i128::as_u128(&last_point_bias)) as u64)
    }

    /// register whitelisted module
    public entry fun register_module<T>(_cap: &VSDBCap, reg: &mut VSDBRegistry){
        assert!(reg.version == VERSION, E_WRONG_VERSION);

        let type = type_name::get<T>();
        assert!(!table::contains(&reg.modules, type), E_ALREADY_REGISTERED);
        table::add(&mut reg.modules, type, true);
    }

    public fun whitelisted<T: copy + store + drop>(reg: &VSDBRegistry):bool {
        table::contains(&reg.modules, type_name::get<T>())
    }

    public entry fun remove_module<T>(_cap: &VSDBCap, reg: &mut VSDBRegistry){
        assert!(reg.version == VERSION, E_WRONG_VERSION);
        table::remove(&mut reg.modules, type_name::get<T>());
    }

    fun init(otw: VSDB, ctx: &mut TxContext){
        // display
        let publisher = package::claim(otw, ctx);
        let keys = vector[
            utf8(b"link"),
            utf8(b"image_url"),
            utf8(b"description"),
            utf8(b"project_url"),
        ];
        let values = vector[
            utf8(b"https://suidobashi.io/vsdb"),
            utf8(b"https://suidobashi.io/vsdb/{level}"),
            utf8(b"A SuiDouBashi Ecosystem Member !"),
            utf8(b"https://suidobashi.io"),
        ];
        let display = display::new_with_fields<Vsdb>(&publisher, keys, values, ctx);
        display::update_version(&mut display);

        transfer::public_transfer(publisher, tx_context::sender(ctx));
        transfer::public_transfer(display, tx_context::sender(ctx));

        transfer::transfer(VSDBCap {id: object::new(ctx)}, tx_context::sender(ctx));
        transfer::share_object(
            VSDBRegistry {
                id: object::new(ctx),
                version: VERSION,
                modules: table::new<TypeName, bool>(ctx),
                minted_vsdb: 0,
                locked_total: 0,
                epoch:0,
                point_history: table_vec::singleton<Point>(point::new(i128::zero(), i128::zero(), tx_context::epoch_timestamp_ms(ctx) / 1000), ctx),
                slope_changes: table::new<u64, I128>(ctx)
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
        assert!(reg.version == VERSION, E_WRONG_VERSION);

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
        assert!(reg.version == VERSION, E_WRONG_VERSION);

        let ts = unix_timestamp(clock);
        let unlock_time = round_down_week(duration + ts);
        assert!(coin::value(&sdb) > 0 , E_ZERO_INPUT);
        assert!(unlock_time > ts && unlock_time <= ts + MAX_TIME, E_INVALID_UNLOCK_TIME);

        let amount = coin::value(&sdb);
        let vsdb = new( sdb,unlock_time, clock, ctx);
        reg.minted_vsdb = reg.minted_vsdb + 1;
        reg.locked_total = reg.locked_total + amount;
        checkpoint_(true, reg, 0, 0, locked_balance(&vsdb), locked_end(&vsdb), clock);

        event::deposit(object::id(&vsdb), amount, unlock_time);

        transfer::public_transfer(vsdb, recipient);
    }

    public entry fun increase_unlock_time(
        reg: &mut VSDBRegistry,
        self: &mut Vsdb,
        extended_duration: u64,
        clock: &Clock,
    ){
        assert!(reg.version == VERSION, E_WRONG_VERSION);

        let ts = unix_timestamp(clock);
        let locked_bal = locked_balance(self);
        let locked_end = locked_end(self);
        let unlock_time = round_down_week(ts + extended_duration );
        assert!(locked_end > ts, E_LOCK);
        assert!(locked_bal > 0, E_EMPTY_BALANCE);
        assert!(unlock_time > locked_end, E_INVALID_UNLOCK_TIME);
        assert!(unlock_time > ts && unlock_time <= ts + MAX_TIME, E_INVALID_UNLOCK_TIME);

        extend(self, option::none<Coin<SDB>>(), unlock_time, clock);

        checkpoint_(true, reg, locked_bal, locked_end, locked_balance(self), locked_end(self), clock);

        event::deposit(object::id(self), locked_balance(self), unlock_time);
    }

    public entry fun increase_unlock_amount(
        reg: &mut VSDBRegistry,
        self: &mut Vsdb,
        sdb: Coin<SDB>,
        clock: &Clock,
    ){
        assert!(reg.version == VERSION, E_WRONG_VERSION);

        let locked_bal = locked_balance(self);
        let locked_end = locked_end(self);
        let value = coin::value(&sdb);
        assert!(locked_end > unix_timestamp(clock), E_LOCK);
        assert!(locked_bal > 0, E_EMPTY_BALANCE);
        assert!(value > 0 , E_ZERO_INPUT);

        extend(self, option::some(sdb), 0, clock);

        reg.locked_total = reg.locked_total + value;
        checkpoint_(true, reg, locked_bal, locked_end, locked_balance(self), locked_end, clock);

        event::deposit(object::id(self), locked_balance(self), locked_end);
    }

    public entry fun merge(
        reg: &mut VSDBRegistry,
        self: &mut Vsdb,
        vsdb:Vsdb,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(reg.version == VERSION, E_WRONG_VERSION);
        assert!(vec::length(&self.modules) == 0, E_NOT_PURE);
        let locked_bal = locked_balance(self);
        let locked_end = locked_end(self);
        let level = level(&vsdb);

        let locked_bal_ = locked_balance(&vsdb);
        let locked_end_ = locked_end(&vsdb);
        let level_ = level(&vsdb);
        let ts = unix_timestamp(clock);

        assert!(locked_end_ >= ts && locked_end >= ts, E_LOCK);
        assert!(locked_bal_ > 0 && locked_bal > 0, E_EMPTY_BALANCE);

        let (level, exp) = if(level > level_){
            (level, self.experience)
        }else if(level == level_){
            let exp = if(self.experience > vsdb.experience){
                self.experience
            }else{
                vsdb.experience
            };
            (level, exp)
        }else{
            (level_, vsdb.experience)
        };
        self.level = level;
        self.experience = exp;

        let coin = withdraw(&mut vsdb, ctx);
        checkpoint_(true, reg, locked_bal_, locked_end_, locked_balance(&vsdb), locked_end(&vsdb), clock);

        destroy(vsdb);

        let end_ = if(locked_end > locked_end_){
            locked_end
        }else{
            locked_end_
        };

        reg.minted_vsdb = reg.minted_vsdb - 1 ;
        extend(self, option::some(coin), end_, clock);
        checkpoint_(true, reg, locked_bal, locked_end, locked_balance(self), locked_end(self), clock);

        event::deposit(object::id(self), locked_balance(self), end_);
    }

    /// Revive expired NFT, extend the unlocked period to at maximum 24 weeks
    public entry fun revive(
        reg: &mut VSDBRegistry,
        self: &mut Vsdb,
        clock: &Clock
    ){
        assert!(reg.version == VERSION, E_WRONG_VERSION);

        let locked_bal = locked_balance(self);
        let locked_end = locked_end(self);
        let ts = unix_timestamp(clock);
        let id = object::id(self);

        assert!(ts >= locked_end , E_LOCK);
        assert!(locked_bal > 0, E_EMPTY_BALANCE);

        checkpoint_(true, reg, locked_bal, locked_end, 0, 0, clock);

        locked_end = round_down_week(ts + max_time());

        extend(self, option::none<Coin<SDB>>(), locked_end, clock);
        checkpoint_(true, reg, 0, 0, locked_balance(self), locked_end(self), clock);

        event::deposit(id, locked_bal, locked_end);
    }

    /// Withdraw all the unlocked coin when due date is expired
    public entry fun unlock(
        reg: &mut VSDBRegistry,
        self: Vsdb,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(reg.version == VERSION, E_WRONG_VERSION);

        let locked_bal = locked_balance(&self);
        let locked_end = locked_end(&self);
        let ts = unix_timestamp(clock);

        assert!(ts >= locked_end , E_LOCK);
        assert!(locked_bal > 0, E_EMPTY_BALANCE);

        let coin = withdraw(&mut self, ctx);
        let withdrawl = coin::value(&coin);
        let id = object::id(&self);

        checkpoint_(true, reg, locked_bal, locked_end, locked_balance(&self), locked_end(&self), clock);

        reg.locked_total = reg.locked_total - withdrawl;

        destroy(self);
        transfer::public_transfer(coin, tx_context::sender(ctx));

        event::withdraw(id, withdrawl, ts);
    }

    // ===== VSDB =====

    public fun level(self: &Vsdb):u8 { self.level }

    public fun experience(self: &Vsdb):u64 { self.experience }

    public fun player_epoch(self: &Vsdb): u64{ self.player_epoch }

    public fun locked_balance(self: &Vsdb): u64{ balance::value(&self.balance) }

    public fun locked_end(self: &Vsdb):u64{ self.end }

    public fun player_point_history(self: &Vsdb, epoch: u64):&Point{
        table_vec::borrow(&self.player_point_history, epoch)
    }

    public fun voting_weight(self: &Vsdb, clock: &Clock):u64{
        voting_weight_at(self, unix_timestamp(clock))
    }

    public fun voting_weight_at(self: &Vsdb, ts: u64): u64{
        let last_point = *table_vec::borrow(&self.player_point_history, self.player_epoch);
        let last_point_bias = point::bias(&last_point);

        if(point::ts(&last_point) > ts) return 0;

        last_point_bias = i128::sub(&last_point_bias, &i128::mul(&point::slope(&last_point), &i128::from(((ts - point::ts(&last_point)) as u128))));

        if(i128::is_neg(&last_point_bias)){
            last_point_bias = i128::zero();
        };

        return ((i128::as_u128(&last_point_bias))as u64)
    }
    // - point
    public fun get_latest_bias(self: &Vsdb): I128{ get_bias(self, self.player_epoch) }

    public fun get_bias(self: &Vsdb, epoch: u64): I128{
        point::bias(table_vec::borrow(&self.player_point_history, epoch))
    }

    public fun get_latest_slope(self: &Vsdb): I128{ get_slope(self, self.player_epoch) }

    public fun get_slope(self: &Vsdb, epoch: u64): I128{
        point::slope( table_vec::borrow(&self.player_point_history, epoch) )
    }

    public fun get_latest_ts(self: &Vsdb): u64{ get_ts(self, self.player_epoch) }

    public fun get_ts(self: &Vsdb, epoch: u64): u64{
        point::ts(table_vec::borrow(&self.player_point_history, epoch))
    }

    // ===== Utils =====
    public fun calculate_slope( amount: u64): I128{
        i128::div( &i128::from((amount as u128)), &i128::from( (MAX_TIME as u128)))
    }

    public fun calculate_bias( amount: u64, end: u64, ts: u64): I128{
        let slope = calculate_slope(amount);
        i128::mul(&slope, &i128::from((end as u128) - (ts as u128)))
    }

    public fun round_down_week(t: u64): u64{ t / WEEK * WEEK}

    public fun max_time(): u64 { MAX_TIME }

    public fun unix_timestamp(clock: &Clock): u64 { clock::timestamp_ms(clock)/ 1000}

    // ===== Main =====
    fun new(locked_sdb: Coin<SDB>, unlock_time: u64, clock: &Clock, ctx: &mut TxContext): Vsdb {
        let amount = coin::value(&locked_sdb);
        let ts = unix_timestamp(clock);
        let player_point_history = table_vec::singleton(point::new(calculate_bias(amount, unlock_time, ts), calculate_slope(amount), ts), ctx);
        let vsdb = Vsdb {
            id: object::new(ctx),
            level: 0,
            experience: 0,
            balance: coin::into_balance(locked_sdb),
            end: unlock_time,
            player_epoch: 0,
            player_point_history,
            modules: vec::empty<TypeName>(),
        };

        vsdb
    }
    /// FOUR SCENARIOS:
    /// 1. extend the amount
    /// 2. extend the locked_time
    /// 3. merge: extend both amount & locked_time
    /// 4. revive: revive the expired NFT
    fun extend(
        self: &mut Vsdb,
        coin: Option<Coin<SDB>>,
        unlock_time: u64,
        clock: &Clock,
    ){
        if(option::is_some<Coin<SDB>>(&coin)){
            coin::put(&mut self.balance, option::extract(&mut coin));
        };
        if(unlock_time != 0){
            self.end = unlock_time;
        };

        option::destroy_none(coin);

        update_player_point_(self, clock);
    }

    fun withdraw(self: &mut Vsdb, ctx: &mut TxContext): Coin<SDB>{
        let bal = balance::withdraw_all(&mut self.balance);
        self.end = 0;
        coin::from_balance(bal, ctx)
    }

    fun destroy(self: Vsdb){
        let Vsdb{
            id,
            level:_,
            experience: _,
            balance,
            end: _,
            player_epoch: _,
            player_point_history,
            modules,
        } = self;

        table_vec::drop<Point>(player_point_history);
        balance::destroy_zero(balance);
        vec::destroy_empty(modules);
        object::delete(id);
    }

    fun update_player_point_(self: &mut Vsdb, clock: &Clock){
        let amount = balance::value(&self.balance);
        let ts = unix_timestamp(clock);
        self.player_epoch = self.player_epoch + 1;

        table_vec::push_back(&mut self.player_point_history, point::new(calculate_bias(amount, self.end, ts), calculate_slope(amount), ts));
    }

    fun checkpoint_(
        player_checkpoint: bool,
        reg: &mut VSDBRegistry,
        old_locked_amount: u64,
        old_locked_end: u64 ,
        new_locked_amount: u64,
        new_locked_end: u64,
        clock: &Clock
    ){
        let time_stamp = unix_timestamp(clock);
        let old_dslope = i128::zero();
        let new_dslope = i128::zero();

        let u_old_slope = i128::zero();
        let u_old_bias = i128::zero();
        let u_new_slope = i128::zero();
        let u_new_bias = i128::zero();

        let epoch = reg.epoch;

        if(player_checkpoint){
            if(old_locked_end > time_stamp && old_locked_amount > 0){
                u_old_slope = calculate_slope(old_locked_amount);
                u_old_bias = calculate_bias(old_locked_amount,  old_locked_end, time_stamp);
            };
            if(new_locked_end > time_stamp && new_locked_amount > 0){
                u_new_slope = calculate_slope(new_locked_amount);
                u_new_bias = calculate_bias(new_locked_amount, new_locked_end, time_stamp);
            };
            if(table::contains(&reg.slope_changes, old_locked_end)){
                old_dslope = *table::borrow(&reg.slope_changes, old_locked_end);
            };
            if(new_locked_end != 0){
                if(new_locked_end == old_locked_end){
                    // Action: increase_unlock_amount
                    new_dslope = old_dslope;
                }else{
                    // Action: increase_unlock_time/ mint
                    if(table::contains(&reg.slope_changes, new_locked_end)){
                        new_dslope = *table::borrow(&reg.slope_changes, new_locked_end);
                    };
                }
            };
        };

        let last_point = if(epoch > 0){
            *table_vec::borrow(&reg.point_history, epoch)
        }else{
            point::new( i128::zero(), i128::zero(), time_stamp )
        };
        let last_point_bias = point::bias(&last_point);
        let last_point_slope = point::slope(&last_point);
        let last_point_ts = point::ts(&last_point);

        let t_i = round_down_week(last_point_ts);
        let i = 0;
        while( i < 255 ){
            t_i = t_i + WEEK;
            let d_slope = i128::zero();

            if(t_i > time_stamp){
                // current epoch
                t_i = time_stamp;
            }else{
                // lasted epoch we record
                if(table::contains(&reg.slope_changes, t_i)){
                    d_slope = *table::borrow(&reg.slope_changes, t_i);
                };
            };

            last_point_bias = i128::sub(&last_point_bias, &i128::mul(&last_point_slope, &i128::sub(&i128::from(((t_i as u128))), &i128::from((last_point_ts as u128)))));
            last_point_slope = i128::add(&last_point_slope, &d_slope);

            if(i128::is_neg(&last_point_bias)){
                last_point_bias = i128::zero();
            };
            if(i128::is_neg(&last_point_slope)){
                last_point_slope = i128::zero();
            };

            last_point_ts = t_i;

            epoch = epoch + 1;
            if(t_i == time_stamp){
                break
            }else{
                table_vec::push_back(&mut reg.point_history, point::new(last_point_bias, last_point_slope, last_point_ts));
            };

            i = i + 1;
        };

        // Now point_history is filled until t=now
        if (player_checkpoint) {
            // update latest checkpoints
            last_point_slope = i128::add(&last_point_slope, &i128::sub(&u_new_slope, &u_old_slope));
            last_point_bias = i128::add(&last_point_bias, &i128::sub(&u_new_bias, &u_old_bias));
            if (i128::is_neg(&last_point_slope)) {
                last_point_slope = i128::zero();
            };
            if (i128::is_neg(&last_point_bias)) {
                last_point_bias = i128::zero();
            };
        };

        // prevent infinitely creating checkpoints
        // Record the changed point into history
        if(point::ts(table_vec::borrow(&reg.point_history, reg.epoch)) != last_point_ts || !i128::is_zero(&last_point_slope) || !i128::is_zero(&last_point_bias)){
            reg.epoch = epoch;
            // Record the changed point into history
            // update latest epoch
            table_vec::push_back(&mut reg.point_history, point::new(last_point_bias, last_point_slope, last_point_ts));
        };

        if(player_checkpoint){
            // Schedule the slope changes (slope is going down)
            // We subtract new_user_slope from [new_locked.end]
            // and add old_user_slope to [old_locked.end]
            if (old_locked_end > time_stamp) {
                // old_dslope was <something> - u_old_slope, so we cancel that
                old_dslope = i128::add(&old_dslope, &u_old_slope);

                if (new_locked_end == old_locked_end) {
                    // Action: extend_amount, new deposit comes in
                    old_dslope = i128::sub(&old_dslope, &u_new_slope);
                };
                // update old_locked.end in slope_changes
                if(table::contains(&reg.slope_changes, old_locked_end)){
                    *table::borrow_mut(&mut reg.slope_changes, old_locked_end) = old_dslope;
                }else{
                    table::add(&mut reg.slope_changes, old_locked_end, old_dslope);
                }
            };

            if (new_locked_end > time_stamp) {
                if (new_locked_end > old_locked_end){
                    // Action: extend_unlock time/ mint
                    // old slope disappeared at this point
                    new_dslope = i128::sub(&new_dslope, &u_new_slope);

                    // update new_locked.end in slope_changes
                    if(table::contains(&reg.slope_changes, new_locked_end)){
                        *table::borrow_mut(&mut reg.slope_changes, new_locked_end) = new_dslope;
                    }else{
                        table::add(&mut reg.slope_changes, new_locked_end, new_dslope);
                    }
                };
            };
        };
    }

    public fun global_checkpoint(
        reg: &mut VSDBRegistry,
        clock: &Clock
    ){
        assert!(reg.version == VERSION, E_WRONG_VERSION);
        checkpoint_(false, reg, 0, 0, 0, 0, clock);
    }

    public fun module_exists<T>(self: &Vsdb):bool{
        vec::contains(&self.modules, &type_name::get<T>())
    }

    public fun earn_xp<T: copy + store + drop>(_witness: T, self: &mut Vsdb, value: u64){
        assert!(vec::contains(&self.modules, &type_name::get<T>()), E_NOT_REGISTERED);
        self.experience = self.experience + value;
        event::earn_xp(object::id(self), value);
    }

    public fun upgrade(self: &mut Vsdb){
        let required_xp = required_xp(self.level + 1, self.level);
        while(self.experience >= required_xp){
            self.experience = self.experience - required_xp;
            self.level = self.level + 1;
            required_xp = required_xp(self.level + 1, self.level);
        };
        event::level_up(object::id(self), self.level);
    }
    /// Required Exp for under each level
    /// Formula: (Level/ 0.2) ^ 2
    public fun required_xp(to_level: u8, from_level: u8):u64{
        assert!(to_level > from_level, E_INVALID_LEVEL);
        if(to_level == 0) return 0;
        let _to = (to_level as u64);
        let _from = (from_level as u64);
        return 25 * (_to * _to - _from * _from)
    }
    /// Authorized module can add dynamic fields into Vsdb
    /// Witness is the entry of dyanmic fields , be careful of your generated witness
    /// otherwise your registered state is exposed to the public
    public fun df_add<T: copy + store + drop, V: store>(
        witness: T, // Witness stands for Entry point
        reg: &VSDBRegistry,
        self: &mut Vsdb,
        value: V
    ){
        let type = type_name::get<T>();
        assert!(table::contains(&reg.modules, type), E_NOT_REGISTERED);
        vec::push_back(&mut self.modules, type);
        df::add(&mut self.id, witness, value);
    }

    public fun df_exists<T: copy + drop + store>(
        self: &Vsdb,
        witness: T,
    ): bool{
        df::exists_(&self.id, witness)
    }

    public fun df_exists_with_type<T: copy + store + drop, V: store>(
        self: &Vsdb,
        witness: T,
    ):bool{
        df::exists_with_type<T, V>(&self.id, witness)
    }

    public fun df_borrow<T: copy + drop + store, V: store>(
        self: &Vsdb,
        witness: T,
    ): &V{
        df::borrow(&self.id, witness)
    }

    public fun df_borrow_mut<T: copy + drop + store, V: store>(
        self: &mut Vsdb,
        witness: T,
    ): &mut V{
        df::borrow_mut(&mut self.id, witness)
    }

    public fun df_remove_if_exists<T: copy + store + drop, V: store>(
        self: &mut Vsdb,
        witness: T,
    ):Option<V>{
        let (success, idx) = vec::index_of(&self.modules, &type_name::get<T>());
        assert!(success, E_NOT_REGISTERED);
        vec::remove(&mut self.modules, idx);
        df::remove_if_exists(&mut self.id, witness)
    }

    public fun df_remove<T: copy + store + drop, V: store>(
        witness: T,
        self: &mut Vsdb,
    ):V{
        let (success, idx) = vec::index_of(&self.modules, &type_name::get<T>());
        assert!(success, E_NOT_REGISTERED);
        vec::remove(&mut self.modules, idx);
        df::remove(&mut self.id, witness)
    }

    // - dof
    public fun dof_add<T: copy + store + drop, V: key + store>(
        witness: T, // Witness stands for Entry point
        reg: & VSDBRegistry,
        self: &mut Vsdb,
        value: V
    ){
        // retrieve address from witness
        let type = type_name::get<T>();
        assert!(table::contains(&reg.modules, type), E_NOT_REGISTERED);

        vec::push_back(&mut self.modules, type);
        dof::add(&mut self.id, witness, value);
    }

    public fun dof_exists<T: copy + drop + store>(
        self: &Vsdb,
        witness: T,
    ): bool{
        dof::exists_(&self.id, witness)
    }

    public fun dof_exists_with_type<T: copy + store + drop, V: key + store>(
        self: &Vsdb,
        witness: T,
    ):bool{
        dof::exists_with_type<T, V>(&self.id, witness)
    }

    public fun dof_borrow<T: copy + drop + store, V: key + store>(
        self: &Vsdb,
        witness: T,
    ): &V{
        dof::borrow(&self.id, witness)
    }

    public fun dof_borrow_mut<T: copy + drop + store, V: key + store>(
        self: &mut Vsdb,
        witness: T,
    ): &mut V{
        dof::borrow_mut(&mut self.id, witness)
    }

    public fun dof_remove<T: copy + store + drop, V: key + store>(
        witness: T,
        self: &mut Vsdb,
    ):V{
        let (success, idx) = vec::index_of(&self.modules, &type_name::get<T>());
        assert!(success, E_NOT_REGISTERED);
        vec::remove(&mut self.modules, idx);
        dof::remove(&mut self.id, witness)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(VSDB{},ctx);
    }
}