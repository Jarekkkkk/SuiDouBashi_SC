module farm::farm{
    use suiDouBashi::pool::{Self, Pool, LP};
    use suiDouBashiVest::vsdb;

    const TOTAL_ALLOC_POINT: u64 = 100;
    /// 625K SDB distribution for duration 4 weeks
    const SDB_PER_SECOND: u64 = 258349867;
    const LOCK: u64 = { 36 * 7 * 86400 };
    const SCALE_FACTOR: u128 = 1_000_000_000_000;

    // ERROR
    const ERR_NOT_GOV: u64 = 001;
    const ERR_INVALID_TIME: u64 = 002;

    // EVENT
    struct Deposit<phantom X, phantom Y> has copy, drop{
        player: address,
        amount: u64
    }
    struct Withdraw<phantom X, phantom Y> has copy, drop{
        player: address,
        amount: u64
    }
    struct EmergencyWithdraw<phantom X, phantom Y> has copy, drop{
        player: address,
        amount: u64
    }
    struct Harvest<phantom X, phantom Y> has copy, drop{
        vsdb_id: ID,
        player: address,
        total_rewards: u64
    }

    // assert
    fun assert_governor(reg: &Reg, ctx: &mut TxContext){
        assert!(tx_context::sender(ctx) == reg.governor, ERR_NOT_GOV);
    }

    // ERROR

    struct Reg has key{
        id: UID,
        governor: address,
        start_time: u64,
        end_time: u64,
        /// 1e12 scaling
        sdb_per_second: u64,
        farms: Table<String, ID>
    }


    struct PlayerInfo has store{
        amount: u64,
        reward_debt: u64,
        pending_reward: u64
    }

    struct Farm<X,Y> has key{
        lp_balance: LP<X,Y>,
        alloc_point: u64,
        last_reward_time: u64,
        acc_sdb_per_share: u128,

        player_infos: Table<address, PlayerInfo>,
    }


    fun init(ctx: &mut TxContext){
        let reg = Reg{
            id: object::new(ctx),
            governor: tx_context::sender(ctx),
            start_time: 0,
            end_time: 0,
            total_alloc_point: 0,
            sdb_per_second: 0,
            farms: table::new<String, ID>(ctx)
        };

        transfer::share_object(reg);
    }

    public fun add_farm<X,Y>(reg: &Reg, pool: &Pool<X,Y>, alloc_point: u64, clock: &Clock, ctx: &mut TxContext){
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

        transfer::share_object(farm);
    }

    public entry fun set_time(reg: &mut Reg, start_time: u64, duration: u64, clock: &Clock, ctx: &mut TxContext){
        assert_governor(reg, ctx);
        assert!(start_time >  clock::timestamp_ms(clock) ,ERR_INVALID_TIME);

        reg.start_time = start_time;
        reg.end_time = start_time + duration * 86400;
    }

    public entry fun set_sdb_per_second(reg: &mut Reg, sdb_per_second: u64, ctx: &mut TxContext){
        assert_governor(reg, ctx);
        reg.sdb_per_second = sdb_per_second;
    }


    // getter
       function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        _from = _from > startTime ? _from : startTime;
        if (_to < startTime || _from >= endTime) {
            return 0;
        } else if (_to <= endTime) {
            return _to - _from;
        } else {
            return endTime - _from;
        }
    }

    public fun get_multiplier(reg:&Reg, from: u64, to: u64):u64{
        let from = if(from > reg.start_time){
            from
        }else{
            reg.start_time
        };

        if(to < start_time || from > reg.end_time){
            return 0
        }else if( to <= reg.end_time ){
            return to - from
        }else{
            return reg.end_time - from
        };
    }

    public fun pending_rewards<X,Y>(self: &Farm<X,Y>, player: address, clock: &Clock): u64{
        if(!table::contains(&self.player_infos, player)) return 0;

        let ts = clock::timestamp_ms(clock);
        let player_info = table::borrow(&self.player_infos, player);
        let acc_sdb_per_share = self.acc_sdb_per_share;
        let lp_balance = pool::lp_balance(&self.lp_balance);

        if(ts > self.last_reward_time && lp_balance != 0){
            let multiplier = get_multiplier(reg, last_reward_time, ts);
            let sdb_reward = multiplier * sdb_per_second * farm.alloc_point / total_alloc_point;
            farm.acc_sdb_per_share = farm.acc_sdb_per_share + ((sdb_reward as u128) * SCALE_FACTOR / (lp_balance as u128))
        };

        return (((player_info.amount as u128) * farm.acc_sdb_per_share / SCALE_FACTOR ) as u64 ) - player_info.reward_debt + player_info.pending_reward
    }

}