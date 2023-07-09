module suiDouBashi_vsdb::art{
    use std::vector as vec;
    use std::ascii::{Self, String};

    use sui::object::{Self, ID};
    use sui::hex;

    use suiDouBashi_vsdb::to_string::to_string;
    use suiDouBashi_vsdb::date;
    use suiDouBashi_vsdb::encode::base64_encode as encode;

    const SVG_PREFIX: vector<u8> = b"data:image/svg+xml;base64,";
    const SCALING: u32 = 10_000;

    // ====== Error ======

    const E_NOT_INVALID_MONTH: u64 = 1;
    const E_OUT_OF_RANGE: u64 = 2;
    const E_NOT_ATTRIBUTE: u64 = 3;

    // ====== Error ======

    /// ATTRIBUTES COLOR
    /// 6 different colors
    const BORDER_COLOR: vector<vector<u8>> = vector[
        b"white",
        b"black",
        b"bronze",
        b"silver",
        b"gold",
        b"rainbow"
    ];
    /// 13 different colors
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
    /// 13 different colors
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
        b"rainbow",
        b"luminous"
    ];

    // Weights
    const BORDER_WEIGHTS: vector<u8> = vector[30, 30, 15, 12, 8, 5]; // [6, 100 bps]
    /// Below weights will be re-calculated if user has
    const CARD_WEIGHTS: vector<u32> = vector[12, 12, 12, 11, 11, 7, 7, 7, 7, 5, 4, 3, 2]; // [13, 100 bps]
    const SHELL_WEIGHTS: vector<u32> = vector[2, 10, 10, 11, 11, 11, 11, 11, 75, 7, 5, 25, 1]; // [13, 200 bps]

    struct BondData has drop{
        id: ID,
        sdb_amount: u64,
        claimed_sdb: u64,
        start_time: u64,
        end_time: u64,
        dna_1: u128,
        dna_2: u128,
        status: u8
    }

    fun img_url(id: vector<u8>, voting_weight: u256, locked_end: u256, locked_amount: u256): String {
        let vsdb = SVG_PREFIX;
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

        vec::append(&mut vsdb,encode(encoded_b));
        ascii::string(vsdb)
    }

    public fun get_metadata_json(bond_data: &BondData): String{
        let url = SVG_PREFIX;
        vec::append(&mut url, encode(get_svg(bond_data)));

        ascii::string(url)
    }

    public fun get_svg(bond: &BondData):vector<u8>{
        let svg = b"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 750 1050'>";
        vec::append(&mut svg, b"'#egg-'");
        vec::append(&mut svg, get_svg_style(bond));
        vec::append(&mut svg, get_svg_card(bond));
        vec::append(&mut svg, get_svg_egg(bond));
        vec::append(&mut svg, get_svg_bond_data(bond));
        vec::append(&mut svg, b"</svg>");

        svg
    }

    public fun get_svg_style(bond: &BondData):vector<u8>{
        let style = b"<style>";

        vec::append(&mut style, b" #egg-");
        vec::append(&mut style, hex::encode(object::id_to_bytes(&bond.id)));
        vec::append(&mut style, b" {");
        vec::append(&mut style, b" animation: shake 3s infinite ease-out;");
        vec::append(&mut style, b" transform-origin: 50%; }");

        vec::append(&mut style, b"@keyframes shake { 0% {transform: rotate(0deg);} 65% { transform: rotate(0deg);} 70% { transform: rotate(3deg);} 75% { transform: rotate(0deg); } 80% { transform: rotate(-3deg); } 85% { transform: rotate(0deg); } 90% { transform: rotate(3deg);} 100% { transform: rotate(0deg); }} </style>");

        style
    }

    public fun get_svg_card(bond: &BondData):vector<u8>{
        let style = b"<rect fill='#fff' mix-blend-mode='color-dodge' width='750' height='1050' rx='37.5' /> <rect fill='#008bf7' x='30' y='30' width='690' height='990' rx='37.5'/> <text fill='#fff' font-family='Arial Black, Arial' font-size='72px' font-weight='800' text-anchor='middle' x='50%' y='151'>SDB</text> <text fill='#fff' font-family='Arial Black, Arial' font-size='30px' font-weight='800' text-anchor='middle' x='50%' y='204'>ID: ";
        vec::append(&mut style, hex::encode(object::id_to_bytes(&bond.id)));
        vec::append(&mut style, b"</text>, <ellipse fill='#0a102e' cx='375.25' cy='618.75' rx='100' ry='19'/>");

        style
    }

    public fun get_svg_egg(bond: &BondData):vector<u8>{
        let style = b"<g id='egg-";
        vec::append(&mut style, hex::encode(object::id_to_bytes(&bond.id)));
        vec::append(&mut style, b"'> <path fill='#fff1cb' d='M239.76,481.87c0,75.6,60.66,136.88,135.49,136.88s135.49-61.28,135.49-136.88S450.08,294.75,375.25,294.75C304.56,294.75,239.76,406.27,239.76,481.87Z'/> <path fill='#fce3b1' d='M443.61,326.7c19.9,34.86,31.91,75.58,31.91,109.2,0,75.6-60.67,136.88-135.5,136.88a134.08,134.08,0,0,1-87.53-32.41C274.2,586.72,320.9,618.78,375,618.78c74.83,0,135.5-61.28,135.5-136.88C510.52,431.58,483.64,365.37,443.61,326.7Z'/> <path fill='#fff8e9' d='M298.26,367.33c-10,22.65-9.13,49.22,5.42,60.19,16.26,12.25,39.81,15,61.63-5.22,20.95-19.43,39.13-73.24,2.07-92.5C347.08,319.25,309.31,342.25,298.26,367.33Z'/> </g>");

        style
    }

    public fun get_svg_bond_data(bond: &BondData):vector<u8>{
        let style = b"<text fill='#fff' font-family='Arial Black, Arial' font-size='40px' font-weight='800' text-anchor='middle' x='50%' y='755'>BOND AMOUNT</text> <text fill='#fff' font-family='Arial Black, Arial' font-size='64px' font-weight='800' text-anchor='middle' x='50%' y='848'>";
        vec::append(&mut style, ascii::into_bytes(to_string((bond.sdb_amount as u256))));
        vec::append(&mut style, b"</text> <text fill='#fff' font-family='Arial Black, Arial' font-size='30px' font-weight='800' text-anchor='middle' x='50%' y='950' opacity='0.6'>");
        vec::append(&mut style, get_month_string(date::get_month(bond.start_time)));
        vec::append(&mut style, b" ");
        vec::append(&mut style, ascii::into_bytes(to_string((date::get_day(bond.start_time)as u256))));
        vec::append(&mut style, b" ");
        vec::append(&mut style, ascii::into_bytes(to_string((date::get_year(bond.start_time) as u256))));
        vec::append(&mut style, b" </text>");
        style
    }

    public fun get_month_string(month: u64):vector<u8>{
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


    // ======= Color  =======

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
        let (exist, idx) = vec::index_of(&BORDER_COLOR, &b"bronze");
        assert!(exist, E_NOT_ATTRIBUTE);

        if(border_color >= idx){
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
                *vec::borrow_mut(&mut card_weights, i) = *vec::borrow(&card_weights, i) * SCALING * (100 - weights)/ (100 - 2 * weights);
                i = i + 1;
            };
            *vec::borrow_mut(&mut card_weights, card_color) = weights * 2 * SCALING;

            card_weights
        }else{
            let i = 0;
            let card_weights = CARD_WEIGHTS;
            while( i < vec::length(&CARD_WEIGHTS)){
                *vec::borrow_mut(&mut card_weights, i) = *vec::borrow(&card_weights, i) * SCALING;
                i = i + 1;
            };
            card_weights
        }
    }

    public fun get_card_color(rand: u32, border_color: u8): u32{
        let card_weights = get_card_affinity_weights(border_color);

        let tier = *vec::borrow(&card_weights, 0);
        if(rand < tier) return 0;
        tier = tier + *vec::borrow(&card_weights, 1);
        if(rand < tier) return 1;
        tier = tier + *vec::borrow(&card_weights, 2);
        if(rand < tier) return 2;
        tier = tier + *vec::borrow(&card_weights, 3);
        if(rand < tier) return 3;
        tier = tier + *vec::borrow(&card_weights, 4);
        if(rand < tier) return 4;
        tier = tier + *vec::borrow(&card_weights, 5);
        if(rand < tier) return 5;
        tier = tier + *vec::borrow(&card_weights, 6);
        if(rand < tier) return 6;
        tier = tier + *vec::borrow(&card_weights, 7);
        if(rand < tier) return 7;
        tier = tier + *vec::borrow(&card_weights, 8);
        if(rand < tier) return 8;
        tier = tier + *vec::borrow(&card_weights, 9);
        if(rand < tier) return 9;
        tier = tier + *vec::borrow(&card_weights, 10);
        if(rand < tier) return 10;
        tier = tier + *vec::borrow(&card_weights, 11);
        if(rand < tier) return 11;
        return 12
    }

    public fun get_shell_affinity_weights(border_color: u8):vector<u32>{
        let border_color = (border_color as u64);
        assert!((border_color as u64) < vec::length(&BORDER_COLOR), E_OUT_OF_RANGE);
        if(border_color > 1){
            let card_color = if(vec::borrow(&BORDER_COLOR, border_color) == &b"bronze"){
                let (_, idx) = vec::index_of(&SHELL_COLOR, &b"bronze");
                idx
            }else if(vec::borrow(&BORDER_COLOR, border_color) == &b"silver"){
                let (_, idx) = vec::index_of(&SHELL_COLOR, &b"silver");
                idx
            }else if(vec::borrow(&BORDER_COLOR, border_color) == &b"gold"){
                let (_, idx) = vec::index_of(&SHELL_COLOR, &b"gold");
                idx
            }else{
                let (_, idx) = vec::index_of(&SHELL_COLOR, &b"rainbow");
                idx
            };

            let weights = *vec::borrow(&SHELL_WEIGHTS, card_color);
            let shell_weights = SHELL_WEIGHTS;
            let i = 0;
            while( i < vec::length(&shell_weights)){
                *vec::borrow_mut(&mut shell_weights, i) = *vec::borrow(&shell_weights, i) * SCALING * (100 - weights)/ (100 - 2 * weights);
                i = i + 1;
            };
            *vec::borrow_mut(&mut shell_weights, card_color) = weights * 2 * SCALING;

            shell_weights
        }else{
            let i = 0;
            let shell_weights = SHELL_WEIGHTS;
            while( i < vec::length(&SHELL_WEIGHTS)){
                *vec::borrow_mut(&mut shell_weights, i) = *vec::borrow(&shell_weights, i) * SCALING;
                i = i + 1;
            };

            shell_weights
        }
    }

    public fun get_shell_color(rand: u32, border_color: u8): u32{
        let shell_weights = get_shell_affinity_weights(border_color);

        let tier = *vec::borrow(&shell_weights, 0);
        if(rand < tier) return 0;
        tier = tier + *vec::borrow(&shell_weights, 1);
        if(rand < tier) return 1;
        tier = tier + *vec::borrow(&shell_weights, 2);
        if(rand < tier) return 2;
        tier = tier + *vec::borrow(&shell_weights, 3);
        if(rand < tier) return 3;
        tier = tier + *vec::borrow(&shell_weights, 4);
        if(rand < tier) return 4;
        tier = tier + *vec::borrow(&shell_weights, 5);
        if(rand < tier) return 5;
        tier = tier + *vec::borrow(&shell_weights, 6);
        if(rand < tier) return 6;
        tier = tier + *vec::borrow(&shell_weights, 7);
        if(rand < tier) return 7;
        tier = tier + *vec::borrow(&shell_weights, 8);
        if(rand < tier) return 8;
        tier = tier + *vec::borrow(&shell_weights, 9);
        if(rand < tier) return 9;
        tier = tier + *vec::borrow(&shell_weights, 10);
        if(rand < tier) return 10;
        tier = tier + *vec::borrow(&shell_weights, 11);
        if(rand < tier) return 11;
        return 12
    }

    #[test]
    fun test_img(){
        let url = img_url(b"0x1234", 100, 1000, 1000);
        std::debug::print(&url);
    }

    #[test]
    fun test_egg_img(){
        let ctx = sui::tx_context::dummy();
        let id = object::new(&mut ctx);
        std::debug::print(&id);
        let bond = BondData{
            id: object::uid_to_inner(&id),
            sdb_amount: 100,
            claimed_sdb: 53,
            start_time: 1684040292000,
            end_time: 1684040292000,
            dna_1: 100,
            dna_2:312,
            status: 124
        };
        let data = get_metadata_json(&bond);
        std::debug::print(&data);
        object::delete(id);
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
     fun test_weights_card(){
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
        let (exist, idx) = vec::index_of(&CARD_COLOR, &b"rainbow");
        assert!(exist, 404);
        assert!(*vec::borrow(&CARD_WEIGHTS, idx) * 2 * SCALING == *vec::borrow(&weights, idx), 404);
     }

    #[test]
     fun test_weights_shell(){
        let weights = get_shell_affinity_weights(0);
        // no affinity bonus
        let i = 0;
        let shell_weights = SHELL_WEIGHTS;
        while( i < vec::length(&SHELL_WEIGHTS)){
            *vec::borrow_mut(&mut shell_weights, i) = *vec::borrow(&shell_weights, i) * 10000;

            i = i + 1;
        };
        assert!(weights == shell_weights, 404);

        // With Affinity Bonus
        weights = get_shell_affinity_weights(5);
        let (exist, idx) = vec::index_of(&SHELL_COLOR, &b"rainbow");
        assert!(exist, 404);
        assert!(*vec::borrow(&SHELL_WEIGHTS, idx) * 2 * SCALING == *vec::borrow(&weights, idx), 404);
     }
}