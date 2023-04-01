// Gauges are used to incentivize pools, they emit reward tokens over 7 days for staked LP tokens
module suiDouBashiVest::gauge{
    use sui::object::{UID, ID};
    use sui::table::{Self, Table};


    use suiDouBashi::amm_v1::{Self, Pool};



    const DURATION: u64 = { 7 * 86400 };
    const PRECISION: u64 = 1_000_000_000_000_000_000;
    const MAX_REWARD_TOKENS: u64 = 16;



    struct Gauge has key{
        id: UID,

    }

    struct Reg has key{
        id: UID,
        /// A record of balance checkpoints for each token, by index
        supply_checkpoints: Table<u64, SupplyCheckpoint>,
        /// A record of balance checkpoints for each token, by index
        reward_per_token_checkpoints: Table<u64, RewardPerTokenCheckpoint>,

        fees_0: u64,
        fees_1: u64
    }

    struct Vote has key{
        id: UID,
        derived_balances: u64,
        reward_rate: u64,
        period_finish: u64,
        last_update_time: u64,
        reward_per_token_stored: u64,

        //checkpoint
        checkpoints: Table<u64, Checkpoint>
    }

    ///checkpoint for marking balance
    struct Checkpoint has store {
        timestamp: u64,
        balance: u64
    }
    ///checkpoint for marking supply
    struct SupplyCheckpoint has store {
        timestamp: u64,
        supply: u64
    }
    ///checkpoint for marking reward rate
    struct RewardPerTokenCheckpoint has store {
        timestamp: u64,
        rewardPerToken: u64

    }

}
