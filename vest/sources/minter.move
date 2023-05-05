module suiDouBashiVest::minter{
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Supply, Balance};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::transfer;
    use sui::object::{Self, UID};
    use std::option::{Self, Option};
    use std::vector as vec;

    use suiDouBashiVest::sdb::SDB;
    use suiDouBashiVest::err;
    use suiDouBashiVest::event;
    use suiDouBashiVest::vsdb::{Self, VSDBRegistry};
    use suiDouBashiVest::reward_distributor::{Self, Distributor};

    use sui::math;

    const WEEK: u64 = {7 * 86400};
    const EMISSION: u64 = 990; // linearly decrease 1 %
    const PRECISION: u64 = 1000;
    const TAIL_EMISSION: u64 = 2; // minium 0.2%
    const WEEKLY: u256 = 15_000_000 ; // 15M
    const LOCK: u64 = { 86400 * 365 * 4 };

    const MAX_TEAM_RATE: u64 = 50; // 50 bps = 5%

    friend suiDouBashiVest::voter;

    struct Minter has key{
        id: UID,
        supply: Supply<SDB>,
        balance: Balance<SDB>,
        team: address,
        team_rate: u64,
        active_period: u64,
        weekly: u64
    }
    public fun balance(self: &Minter): u64 { balance::value(&self.balance) }
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
        let minter = Minter{
            id: object::new(ctx),
            supply: coin::treasury_into_supply(treasury),
            balance: balance::zero<SDB>(),
            team: tx_context::sender(ctx),
            team_rate: 30,
            active_period: tx_context::epoch_timestamp_ms(ctx) / WEEK * WEEK,
            weekly: 15_000_000 * (math::pow(10, 9)) // 9 decimals
        };
        let sdb_balance = balance::increase_supply(&mut minter.supply, initial_amount);

        // transfer VeNFT
        let i = 0;
        while ( i < vec::length(&claimants)){
            let ads = vec::pop_back(&mut claimants);
            let amount = vec::pop_back(&mut claim_amounts);
            let sdb_coin = coin::take(&mut sdb_balance, amount, ctx);
            vsdb::lock_for(vsdb_reg, sdb_coin, 4 * 365 * 86400, ads, clock, ctx);
        };

        balance::join(&mut minter.balance, sdb_balance);
        transfer::share_object(minter);
    }

    public entry fun set_team(self: &mut Minter, team: address, ctx: &mut TxContext){
        assert!(tx_context::sender(ctx) == self.team, err::invalid_team());
        self.team = team;
    }

    public entry fun set_team_rate(self: &mut Minter, rate: u64, ctx: &mut TxContext){
        assert!(tx_context::sender(ctx) == self.team, err::invalid_team());
        assert!( rate < MAX_TEAM_RATE, err::max_rate());
        self.team_rate = rate;
    }

    // calculate circulating supply as total token supply - locked supply
    public fun circulating_supply(self: &Minter, vsdb_reg: &VSDBRegistry): u64{
        balance::supply_value(&self.supply) - vsdb::total_minted(vsdb_reg)
    }

    /// decay at 1% per week
    public fun calculate_emission(self: &Minter):u64{
        ( self.weekly * EMISSION ) / PRECISION
    }
    /// ( VSDB_supply - sdb_supply ) * 0.2%
    public fun circulating_emission(self: &Minter, vsdb_reg: &VSDBRegistry):u64{
        (circulating_supply(self, vsdb_reg) * TAIL_EMISSION ) / PRECISION
    }

    public fun weekly_emission(self: &Minter, vsdb_reg: &VSDBRegistry):u64{
        math::max(calculate_emission(self), circulating_emission(self, vsdb_reg))
    }
    /// (veVELO.totalSupply / VELO.totalsupply)^3 * 0.5 * Emissions
    public fun calculate_growth(self: &Minter, vsdb_reg: &VSDBRegistry, minted: u64): u64{
        let ve_total = vsdb::total_minted(vsdb_reg);
        let sdb_total = balance::supply_value(&self.supply);
        ((minted * ve_total) / sdb_total ) * ve_total / sdb_total * ve_total / sdb_total / 2
    }

     // TODO: add firned module
     /// update period can only be called once per epoch (1 week)
     public fun update_period (
        self: &mut Minter,
        distributor: &mut Distributor,
        vsdb_reg: &mut VSDBRegistry ,
        clock: &Clock,
        ctx: &mut TxContext
    ):  Option<Coin<SDB>>{
        let period = self.active_period;
        // new week
        if(clock::timestamp_ms(clock) >= period + WEEK){
            period = ( clock::timestamp_ms(clock) / WEEK * WEEK);
            self.active_period = period;
            self.weekly = weekly_emission(self, vsdb_reg);

            let weekly = self.weekly;
            // rebase
            let rebase = calculate_growth(self, vsdb_reg, weekly);
            let team_emission = (self.team_rate * (rebase + weekly)) / (PRECISION - self.team_rate);
            let required = rebase + weekly + team_emission;
            let balance = balance::value(&self.balance);

            if(required > balance){
                // infinite supply, decimals should be adjusted
                let minted = balance::increase_supply(&mut self.supply, required - balance);
                balance::join(&mut self.balance, minted);
            };

            //transfer to team
            let team_coin = coin::take(&mut self.balance, team_emission, ctx);
            transfer::public_transfer(team_coin, self.team);
            // rebase
            let rebase_coin = coin::take(&mut self.balance, rebase, ctx);
            reward_distributor::deposit_reward(distributor, rebase_coin);

            // checkpoint balance that was just distributed
            reward_distributor::checkpoint_token(distributor, clock);
            reward_distributor::checkpoint_total_supply(distributor, vsdb_reg, clock);

            event::mint(tx_context::sender(ctx), self.weekly, circulating_supply(self, vsdb_reg), circulating_emission(self, vsdb_reg));
            return option::some(coin::take(&mut self.balance, self.weekly, ctx))
        };
        option::none()
     }

}