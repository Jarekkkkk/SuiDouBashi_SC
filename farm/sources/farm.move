module suiDouBashi_farm::farm{
    use suiDouBashi_amm::pool::{Self, Pool, LP};
    use suiDouBashi_amm::pool_reg;
    use suiDouBashi_vsdb::vsdb::{Self, VSDBRegistry};
    use suiDouBashi_vsdb::sdb::SDB;
    use sui::event::emit;

    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, ID, UID};
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};
    use std::string::String;
    use sui::vec_map::{Self, VecMap};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};

    const TOTAL_ALLOC_POINT: u64 = 100;
    /// 625K SDB distribution for 4 weeks duration
    const SDB_PER_SECOND: u64 = 258349867;
    const LOCK: u64 = { 36 * 7 * 86400 };
    const SCALE_FACTOR: u256 = 1_000_000_000_000_000_000;

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

    // EVENT
    struct Stake<phantom X, phantom Y> has copy, drop{
        player: address,
        amount: u64
    }
    struct Unstake<phantom X, phantom Y> has copy, drop{
        player: address,
        amount: u64
    }
    struct Harvest<phantom X, phantom Y> has copy, drop{
        player: address,
        reward: u64
    }

    // assert
    fun assert_governor(reg: &FarmReg, ctx: &mut TxContext){
        assert!(tx_context::sender(ctx) == reg.governor, ERR_NOT_GOV);
    }
    fun assert_setup(reg: &FarmReg){
        assert!(reg.total_acc_points == TOTAL_ALLOC_POINT, ERR_NOT_SETUP);
    }

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
        total_pending: Table<address, u64>
    }

    public fun get_sdb_balance(reg: &FarmReg):u64{ balance::value(&reg.sdb_balance)}
    public fun get_start_time(reg: &FarmReg):u64 {reg.start_time }
    public fun get_end_time(reg: &FarmReg):u64 {reg.end_time }
    public fun sdb_per_second(reg: &FarmReg): u64 { reg.sdb_per_second }
    public fun total_pending(reg: &FarmReg, player: address): u64 { *table::borrow(&reg.total_pending, player )}

    struct Farm<phantom X, phantom Y> has key{
        id: UID,
        lp_balance: LP<X,Y>,
        alloc_point: u64,
        last_reward_time: u64,
        index: u256,
        player_infos: Table<address, PlayerInfo>,
    }

    struct PlayerInfo has copy, store{
        amount: u64,
        index: u256,
        pending_reward: u64
    }

    public fun get_farm_lp<X,Y>(self: &Farm<X,Y>): u64 { pool::get_lp_balance(&self.lp_balance)}


    fun init(ctx: &mut TxContext){
        let reg = FarmReg{
            id: object::new(ctx),
            initialized: false,
            governor: tx_context::sender(ctx),
            sdb_balance: balance::zero<SDB>(),
            total_acc_points: 0,
            start_time: 0,
            end_time: 0,
            sdb_per_second: 0,
            farms: vec_map::empty<String, ID>(),
            total_pending: table::new<address, u64>(ctx)
        };

        transfer::share_object(reg);
    }

    public fun initialize(
        reg: &mut FarmReg,
        start_time: u64,
        duration: u64,
        sdb: Coin<SDB>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert_governor(reg, ctx);
        assert!(!reg.initialized, ERR_INITIALIZED);
        assert!(start_time > clock::timestamp_ms(clock) / 1000 || duration != 0, ERR_INVALID_TIME);

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
        pool: &Pool<X,Y>,
        alloc_point: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert_governor(reg, ctx);
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
            player_infos: table::new<address, PlayerInfo>(ctx),
        };

        let pool_name = pool_reg::get_pool_name<X,Y>();
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

    public fun pending_rewards<X,Y>(self: &Farm<X,Y>, reg: &FarmReg, player: address, clock: &Clock): u64{
        if(!table::contains(&self.player_infos, player)) return 0;

        let ts = clock::timestamp_ms(clock) / 1000;
        let player_info = table::borrow(&self.player_infos, player);
        let index = self.index;
        let lp_balance = pool::get_lp_balance(&self.lp_balance);

        if(ts > self.last_reward_time && lp_balance != 0){
            let multiplier = get_multiplier(reg, self.last_reward_time, ts);
            let sdb_reward = multiplier * reg.sdb_per_second * self.alloc_point / TOTAL_ALLOC_POINT;
            index = index + ((sdb_reward as u256) * SCALE_FACTOR / (lp_balance as u256))
        };

        return (((player_info.amount as u256) * ( index - player_info.index ) / SCALE_FACTOR ) as u64 ) + player_info.pending_reward
    }

    /// settle accumulated rewards
    fun update_farm<X,Y>(reg: &FarmReg, self: &mut Farm<X,Y>, clock: &Clock){
        let ts = clock::timestamp_ms(clock) / 1000;

        if(ts <= self.last_reward_time) return;

        let lp_balance = pool::get_lp_balance(&self.lp_balance);
        if(lp_balance == 0){
            self.last_reward_time = ts;
            return
        };

        let multiplier = get_multiplier(reg, self.last_reward_time, ts);
        let sdb_reward = multiplier * reg.sdb_per_second * self.alloc_point / TOTAL_ALLOC_POINT;

        self.index = self.index + ((sdb_reward as u256) * SCALE_FACTOR / (lp_balance as u256));
        self.last_reward_time = ts;
    }

    fun update_player<X,Y>(self: &mut Farm<X,Y>, player: address){
        let player_info = table::borrow_mut(&mut self.player_infos, player);
        let staked = player_info.amount;
        if(staked > 0){
            let delta = self.index - player_info.index;
            player_info.index = self.index;

            if(delta > 0){
                let share = (staked as u256) * delta / SCALE_FACTOR;
                player_info.pending_reward = player_info.pending_reward + (share as u64);
            };
        }else{
            player_info.index = self.index;
        };
    }

    public fun stake<X,Y>(
        reg: &FarmReg,
        self: &mut Farm<X,Y>,
        pool: &Pool<X,Y>,
        lp: &mut LP<X,Y>,
        value: u64,
        clock: &Clock,
        ctx:&mut TxContext
    ){
        assert_setup(reg);
        let player = tx_context::sender(ctx);
        if(!table::contains(&self.player_infos, player)){
            let player_info = PlayerInfo{
                amount: 0,
                index: 0,
                pending_reward: 0
            };
            table::add(&mut self.player_infos, player, player_info);
        };
        update_farm(reg, self, clock);
        update_player(self, player);

        let player_info = table::borrow_mut(&mut self.player_infos, player);
        pool::join_lp(pool, &mut self.lp_balance, lp, value);
        player_info.amount = player_info.amount + value;

        emit(
            Stake<X,Y>{
                player,
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
        clock:&Clock,
        ctx:&mut TxContext
    ){
        assert_setup(reg);
        let player = tx_context::sender(ctx);
        assert!(table::contains(&self.player_infos, player), ERR_NOT_PLAYER);

        update_farm(reg, self, clock);
        update_player(self, player);

        let player_info = table::borrow_mut(&mut self.player_infos, player);
        assert!(player_info.amount >= value, ERR_INSUFFICIENT_LP);
        player_info.amount = player_info.amount - value;
        pool::join_lp(pool, lp, &mut self.lp_balance, value);

        emit(
            Unstake<X,Y>{
                player,
                amount: value
            }
        );
    }

    public fun harvest<X,Y>(
        reg: &mut FarmReg,
        self: &mut Farm<X,Y>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert_setup(reg);
        let player = tx_context::sender(ctx);
        assert!(table::contains(&self.player_infos, player), ERR_NOT_PLAYER);

        update_farm(reg, self, clock);
        update_player(self, player);

        let player_info = table::borrow_mut(&mut self.player_infos, player);
        let pending = player_info.pending_reward;
        if(pending > 0){
            if(!table::contains(&reg.total_pending, player)){
                table::add(&mut reg.total_pending, player, pending);
            }else{
                *table::borrow_mut(&mut reg.total_pending, player) = *table::borrow(&reg.total_pending, player) + pending;
            };
        };
        player_info.pending_reward = 0;

        emit(
            Harvest<X,Y>{
                player,
                reward: pending
            }
        )
    }

    public fun claim_vsdb(
        reg: &mut FarmReg,
        vsdb_reg: &mut VSDBRegistry,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert_setup(reg);
        let player = tx_context::sender(ctx);
        assert!(table::contains(&reg.total_pending, player) && *table::borrow(&reg.total_pending, player) > 0, ERR_NO_REWARD);
        assert!(clock::timestamp_ms(clock) / 1000 >= reg.end_time, ERR_NOT_FINISH);
        let reward = table::borrow(&reg.total_pending, player);
        let sdb = coin::take(&mut reg.sdb_balance, *reward, ctx);
        vsdb::lock(vsdb_reg, sdb, LOCK, clock, ctx);

        table::remove(&mut reg.total_pending, player);
    }

    // TODO: collect the Pool fees during farming campaign

    #[test_only] public fun init_for_testing( ctx: &mut TxContext) { init(ctx) }
}