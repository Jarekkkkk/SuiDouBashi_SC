module suiDouBashiVest::reward{
    use sui::object::{UID, ID};
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};
    use sui::tx_context::TxContext;
    use sui::object;
    use sui::table_vec::{Self, TableVec};

    use suiDouBashiVest::checkpoints::RewardPerTokenCheckpoint;

    struct Reward<phantom X, phantom Y, phantom T> has key, store{
        id: UID,

        balance: Balance<T>,
        reward_rate: u64, // pair
        period_finish: u64,// pair
        last_update_time: u64, // pair
        reward_per_token_stored: u64, // pair
        is_reward: bool,// pair

        reward_per_token_checkpoints: Table<ID, TableVec< RewardPerTokenCheckpoint>>, // pair
        user_reward_per_token_stored: Table<ID, u64>, // player -> token_value
        last_earn: Table<ID, u64>, // VSDB -> ts
    }



    public fun new<X,Y,T>(ctx: &mut TxContext): Reward<X,Y,T>{
        Reward<X,Y,T>{
            id: object::new(ctx),
            balance: balance::zero<T>(),
            reward_rate: 0,
            period_finish: 0,
            last_update_time: 0,
            reward_per_token_stored: 0,
            reward_per_token_checkpoints: table::new<ID, TableVec<RewardPerTokenCheckpoint>>(ctx),

            user_reward_per_token_stored: table::new<ID, u64>(ctx),
            last_earn: table::new<ID, u64>(ctx),
            is_reward: false,
        }
    }


    // ===== Getter =====
    public fun balance<X,Y,T>(self: &Reward<X,Y,T>):u64{
        balance::value(&self.balance)
    }

    public fun reward_rate<X,Y,T>(self: &Reward<X,Y,T>):u64{
        self.reward_rate
    }

    public fun period_finish<X,Y,T>(self: &Reward<X,Y,T>):u64{
        self.period_finish
    }

    public fun last_update_time<X,Y,T>(self: &Reward<X,Y,T>):u64{
        self.last_update_time
    }

    public fun reward_per_token_stored<X,Y,T>(self: &Reward<X,Y,T>):u64{
        self.reward_per_token_stored
    }

    public fun is_reward<X,Y,T>(self: &Reward<X,Y,T>):bool{
        self.is_reward
    }

    public fun reward_per_token_checkpoints<X,Y,T>(self: &Reward<X,Y,T>, id: ID)
    :&TableVec<RewardPerTokenCheckpoint>{
        table::borrow(&self.reward_per_token_checkpoints, id)
    }
    public fun reward_per_token_checkpoints_mut<X,Y,T>(self: &mut Reward<X,Y,T>, id: ID)
    :&mut TableVec<RewardPerTokenCheckpoint>{
        table::borrow_mut(&mut self.reward_per_token_checkpoints, id)
    }

    public fun reward_per_token_checkpoints_contains<X,Y,T>(self: &Reward<X,Y,T>, id: ID):bool{
        table::contains(&self.reward_per_token_checkpoints, id)
    }

    public fun user_reward_per_token_stored<X,Y,T>(self: &Reward<X,Y,T>, id: ID):u64{
        *table::borrow(&self.user_reward_per_token_stored, id)
    }

    public fun last_earn<X,Y,T>(self: &Reward<X,Y,T>, id:ID):u64{
        *table::borrow(&self.last_earn, id)
    }
    public fun last_earn_contain<X,Y,T>(self: &Reward<X,Y,T>, id:ID):bool{
        table::contains(&self.last_earn, id)
    }


    // ===== Setter =====
    public fun add_new_user_reward<X,Y,T>(self: &mut Reward<X,Y,T>, id: ID, ctx: &mut TxContext){
        let table_vec = table_vec::empty(ctx);
        table::add(&mut self.reward_per_token_checkpoints, id, table_vec);
    }
}