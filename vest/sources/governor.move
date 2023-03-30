module suiDouBashiVest::governor{
    use sui::object::ID;


    struct CheckPoint has store {
        timestamp: u256,
        // TODO: dynamic fields to store, if no need of accessing into tokens, we could replaced with
        // Table <ts, token_amounts>
        tokenIds: vector<ID>
    }
}