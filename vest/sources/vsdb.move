module suiDouBashiVest::vsdb{
    use sui::url::{Self, Url};
    use std::string::{Self};
    use sui::tx_context::{TxContext};
    use sui::object::{Self, ID, UID};
    use sui::tx_context;
    use sui::transfer;
    use std::vector as vec;
    use sui::table_vec::{Self, TableVec};
    use sui::balance::{Self, Balance};

    use suiDouBashiVest::sdb::SDB;
    use suiDouBashiVest::point::{Self, Point};
    use suiDouBashi::string::to_string;
    use suiDouBashi::encode::base64_encode as encode;
    use suiDouBashi::i128::{I128};


    const SVG_PREFIX: vector<u8> = b"data:image/svg+xml;base64,";

    // TODO: display pkg format rule
    struct VSDB has key, store {
        id: UID,
        name: string::String,
        url: Url,
        // useful for preventing high-level transfer function & traceability of the owner
        logical_owner: address,
        locked: bool, // Option(?)

        /// latest epoch player trigger
        user_point_epoch: u256,

        /// the most recently recorded rate of voting power decrease for Player
        user_point_history: TableVec<Point>, // epoch -> point_history // TableVec (?)
        /// Should this assign UID (?)
        locekd_balance: LockedSDB
    }


    struct LockedSDB has store{
        /// ID of VSDB
        id: ID,
        balance: Balance<SDB>,
        end: u256
    }

    //https://github.com/velodrome-finance/contracts/blob/afed728d26f693c4e05785d3dbb1b7772f231a76/contracts/VotingEscrow.sol#L766
    public fun new( name: vector<u8>, balance: u256, locked_end: u256, value: u256, ctx: &mut TxContext): VSDB {
        let uid = object::new(ctx);
        let id = object::uid_to_inner(&uid);
        VSDB {
            id: uid,
            name: string::utf8(name),
            url: img_url(object::id_to_bytes(&id), balance, locked_end, value),
            logical_owner: tx_context::sender(ctx),
            locked: false,

            user_point_epoch: 0,
            user_point_history: table_vec::empty<Point>(ctx),
            locekd_balance: LockedSDB{
                id,
                balance: balance::zero<SDB>(),
                end: 0
            }
        }
    }

    // ===== Display & Transfer =====
    public entry fun transfer(self: VSDB, to:address){
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
    fun img_url(id: vector<u8>, balance: u256, locked_end: u256, value: u256): Url {
        let vesdb = SVG_PREFIX;
        let encoded_b = vec::empty<u8>();

        vec::append(&mut encoded_b, b"<svg xmlns='http://www.w3.org/2000/svg' preserveAspectRatio='xMinYMin meet' viewBox='0 0 350 350'><style>.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width='100%' height='100%' fill='#93c5fd' /><text x='10' y='20' class='base'>Token ");
        vec::append(&mut encoded_b,id);
        vec::append(&mut encoded_b,b"</text><text x='10' y='40' class='base'>Balance: ");
        vec::append(&mut encoded_b,*string::bytes(&to_string(balance)));
        vec::append(&mut encoded_b,b"</text><text x='10' y='60' class='base'>Locked end: ");
        vec::append(&mut encoded_b,*string::bytes(&to_string(locked_end)));
        vec::append(&mut encoded_b,b"</text><text x='10' y='80' class='base'>Value: ");
        vec::append(&mut encoded_b,*string::bytes(&to_string(value)));
        vec::append(&mut encoded_b,b"</text></svg>");

        vec::append(&mut vesdb,encode(encoded_b));
        url::new_unsafe_from_bytes(vesdb)
    }

    // ===== fields lookup  =====
    public fun point(self: &VSDB, epoch: u64):&Point{
        table_vec::borrow(&self.user_point_history, epoch)
    }
    public fun latest_point(self: &VSDB):&Point{
        table_vec::borrow(&self.user_point_history, table_vec::length(&self.user_point_history))
    }

    public fun bias(self: &VSDB, epoch: u64): I128{
        point::bias( point(self, epoch) )
    }
    public fun latest_bias(self: &VSDB):I128{
        let point = table_vec::borrow(&self.user_point_history, table_vec::length(&self.user_point_history));
        point::bias(point)
    }

    public fun slope(self: &VSDB, epoch: u64): I128{
        point::slope( point(self, epoch) )
    }
     public fun latest_slope(self: &VSDB):I128{
        let point = table_vec::borrow(&self.user_point_history, table_vec::length(&self.user_point_history));
        point::slope(point)
    }




    // ===== Main =====

    #[test] fun test_url(){
        let foo = img_url(b"0x1234", 2, 3, 4);
        std::debug::print(&foo);
    }

}