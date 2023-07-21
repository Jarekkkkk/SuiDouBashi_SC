module suiDouBashi_vote::minter{
    const VERSION: u64 = 1;
    public fun package_version(): u64 { VERSION }

    use std::option::{Self, Option};
    use std::vector as vec;

    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Supply, Balance};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::transfer;
    use sui::math;
    use sui::object::{Self, UID};

    use suiDouBashi_vsdb::sdb::{Self, SDB};
    use suiDouBashi_vsdb::vsdb::{Self, VSDBRegistry};
    use suiDouBashi_vote::event;

    const WEEK: u64 = { 7 * 86400 };
    const PRECISION: u64 = 1000;
    const TAIL_EMISSION: u64 = 2; // minimum 0.2%
    const MAX_TEAM_RATE: u64 = 50; // 50 bps = 5%

    const E_WRONG_VERSION: u64 = 001;
    const E_INVALID_TEAM: u64 = 100;
    const ERR_MAX_RATE:u64 = 101;
    const E_NOT_MATCH_LENGTH: u64 = 102;

    friend suiDouBashi_vote::voter;

    struct MinterCap has key { id: UID }

    struct Minter has key{
        id: UID,
        /// package version
        verison: u64,
        /// supply of SDB coin emit weekly SDB emissions
        supply: Supply<SDB>,
        /// balance of SDB coin
        balance: Balance<SDB>,
        /// team address reveive a portion of weekly SDB emissio
        team: address,
        /// the percentage rate of team rewards
        team_rate: u64,
        /// lsst time distribute weekly SDB emission
        active_period: u64,
        weekly: u64,
        emission: u16,
        epoch: u32
    }

    public fun balance(self: &Minter): u64 { balance::value(&self.balance) }

    public fun total_sypply(self: &Minter): u64 { balance::supply_value(&self.supply) }

    fun init(ctx: &mut TxContext){
        transfer::transfer(
            MinterCap { id: object::new(ctx)},
            tx_context::sender(ctx)
        );
    }

    // consume treasury to trigger one time initialize
    public fun initialize(
        treasury: TreasuryCap<SDB>,
        vsdb_reg: &mut VSDBRegistry,
        initial_amount: u64,
        claimants: vector<address>,
        claim_amounts: vector<u64>,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        assert!(vec::length(&claim_amounts) == vec::length(&claimants), E_NOT_MATCH_LENGTH);
        let minter = Minter{
            id: object::new(ctx),
            verison: VERSION,
            supply: coin::treasury_into_supply(treasury),
            balance: balance::zero<SDB>(),
            team: tx_context::sender(ctx),
            team_rate: 30,
            active_period: tx_context::epoch_timestamp_ms(ctx) / 1000 / WEEK * WEEK,
            weekly: 75_000 * (math::pow(10, sdb::decimals())),
            emission: 980,
            epoch: 0
        };
        let sdb_balance = balance::increase_supply(&mut minter.supply, initial_amount);

        // transfer VeNFT
        let i = 0;
        while ( i < vec::length(&claimants)){
            let ads = vec::pop_back(&mut claimants);
            let amount = vec::pop_back(&mut claim_amounts);
            let sdb_coin = coin::take(&mut sdb_balance, amount, ctx);
            vsdb::lock_for(vsdb_reg, sdb_coin, vsdb::max_time(), ads, clock, ctx);
        };

        balance::join(&mut minter.balance, sdb_balance);
        transfer::share_object(minter);
    }

    public entry fun set_team(self: &mut Minter, team: address, ctx: &mut TxContext){
        assert!(self.verison == VERSION, E_WRONG_VERSION);
        assert!(tx_context::sender(ctx) == self.team, E_INVALID_TEAM);
        self.team = team;
    }

    public entry fun set_team_rate(self: &mut Minter, rate: u64, ctx: &mut TxContext){
        assert!(self.verison == VERSION, E_WRONG_VERSION);
        assert!(tx_context::sender(ctx) == self.team, E_INVALID_TEAM);
        assert!( rate < MAX_TEAM_RATE, ERR_MAX_RATE);
        self.team_rate = rate;
    }

    // calculate circulating supply as total token supply - locked supply
    public fun circulating_supply(self: &Minter, vsdb_reg: &VSDBRegistry, clock: &Clock): u64{
        balance::supply_value(&self.supply) - vsdb::total_VeSDB(vsdb_reg, clock)
    }

    /// decay at 1% per week
    public fun calculate_emission(self: &Minter):u64{
        (( (self.weekly as u128) * (self.emission as u128) ) / (PRECISION as u128) as u64)
    }
    /// ( SDB_supply - VSDB_supply ) * 0.2%
    public fun circulating_emission(self: &Minter, vsdb_reg: &VSDBRegistry, clock: &Clock):u64{
        (((circulating_supply(self, vsdb_reg, clock) as u128) * (TAIL_EMISSION as u128) ) / (PRECISION as u128) as u64)
    }

    public fun weekly_emission(self: &Minter, vsdb_reg: &VSDBRegistry, clock: &Clock):u64{
        math::max(calculate_emission(self), circulating_emission(self, vsdb_reg, clock))
    }

    /// update period can only be called once per epoch (1 week)
    public (friend) fun update_period (
        self: &mut Minter,
        //distributor: &mut Distributor,
        vsdb_reg: &mut VSDBRegistry ,
        clock: &Clock,
        ctx: &mut TxContext
    ):  Option<Coin<SDB>>{
        assert!(self.verison == VERSION, E_WRONG_VERSION);
        let period = self.active_period;
        // new week
        if(clock::timestamp_ms(clock) / 1000 >= period + WEEK){
            period = ( clock::timestamp_ms(clock) / 1000 / WEEK * WEEK);
            self.active_period = period;
            self.weekly = weekly_emission(self, vsdb_reg, clock);

            let weekly = self.weekly;

            let team_emission = (self.team_rate * weekly) / (PRECISION - self.team_rate);
            let required = weekly + team_emission;
            let balance = balance::value(&self.balance);

            if(required > balance){
                // infinite supply, decimals should be adjusted
                let minted = balance::increase_supply(&mut self.supply, required - balance);
                balance::join(&mut self.balance, minted);
            };

            let team_coin = coin::take(&mut self.balance, team_emission, ctx);
            transfer::public_transfer(team_coin, self.team);

            self.epoch = self.epoch + 1;

            if(self.epoch < 96 && self.epoch % 24 == 0) self.emission = self.emission + 5 ;
            if(self.epoch == 96) self.emission = 999;

            event::mint(tx_context::sender(ctx), self.weekly, circulating_supply(self, vsdb_reg, clock), circulating_emission(self, vsdb_reg, clock));
            return option::some(coin::take(&mut self.balance, self.weekly, ctx))
        };
        option::none()
    }

    public fun buyback(_cap: &MinterCap, self: &mut Minter, sdb: Coin<SDB>){
        assert!(self.verison == VERSION, E_WRONG_VERSION);
        balance::decrease_supply(&mut self.supply, coin::into_balance(sdb));
    }

    #[test_only] public fun mint_sdb(self: &mut Minter, value: u64, ctx: &mut TxContext):Coin<SDB>{
        coin::from_balance(balance::increase_supply(&mut self.supply, value), ctx)
    }
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }
}