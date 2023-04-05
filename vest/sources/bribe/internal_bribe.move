// Internal Bribes represent pool fee
module suiDouBashiVest::internal_bribe{
    use std::type_name::{Self, TypeName};
    use std::vector as vec;
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{TxContext};
    use sui::dynamic_field as df;
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::object_table::{Self as ot, ObjectTable};
    use std::string::{Self, String};
    use sui::table_vec::{Self, TableVec};
    use sui::clock::{Self, Clock};
    use sui::math;

    use suiDouBashi::amm_v1::{Self, Pool};
    use suiDouBashiVest::vsdb::{Self, VSDB};

    //use suiDouBashiVest::vsdb::{Self, VSDB};


    // use suiDouBashiVest::vsdb::VSDB;
    // use suiDouBashi::amm_v1::Pool;
    use sui::table::{ Self, Table};

    const DURATION: u64 = { 7 * 86400 };
    const PRECISION: u64 = 1_000_000_000_000_000_000;
    const MAX_REWARD_TOKENS: u64 = 16;

    /// Rough illustration of the dynamic field architecture for reg:
    /// ```
    ///            type_name /--->Brbe--->Balance
    /// (Reg)-     type_name  -->Brbe--->Balance
    ///            type_name \--->Brbe--->Balance
    /// ```
    struct Reg has key{
        id: UID,
        // we wrapp the balance into coin_lsiting through df for hiding types
        bribes: Table<String, ID>,
        total_supply: u64,
        balace_of: Table<ID, u64>,
    }

    // per token_ads
    struct InternalBribe<phantom X, phantom Y> has key, store{
        id: UID,
        reward_rate: u64,
        period_finish: u64,
        last_update_time: u64,
        reward_per_token_stored: u64,

        last_earn: Table<ID, u64>, // VSDB -> ts
        user_reward_per_token_stored: Table<ID, u64>, // VSDB -> token_value
        isReward: bool,

        // Question: will vector be too gas consuming ?
        checkpoints: Table<ID, TableVec<Checkpoint>>, // VSDB -> balance checkpoint
        supply_checkpoints: TableVec<SupplyCheckpoint>,
        reward_per_token_checkpoints: Table<ID, TableVec<RewardPerTokenCheckpoint>>, // VSDb -> balance checkpoints

        reward_x: Balance<X>,
        reward_y: Balance<Y>,
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
        reward_per_token: u64

    }

    fun init(ctx: &mut TxContext){
        let reg = Reg{
            id: object::new(ctx),
            bribes: table::new<String, ID>(ctx),
            total_supply: 0,
            balace_of: table::new<ID, u64>(ctx)
        };
        transfer::share_object(reg);
    }


    public fun create_bribe<X,Y>(
        reg: &mut Reg,
        pool: &mut Pool<X,Y>,
        ctx: &mut TxContext
    ) {
        let bribe = InternalBribe<X,Y>{
            id: object::new(ctx),
            reward_rate: 0,
            period_finish: 0,
            last_update_time: 0,
            reward_per_token_stored: 0,
            last_earn: table::new<ID, u64>(ctx),
            user_reward_per_token_stored: table::new<ID, u64>(ctx),
            isReward: false,
            checkpoints: table::new<ID, TableVec<Checkpoint>>(ctx),
            reward_per_token_checkpoints: table::new<ID, TableVec<RewardPerTokenCheckpoint>>(ctx),
            supply_checkpoints: table_vec::empty<SupplyCheckpoint>(ctx),
            reward_x: balance::zero<X>(),
            reward_y: balance::zero<Y>(),
        };
        let pool_symbol = amm_v1::get_pool_name(pool);
        table::add(&mut reg.bribes, pool_symbol, object::id(&bribe));

        transfer::share_object(bribe);
    }


    // ===== Getter =====
    public fun get_prior_balance_index<X,Y>(
        self: & InternalBribe<X,Y>,
        vsdb: &VSDB,
        ts:u64
    ):u64 {
        if(!table::contains(&self.checkpoints, object::id(vsdb))){
            return 0
        };
        let checkpoints = table::borrow(&self.checkpoints, object::id(vsdb));
        let len = table_vec::length(checkpoints);

        if( len == 0){
            return 0
        };

        if( table_vec::borrow(checkpoints, len - 1).timestamp <= ts ){
            return len - 1
        };

        if( table_vec::borrow(checkpoints, 0).timestamp > ts){
            return 0
        };


        let lower = 0;
        let upper = len - 1;
        while ( lower < upper){
            let center = upper - (upper - lower) / 2;
            let checkoint = table_vec::borrow(checkpoints, center);
            if(checkoint.timestamp == ts ){
                return center
            }else if (checkoint.timestamp < ts){
                lower = center;
            }else{
                upper = center -1 ;
            }
        };

        return lower
    }

    public fun get_prior_supply_index<X,Y>(
        self: & InternalBribe<X,Y>,
        ts:u64
    ):u64 {
        let len = table_vec::length(&self.supply_checkpoints);

        if( len == 0){
            return 0
        };

        if( table_vec::borrow(&self.supply_checkpoints, len - 1).timestamp <= ts ){
            return len - 1
        };

        if( table_vec::borrow(&self.supply_checkpoints, 0).timestamp > ts){
            return 0
        };


        let lower = 0;
        let upper = len - 1;
        while ( lower < upper){
            let center = upper - (upper - lower) / 2;
            let checkoint = table_vec::borrow(&self.supply_checkpoints, center);
            if(checkoint.timestamp == ts ){
                return center
            }else if (checkoint.timestamp < ts){
                lower = center;
            }else{
                upper = center -1 ;
            }
        };

        return lower
    }

    public fun get_prior_reward_per_token<X,Y>(
        self: & InternalBribe<X,Y>,
        vsdb: &VSDB,
        ts:u64
    ):(u64, u64) // ( ts, reward_per_token )
    {
        if(!table::contains(&self.reward_per_token_checkpoints, object::id(vsdb))){
            return ( 0, 0 )
        };
        let checkpoints = table::borrow(&self.reward_per_token_checkpoints, object::id(vsdb));
        let len = table_vec::length(checkpoints);

        if( len == 0){
            return ( 0, 0 )
        };

        if( table_vec::borrow(checkpoints, len - 1).timestamp <= ts ){
            let last_checkpoint = table_vec::borrow(checkpoints, len - 1);
            return ( last_checkpoint.timestamp, last_checkpoint.reward_per_token)
        };

        if( table_vec::borrow(checkpoints, 0).timestamp > ts){
            return ( 0, 0 )
        };


        let lower = 0;
        let upper = len - 1;
        while ( lower < upper){
            let center = upper - (upper - lower) / 2;
            let checkpoint = table_vec::borrow(checkpoints, center);
            if(checkpoint.timestamp == ts ){
                return (checkpoint.timestamp, checkpoint.reward_per_token )
            }else if (checkpoint.timestamp < ts){
                lower = center;
            }else{
                upper = center -1 ;
            }
        };

        let checkpoint = table_vec::borrow(checkpoints, lower);
        return ( checkpoint.timestamp, checkpoint.reward_per_token)
    }

    public fun last_time_reward_applicable<X,Y>(self: &InternalBribe<X,Y>, clock: &Clock):u64{
        math::min(clock::timestamp_ms(clock), self.period_finish)
    }

    public fun bribe_start(ts: u64):u64{
        ts - (ts % vsdb::week())
    }

    public fun get_epoch_start( ts: u64):u64{
        let bribe_start = bribe_start(ts);
        let bribe_end = bribe_start + DURATION;
        if( ts < bribe_end){
            return bribe_start
        }else{
            return bribe_end
        }
    }

    //public fun getf_reward<X,Y>(self: &InternalBribe, )

    // ===== Setter =====
    fun write_checkpoint<X,Y>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &VSDB,
        balance: u64, // record down balance
        clock: &Clock,
        ctx: &mut TxContext
    ){
        let vsdb = object::id(vsdb);
        let timestamp = clock::timestamp_ms(clock);

        // create table_vec for new registry
        if( !table::contains(&self.checkpoints, vsdb)){
            let checkpoints = table_vec::empty(ctx);
            table::add(&mut self.checkpoints, vsdb, checkpoints);
        };

        let player_checkpoint = table::borrow_mut(&mut self.checkpoints, vsdb);
        let len = table_vec::length(player_checkpoint);

        if( len > 0 && table_vec::borrow(player_checkpoint, len - 1).timestamp == timestamp){
            let cp_mut = table_vec::borrow_mut(player_checkpoint, len - 1 );
            cp_mut.balance = balance;
        }else{
            let checkpoint = Checkpoint{
                timestamp,
                balance
            };
            table_vec::push_back(player_checkpoint, checkpoint);
        };
    }

     fun write_reward_per_token_checkpoint<X,Y>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &VSDB,
        reward: u64, // record down balance
        timestamp: u64,
        ctx: &mut TxContext
    ){
        let vsdb = object::id(vsdb);

        if( !table::contains(&self.reward_per_token_checkpoints, vsdb)){
            let checkpoints = table_vec::empty(ctx);
            table::add(&mut self.reward_per_token_checkpoints, vsdb, checkpoints);
        };

        let player_checkpoint = table::borrow_mut(&mut self.reward_per_token_checkpoints, vsdb);
        let len = table_vec::length(player_checkpoint);

        if( len > 0 && table_vec::borrow(player_checkpoint, len - 1).timestamp == timestamp){
            let cp_mut = table_vec::borrow_mut(player_checkpoint, len - 1 );
            cp_mut.reward_per_token = reward;
        }else{
            let checkpoint = RewardPerTokenCheckpoint{
                timestamp,
                reward_per_token: reward
            };
            table_vec::push_back(player_checkpoint, checkpoint);
        };
    }

     fun write_supply_checkpoint<X,Y>(
        reg: &Reg,
        self: &mut InternalBribe<X,Y>,
        clock: &Clock,
        //ctx: &mut TxContext
    ){
        let timestamp = clock::timestamp_ms(clock);
        let supply = reg.total_supply;

        let len = table_vec::length(&self.supply_checkpoints);

        if( len > 0 && table_vec::borrow(&self.supply_checkpoints, len - 1).timestamp == timestamp){
            let cp_mut = table_vec::borrow_mut(&mut self.supply_checkpoints, len - 1 );
            cp_mut.supply = supply;
        }else{
            let checkpoint = SupplyCheckpoint{
                timestamp,
                supply
            };
            table_vec::push_back(&mut self.supply_checkpoints, checkpoint);
        };
    }

    fun earned<X,Y>(
        self: &mut InternalBribe<X,Y>,
        vsdb: &VSDB
    ):u64{
        let id = object::id(vsdb);
        // check contain is sufficient
        if(!table::contains(&self.last_earn, id) || !table::contains(&self.checkpoints, id)){
            return 0
        };

        let last_earn = *table::borrow(&self.last_earn, id);
        let checkpoint = table::borrow(&self.checkpoints, id);

        let start_idx = get_prior_balance_index(self, vsdb, last_earn);
        let end_idx = table_vec::length(checkpoint) - 1;
        6
    }


    // ===== getter =====
    #[test_only]public fun mock_init(ctx: &mut TxContext){
        init(ctx);
    }

}