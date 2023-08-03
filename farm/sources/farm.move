module suiDouBashi_farm::farm{
    use suiDouBashi_amm::pool::{Self, Pool, LP};
    use suiDouBashi_vsdb::vsdb::{Self, VSDBRegistry, Vsdb};
    use suiDouBashi_vsdb::sdb::SDB;
    use std::string::String;
    use std::option;
    use sui::event::emit;
    use sui::tx_context::{Self, TxContext, sender};
    use sui::object::{Self, ID, UID};
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};
    use sui::vec_map::{Self, VecMap};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};

    const TOTAL_ALLOC_POINT: u64 = 100;
    const SCALE_FACTOR: u256 = 1_000_000_000_000_000_000;
    const WEEK: u64 = { 7 * 86400 };

    // ERROR
    const ERR_INITIALIZED: u64 = 000;
    const ERR_NOT_GOV: u64 = 001;
    const ERR_INVALID_TIME: u64 = 002;
    const ERR_NOT_PLAYER: u64 = 003;
    const ERR_INSUFFICIENT_LP: u64 = 004;
    const ERR_NO_REWARD: u64 = 005;
    const ERR_NOT_FINISH: u64 = 006;
    const ERR_INVALID_POINT: u64 = 007;
    const ERR_NOT_SETUP: u64 = 008;
    const E_ALREADY_CLAIMED: u64 = 009;
    const E_INVALID_PERIOD: u64 = 010;

    // EVENT
    struct Deposit<phantom X, phantom Y> has copy, drop{
        id: ID,
        amount: u64
    }
    struct Unstake<phantom X, phantom Y> has copy, drop{
        id: ID,
        amount: u64
    }
    struct Harvest<phantom X, phantom Y> has copy, drop{
        sender: address,
        reward: u64
    }

    // assert
    fun assert_setup(reg: &FarmReg){
        assert!(reg.total_acc_points == TOTAL_ALLOC_POINT, ERR_NOT_SETUP);
    }

    struct VSDB has drop {}

    struct FarmCap has key { id: UID }

    struct FarmReg has key{
        id: UID,
        initialized: bool,
        governor: address,
        sdb_balance: Balance<SDB>,
        total_acc_points: u64,
        start_time: u64,
        end_time: u64,
        sdb_per_second: u64,
        farms: VecMap<String, ID>,
        total_pending: Table<address, u64>,
        claimed_vsdb: Table<address, ID>
    }

    public fun get_sdb_balance(reg: &FarmReg):u64{ balance::value(&reg.sdb_balance)}
    public fun get_start_time(reg: &FarmReg):u64 {reg.start_time }
    public fun get_end_time(reg: &FarmReg):u64 {reg.end_time }
    public fun sdb_per_second(reg: &FarmReg): u64 { reg.sdb_per_second }
    public fun total_pending(reg: &FarmReg, id: address): u64 { *table::borrow(&reg.total_pending, id )}

    struct Farm<phantom X, phantom Y> has key{
        id: UID,
        lp_balance: LP<X,Y>,
        alloc_point: u64,
        last_reward_time: u64,
        index: u256,
        lp_stake: Table<ID, Stake>,
    }

    struct Stake has store{
        amount: u64,
        index: u256,
        pending_reward: u64
    }

    public fun farm_lp<X,Y>(self: &Farm<X,Y>):&LP<X,Y> { &self.lp_balance }

    fun init(ctx: &mut TxContext){
        let reg = FarmReg {
            id: object::new(ctx),
            initialized: false,
            governor: tx_context::sender(ctx),
            sdb_balance: balance::zero<SDB>(),
            total_acc_points: 0,
            start_time: 0,
            end_time: 0,
            sdb_per_second: 0,
            farms: vec_map::empty<String, ID>(),
            total_pending: table::new<address, u64>(ctx),
            claimed_vsdb: table::new<address, ID>(ctx)
        };
        transfer::share_object(reg);

        transfer::transfer(FarmCap{ id: object::new(ctx) }, sender(ctx));
    }

    public fun initialize(
        reg: &mut FarmReg,
        _: &FarmCap,
        start_time: u64,
        duration: u64,
        sdb: Coin<SDB>,
        clock: &Clock
    ){
        assert!(!reg.initialized, ERR_INITIALIZED);
        assert!(start_time > clock::timestamp_ms(clock) / 1000 && duration != 0, ERR_INVALID_TIME);

        let end_time = start_time + duration;
        let sdb_per_second = coin::value(&sdb) / duration;

        reg.initialized = true;
        coin::put(&mut reg.sdb_balance, sdb);
        reg.start_time = start_time;
        reg.end_time = end_time;
        reg.sdb_per_second = sdb_per_second;
    }

    /// Here's some modifications from orignal MasterChef smart contract,
    /// 1. remove dynamic alloc_points setting that requires all pools update
    /// 2. total alloc points have to be fully distributed before start_time
    public fun add_farm<X,Y>(
        reg: &mut FarmReg,
        _: &FarmCap,
        pool: &Pool<X,Y>,
        alloc_point: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(alloc_point <= TOTAL_ALLOC_POINT, ERR_INVALID_POINT);

        let ts = clock::timestamp_ms(clock) / 1000;

        let last_reward_time = if(ts > reg.start_time){
            ts
        }else{
            reg.start_time
        };
        let farm = Farm{
            id: object::new(ctx),
            lp_balance: pool::create_lp(pool, ctx),
            alloc_point,
            last_reward_time,
            index:0,
            lp_stake: table::new<ID, Stake>(ctx),
        };

        let pool_name = pool::name<X,Y>(pool);
        vec_map::insert(&mut reg.farms, pool_name, object::id(&farm));
        reg.total_acc_points = reg.total_acc_points + alloc_point;
        assert!(reg.total_acc_points <= TOTAL_ALLOC_POINT, ERR_INVALID_POINT);

        transfer::share_object(farm);
    }

    public fun get_multiplier(reg:&FarmReg, from: u64, to: u64):u64{
        let from = if(from > reg.start_time){
            from
        }else{
            reg.start_time
        };

        if(to < reg.start_time || from > reg.end_time){
            return 0
        }else if( to <= reg.end_time ){
            return to - from
        }else{
            return reg.end_time - from
        }
    }

    public fun pending_rewards<X,Y>(self: &Farm<X,Y>, reg: &FarmReg, lp: &LP<X,Y>, clock: &Clock): u64{
        let id = object::id(lp);
        if(!table::contains(&self.lp_stake, id)) return 0;

        let ts = clock::timestamp_ms(clock) / 1000;
        let stake = table::borrow(&self.lp_stake, id);
        let index = self.index;
        let lp_balance = pool::lp_balance(&self.lp_balance);

        if(ts > self.last_reward_time && lp_balance != 0){
            let multiplier = get_multiplier(reg, self.last_reward_time, ts);
            let sdb_reward = multiplier * reg.sdb_per_second * self.alloc_point / TOTAL_ALLOC_POINT;
            index = index + ((sdb_reward as u256) * SCALE_FACTOR / (lp_balance as u256))
        };

        return (((stake.amount as u256) * ( index - stake.index ) / SCALE_FACTOR ) as u64 ) + stake.pending_reward
    }

    /// settle accumulated rewards
    fun update_farm<X,Y>(reg: &FarmReg, self: &mut Farm<X,Y>, clock: &Clock){
        let ts = clock::timestamp_ms(clock) / 1000;

        if(ts <= self.last_reward_time) return;

        let lp_balance = pool::lp_balance(&self.lp_balance);
        if(lp_balance == 0){
            self.last_reward_time = ts;
            return
        };

        let multiplier = get_multiplier(reg, self.last_reward_time, ts);
        let sdb_reward = multiplier * reg.sdb_per_second * self.alloc_point / TOTAL_ALLOC_POINT;

        self.index = self.index + ((sdb_reward as u256) * SCALE_FACTOR / (lp_balance as u256));
        self.last_reward_time = ts;
    }

    fun update_player<X,Y>(self: &mut Farm<X,Y>, lp: &LP<X,Y>){
        let id = object::id(lp);
        let stake = table::borrow_mut(&mut self.lp_stake, id);
        let staked = stake.amount;
        if(staked > 0){
            let delta = self.index - stake.index;

            if(delta > 0){
                let share = (staked as u256) * delta / SCALE_FACTOR;
                stake.pending_reward = stake.pending_reward + (share as u64);
            };
        };
        stake.index = self.index;
    }

    public fun stake_all<X,Y>(
        reg: &FarmReg,
        self: &mut Farm<X,Y>,
        pool: &Pool<X,Y>,
        lp: &mut LP<X,Y>,
        clock: &Clock
    ){
        let lp_balance = pool::lp_balance(lp);
        stake(reg, self, pool, lp, lp_balance, clock);
    }

    public fun stake<X,Y>(
        reg: &FarmReg,
        self: &mut Farm<X,Y>,
        pool: &Pool<X,Y>,
        lp: &mut LP<X,Y>,
        value: u64,
        clock: &Clock
    ){
        assert_setup(reg);
        let lp_balance = pool::lp_balance(lp);
        let id = object::id(lp);
        assert!(lp_balance >= value, ERR_INSUFFICIENT_LP);

        if(!table::contains(&self.lp_stake, id)){
            let stake = Stake{
                amount: 0,
                index: 0,
                pending_reward: 0
            };
            table::add(&mut self.lp_stake, id, stake);
        };
        update_farm(reg, self, clock);
        update_player(self, lp);

        let stake = table::borrow_mut(&mut self.lp_stake, id);
        pool::join_lp(pool, &mut self.lp_balance, lp, value);
        stake.amount = stake.amount + value;

        emit(
            Deposit<X,Y>{
                id,
                amount: value
            }
        );
    }

    public fun unstake<X,Y>(
        reg: &FarmReg,
        self: &mut Farm<X,Y>,
        pool: &Pool<X,Y>,
        lp: &mut LP<X,Y>,
        value: u64,
        clock:&Clock
    ){
        assert_setup(reg);
        let id = object::id(lp);
        assert!(table::contains(&self.lp_stake, id), ERR_NOT_PLAYER);

        update_farm(reg, self, clock);
        update_player(self, lp);

        let stake = table::borrow_mut(&mut self.lp_stake, id);
        assert!(stake.amount >= value, ERR_INSUFFICIENT_LP);
        stake.amount = stake.amount - value;
        pool::join_lp(pool, lp, &mut self.lp_balance, value);

        emit(
            Unstake<X,Y>{
                id,
                amount: value
            }
        );
    }

    public fun unstake_all<X,Y>(
        reg: &FarmReg,
        self: &mut Farm<X,Y>,
        pool: &Pool<X,Y>,
        lp: &mut LP<X,Y>,
        clock:&Clock
    ){
        let id = object::id(lp);
        let stake = table::borrow(&mut self.lp_stake, id);
        unstake(reg, self, pool, lp, stake.amount, clock);
    }

    public fun harvest<X,Y>(
        reg: &mut FarmReg,
        self: &mut Farm<X,Y>,
        clock: &Clock,
        lp: &LP<X,Y>,
        ctx: &mut TxContext
    ){
        assert_setup(reg);
        let id = object::id(lp);
        let sender = sender(ctx);
        assert!(table::contains(&self.lp_stake, id), ERR_NOT_PLAYER);

        update_farm(reg, self, clock);
        update_player(self, lp);

        let stake = table::borrow_mut(&mut self.lp_stake, id);
        let pending = stake.pending_reward;
        if(pending > 0){
            if(!table::contains(&reg.total_pending, sender)){
                table::add(&mut reg.total_pending, sender, pending);
            }else{
                *table::borrow_mut(&mut reg.total_pending, sender) = *table::borrow(&reg.total_pending, sender) + pending;
            };
        };
        stake.pending_reward = 0;

        emit(
            Harvest<X,Y>{
                sender,
                reward: pending
            }
        )
    }

    public fun claim(
        reg: &mut FarmReg,
        vsdb_reg: &mut VSDBRegistry,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(clock::timestamp_ms(clock) / 1000 >= reg.end_time, ERR_NOT_FINISH);
        let sdb = claim_(reg, ctx);
        vsdb::lock(vsdb_reg, sdb, vsdb::max_time(), clock, ctx);
    }

    public fun claim_vsdb(
        reg: &mut FarmReg,
        vsdb_reg: &mut VSDBRegistry,
        vsdb: &mut Vsdb,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        let id = tx_context::sender(ctx);
        assert!(!table::contains(&reg.claimed_vsdb, id), E_ALREADY_CLAIMED);
        let ts = clock::timestamp_ms(clock) / 1000;
        assert!(ts >= reg.end_time && ts <= reg.end_time * WEEK, E_INVALID_PERIOD);
        let sdb = claim_(reg, ctx);
        vsdb::increase_unlock_amount(vsdb_reg, vsdb, sdb, clock);

        let exp = vsdb::experience(vsdb);
        if(exp >= 24){
            earn_xp_(vsdb_reg, vsdb, 20);
        }else if(exp >= 20){
            earn_xp_(vsdb_reg, vsdb, 10);
        }else if(exp >= 16){
            earn_xp_(vsdb_reg, vsdb, 5);
        };

        table::add(&mut reg.claimed_vsdb, id, object::id(vsdb));
    }

    fun claim_(
        reg: &mut FarmReg,
        ctx: &mut TxContext
    ):Coin<SDB>{
        assert_setup(reg);
        let id = tx_context::sender(ctx);
        assert!(table::contains(&reg.total_pending, id) && *table::borrow(&reg.total_pending, id) > 0, ERR_NO_REWARD);
        let reward = table::remove(&mut reg.total_pending, id);
        coin::take(&mut reg.sdb_balance, reward, ctx)
    }

    fun earn_xp_(
        vsdb_reg: &mut VSDBRegistry,
        vsdb: &mut Vsdb,
        exp: u64
    ){
        vsdb::df_add(VSDB{}, vsdb_reg, vsdb, true);
        vsdb::earn_xp(VSDB{}, vsdb, exp);
        vsdb::df_remove<VSDB, bool>(VSDB{}, vsdb);
    }

    /// Claim the accumulated fees during farming campaign and deposit it into pool
    public entry fun claim_pool_fees<X,Y>(
        reg: &FarmReg,
        _: &FarmCap,
        self: &mut Farm<X,Y>,
        pool: &mut Pool<X,Y>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(clock::timestamp_ms(clock) / 1000 >= reg.end_time, ERR_NOT_FINISH);
        let (coin_x, coin_y, _, _) = pool::claim_fees_dev(pool, &mut self.lp_balance, ctx);

        if(option::is_some(&coin_x)){
            transfer::public_transfer(option::extract(&mut coin_x), sender(ctx));
        };
        if(option::is_some(&coin_y)){
            transfer::public_transfer(option::extract(&mut coin_y), sender(ctx));
        };

        option::destroy_none(coin_x);
        option::destroy_none(coin_y);
    }

    #[test_only] public fun init_for_testing( ctx: &mut TxContext) { init(ctx) }
}