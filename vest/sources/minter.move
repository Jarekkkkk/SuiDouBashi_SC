module suiDouBashiVest::minter{
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Supply, Balance};
    use sui::clock::{Self, Clock};


    use suiDouBashiVest::sdb::{Self, SDB};
    use suiDouBashiVest::err;
    use suiDouBashiVest::vsdb::{Self, VSDBRegistry};
    use suiDouBashiVest::voter::Voter;


    use sui::math;

    const WEEK: u64 = {7 * 86400};
    const EMISSION: u64 = 990;
    const TAIL_EMISSION: u64 = 2;
    const PRECISION: u64 = 1000;
    const WEEKLY: u256 = { 15_000_000 * 10}; //15M
    const LOCK: u64 = { 86400 * 365 * 4 };

    const MAX_TEAM_RATE: u64 = 50; // 50 bps = 0.5%

    friend suiDouBashiVest::voter;

    struct Minter has key{
        supply: Supply<SDB>,
        balance: Balance<SDB>,
        team: address,
        team_rate: u64,
        active_period: u64,

        weekly: u64 // current supply only contains u64
    }


    fun new(ctx: &mut TxContext):Minter{
        Minter{
            supply: sdb::new(ctx),
            balance: balance::zero<SDB>(),
            team: tx_context::sender(ctx),
            team_rate: 30,
            active_period: ( tx_context::epoch_timestamp_ms(ctx) + ( 2 * WEEK) ) / WEEK * WEEK,

            weekly: 15_000_000 * math::pow(10, 6)
        }
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
        balance::supply_value(&self.supply) - vsdb::total_supply(vsdb_reg)
    }

    public fun calculate_emission(self: &Minter):u64{
        ( self.weekly * EMISSION ) / PRECISION
    }

    public fun circulating_emission(self: &Minter, vsdb_reg: &VSDBRegistry):u64{
        (circulating_supply(self, vsdb_reg) * TAIL_EMISSION ) / PRECISION
    }

    public fun weekly_emission(self: &Minter, vsdb_reg: &VSDBRegistry):u64{
        math::max(calculate_emission(self), circulating_emission(self, vsdb_reg))
    }

    /// calculate inflation and adjust ve balances accordingly
    public fun calculate_growth(self: &Minter, vsdb_reg: &VSDBRegistry, minted: u64): u64{
        let ve_total = vsdb::total_supply(vsdb_reg);
        let sdb_total = balance::supply_value(&self.supply);

        ((minted * ve_total) / sdb_total ) * ve_total / sdb_total * ve_total / sdb_total / 2
    }

     /// update period can only be called once per epoch (1 week)
     public fun update_period (self: &mut Minter, vsdb_reg: &VSDBRegistry , clock: &Clock): u64{
        let period = self.active_period;

        // new week
        if(clock::timestamp_ms(clock) >= period + WEEK ){
            period = ( clock::timestamp_ms(clock) / WEEK * WEEK);
            self.active_period = period;
            self.weekly = weekly_emission(self, vsdb_reg);

            let growth = calculate_growth(self, vsdb_reg, self.weekly);
            let team_emission = (self.team_rate * (growth + self.weekly)) / (PRECISION - self.team_rate);
            let required = growth + self.weekly + team_emission;
            let balance = balance::value(&self.balance);

            if(required > balance){
                let minted = balance::increase_supply(&mut self.supply, required - balance);
                balance::join(&mut self.balance, minted);
            };

            //transfer to team
            let team_coin = coin::take(&mut self.balance, team_emission);
            // rebase
            let rewards_coin = coin::take(&mut self.balance, team_emission);
        };

        period
     }



}