module suiDouBashiVest::minter{

    use suiDouBashiVest::sdb;
    use sui::tx_context::{Self, TxContext};



    const WEEK: u64 = {7 * 86400};
    const EMISSION: u64 = 990;
    const TAIL_EMISSION: u64 = 2;
    const PRECISION: u64 = 1000;
    const WEEKLY: u256 = { 15_000_000 * 10}; //15M
    const LOCK: u64 = { 86400 * 365 * 4 };

    const MAX_TEAM_RATE: u64 = 50; // 50 bps = 0.5%


    struct Minter has key{
        team: address,
        team_rate: u64,
        active_period: u64
    }


    fun new(ctx: &mut TxContext):Minter{
        Minter{
            team: tx_context::sender(ctx),
            team_rate: 30,
            active_period: ( tx_context::epoch_timestamp_ms(ctx) + ( 2 * WEEK) ) / WEEK * WEEK
        }
    }


    friend suiDouBashiVest::voter;

}