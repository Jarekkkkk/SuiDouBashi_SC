/// VSDB Vesting NFT stands for membership of SuiDoBashi Ecosystem,
/// Anyone holding VSDB can be verified project contributor as it retain our token value by holding SDB coins
/// Whne holding VSDB, holder can enjoy the features in the SuiDoBashi ecosystem
module suiDouBashi_vsdb::vsdb{
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
    use std::string::utf8;
    use sui::package;
    use sui::display;
    use sui::dynamic_field as df;
    use sui::dynamic_object_field as dof;

    use suiDouBashi_vsdb::sdb::SDB;
    use suiDouBashi_vsdb::point::{Self, Point};
    use suiDouBashi_vsdb::event;
    use suiDouBashi_vsdb::encode::base64_encode as encode;
    use suiDouBashi_vsdb::i128::{Self, I128};

    const MAX_TIME: u64 = { 24 * 7 * 86400 };
    const WEEK: u64 = { 7 * 86400 };
    const VERSION: u64 = 1;

    const E_INVALID_VERSION: u64 = 000;
    const E_INVALID_UNLOCK_TIME: u64 = 001;
    const E_LOCK: u64 = 002;
    const E_ALREADY_REGISTERED: u64 = 003;
    const E_ZERO_INPUT: u64 = 004;
    const E_EMPTY_BALANCE: u64 = 005;
    const E_NOT_REGISTERED: u64 = 006;
    const E_NOT_PURE: u64 = 007;
    const E_INVALID_LEVEL: u64 = 008;

    struct VSDB has drop {}

    struct Vsdb has key, store{
        id: UID,
        level: u8,
        experience: u64,
        last_updated: u64,
        // Locked SDB Balance
        balance: Balance<SDB>,
        // Unlocked date ( week-based )
        end: u64,
        player_epoch: u64,
        /// we use tyep Table since we can't drop TableVec if it's not empty
        player_point_history: Table<u64, Point>,
        modules: vector<String>
    }

    struct VSDBCap has key, store { id: UID }

    struct VSDBRegistry has key {
        id: UID,
        modules: Table<TypeName, bool>,
        minted_vsdb: u64,
        locked_total: u64,
        epoch: u64,
        point_history: TableVec<Point>,
        /// slope difference for each week
        slope_changes: Table<u64, I128>
    }

    public fun get_minted(reg: &VSDBRegistry): u64 { reg.minted_vsdb }

    public fun locked_total(reg: &VSDBRegistry): u64 { reg.locked_total }

    public fun epoch(reg: &VSDBRegistry ): u64 { reg.epoch }

    public fun point_history(reg: &VSDBRegistry):&TableVec<Point> { &reg.point_history }

    public fun get_global_point_history(reg: &VSDBRegistry, epoch: u64): &Point{ table_vec::borrow(&reg.point_history, epoch) }

    public fun total_VeSDB(reg: &VSDBRegistry, clock: &Clock): u64{ total_VeSDB_at(reg, clock::timestamp_ms(clock) / 1000) }

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
        assert!(!table::contains(&reg.modules, type), E_ALREADY_REGISTERED);
        table::add(&mut reg.modules, type, true);
    }
    public fun whitelisted<T: copy + store + drop>(reg: &VSDBRegistry):bool {
        table::contains(&reg.modules, type_name::get<T>())
    }
    public entry fun remove_module<T>(_cap: &VSDBCap, reg: &mut VSDBRegistry){
        table::remove(&mut reg.modules, type_name::get<T>());
    }

    // ===== entry =====
    fun init(otw: VSDB, ctx: &mut TxContext){
        // display
        let publisher = package::claim(otw, ctx);
        let keys = vector[
            utf8(b"level"),
            utf8(b"link"),
            utf8(b"image_url"),
            utf8(b"description"),
            utf8(b"project_url"),
        ];
        let values = vector[
            utf8(b"https://suidobashi.io/vsdb/{level}"),
            utf8(b"https://suidobashi.io/vsdb/{id}"),
            utf8(b"ipfs://{img_url}"),
            utf8(b"A SuiDouBashi Ecosystem Member !"),
            utf8(b"https://suidobashi.io"),
        ];
        let display = display::new_with_fields<Vsdb>(&publisher, keys, values, ctx);
        display::update_version(&mut display);

        transfer::public_transfer(publisher, tx_context::sender(ctx));
        transfer::public_transfer(display, tx_context::sender(ctx));

        // Main Logic
        let point_history = table_vec::singleton<Point>(point::new(i128::zero(), i128::zero(), tx_context::epoch_timestamp_ms(ctx) / 1000), ctx);
        let slope_changes = table::new<u64, I128>(ctx);

        transfer::transfer(VSDBCap { id: object::new(ctx)}, tx_context::sender(ctx));
        transfer::share_object(
            VSDBRegistry {
                id: object::new(ctx),
                modules: table::new<TypeName, bool>(ctx),
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
        duration: u64, // timestamp
        recipient: address,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        let ts = clock::timestamp_ms(clock) / 1000;
        let unlock_time = round_down_week(duration + ts);

        assert!(coin::value(&sdb) > 0 , E_ZERO_INPUT);
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
    public entry fun increase_unlock_time(
        reg: &mut VSDBRegistry,
        self: &mut Vsdb,
        extended_duration: u64, // timestamp
        clock: &Clock,
    ){
        let ts = clock::timestamp_ms(clock) / 1000;
        let locked_bal = locked_balance(self);
        let locked_end = locked_end(self);
        let unlock_time = round_down_week(ts + extended_duration );

        assert!(locked_end > ts, E_LOCK);
        assert!(locked_bal > 0, E_EMPTY_BALANCE);
        assert!(unlock_time > locked_end, E_INVALID_UNLOCK_TIME);
        assert!(unlock_time > ts && unlock_time <= ts + MAX_TIME, E_INVALID_UNLOCK_TIME);

        extend(self, option::none<Coin<SDB>>(), unlock_time, clock);

        checkpoint_(true, reg, locked_balance(self), locked_end(self), locked_bal, locked_end, clock);

        event::deposit(object::id(self), locked_balance(self), unlock_time);
    }

    public entry fun increase_unlock_amount(
        reg: &mut VSDBRegistry,
        self: &mut Vsdb,
        sdb: Coin<SDB>,
        clock: &Clock,
    ){
        let locked_bal = locked_balance(self);
        let locked_end = locked_end(self);
        let value = coin::value(&sdb);

        assert!(locked_end > clock::timestamp_ms(clock) / 1000, E_LOCK);
        assert!(locked_bal > 0, E_EMPTY_BALANCE);
        assert!(value > 0 , E_ZERO_INPUT);

        extend(self, option::some(sdb), 0, clock);

        reg.locked_total = reg.locked_total + value;
        checkpoint_(true, reg, locked_balance(self), locked_end, locked_bal, locked_end, clock);

        event::deposit(object::id(self), locked_balance(self), locked_end);
    }

    public entry fun merge(
        reg: &mut VSDBRegistry,
        self: &mut Vsdb,
        vsdb:Vsdb,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(vec::length(&self.modules) == 0, E_NOT_PURE);
        let locked_bal = locked_balance(self);
        let locked_end = locked_end(self);
        let locked_bal_ = locked_balance(&vsdb);
        let locked_end_ = locked_end(&vsdb);
        let ts = clock::timestamp_ms(clock)/ 1000;

        assert!(locked_end_ >= ts , E_LOCK);
        assert!(locked_bal_ > 0, E_EMPTY_BALANCE);
        assert!(locked_end_ >= ts , E_LOCK);
        assert!(locked_bal_ > 0, E_EMPTY_BALANCE);

        let coin = withdraw(&mut vsdb, ctx);
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

    /// Withdraw all the unlocked coin when due date is expired
    public entry fun unlock(reg: &mut VSDBRegistry, self: Vsdb, clock: &Clock, ctx: &mut TxContext){
        let locked_bal = locked_balance(&self);
        let locked_end = locked_end(&self);
        let ts = clock::timestamp_ms(clock)/ 1000;

        assert!(ts >= locked_end , E_LOCK);
        assert!(locked_bal > 0, E_EMPTY_BALANCE);

        let coin = withdraw(&mut self, ctx);
        let withdrawl = coin::value(&coin);
        let id = object::id(&self);

        checkpoint_(true, reg, locked_balance(&self), locked_end(&self), locked_bal, locked_end, clock);

        reg.locked_total = reg.locked_total - withdrawl;

        destroy(self);
        transfer::public_transfer(coin, tx_context::sender(ctx));

        event::withdraw(id, withdrawl, ts);
    }

    // ===== VSDB =====

    public fun level(self: &Vsdb):u8 { self.level }

    public fun experience(self: &Vsdb):u64 { self.experience }

    public fun last_updated(self: &Vsdb):u64 { self.last_updated }

    public fun player_epoch(self: &Vsdb): u64{ self.player_epoch }

    public fun locked_balance(self: &Vsdb): u64{ balance::value(&self.balance) }

    public fun locked_end(self: &Vsdb):u64{ self.end }

    public fun player_point_history(self: &Vsdb, epoch: u64):&Point{
        table::borrow(&self.player_point_history, epoch)
    }

    public fun voting_weight(self: &Vsdb, clock: &Clock):u64{
        voting_weight_at(self, clock::timestamp_ms(clock)/ 1000)
    }

    public fun voting_weight_at(self: &Vsdb, ts: u64): u64{
        let last_point = *table::borrow(&self.player_point_history, self.player_epoch);
        let last_point_bias = point::bias(&last_point);
        let diff = i128::mul(&point::slope(&last_point), &i128::from(((ts - point::ts(&last_point)) as u128)));

        last_point_bias = i128::sub(&last_point_bias, &diff);

        if(i128::is_neg(&last_point_bias)){
            last_point_bias = i128::zero();
        };
        return ((i128::as_u128(&last_point_bias))as u64)
    }
    // - point
    public fun get_player_epoch(self: &Vsdb): u64 { self.player_epoch }

    public fun get_latest_bias(self: &Vsdb): I128{ get_bias(self, self.player_epoch) }

    public fun get_bias(self: &Vsdb, epoch: u64): I128{
        point::bias(table::borrow(&self.player_point_history, epoch))
    }

    public fun get_latest_slope(self: &Vsdb): I128{ get_slope(self, self.player_epoch) }

    public fun get_slope(self: &Vsdb, epoch: u64): I128{
        point::slope( table::borrow(&self.player_point_history, epoch) )
    }

    public fun get_latest_ts(self: &Vsdb): u64{ get_ts(self, self.player_epoch) }

    public fun get_ts(self: &Vsdb, epoch: u64): u64{
        point::ts(table::borrow(&self.player_point_history, epoch))
    }

    fun update_player_point_(self: &mut Vsdb, clock: &Clock){
        let ts = clock::timestamp_ms(clock)/ 1000;
        let amount = balance::value(&self.balance);
        let slope = calculate_slope(amount);
        let bias = calculate_bias(amount, self.end, ts);

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

    public fun max_time(): u64 { MAX_TIME }

    // ===== Main =====
    fun new(locked_sdb: Coin<SDB>, unlock_time: u64, clock: &Clock, ctx: &mut TxContext): Vsdb {
        let vsdb = Vsdb {
            id: object::new(ctx),
            level: 0,
            experience: 0,
            last_updated: 0,
            balance: coin::into_balance(locked_sdb),
            end: unlock_time,
            player_epoch: 0,
            player_point_history: table::new<u64, Point>(ctx),
            modules: vec::empty<String>(),
        };

        update_player_point_(&mut vsdb, clock);

        vsdb
    }
    /// TWO SCENARIO:
    /// 1. extend the amount
    /// 2. extend the locked_time
    /// 3. merge: extend both amount & locked_time
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
        self.last_updated = clock::timestamp_ms(clock) / 1000;
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
            last_updated: _,
            player_epoch: _,
            player_point_history,
            modules,
        } = self;

        table::drop<u64, Point>(player_point_history);
        balance::destroy_zero(balance);
        vec::destroy_empty(modules);
        object::delete(id);
    }

    fun checkpoint_(
        player_checkpoint: bool,
        self: &mut VSDBRegistry,
        new_locked_amount: u64,
        new_locked_end: u64,
        old_locked_amount: u64,
        old_locked_end: u64 ,
        clock: &Clock
    ){
        let time_stamp = clock::timestamp_ms(clock) / 1000;
        let old_dslope = i128::zero();
        let new_dslope = i128::zero();

        let u_old_slope = i128::zero();
        let u_old_bias = i128::zero();
        let u_new_slope = i128::zero();
        let u_new_bias = i128::zero();

        let epoch = self.epoch;

        if(player_checkpoint){
            if(old_locked_end > time_stamp && old_locked_amount > 0){
                u_old_slope = calculate_slope(old_locked_amount);
                u_old_bias = calculate_bias(old_locked_amount,  old_locked_end, time_stamp);
            };
            if(new_locked_end > time_stamp && new_locked_amount > 0){
                u_new_slope = calculate_slope(new_locked_amount);
                u_new_bias = calculate_bias(new_locked_amount, new_locked_end, time_stamp);
            };
            if(table::contains(&self.slope_changes, old_locked_end)){
                old_dslope = *table::borrow(&self.slope_changes, old_locked_end);
            };
            if(new_locked_end != 0){
                if(new_locked_end == old_locked_end){
                    // Action: increase_unlock_amount
                    new_dslope = old_dslope;
                }else{
                    // Action: increase_unlock_time, new d_slope has to be updated
                    if(table::contains(&self.slope_changes, new_locked_end)){
                        new_dslope = *table::borrow(&self.slope_changes, new_locked_end);
                    };
                }
            };
        };

        let last_point = if(epoch > 0){
            *table_vec::borrow(&self.point_history, epoch)
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

            if( t_i > time_stamp ){
                t_i = time_stamp;
            }else{
                // latest obsolete checkpoint
                if(table::contains(&self.slope_changes, t_i)){
                    d_slope = *table::borrow(&self.slope_changes, t_i);
                };
            };

            let time_left = i128::sub(&i128::from(((t_i as u128))), &i128::from((last_point_ts as u128)));

            last_point_bias = i128::sub(&last_point_bias, &i128::mul(&last_point_slope, &time_left));
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
                let point = point::new(last_point_bias, last_point_slope, last_point_ts);
                table_vec::push_back(&mut self.point_history, point);
            };

            i = i + 1;
        };

        // Now point_history is filled until t=now
        if (player_checkpoint) {
            // update the latest point
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
        let latest_point =  table_vec::borrow(&self.point_history, self.epoch);
        if(point::ts(latest_point) != last_point_ts || !i128::is_zero(&last_point_slope) || !i128::is_zero(&last_point_bias)){
            self.epoch = epoch;
            // Record the changed point into history
            let last_point = point::new(last_point_bias, last_point_slope, last_point_ts);
            // update latest epoch
            table_vec::push_back(&mut self.point_history, last_point);
        };

        if(player_checkpoint){
            // Schedule the slope changes (slope is going down)
            // We subtract new_user_slope from [new_locked.end]
            // and add old_user_slope to [old_locked.end]
            if (old_locked_end > time_stamp) {
                // old_dslope was <something> - u_old.slope, so we cancel that
                old_dslope = i128::add(&old_dslope, &u_old_slope);

                if (new_locked_end == old_locked_end) {
                    // Action: extend_amount, new deposit comes in
                    old_dslope = i128::sub(&old_dslope, &u_new_slope);
                };
                // update old_locked.end in slope_changes
                if(table::contains(&self.slope_changes, old_locked_end)){
                    *table::borrow_mut(&mut self.slope_changes, old_locked_end) = old_dslope;
                }else{
                    table::add(&mut self.slope_changes, old_locked_end, old_dslope);
                }
            };

            if (new_locked_end > time_stamp) {
                if (new_locked_end > old_locked_end) {
                    // Action: extend_unlock time
                    // old slope disappeared at this point
                    new_dslope =  i128::sub(&new_dslope, &u_new_slope);

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

    public fun module_exists(self: &Vsdb, name: vector<u8>):bool{
        vec::contains(&self.modules, &ascii::string(name))
    }

    public fun earn_xp<T: copy + store + drop>(_witness: T, self: &mut Vsdb, value: u64){
        let type = type_name::into_string(type_name::get<T>());
        assert!(vec::contains(&self.modules, &type), E_NOT_REGISTERED);
        self.experience = self.experience + value;
    }

    public fun upgrade(self: &mut Vsdb){
        let required_xp = required_xp(self.level + 1, self.level);
        while(self.experience >= required_xp){
            self.experience = self.experience - required_xp;
            self.level = self.level + 1;
            required_xp = required_xp(self.level + 1, self.level);
        };
    }

    /// Exp = (Level/ 0.2) ^ 2
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
        reg: & VSDBRegistry,
        self: &mut Vsdb,
        value: V
    ){
        let type = type_name::get<T>();
        assert!(table::contains(&reg.modules, type), E_NOT_REGISTERED);
        vec::push_back(&mut self.modules, type_name::into_string(type));
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
    /// registered module should check borrow_mut reference
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
        let (success, idx) = vec::index_of(&self.modules, &type_name::into_string(type_name::get<T>()));
        assert!(success, E_NOT_REGISTERED);
        vec::remove(&mut self.modules, idx);
        df::remove_if_exists(&mut self.id, witness)
    }
    public fun df_remove<T: copy + store + drop, V: store>(
        witness: T,
        self: &mut Vsdb,
    ):V{
        let (success, idx) = vec::index_of(&self.modules, &type_name::into_string(type_name::get<T>()));
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

        vec::push_back(&mut self.modules, type_name::into_string(type));
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
        let (success, idx) = vec::index_of(&self.modules, &type_name::into_string(type_name::get<T>()));
        assert!(success, E_NOT_REGISTERED);
        vec::remove(&mut self.modules, idx);
        dof::remove(&mut self.id, witness)
    }

    const SVG_PREFIX: vector<u8> = b"data:image/svg+xml;base64,";
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
        vec::append(&mut vesdb, encode(encoded_b));
        url::new_unsafe_from_bytes(vesdb)
    }
    public fun to_string(value: u256): std::string::String {
        if(value == 0) {
            return string::utf8(b"0")
         };
        let temp = value;
        let digits = 0;
        while (temp != 0) {
            digits = digits + 1;
            temp = temp / 10;
        };
        let retval = vec::empty<u8>();
        while (value != 0) {
            digits = digits - 1;

            vec::push_back(&mut retval, ((value % 10+ 48) as u8));
            value = value / 10;

        };
        vec::reverse(&mut retval);
        return string::utf8(retval)
    }

    #[test] fun test_toString(){
        let str = to_string(123123124312);
        assert!(string::bytes(&str) == &b"123123124312",1);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(VSDB{},ctx);
    }
}