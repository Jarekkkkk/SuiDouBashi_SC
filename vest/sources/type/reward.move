module suiDouBashiVest::reward{
    use sui::object::{UID, ID};
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};
    use sui::tx_context::TxContext;
    use sui::object;

    use suiDouBashiVest::checkpoints::RewardPerTokenCheckpoint;

    struct Reward<phantom X, phantom Y, phantom T> has key, store{
        id: UID,

        balance: Balance<T>,

        //update when bribe is deposited
        reward_rate: u64,
        period_finish: u64, // update when bribe is deposited, (internal_bribe -> fee ), (external_bribe -> doverse coins)

        last_update_time: u64, // update when someone 1.voting/ 2.reset/ 3.withdraw bribe/ 4. deposite bribe
        reward_per_token_stored: u64,

        user_reward_per_token_stored: Table<ID, u64>, // udpate when user deposit
        is_reward: bool,

        /// TODO: move to VSDB
        reward_per_token_checkpoints: Table<ID, Table<u64,  RewardPerTokenCheckpoint>>,
        last_earn: Table<ID, u64>, // last time player deposit the reward
    }

    public fun new<X,Y,T>(ctx: &mut TxContext): Reward<X,Y,T>{
        Reward<X,Y,T>{
            id: object::new(ctx),
            balance: balance::zero<T>(),
            reward_rate: 0,
            period_finish: 0,
            last_update_time: 0,
            reward_per_token_stored: 0,
            reward_per_token_checkpoints: table::new<ID, Table<u64, RewardPerTokenCheckpoint>>(ctx),

            user_reward_per_token_stored: table::new<ID, u64>(ctx),
            last_earn: table::new<ID, u64>(ctx),
            is_reward: false,
        }
    }


    // ===== Getter =====
    public fun balance<X,Y,T>(self: &Reward<X,Y,T>):u64{
        balance::value(&self.balance)
    }

    public fun balance_mut<X,Y,T>(self: &mut Reward<X,Y,T>):&mut Balance<T>{
        &mut self.balance
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
    :&Table<u64, RewardPerTokenCheckpoint>{
        table::borrow(&self.reward_per_token_checkpoints, id)
    }
    public fun reward_per_token_checkpoints_mut<X,Y,T>(self: &mut Reward<X,Y,T>, id: ID)
    :&mut Table<u64, RewardPerTokenCheckpoint>{
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
        let table = table::new(ctx);
        table::add(&mut self.reward_per_token_checkpoints, id, table);
    }

    public fun update_reward_per_token_stored<X,Y,T>(self: &mut Reward<X,Y,T>, reward_per_token_stored:u64){
        self.reward_per_token_stored = reward_per_token_stored;
    }

    public fun update_last_update_time<X,Y,T>(self: &mut Reward<X,Y,T>, last_update_time: u64){
        self.last_update_time = last_update_time;
    }

    public fun update_last_earn<X,Y,T>(self: &mut Reward<X,Y,T>, id: ID, last_earn:u64){
        *table::borrow_mut(&mut self.last_earn, id) = last_earn ;
    }

    public fun update_reward_rate<X,Y,T>(self:&mut Reward<X,Y,T>, reward_rate:u64){
        self.reward_rate = reward_rate;
    }

    public fun update_period_finish<X,Y,T>(self:&mut Reward<X,Y,T>, period_finish: u64){
        self.period_finish = period_finish;
    }

    public fun update_user_reward_per_token_stored<X,Y,T>(self: &mut Reward<X,Y,T>, id: ID, user_reward_per_token_stored:u64){
        *table::borrow_mut(&mut self.user_reward_per_token_stored, id) = user_reward_per_token_stored ;
    }

}