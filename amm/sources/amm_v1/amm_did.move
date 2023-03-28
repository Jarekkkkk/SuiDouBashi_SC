/// Configurable and scalable object for storing personal DID data, schema could refers to sui token's model
/// Coin(parent) -> Profile
/// Balance(child) -> DID (this would be constantly added on depends on our future project)
module suiDouBashi::amm_did{
    use sui::object::UID;
    use sui::object;
    use sui::tx_context::TxContext;
    use sui::vec_map::{Self, VecMap};
    use std::string::String;

    // === object ===
    struct AMM_DID has key, store{
        id: UID,
        pools_playin: VecMap<String, u64>,
    }

    public fun create_did(ctx: &mut TxContext):AMM_DID{
        AMM_DID{
            id: object::new(ctx),
            pools_playin: vec_map::empty<String, u64>(),
        }
    }

    public fun update_playin(self: &mut AMM_DID, pool: &String, value: u64){
        let value_mut = vec_map::get_mut(&mut self.pools_playin, pool);
        *value_mut = value;
    }

    public fun get_playin(self: &AMM_DID, pool: &String): u64{
        *vec_map::get(&self.pools_playin, pool)
    }
}