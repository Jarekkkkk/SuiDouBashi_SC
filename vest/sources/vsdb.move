module suiDouBashiVest::vsdb{
    use sui::url::{Self, Url};
    use std::string::{Self};
    use sui::tx_context::{TxContext};
    use sui::object::{Self, ID, UID};
    use sui::tx_context;
    use sui::transfer;
    use std::vector as vec;
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};
    use sui::coin::{Self, Coin};
    use std::option::{Self, Option};
    use sui::clock::{Self, Clock};

    use suiDouBashiVest::sdb::SDB;
    use suiDouBashiVest::point::{Self, Point};

    use suiDouBashi::string::to_string;
    use suiDouBashi::encode::base64_encode as encode;
    use suiDouBashi::i128::{Self, I128};

    friend suiDouBashiVest::vest;

    const MAX_TIME: u64 = { 4 * 365 * 86400 };
    const SVG_PREFIX: vector<u8> = b"data:image/svg+xml;base64,";

    // TODO: display pkg format rule
    struct VSDB has key, store {
        id: UID,
        url: Url,
        // useful for preventing high-level transfer function & traceability of the owner
        logical_owner: address,

        // version: latest count
        user_epoch: u64,
        // this table is bined at above user_epoch or global_epoch (?)
        /// the most recently recorded rate of voting power decrease for Player
        user_point_history: Table<u64, Point>, // epoch -> point_history // TableVec (?)

        /// Should this assign UID (?)
        locked_balance: LockedSDB
    }

    struct LockedSDB has store{
        /// ID of VSDB
        id: ID,
        balance: Balance<SDB>,
        end: u64
    }

    //https://github.com/velodrome-finance/contracts/blob/afed728d26f693c4e05785d3dbb1b7772f231a76/contracts/VotingEscrow.sol#L766
    /// Useful when we first deposit
    public (friend) fun new(locked_sdb: Coin<SDB>, unlock_time: u64, ts: u64, ctx: &mut TxContext): VSDB {
        let uid = object::new(ctx);
        let id = object::uid_to_inner(&uid);
        let amount = coin::value(&locked_sdb);
        let slope = i128::div( &i128::from((amount as u128)), &i128::from((MAX_TIME as u128)));
        let voting_weight = i128::as_u128(&i128::mul(&slope ,&i128::from(((unlock_time - ts) as u128))));
        let user_point_history = table::new<u64, Point>(ctx);

        let vsdb = VSDB {
            id: uid,
            url: img_url(object::id_to_bytes(&id),(voting_weight as u256) , (unlock_time as u256), (amount as u256)),
            logical_owner: tx_context::sender(ctx),

            user_epoch: 0,
            user_point_history,
            locked_balance: LockedSDB{
                id,
                balance: coin::into_balance(locked_sdb),
                end: unlock_time
            }
        };

        update_user_point(&mut vsdb, ts);

        vsdb
    }

    /// TWO SCENARIO:
    /// 1. extend the amount
    /// 2. extend the locked_time
    public (friend) fun extend(
        self: &mut VSDB,
        coin: Option<Coin<SDB>>,
        extended_duration: u64, // extended ! not specific value
        ts: u64,
    ):(u64, u64){
        if(option::is_some<Coin<SDB>>(&coin)){
            // extend the amount
            balance::join(&mut self.locked_balance.balance, coin::into_balance(option::destroy_some(coin)));
        }else{
            // extedn the time_lock
            self.locked_balance.end = self.locked_balance.end + extended_duration;
            option::destroy_none(coin);
        };

        update_user_point(self, ts);

        (balance::value(&self.locked_balance.balance), self.locked_balance.end)
    }

    public (friend) fun withdraw(self: &mut VSDB, ctx: &mut TxContext): Coin<SDB>{
        let bal = balance::withdraw_all(&mut self.locked_balance.balance);
        coin::from_balance(bal, ctx)
    }

    public fun destroy(self: VSDB){
       let VSDB{
            id,
            url: _,
            logical_owner: _,
            user_epoch: _,
            user_point_history,
            locked_balance
        } = self;

        let LockedSDB{
            id: _,
            balance,
            end: _
        } = locked_balance;

        table::drop<u64, Point>(user_point_history);
        balance::destroy_zero(balance);
        object::delete(id);
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


    // ===== Getter  =====
    public fun max_time():u64{MAX_TIME}


    // - Self
    public fun user_epoch(self: &VSDB): u64{
        self.user_epoch
    }

    public fun locked_balance(self: &VSDB): u64{
        balance::value(&self.locked_balance.balance)
    }

    public fun locked_end(self: &VSDB):u64{
        self.locked_balance.end
    }

    // - point
    public fun get_latest_bias(self: &VSDB): I128{
        // no need of len - 1, as epoch 1 = table::new()
        get_bias(self, table::length(&self.user_point_history))
    }
    public fun get_bias(self: &VSDB, epoch: u64): I128{
        let point = table::borrow(&self.user_point_history, epoch);
        point::bias(point)
    }

    public fun get_latest_slope(self: &VSDB): I128{
        get_slope(self, table::length(&self.user_point_history))
    }
    public fun get_slope(self: &VSDB, epoch: u64): I128{
        let point = table::borrow(&self.user_point_history, epoch);
        point::slope( point )
    }

      public fun get_latest_ts(self: &VSDB): u64{
        get_ts(self, table::length(&self.user_point_history))
    }
    public fun get_ts(self: &VSDB, epoch: u64): u64{
        let point = table::borrow(&self.user_point_history, epoch);
        point::ts( point )
    }







    // ===== Setter  =====
    /// 1. increase version
    /// 2. update point
    ///
    /// have to called after modification of locked_balance
    public fun update_user_point(self: &mut VSDB, time_stamp: u64){
        let amount = balance::value(&self.locked_balance.balance);
        let slope = i128::div( &i128::from((amount as u128)), &i128::from((MAX_TIME as u128)));
        let bias = i128::mul(&slope, &i128::from((self.locked_balance.end as u128) - (time_stamp as u128)) );
        // update epoch version
        self.user_epoch = self.user_epoch + 1;

        let point = point::from(bias, slope, time_stamp);
        table::add(&mut self.user_point_history, self.user_epoch, point);
    }




    // ===== Utils =====
    /// get the voting weight depends on
    public fun voting_weight(self: &VSDB, ts: u64): u64{
        if(self.user_epoch == 0){
            return 0
        }else{
            let last_point = *table::borrow(&self.user_point_history, self.user_epoch);
            let last_point_bias = point::bias(&last_point);
            last_point_bias = i128::sub(&last_point_bias, &i128::from(((ts - point::ts(&last_point)) as u128)));

            if(i128::compare(&last_point_bias, &i128::zero()) == 1){
                last_point_bias = i128::zero();
            };
            return ((i128::as_u128(&last_point_bias))as u64)
        }
    }
    public fun latest_voting_weight(self: &VSDB, clock: &Clock):u64{
        voting_weight(self, clock::timestamp_ms())
    }


    // ===== Internal =====
    fun img_url(id: vector<u8>, voting_weight: u256, locked_end: u256, locked_amount: u256): Url {
        let vesdb = SVG_PREFIX;
        let encoded_b = vec::empty<u8>();

        vec::append(&mut encoded_b, b"<svg xmlns='http://www.w3.org/2000/svg' preserveAspectRatio='xMinYMin meet' viewBox='0 0 350 350'><style>.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width='100%' height='100%' fill='#93c5fd' /><text x='10' y='20' class='base'>Token ");
        vec::append(&mut encoded_b,id);
        vec::append(&mut encoded_b,b"</text><text x='10' y='40' class='base'>Voting Weight: ");
        vec::append(&mut encoded_b,*string::bytes(&to_string(voting_weight)));
        vec::append(&mut encoded_b,b"</text><text x='10' y='60' class='base'>Locked end: ");
        vec::append(&mut encoded_b,*string::bytes(&to_string(locked_end)));
        vec::append(&mut encoded_b,b"</text><text x='10' y='80' class='base'>Locked_amount: ");
        vec::append(&mut encoded_b,*string::bytes(&to_string(locked_amount)));
        vec::append(&mut encoded_b,b"</text></svg>");

        vec::append(&mut vesdb,encode(encoded_b));
        url::new_unsafe_from_bytes(vesdb)
    }

    #[test] fun test_url(){
        let foo = img_url(b"0x1234", 2, 3, 4);
        std::debug::print(&foo);
    }
}