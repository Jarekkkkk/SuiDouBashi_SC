module farm::farm{
    use suiDouBashi::pool::{Self, Pool, LP};
    use suiDouBashi::pool_reg;
    use suiDouBashiVest::vsdb::{Self, VSDBRegistry};
    use suiDouBashiVest::sdb::SDB;
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
    /// 625K SDB distribution for duration 4 weeks
    const SDB_PER_SECOND: u64 = 258349867;
    const LOCK: u64 = { 36 * 7 * 86400 };
    const SCALE_FACTOR: u128 = 1_000_000_000_000;

    // ERROR
    const ERR_INITIALIZED: u64 = 000;
    const ERR_NOT_GOV: u64 = 001;
    const ERR_INVALID_TIME: u64 = 002;
    const ERR_NOT_PLAYER: u64 = 003;
    const ERR_INSUFFICIENT_LP: u64 = 004;
    const ERR_NO_REWARD: u64 = 005;

    // EVENT
    struct Stake<phantom X, phantom Y> has copy, drop{
        player: address,
        amount: u64
    }
    struct Unstake<phantom X, phantom Y> has copy, drop{
        player: address,
        amount: u64
    }
    struct EmergencyWithdraw<phantom X, phantom Y> has copy, drop{
        player: address,
        amount: u64
    }
    struct Harvest<phantom X, phantom Y> has copy, drop{
        player: address,
        reward: u64
    }

    // assert
    fun assert_governor(reg: &Reg, ctx: &mut TxContext){
        assert!(tx_context::sender(ctx) == reg.governor, ERR_NOT_GOV);
    }

    // ERROR

    // TODO: move start_time & end_time to const, which relieve the usage of reg object in every function
    struct Reg has key{
        id: UID,
        initialized: bool,
        governor: address,
        sdb_balance: Balance<SDB>,
        start_time: u64,
        end_time: u64,
        /// 1e12 scaling
        sdb_per_second: u64,
        farms: VecMap<String, ID>,
        total_pending: Table<address, u64>
    }

    public fun get_sdb_balance(reg: &Reg):u64{ balance::value(&reg.sdb_balance)}
    public fun get_start_time(reg: &Reg):u64 {reg.start_time }
    public fun get_end_time(reg: &Reg):u64 {reg.end_time }
    public fun sdb_per_second(reg: &Reg): u64 { reg.sdb_per_second }

    struct PlayerInfo has copy, store{
        amount: u64,
        reward_debt: u64,
        pending_reward: u64
    }

    struct Farm<phantom X, phantom Y> has key{
        id: UID,
        lp_balance: LP<X,Y>,
        alloc_point: u64,
        last_reward_time: u64,
        acc_sdb_per_share: u128,

        player_infos: Table<address, PlayerInfo>,
    }

    public fun get_farm_lp<X,Y>(self: &Farm<X,Y>): u64 { pool::get_lp_balance(&self.lp_balance)}

    fun init(ctx: &mut TxContext){
        let reg = Reg{
            id: object::new(ctx),
            initialized: false,
            governor: tx_context::sender(ctx),
            sdb_balance: balance::zero<SDB>(),
            start_time: 0,
            end_time: 0,

            sdb_per_second: 0,
            farms: vec_map::empty<String, ID>(),
            total_pending: table::new<address, u64>(ctx)
        };

        transfer::share_object(reg);
    }

    public fun initialize(
        reg: &mut Reg,
        start_time: u64,
        duration: u64,
        sdb: Coin<SDB>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert_governor(reg, ctx);
        assert!(!reg.initialized, ERR_INITIALIZED);
        assert!(start_time > clock::timestamp_ms(clock) || duration != 0, ERR_INVALID_TIME);

        let end_time = start_time + duration;
        let sdb_per_second = coin::value(&sdb) / duration;

        reg.initialized = true;
        coin::put(&mut reg.sdb_balance, sdb);
        reg.start_time = start_time;
        reg.end_time = end_time;
        reg.sdb_per_second = sdb_per_second;
    }

    public fun add_farm<X,Y>(
        reg: &mut Reg,
        pool: &Pool<X,Y>,
        alloc_point: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert_governor(reg, ctx);

        let ts = clock::timestamp_ms(clock);

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
            acc_sdb_per_share:0,
            player_infos: table::new<address, PlayerInfo>(ctx),
        };

        let pool_name = pool_reg::get_pool_name<X,Y>();
        vec_map::insert(&mut reg.farms, pool_name, object::id(&farm));

        transfer::share_object(farm);
    }

    public fun get_multiplier(reg:&Reg, from: u64, to: u64):u64{
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

    public fun pending_rewards<X,Y>(self: &Farm<X,Y>, reg: &Reg, player: address, clock: &Clock): u64{
        if(!table::contains(&self.player_infos, player)) return 0;

        let ts = clock::timestamp_ms(clock);
        let player_info = table::borrow(&self.player_infos, player);
        let acc_sdb_per_share = self.acc_sdb_per_share;
        let lp_balance = pool::get_lp_balance(&self.lp_balance);

        if(ts > self.last_reward_time && lp_balance != 0){
            let multiplier = get_multiplier(reg, self.last_reward_time, ts);
            let sdb_reward = multiplier * reg.sdb_per_second * self.alloc_point / TOTAL_ALLOC_POINT;
            acc_sdb_per_share = acc_sdb_per_share + ((sdb_reward as u128) * SCALE_FACTOR / (lp_balance as u128))
        };

        return (((player_info.amount as u128) * acc_sdb_per_share / SCALE_FACTOR ) as u64 ) - player_info.reward_debt + player_info.pending_reward
    }

    public fun update_farm<X,Y>(reg: &Reg, self: &mut Farm<X,Y>, clock: &Clock){
        let ts = clock::timestamp_ms(clock);

        if(ts <= self.last_reward_time) return;

        let lp_balance = pool::get_lp_balance(&self.lp_balance);
        if(lp_balance == 0){
            self.last_reward_time = ts;
            return
        };

        let multiplier = get_multiplier(reg, self.last_reward_time, ts);
        let sdb_reward = multiplier * reg.sdb_per_second * self.alloc_point / TOTAL_ALLOC_POINT;

        self.acc_sdb_per_share  = self.acc_sdb_per_share + ( (sdb_reward as u128) * SCALE_FACTOR / (lp_balance as u128) );
        self.last_reward_time = ts;
    }

    public fun stake<X,Y>(
        reg: &Reg,
        self: &mut Farm<X,Y>,
        pool: &Pool<X,Y>,
        lp: &mut LP<X,Y>,
        value: u64,
        clock:&Clock,
        ctx:&mut TxContext
    ){
        update_farm(reg, self, clock);

        let player = tx_context::sender(ctx);

        if(!table::contains(&self.player_infos, player)){
            let player_info = PlayerInfo{
                amount: 0,
                reward_debt: 0,
                pending_reward: 0
            };
            table::add(&mut self.player_infos, player, player_info);
        };

        let player_info = table::borrow_mut(&mut self.player_infos, player);
        let pending = (player_info.amount as u128) * (self.acc_sdb_per_share as u128) / SCALE_FACTOR - (player_info.reward_debt as u128);

        pool::join_lp(pool, &mut self.lp_balance, lp, value);
        player_info.amount = player_info.amount + value;
        player_info.reward_debt = (((player_info.amount as u128) * self.acc_sdb_per_share / SCALE_FACTOR) as u64);
        player_info.pending_reward = player_info.pending_reward + (pending as u64);

        emit(
            Stake<X,Y>{
                player,
                amount: value
            }
        );
    }

    public fun unstake<X,Y>(
        reg: &Reg,
        self: &mut Farm<X,Y>,
        lp: &mut LP<X,Y>,
        pool: &Pool<X,Y>,
        value: u64,
        clock:&Clock,
        ctx:&mut TxContext
    ){
        let player = tx_context::sender(ctx);
        assert!(table::contains(&self.player_infos, player), ERR_NOT_PLAYER);
        update_farm(reg, self, clock);


        let player_info = table::borrow_mut(&mut self.player_infos, player);
        assert!(player_info.amount >= value, ERR_INSUFFICIENT_LP);

        let pending = (player_info.amount as u128) * (self.acc_sdb_per_share as u128) / SCALE_FACTOR - (player_info.reward_debt as u128);

        player_info.amount = player_info.amount - value;
        player_info.reward_debt = (((player_info.amount as u128) * self.acc_sdb_per_share / SCALE_FACTOR) as u64);

        player_info.pending_reward = player_info.pending_reward + (pending as u64);

        pool::join_lp(pool, lp, &mut self.lp_balance, value);

        emit(
            Unstake<X,Y>{
                player,
                amount: value
            }
        );
    }

    public fun harvest<X,Y>(
        reg: &mut Reg,
        self: &mut Farm<X,Y>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        let player = tx_context::sender(ctx);
        assert!(table::contains(&self.player_infos, player), ERR_NOT_PLAYER);

        update_farm(reg, self, clock);
        let player_info = table::borrow_mut(&mut self.player_infos, player);

        let calc = (((player_info.amount as u128) * (self.acc_sdb_per_share as u128) / SCALE_FACTOR) as u64);
        let pending = calc - player_info.reward_debt + player_info.pending_reward;
        player_info.reward_debt = calc;

        if(pending > 0){
            if(!table::contains(&reg.total_pending, player)){
                table::add(&mut reg.total_pending, player, pending);
            }else{
                *table::borrow_mut(&mut reg.total_pending, player) = *table::borrow(&reg.total_pending, player) + pending;
            };
        };

        emit(
            Harvest<X,Y>{
                player,
                reward: pending
            }
        )
    }

    public fun claim_vsdb(
        reg: &mut Reg,
        vsdb_reg: &mut VSDBRegistry,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        let player = tx_context::sender(ctx);
        assert!(table::contains(&reg.total_pending, player) && *table::borrow(&reg.total_pending, player) > 0, ERR_NO_REWARD);

        let reward = table::borrow_mut(&mut reg.total_pending, player);

        let sdb = coin::take(&mut reg.sdb_balance, *reward, ctx);
        vsdb::lock_for(vsdb_reg, sdb, LOCK, player, clock, ctx);

        table::remove(&mut reg.total_pending, player);
    }

    #[test_only] public fun init_for_testing(ctx: &mut TxContext) { init(ctx) }
}