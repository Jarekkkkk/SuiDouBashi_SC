module coin_list::faucet {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::transfer;
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};

    use suiDouBashi_vsdb::sdb::SDB;

    struct Faucet has key{
        id: UID,
        balance: Balance<SDB>
    }

    fun init(ctx: &mut TxContext){
        let faucet = Faucet{
            id: object::new(ctx),
            balance: balance::zero<SDB>()
        };

        transfer::share_object(faucet);
    }

    entry public fun deposit(self: &mut Faucet, coin: Coin<SDB>){
       coin::put(&mut self.balance, coin);
    }

    entry public fun take(self: &mut Faucet, ctx: &mut TxContext){
        transfer::public_transfer(coin::take(&mut self.balance, 100_000_000_000, ctx),tx_context::sender(ctx))
    }
}