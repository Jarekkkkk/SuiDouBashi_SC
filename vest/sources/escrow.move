/// An escrow for atomic swap of objects that trusts a third party for liveness, but not safety.
module suiDouBashiVest::escrow {
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};


    /// An object held in escrow
    struct EscrowedObj<T: key + store, phantom ExchangeForT: key + store> has key, store {
        id: UID,
        sender: address,
        recipient: address,
        exchange_for: ID,
        escrowed: T,
    }

    const EMismatchedSenderRecipient: u64 = 0;
    const EMismatchedExchangeObject: u64 = 1;

    public fun create<T: key + store, ExchangeForT: key + store>(
        recipient: address,
        third_party: address,
        exchange_for: ID,
        escrowed: T,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let id = object::new(ctx);
        transfer::transfer(
            EscrowedObj<T,ExchangeForT> {
                id, sender, recipient, exchange_for, escrowed
            },
            third_party
        );
    }

    public entry fun swap<T1: key + store, T2: key + store>(
        obj1: EscrowedObj<T1, T2>,
        obj2: EscrowedObj<T2, T1>,
    ) {
        let EscrowedObj {
            id: id1,
            sender: sender1,
            recipient: recipient1,
            exchange_for: exchange_for1,
            escrowed: escrowed1,
        } = obj1;
        let EscrowedObj {
            id: id2,
            sender: sender2,
            recipient: recipient2,
            exchange_for: exchange_for2,
            escrowed: escrowed2,
        } = obj2;
        object::delete(id1);
        object::delete(id2);
        assert!(&sender1 == &recipient2, EMismatchedSenderRecipient);
        assert!(&sender2 == &recipient1, EMismatchedSenderRecipient);
        assert!(object::id(&escrowed1) == exchange_for2, EMismatchedExchangeObject);
        assert!(object::id(&escrowed2) == exchange_for1, EMismatchedExchangeObject);
        transfer::transfer(escrowed1, sender2);
        transfer::transfer(escrowed2, sender1)
    }

    public entry fun return_to_sender<T: key + store, ExchangeForT: key + store>(
        obj: EscrowedObj<T, ExchangeForT>,
    ) {
        let EscrowedObj {
            id, sender, recipient: _, exchange_for: _, escrowed
        } = obj;
        object::delete(id);
        transfer::transfer(escrowed, sender)
    }
}