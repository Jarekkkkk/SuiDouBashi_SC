// Gauges are used to incentivize pools, they emit reward tokens over 7 days for staked LP tokens
module suiDouBashi_vote::gauge{
    use std::option;

    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::clock::{Self, Clock};
    use sui::math;

    use suiDouBashi_vsdb::sdb::SDB;
    use suiDouBashi_vote::event;
    use suiDouBashi_amm::pool::{Self, Pool, LP};
    use suiDouBashi_vote::bribe::{Self, Rewards};
    use suiDouBashi_vote::minter::package_version;

    friend suiDouBashi_vote::voter;

    // ====== Constants =======

    const WEEK: u64 = { 7 * 86400 };
    const PRECISION: u256 = 1_000_000_000_000_000_000;
    const MAX_U64: u64 = 18446744073709551615_u64;

    // ====== Constants =======

    // ====== Error =======

    const E_WRONG_VERSION: u64 = 001;
    const E_INVALID_STAKER: u64 = 101;
    const E_EMPTY_VALUE: u64 = 102;
    const E_INSUFFICENT_BALANCE: u64 = 103;
    const E_INSUFFICENT_BRIBES: u64 = 104;
    const E_INVALID_REWARD_RATE: u64 = 105;
    const E_MAX_REWARD: u64 = 106;
    const E_UNCLAIMED_REWARD: u64 = 107;

    // ====== Error =======

    // ===== Assertion =====

    public fun assert_pkg_version<X,Y>(self: &Gauge<X,Y>){
        assert!(self.version == package_version(), E_WRONG_VERSION);
    }

    // ===== Assertion =====

    /// Guage manages all staked Liquidity from Liquidity Provider, all LPs no longer take tx fees, but receive SDB coin as the rewards instead
    struct Gauge<phantom X, phantom Y> has key, store{
        id: UID,
        /// package version
        version: u64,
        /// detremine whether the gauge is able to receive the SDB rewards
        is_alive:bool,
        /// ID of DEX pool we are staking with
        pool: ID,
        /// ID of bribe object,
        bribe: ID,
        /// ID of rewards object
        rewards: ID,
        /// balance of coin X
        fees_x: Balance<X>,
        /// balance of coin Y
        fees_y: Balance<Y>,
        /// balance of emission coin SDB
        sdb_balance: Balance<SDB>,
        /// current estimated rewerds per second
        reward_rate: u64,
        /// last time sdb comes in or LP stake/unstake
        last_update_time: u64,
        /// period finish time
        period_finish: u64,
        /// accumlating distribution for SDB rewards per casted votes
        voting_index: u256,
        /// claimable SDB amount
        claimable: u64,
        /// total staked liquidity
        total_stakes: LP<X,Y>,
        /// accumlating distribution SDB rewards per lp balance
        staking_index: u256,
        /// staking information for LP object
        lp_stake: Table<address, Stake>
    }

    struct Stake has store{
        stakes: u64,
        staking_index: u256,
        pending_sdb: u64
    }

    public fun is_alive<X,Y>(self: &Gauge<X,Y>):bool{ self.is_alive }

    public (friend) fun update_is_alive<X,Y>(self: &mut Gauge<X,Y>, alive: bool ){
        assert!(self.version == package_version(), E_WRONG_VERSION);
        self.is_alive = alive
     }

    public fun pool_id<X,Y>(self: &Gauge<X,Y>):ID{ self.pool }

    public fun bribe_id<X,Y>(self: &Gauge<X,Y>):ID{ self.bribe }

    public fun rewards_id<X,Y>(self: &Gauge<X,Y>):ID{ self.rewards }

    public fun reward_rate<X,Y>(self: &Gauge<X,Y>): u64 { self.reward_rate }

    public fun period_finish<X,Y>(self: &Gauge<X,Y>): u64 { self.period_finish }

    public fun voting_index<X,Y>(self: &Gauge<X,Y>):u256{ self.voting_index }

    public (friend) fun update_voting_index<X,Y>(self: &mut Gauge<X,Y>, v: u256){
        assert_pkg_version(self);
        self.voting_index = v;
    }

    public (friend) fun update_claimable<X,Y>(self: &mut Gauge<X,Y>, v: u64){
        assert_pkg_version(self);
        self.claimable = v;
    }

    public fun sdb_balance<X,Y>(self: &Gauge<X,Y>): u64{ balance::value(&self.sdb_balance)}

    public fun claimable<X,Y>(self: &Gauge<X,Y>):u64{ self.claimable }

    public fun total_stakes<X,Y>(self: &Gauge<X,Y>):&LP<X,Y>{ &self.total_stakes }

    public fun lp_stakes<X,Y>(self: &Gauge<X,Y>, staker: address): u64{
        table::borrow(&self.lp_stake, staker).stakes
    }

    public fun gauge_staking_index<X,Y>(self: &Gauge<X,Y>): u256{ self.staking_index }

    public (friend) fun new<X,Y>(
        pool: &Pool<X,Y>,
        ctx: &mut TxContext
    ):Gauge<X,Y>{
        let (bribe, rewards) = bribe::new<X,Y>(ctx);

        let gauge = Gauge<X,Y>{
            id: object::new(ctx),
            version: package_version(),
            is_alive: true,
            pool: object::id(pool),
            bribe,
            rewards,
            fees_x: balance::zero<X>(),
            fees_y: balance::zero<Y>(),
            sdb_balance: balance::zero<SDB>(),
            reward_rate: 0,
            last_update_time: 0,
            period_finish: 0,
            voting_index: 0,
            claimable: 0,
            total_stakes: pool::create_lp(pool, ctx),
            staking_index: 0,
            lp_stake: table::new<address, Stake>(ctx)
        };
        gauge
    }

    // ====== GETTER ======

    public fun pending_sdb<X,Y>(self: &Gauge<X,Y>, staker: address, clock: &Clock): u64{
        if(!table::contains(&self.lp_stake, staker)) return 0;

        let stake = table::borrow(&self.lp_stake, staker);
        let ts = unix_timestamp(clock);
        let pending_sdb = stake.pending_sdb;

        if( ts > self.last_update_time && stake.stakes > 0){
            let delta = cal_staking_index(self, clock) - stake.staking_index;
            if(delta > 0){
                let share = (stake.stakes as u256) * delta / PRECISION;
                pending_sdb = pending_sdb + (share as u64);
            };
        };

        pending_sdb
    }

    public fun pool_bribes<X,Y>(
        self: &Gauge<X,Y>,
        pool: &Pool<X,Y>
    ):(u64, u64){
        pool::claimable(pool, &self.total_stakes)
    }

    // ====== GETTER ======

    // ====== ENTRY ======

    public entry fun get_reward<X,Y>(
        self: &mut Gauge<X,Y>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);

        let staker = tx_context::sender(ctx);
        assert!(table::contains(&self.lp_stake, staker), E_INVALID_STAKER);

        update_gauge_(self, clock);
        update_stake_(self, staker);

        let stake = table::borrow_mut(&mut self.lp_stake, staker);
        let pending = stake.pending_sdb;
        if(pending > 0){
            transfer::public_transfer(coin::take(&mut self.sdb_balance, pending, ctx), tx_context::sender(ctx));
        };
        stake.pending_sdb = 0;

        event::claim_reward(tx_context::sender(ctx), pending);
    }

    /// Stake LP_TOKEN
    public entry fun stake_all<X,Y>(
        self: &mut Gauge<X,Y>,
        pool: &Pool<X,Y>,
        lp: &mut LP<X,Y>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);

        let balance = pool::lp_balance(lp);
        assert!(balance > 0, E_EMPTY_VALUE);
        stake(self, pool, lp, balance, clock, ctx);
    }

    public entry fun stake<X,Y>(
        self: &mut Gauge<X,Y>,
        pool: &Pool<X,Y>,
        lp: &mut LP<X,Y>,
        value: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);

        let staker = tx_context::sender(ctx);
        if(!table::contains(&self.lp_stake, staker)){
            table::add(&mut self.lp_stake,
                staker,
                Stake{
                    stakes: 0,
                    staking_index: 0,
                    pending_sdb: 0
                }
            )
        };

        let lp_value = pool::lp_balance(lp);
        assert!(lp_value >= value, E_EMPTY_VALUE);
        assert!(value > 0, E_EMPTY_VALUE);

        update_gauge_(self, clock);
        update_stake_(self, staker);

        let stake = table::borrow_mut(&mut self.lp_stake, staker);
        pool::join_lp(pool, &mut self.total_stakes, lp, value);

        stake.stakes = stake.stakes + value;

        event::deposit_lp<X,Y>(tx_context::sender(ctx), value);
    }

    /// LP unstake lp
    public fun unstake_all<X,Y>(
        self: &mut Gauge<X,Y>,
        pool: &Pool<X,Y>,
        lp: &mut LP<X,Y>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);

        let stake = table::borrow(&self.lp_stake, tx_context::sender(ctx));
        let value = stake.stakes;
        assert!(value <= stake.stakes, E_INSUFFICENT_BALANCE);
        unstake(self, pool, lp, value, clock, ctx);
    }

    public fun unstake<X,Y>(
        self: &mut Gauge<X,Y>,
        pool: &Pool<X,Y>,
        lp: &mut LP<X,Y>,
        value: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);

        let staker = tx_context::sender(ctx);
        assert!(table::contains(&self.lp_stake, staker), E_INVALID_STAKER);

        update_gauge_(self, clock);
        update_stake_(self, staker);

        let stake = table::borrow_mut(&mut self.lp_stake, staker);
        assert!(value <= stake.stakes, E_INSUFFICENT_BALANCE);

        pool::join_lp(pool, lp, &mut self.total_stakes, value);
        stake.stakes = stake.stakes - value;

        event::withdraw_lp<X,Y>(tx_context::sender(ctx), value);
    }

    public fun distribute_emissions<X,Y>(
        self: &mut Gauge<X,Y>,
        rewards: &mut Rewards<X,Y>,
        pool: &mut Pool<X,Y>,
        coin: Coin<SDB>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);

        let value = coin::value(&coin);
        assert!(value > 0, E_EMPTY_VALUE);
        let ts = unix_timestamp(clock);
        let time_left = epoch_end(ts) - ts;

        claim_fee(self, rewards, pool, clock, ctx);
        update_gauge_(self, clock);

        if(ts >= self.period_finish){
            coin::put(&mut self.sdb_balance, coin);
            self.reward_rate = value / time_left;
        }else{
            let _remaining = self.period_finish - ts;
            let _left = _remaining * self.reward_rate;
            coin::put(&mut self.sdb_balance, coin);
            self.reward_rate = ( value + _left ) / time_left;
        };

        assert!(self.reward_rate > 0, E_INVALID_REWARD_RATE);
        assert!( self.reward_rate <= balance::value(&self.sdb_balance) / time_left, E_MAX_REWARD);

        self.period_finish = epoch_end(ts);
        self.last_update_time = ts;

        event::notify_reward<SDB>(value);
    }

    // ====== ENTRY ======

    // ====== UTILS ======

    public fun cal_staking_index<X,Y>(
        self: &Gauge<X,Y>,
        clock: &Clock
    ): u256{
        let total_stakes = pool::lp_balance(&self.total_stakes);
        if(total_stakes == 0) return self.staking_index;

        self.staking_index + ((last_time_reward_applicable(self,clock) - self.last_update_time) as u256) * (self.reward_rate as u256) * PRECISION / (total_stakes as u256)
    }

    fun unix_timestamp(clock: &Clock): u64 { clock::timestamp_ms(clock) / 1000 }

    public fun left<X, Y>(self: &Gauge<X, Y>, clock: &Clock):u64{
        let ts = unix_timestamp(clock);

        if(ts >= self.period_finish) return 0;

        let _remaining = self.period_finish - ts;
        return _remaining * self.reward_rate
    }

    public fun last_time_reward_applicable<X, Y>(self: &Gauge<X,Y>, clock: &Clock):u64{
        math::min(unix_timestamp(clock), self.period_finish)
    }

    public fun epoch_start(ts: u64): u64{ ts / WEEK * WEEK }

    public fun epoch_end(ts: u64): u64{ ts / WEEK * WEEK + WEEK }

    // ====== UTILS ======

    // ====== LOGIC ======

    fun update_gauge_<X,Y>(
        self: &mut Gauge<X,Y>,
        clock: &Clock
    ){
        self.staking_index = cal_staking_index<X,Y>(self, clock);
        self.last_update_time = last_time_reward_applicable(self, clock);
    }

    fun update_stake_<X,Y>(
        self: &mut Gauge<X,Y>,
        staker: address
    ){
        let stake = table::borrow_mut(&mut self.lp_stake, staker);
        let staked = stake.stakes;
        if(staked > 0){
            let delta = self.staking_index - stake.staking_index;

            if(delta > 0){
                let share = (staked as u256) * delta / PRECISION;
                stake.pending_sdb = stake.pending_sdb + (share as u64);
            }
        };
        stake.staking_index = self.staking_index;
    }

    // TODO: add friend module
    /// Claim the fees from pool
    public fun claim_fee<X,Y>(
        self: &mut Gauge<X,Y>,
        rewards: &mut Rewards<X,Y>,
        pool: &mut Pool<X,Y>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(self.version == package_version(), E_WRONG_VERSION);

        let (coin_x, coin_y, value_x, value_y) = pool::claim_fees_dev(pool, &mut self.total_stakes, ctx);
        if(option::is_some(&coin_x)){
            let coin_x = option::extract(&mut coin_x);
            coin::put(&mut self.fees_x, coin_x);
        };
        if(option::is_some(&coin_y)){
            let coin_y = option::extract(&mut coin_y);
            coin::put(&mut self.fees_y, coin_y);
        };
        option::destroy_none(coin_x);
        option::destroy_none(coin_y);

        if(value_x > 0){
            let bal_x = balance::value(&self.fees_x);
            if(bal_x > WEEK){
                let withdraw = balance::withdraw_all(&mut self.fees_x);
                bribe::bribe(rewards, coin::from_balance(withdraw, ctx), clock);
            };
        };
        if(value_y > 0){
            let bal_y = balance::value(&self.fees_y);
            if(bal_y > WEEK){
                let withdraw = balance::withdraw_all(&mut self.fees_y);
                bribe::bribe(rewards, coin::from_balance(withdraw, ctx), clock);
            }
        };
    }

    // ====== LOGIC ======
}