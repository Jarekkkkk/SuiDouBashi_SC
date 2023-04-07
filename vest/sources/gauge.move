// Gauges are used to incentivize pools, they emit reward tokens over 7 days for staked LP tokens
module suiDouBashiVest::gauge{
    use sui::object::{UID};
    use sui::table::{ Table};
    use sui::balance::{Self, Balance};

    use suiDouBashi::amm_v1::{Pool, LP_TOKEN};
    use suiDouBashiVest::vsdb::VSDB;
    use suiDouBashiVest::internal_bribe::Reward;

    const DURATION: u64 = { 7 * 86400 };
    const PRECISION: u64 = 1_000_000_000_000_000_000;
    const MAX_REWARD_TOKENS: u64 = 16;


    struct Guage<phantom X, phantom Y> has key, store{
        id: UID,
        stake: Balance<LP_TOKEN<X,Y>>,

        derived_supply: u64,
        derived_balances: Table<address, u64>,

        is_for_pair: bool,
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



// pool -> Guage
//          1. internal Bribe
//          2. external Bribe
//          3.


// bribe:
//      1. notifyRewardAmount
//      2. left