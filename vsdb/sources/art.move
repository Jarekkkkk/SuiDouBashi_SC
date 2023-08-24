module suiDouBashi_vsdb::art{
    use std::vector as vec;
    use std::ascii::{Self, String};
    use sui::object::{Self, UID};

    use suiDouBashi_vsdb::to_string::to_string;
    use suiDouBashi_vsdb::encode::base64_encode as encode;


    // ====== IMAGE ======
    const DEFAULT: vector<u8> = b"https://ucarecdn.com/21e97dbe-3431-49bb-a80f-820dbc765efb/Empty.png";
    const LV1: vector<u8> = b"https://ucarecdn.com/e4581e34-4800-4a97-ae8e-c6cc66376653/LV1.png";
    const LV2: vector<u8> = b"https://ucarecdn.com/a889238e-f759-4c7a-b288-a80e41ce6ead/LV2.png";
    const LV3: vector<u8> = b"https://ucarecdn.com/013ef661-dbf3-4b90-9578-9ccf7d7ecacf/LV3.png";

    public fun image_url(id: &UID):String{
        let bytes = object::uid_to_bytes(id);
        let value = *vec::borrow(&bytes, 0);
        let point = value - value / 4 * 4;
        if(point == 0) return ascii::string(DEFAULT);
        if(point == 1) return ascii::string(LV1);
        if(point == 2) return ascii::string(LV2);
        return ascii::string(LV3)
    }

    const SVG_PREFIX: vector<u8> = b"data:image/svg+xml;base64,";

    // ====== Error ======

    const E_NOT_INVALID_MONTH: u64 = 1;
    const  E_OUT_OF_RANGE: u64 = 2;

    // ====== Error ======

    /// ATTRIBUTES COLOR
    const BORDER_COLOR: vector<vector<u8>> = vector[
        b"white",
        b"black",
        b"bronze",
        b"silver",
        b"gold",
        b"rainbow"
    ];
    const CARD_COLOR: vector<vector<u8>> = vector[
        b"red",
        b"green",
        b"blue",
        b"purple",
        b"pink",
        b"yellow_pink",
        b"blue_green",
        b"pink_blue",
        b"red_purple",
        b"bronze",
        b"silver",
        b"gold",
        b"rainbow"
    ];
    const SHELL_COLOR: vector<vector<u8>> = vector[
        b"off_white",
        b"light_blue",
        b"darker_blue",
        b"lighter_orange",
        b"light_orange",
        b"darker_orange",
        b"light_green",
        b"darker_greeen",
        b"bronze",
        b"silver",
        b"gold",
        b"rainbow"
    ];

    // Weights
    const BORDER_WEIGHTS: vector<u8> = vector[30, 30, 15, 12, 8, 5]; // [6, 100 bps]
    const CARD_WEIGHTS: vector<u32> = vector[12, 12, 12, 11, 11, 7, 7, 7, 7, 5, 4, 3, 2]; // [13, 100 bps]
    const SHELL_WEIGHTS: vector<u8> = vector[2, 10, 10, 11, 11, 11, 11, 11, 75, 7, 5, 25, 1]; // [13, 200 bps]

    public fun img_url(id: vector<u8>, voting_weight: u256, locked_end: u256, locked_amount: u256): String {
        let vesdb = SVG_PREFIX;
        let encoded_b = vec::empty<u8>();

        vec::append(&mut encoded_b, b"<svg xmlns='http://www.w3.org/2000/svg' preserveAspectRatio='xMinYMin meet' viewBox='0 0 350 350'><style>.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width='100%' height='100%' fill='#93c5fd' /><text x='10' y='20' class='base'>Token ");
        vec::append(&mut encoded_b, id);
        vec::append(&mut encoded_b, b"</text><text x='10' y='40' class='base'>Voting Weight: ");
        vec::append(&mut encoded_b, ascii::into_bytes(to_string(voting_weight)));
        vec::append(&mut encoded_b, b"</text><text x='10' y='60' class='base'>Locked end: ");
        vec::append(&mut encoded_b, ascii::into_bytes(to_string(locked_end)));
        vec::append(&mut encoded_b, b"</text><text x='10' y='80' class='base'>Locked_amount: ");
        vec::append(&mut encoded_b, ascii::into_bytes(to_string(locked_amount)));
        vec::append(&mut encoded_b, b"</text></svg>");

        vec::append(&mut vesdb,encode(encoded_b));
        ascii::string(vesdb)
    }

    public fun get_svg(){
        let svg = b"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 750 1050'>";

        vec::append(&mut svg, b"</svg>");
    }

    public fun get_svg_style():vector<u8>{
        let style = b"<style>";

        vec::append(&mut style, b"</style>");
        style
    }

    public fun get_month_string(month: u8):vector<u8>{
        if (month ==  1) return b"JANUARY";
        if (month ==  2) return b"FEBRUARY";
        if (month ==  3) return b"MARCH";
        if (month ==  4) return b"APRIL";
        if (month ==  5) return b"MAY";
        if (month ==  6) return b"JUNE";
        if (month ==  7) return b"JULY";
        if (month ==  8) return b"AUGUST";
        if (month ==  9) return b"SEPTEMBER";
        if (month == 10) return b"OCTOBER";
        if (month == 11) return b"NOVEMBER";
        if (month == 12) return b"DECEMBER";
        abort E_NOT_INVALID_MONTH
    }

    public fun get_border_color(rand: u8):u8{
        let tier = *vec::borrow(&BORDER_WEIGHTS, 0);
        if(rand < tier) return 0;
        tier = tier + *vec::borrow(&BORDER_WEIGHTS, 1);
        if(rand < tier) return 1;
        tier = tier + *vec::borrow(&BORDER_WEIGHTS, 2);
        if(rand < tier) return 2;
        tier = tier + *vec::borrow(&BORDER_WEIGHTS, 3);
        if(rand < tier) return 3;
        tier = tier + *vec::borrow(&BORDER_WEIGHTS, 4);
        if(rand < tier) return 4;
        return 5
    }

    public fun get_card_affinity_weights(border_color: u8):vector<u32>{
        let border_color = (border_color as u64);
        assert!((border_color as u64) < vec::length(&BORDER_COLOR), E_OUT_OF_RANGE);
        if(border_color > 1){
            let card_color = if(vec::borrow(&BORDER_COLOR, border_color) == &b"bronze"){
                let (_, idx) = vec::index_of(&CARD_COLOR, &b"bronze");
                idx
            }else if(vec::borrow(&BORDER_COLOR, border_color) == &b"silver"){
                let (_, idx) = vec::index_of(&CARD_COLOR, &b"silver");
                idx
            }else if(vec::borrow(&BORDER_COLOR, border_color) == &b"gold"){
                let (_, idx) = vec::index_of(&CARD_COLOR, &b"gold");
                idx
            }else{
                let (_, idx) = vec::index_of(&CARD_COLOR, &b"rainbow");
                idx
            };

            let weights = *vec::borrow(&CARD_WEIGHTS, card_color);
            let card_weights = CARD_WEIGHTS;
            let i = 0;
            while( i < vec::length(&card_weights)){
                *vec::borrow_mut(&mut card_weights, i) = *vec::borrow(&card_weights, i) * 10000 * ((100 - weights)/ (100 - 2 * weights));
                i = i + 1;
            };
            *vec::borrow_mut(&mut card_weights, card_color) = weights * 2 * 10000;

            card_weights
        }else{
            let i = 0;
            let card_weights = CARD_WEIGHTS;
            while( i < vec::length(&CARD_WEIGHTS)){
               std::debug::print(vec::borrow(&card_weights, i));
                *vec::borrow_mut(&mut card_weights, i) = *vec::borrow(&card_weights, i) * 10000;

                i = i + 1;
            };
            card_weights
        }
    }

    #[test]
    fun test_img(){
        let url = img_url(b"0x1234", 100, 1000, 1000);
        std::debug::print(&url);
    }

    #[test]
    fun test_month(){
        let month = get_month_string(1);
        assert!(month == b"JANUARY", 404);
    }

    #[test]
    #[expected_failure(abort_code = E_NOT_INVALID_MONTH)]
    fun test_month_fail(){
        get_month_string(0);
    }

    #[test]
     fun test_weights(){
        let weights = get_card_affinity_weights(0);
        // no affinity bonus
        let i = 0;
        let card_weights = CARD_WEIGHTS;
        while( i < vec::length(&CARD_WEIGHTS)){
            *vec::borrow_mut(&mut card_weights, i) = *vec::borrow(&card_weights, i) * 10000;

            i = i + 1;
        };
        assert!(weights == card_weights, 404);

        // With Affinity Bonus
        weights = get_card_affinity_weights(5);
        std::debug::print(&weights);
     }
}