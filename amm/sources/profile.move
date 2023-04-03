module suiDouBashi::profile{
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use std::ascii::{Self, String};
    use std::vector::{Self};
    use suiDouBashi::err;
    use sui::url::{Self, Url};
    use std::option::{Self, Option};
    use suiDouBashi::encode;
    use sui::transfer::{transfer, share_object};
    use sui::dynamic_object_field as dof;

    use suiDouBashi::event;

    const MAX_NAME_LENGTH:u8 = 30;
    const MAX_IMG_URI_LENGTH: u64 = 6000;
    const USER_URL: vector<u8> = b"http://localhost:3000/"; //TODO: prefix with deployed app

    // --OTW
    struct PRO has drop {}

    // --ProfileReg
     struct PlayerRegistry has key {
        id: UID,
        players: Table<String, address>,
    }

    // --Profile
    struct Attribute has copy, store, drop{
        key: String,
        value: String
    }
    struct Profile has key, store{
        id: UID,
        name: String,
        avatar: Url,
        level: u64,
        /// Metadata
        link: Url,
        ///DID

        // something magic to come up
        attributes: vector<Attribute>,
    }

    // === Entry ===
    fun init(ctx: &mut TxContext){
        let reg = PlayerRegistry{
            id: object::new(ctx),
            players:table::new<String, address>(ctx)
        };
        share_object(reg);
    }
    public entry fun register(registry: &mut PlayerRegistry, url:String, name: String, ctx: &mut TxContext){
        assert!(!is_registered(registry, name), err::alreday_registered());

        table::add(&mut registry.players, name, tx_context::sender(ctx));

        let attr = create_attribute_(b"gender:", b"male");
        let profile = Profile{
            id: object::new(ctx),
            name,
            avatar: url::new_unsafe(url),
            level:0,
            link: link_url(name),
            attributes: vector[attr]
        };

        let defi_did = suiDouBashi::amm_did::create_did(ctx);
        add_item<suiDouBashi::amm_did::AMM_DID>(&mut profile, defi_did);

        transfer(
            profile,
            tx_context::sender(ctx)
        );
    }
    public entry fun create_attribute(profile: &mut Profile, name: vector<u8>, value: vector<u8>) {
        let attr = create_attribute_(name, value);
        let attr_mut = &mut profile.attributes;
        vector::push_back(attr_mut, attr);
    }
    fun create_attribute_(name: vector<u8>, value: vector<u8>): Attribute {
        Attribute {
            key: ascii::string(name),
            value: ascii::string(value)
        }
    }
    // === Utils ===
    public fun is_registered(self: &PlayerRegistry, name: String): bool {
        table::contains(&self.players, name)
    }
    fun validate_name(name: &String){
        let name_bytes = ascii::as_bytes(name);

        let name_len = vector::length<u8>(name_bytes);
        assert!((name_len != 0 || name_len <= (MAX_NAME_LENGTH as u64)), err::invalid_name());

        let i = 0;
        while ( i < name_len){
            // only allow characters and '.', '-', '_'
            let b = *vector::borrow<u8>(name_bytes, i);
            let fail = if(
                (b < *vector::borrow<u8>(&b"0", 0)
                ||  b > *vector::borrow<u8>(&b"z", 0)
                || (
                    ( b > *vector::borrow<u8>(&b"9", 0))
                    &&(b < *vector::borrow<u8>(&b"A", 0))
                    )
                || (
                    ( b > *vector::borrow<u8>(&b"Z", 0))
                    &&(b < *vector::borrow<u8>(&b"a", 0))
                )
                )
                && b != *vector::borrow<u8>(&b".", 0)
                && b != *vector::borrow<u8>(&b"-", 0)
                && b != *vector::borrow<u8>(&b"_", 0)
            ){
                true
            }else{
                false
            };
            assert!(!fail, err::invalid_name());
            i = i + 1 ;
        }
    }
    /// Profile dashboard
    fun link_url(name: String): Url {
        let url = *&USER_URL;
        vector::append(&mut url, encode::hex_encode(ascii::into_bytes(name)));
        url::new_unsafe_from_bytes(url)
    }
    /// IPFS storage URL
    fun validate_img_length(image_url: &Url){
        assert!(ascii::length(&url::inner_url(image_url)) <= MAX_IMG_URI_LENGTH, err::invalid_img_url());
    }
    // Index players by name key
    public fun player_address(reg: &PlayerRegistry, name: String): Option<address> {
        let players = &reg.players;
        if (table::contains(players, name)) {
            option::some(*table::borrow(players, name))
        } else {
            option::none()
        }
    }
    // governacne function
    public entry fun add_item<T: key + store>(profile: &mut Profile, item: T) {
        let item_id = object::id(&item);

        dof::add(&mut profile.id, item_id, item);

        event::item_added<T>(object::uid_to_inner(&profile.id),item_id );
    }

}