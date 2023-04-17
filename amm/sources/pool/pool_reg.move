module suiDouBashi::pool_reg{
    use sui::object::{UID, ID};
    use sui::table::{Self, Table};
    use std::string::{Self, String};
    use sui::tx_context::{Self,TxContext};
    use sui::object;
    use sui::coin::CoinMetadata;
    use sui::transfer;
    use std::vector;

    use suiDouBashi::type;
    use suiDouBashi::err;
    use suiDouBashi::event;
    use suiDouBashi::pool::{Self, Pool};


    struct PoolReg has key {
        id: UID,
        pools: Table<String, ID>,
        guardian: address
    }

    fun assert_guardian(self :&PoolReg, guardian: address){
        assert!(self.guardian == guardian,err::invalid_guardian());
    }

    fun assert_fee(fee: u64){
        assert!(fee == 1 || fee == 2 || fee == 3 || fee == 4 || fee == 5, err::invalid_fee());
    }

    fun assert_sorted<X, Y>() {
        let (_,_,coin_x_symbol) = type::get_package_module_type<X>();
        let (_,_,coin_y_symbol) = type::get_package_module_type<Y>();

        assert!(coin_x_symbol != coin_y_symbol, err::same_type());

        let coin_x_bytes = std::string::bytes(&coin_x_symbol);
        let coin_y_bytes = std::string::bytes(&coin_y_symbol);

        assert!(vector::length<u8>(coin_x_bytes) <= vector::length<u8>(coin_y_bytes), err::wrong_pair_ordering());

        if (vector::length<u8>(coin_x_bytes) == vector::length<u8>(coin_y_bytes)) {
            let length = vector::length<u8>(coin_x_bytes);
            let i = 0;
            while (i < length) {
                let str_x = *vector::borrow<u8>(coin_x_bytes, i);
                let str_y = *vector::borrow<u8>(coin_y_bytes, i);

                assert!(str_x <= str_y, err::wrong_pair_ordering());
                if(str_x < str_y){
                    break
                };
                i = i + 1;
            }
        };
    }

    // ===== entry =====
    fun init(ctx:&mut TxContext){
        let pool_gov = PoolReg{
            id: object::new(ctx),
            pools: table::new<String, ID>(ctx),
            guardian: tx_context::sender(ctx)
        };
        transfer::share_object(
            pool_gov
        );
    }

    public entry fun create_pool<X,Y>(
        self: &mut PoolReg,
        stable: bool,
        metadata_x: &CoinMetadata<X>,
        metadata_y: &CoinMetadata<Y>,
        fee_percentage: u64,
        ctx: &mut TxContext
    ){
        assert_sorted<X, Y>();
        assert_guardian(self, tx_context::sender(ctx));
        assert_fee(fee_percentage);

        let pool_id = pool::new<X, Y>( stable, metadata_x, metadata_y, fee_percentage, ctx );

        let pool_name = get_pool_name<X,Y>();
        table::add(&mut self.pools, pool_name, pool_id);

        event::pool_created<X,Y>(pool_id, tx_context::sender(ctx))
    }

    entry fun lock_pool<X, Y>(
        self: &PoolReg,
        pool: &mut Pool<X, Y>,
        locked: bool,
        ctx: &mut TxContext
    ){
        assert_guardian(self, tx_context::sender(ctx));
        pool::udpate_lock(pool, locked);
    }

    entry fun update_fee_percentage<X,Y>(self: &PoolReg,pool: &mut Pool<X,Y>, fee: u64, ctx:&mut TxContext){
        assert_guardian(self, tx_context::sender(ctx));
        assert_fee(fee);

        pool::update_fee(pool, fee);
    }

    // ===== Utils =====
    public fun get_pool_name<X,Y>():String{
        let (_, _, symbol_x) = type::get_package_module_type<X>();
        let (_, _, symbol_y) = type::get_package_module_type<Y>();

        string::append(&mut symbol_x, string::utf8(b"-"));
        string::append(&mut symbol_x, symbol_y);
        symbol_x
    }


    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }
}