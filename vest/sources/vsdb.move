module suiDouBashiVest::vsdb{
    use sui::url::{Self, Url};
    use std::string::{Self};
    use sui::tx_context::{TxContext};
    use sui::object::{Self, UID};
    use sui::tx_context;
    use sui::transfer;
    use std::vector as vec;
    use sui::table::Table;
    use sui::balance::Balance;


    use suiDouBashi::string::to_string;
    use suiDouBashi::encode::base64_encode as encode;


    const SVG_PREFIX: vector<u8> = b"data:image/svg+xml;base64,";

    // Display:
    // metadata
    struct VSDB has key, store {
        id: UID,
        name: string::String,
        url: Url,
        locked: bool,
        // useful for preventing high-level transfer function & traceability of the owner
        logical_owner: address,

        // escrow fileds
        user_point_epoch: u256,
        // TableVec (?)
        user_point_history: Table<u256, Point>, // epoch -> point_history
        locekd_balance: LockedSDB
    }

         /// locked balance
    struct LockedSDB has key, store{
        id: UID,
        balance: Balance<SDB>,
        end: u256
    }

    public fun new( name: vector<u8>, balance: u256, locked_end: u256, value: u256, ctx: &mut TxContext): VSDB {
        let uid = object::new(ctx);
        let id = object::uid_to_inner(&uid);
        VSDB {
            id: uid,
            name: string::utf8(name),
            url: img_url(object::id_to_bytes(&id), balance, locked_end, value),
            logical_owner: tx_context::sender(ctx)
        }
    }

    public entry fun trasnfer(self: VSDB, to:address){
        transfer::transfer(
            self,
            to
        )
    }

    public fun token_id(self: &VSDB): &UID {
        &self.id
    }

    public fun token_url(self: &VSDB): &Url {
        &self.url
    }

    public fun name(self: &VSDB): &string::String {
        &self.name
    }
    // TODO: compatiable with u256
    fun img_url(id: vector<u8>, balance: u256, locked_end: u256, value: u256): Url {
        let vesdb = SVG_PREFIX;
        let encoded_b = vec::empty<u8>();

        vec::append(&mut encoded_b, b"<svg xmlns='http://www.w3.org/2000/svg' preserveAspectRatio='xMinYMin meet' viewBox='0 0 350 350'><style>.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width='100%' height='100%' fill='#93c5fd' /><text x='10' y='20' class='base'>Token ");
        vec::append(&mut encoded_b,id);
        vec::append(&mut encoded_b,b"</text><text x='10' y='40' class='base'>Balance: ");
        vec::append(&mut encoded_b,*string::bytes(&to_string((balance as u64))));
        vec::append(&mut encoded_b,b"</text><text x='10' y='60' class='base'>Locked end: ");
        vec::append(&mut encoded_b,*string::bytes(&to_string((locked_end as u64))));
        vec::append(&mut encoded_b,b"</text><text x='10' y='80' class='base'>Value: ");
        vec::append(&mut encoded_b,*string::bytes(&to_string((value as u64))));
        vec::append(&mut encoded_b,b"</text></svg>");

        vec::append(&mut vesdb,encode(encoded_b));
        url::new_unsafe_from_bytes(vesdb)
    }





    // ===== Main =====
    #[test] fun test_toString(){
        let str = to_string(51);
        std::debug::print(&str);
    }
    #[test] fun test_url(){
        let foo = img_url(b"0x1234", 2, 3, 4);
        std::debug::print(&foo);
    }

}