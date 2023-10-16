/// Pool's governance interactinos, only PoolCap holder is allowed to invoke below functions
module suiDouBashi_amm::pool_reg{
    use sui::object::{UID, ID};
    use sui::table::{Self, Table};
    use sui::coin;
    use std::string::{Self, String};
    use sui::tx_context::{Self,TxContext};
    use sui::object;
    use sui::coin::CoinMetadata;
    use sui::transfer;
    use std::vector;
    use std::type_name::{get, borrow_string};
    use std::bcs;

    use suiDouBashi_amm::event;
    use suiDouBashi_amm::pool::{Self, Pool};

    const ERR_INVALD_FEE: u64 = 0;
    const ERR_INVALD_PAIR: u64 = 0;



    struct PoolCap has key { id: UID }

    struct PoolReg has key {
        id: UID,
        pools: Table<vector<u8>, ID>
    }


    fun assert_fee(stable: bool, fee: u8){
        if(stable){
            assert!(fee >= 1 && fee <= 5, ERR_INVALD_FEE);
        }else{
            assert!(fee >= 10 && fee <= 50, ERR_INVALD_FEE);
        }
    }

    // ===== entry =====
    fun init(ctx:&mut TxContext){
        let pool_gov = PoolReg{
            id: object::new(ctx),
            pools: table::new<vector<u8>, ID>(ctx)
        };
        transfer::share_object(
            pool_gov
        );
        transfer::transfer(
            PoolCap{
                id: object::new(ctx)
            },
            tx_context::sender(ctx)
        );
    }

    /// Only Governor can create pool as stable argument has to be determined beforehand
    public entry fun create_pool<X,Y>(
        self: &mut PoolReg,
        _cap: &PoolCap,
        stable: bool,
        metadata_x: &CoinMetadata<X>,
        metadata_y: &CoinMetadata<Y>,
        fee_percentage: u8,
        ctx: &mut TxContext
    ){
        assert_fee(stable, fee_percentage);
        let name = get_pool_name<X,Y>(metadata_x, metadata_y);
        let pool_id = pool::new<X,Y>(name, stable, metadata_x, metadata_y, fee_percentage, ctx);

        let hash = bcs::to_bytes(borrow_string(&get<X>()));
        vector::append(&mut hash, bcs::to_bytes(borrow_string(&get<Y>())));
        hash = std::hash::sha2_256(hash);

        table::add(&mut self.pools, hash, pool_id);
        event::pool_created<X,Y>(pool_id, tx_context::sender(ctx))
    }

    entry fun update_pool<X,Y>(
        _cap: &PoolCap,
        pool: &mut Pool<X, Y>,
        locked: bool
    ){
        pool::udpate_lock(pool, locked);
    }

    entry public fun update_fee<X,Y>(
        _cap: &PoolCap,
        pool: &mut Pool<X,Y>,
        fee: u8
    ){
        assert_fee(pool::stable(pool), fee);
        pool::update_fee(pool, fee);
    }

    entry public fun update_stable<X,Y>(
        _cap: &PoolCap,
        pool: &mut Pool<X,Y>,
        stable: bool
    ){
        pool::update_stable(pool, stable);
    }

    // ===== Utils =====
    public fun get_pool_name<X,Y>(metadata_x: &CoinMetadata<X>, metadata_y: &CoinMetadata<Y>):String{
        let coin_x_symbol = coin::get_symbol(metadata_x);
        let coin_y_symbol = coin::get_symbol(metadata_y);

        // sort the type_name
        assert!(coin_x_symbol != coin_y_symbol, ERR_INVALD_PAIR);

        let coin_x_bytes = std::ascii::as_bytes(&coin_x_symbol);
        let coin_y_bytes = std::ascii::as_bytes(&coin_y_symbol);

        assert!(vector::length<u8>(coin_x_bytes) <= vector::length<u8>(coin_y_bytes), ERR_INVALD_PAIR);

        if (vector::length<u8>(coin_x_bytes) == vector::length<u8>(coin_y_bytes)) {
            let length = vector::length<u8>(coin_x_bytes);
            let i = 0;
            while (i < length) {
                let str_x = *vector::borrow<u8>(coin_x_bytes, i);
                let str_y = *vector::borrow<u8>(coin_y_bytes, i);

                assert!(str_x <= str_y, ERR_INVALD_PAIR);
                if(str_x < str_y){
                    break
                };
                i = i + 1;
            }
        };
        let symbol_x = string::from_ascii(coin_x_symbol);
        let symbol_y = string::from_ascii(coin_y_symbol);
        string::append(&mut symbol_x, string::utf8(b"-"));
        string::append(&mut symbol_x, symbol_y);
        symbol_x
    }

    public fun pools_length(self: &PoolReg):u64{ table::length(&self.pools) }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }
}