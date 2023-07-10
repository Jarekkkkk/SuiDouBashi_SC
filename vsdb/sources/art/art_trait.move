module suiDouBashi_vsdb::art_trait{
    use std::vector as vec;
    use std::ascii::{Self, String};
    use std::option::{Self, Option};

    use sui::object::{Self, ID};
    use sui::hex;

    use suiDouBashi_vsdb::to_string::to_string;
    use suiDouBashi_vsdb::date;
    use suiDouBashi_vsdb::encode::base64_encode as encode;

    const SVG_PREFIX: vector<u8> = b"data:image/svg+xml;base64,";
    const SCALING: u64 = 10_000;

    // ====== Error ======

    const E_NOT_INVALID_MONTH: u64 = 1;
    const E_NOT_BORDER_COLOR: u64 = 2;
    const E_NOT_CARD_COLOR: u64 = 3;
    const E_NOT_SHELL_COLOR: u64 = 4;
    const E_NOT_ATTRIBUTE: u64 = 5;

    // ====== Error ======

    /// ATTRIBUTES COLOR
    /// 6 different colors
    const BORDER_COLOR: vector<vector<u8>> = vector[
        b"white",
        b"black",
        b"bronze",
        b"silver", // idx - 3
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
        b"bronze", // idx - 9
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
        b"bronze", // idx - 8
        b"silver",
        b"gold",
        b"rainbow",
        b"luminous"
    ];

    // Weights
    const BORDER_WEIGHTS: vector<u64> = vector[
        30 * 10_000,
        30 * 10_000,
        15 * 10_000,
        12 * 10_000,
        8 * 10_000,
        5 * 10_000
    ];  //[6, 100 bps]

    /// Below weights will be re-calculated if user has affimity bonus
    const CARD_WEIGHTS: vector<u64> = vector[
        12 * 10_000,
        12 * 10_000,
        12 * 10_000,
        11 * 10_000,
        11 * 10_000,
        7 * 10_000,
        7 * 10_000,
        7 * 10_000,
        7 * 10_000,
        5 * 10_000,
        4 * 10_000,
        3 * 10_000,
        2 * 10_000
    ]; // [13, 100 bps]

    const SHELL_WEIGHTS: vector<u64> = vector[
        22 * 10_000,
        10 * 10_000,
        10 * 10_000,
        11 * 10_000,
        11 * 10_000,
        11 * 10_000,
        11 * 10_000,
        11 * 10_000,
        75 * 10_000,
        7 * 10_000,
        5 * 10_000,
        25 * 10_000,
        1 * 10_000
    ]; // [13, 200 bps]

    fun assert_border_color(idx: u64){ assert!(idx < vec::length(&BORDER_COLOR), E_NOT_BORDER_COLOR) }

    fun assert_card_color(idx: u64){ assert!(idx < vec::length(&CARD_COLOR), E_NOT_CARD_COLOR) }

    fun assert_shell_color(idx: u64){ assert!(idx < vec::length(&SHELL_COLOR), E_NOT_SHELL_COLOR) }

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
        vec::append(&mut style, format_id(&bond.id));
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

    /// Return idx of border_color
    public fun get_border_color(rand: u64):u8{
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

    /// Return updated weights by affinity bonus
    public fun get_card_affinity_weights(border_color: u8):vector<u64>{
        let border_color = (border_color as u64);
        assert_border_color(border_color);
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
                // double the weights by affinity attribution
                // scales down the other weights
                *vec::borrow_mut(&mut card_weights, i) = *vec::borrow(&card_weights, i) * (100 * SCALING - weights)/ (100 * SCALING - 2 * weights);
                i = i + 1;
            };
            *vec::borrow_mut(&mut card_weights, card_color) = weights * 2;

            card_weights
        }else{
            let i = 0;
            let card_weights = CARD_WEIGHTS;
            while( i < vec::length(&CARD_WEIGHTS)){
                *vec::borrow_mut(&mut card_weights, i) = *vec::borrow(&card_weights, i);
                i = i + 1;
            };
            card_weights
        }
    }

    /// Return idx of card_color
    public fun get_card_color(rand: u64, border_color: u8): u8{
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

    /// Return updated shell weights by border affinity
    public fun get_shell_affinity_weights(border_color: u8):vector<u64>{
        let border_color = (border_color as u64);
        assert_border_color(border_color);

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
                *vec::borrow_mut(&mut shell_weights, i) = *vec::borrow(&shell_weights, i) * (100 - weights)/ (100 - 2 * weights);
                i = i + 1;
            };
            *vec::borrow_mut(&mut shell_weights, card_color) = weights * 2;

            shell_weights
        }else{
            let i = 0;
            let shell_weights = SHELL_WEIGHTS;
            while( i < vec::length(&SHELL_WEIGHTS)){
                *vec::borrow_mut(&mut shell_weights, i) = *vec::borrow(&shell_weights, i);
                i = i + 1;
            };

            shell_weights
        }
    }

    // get shell_color idx
    public fun get_shell_color(rand: u64, border_color: u8): u8{
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

    // ====== Solid Options ======



    public fun get_solid_border_color(border_color: u8):vector<u8>{
        assert_border_color((border_color as u64));
        // white
        if(border_color == 0) return b"#fff";
        // black
        if(border_color == 1) return b"#000";
        // bronze
        if(border_color == 2) return b"#cd7f32";
        // silver
        if(border_color == 3) return b"#c0c0c0";
        // gold
        if(border_color == 4) return b"#ffd700";
        b""
    }

    public fun get_solid_card_color(card_color: u8):vector<u8>{
        assert_card_color((card_color as u64));
        // red
        if(card_color == 0) return b"#ea394e";
        // green
        if(card_color == 1) return b"#5caa4b";
        // blue
        if(card_color == 2) return b"#008bf7";
        // purple
        if(card_color == 3) return b"#9d34e8";
        // pink
        if(card_color == 4) return b"#e54cae";
        b""
    }

    public fun get_card_gradient(card_color: u8
    ):Option<vector<vector<u8>>>{
        assert_card_color((card_color as u64));
        // yellow_pink
        if(card_color == 5) return option::some(vector[b"#ffd200", b"#ff0087"]);
        // blue_green
        if(card_color == 6) return option::some(vector[b"#008bf7", b"#58b448"]);
        // pink_blue
        if(card_color == 7) return option::some(vector[b"#f900bd", b"#00a7f6"]);
        // red_purple
        if(card_color == 8) return option::some(vector[b"#ea394e", b"#9d34e8"]);
        // bronze
        if(card_color == 9) return option::some(vector[b"#804a00", b"#cd7b26"]);
        // silver
        if(card_color == 10) return option::some(vector[b"#71706e", b"#b6b6b6"]);
        // gold
        if(card_color == 11) return option::some(vector[b"#aa6c39", b"#ffae00"]);

        option::none<vector<vector<u8>>>()
    }

    public fun get_solid_shell_color(shell_color: u8, card_color: u8):vector<u8>{
        assert_card_color((card_color as u64));
        assert_shell_color((shell_color as u64));
        // off_white
        if(shell_color == 0) return b"#fff1cb";
        // light_blue
        if(shell_color == 1) return b"#e5eff9";
        // darker_blue
        if(shell_color == 2) return b"#aedfe2";
        // lighter_orange
        if(shell_color == 3) return b"#f6dac9";
        // light_orange
        if(shell_color == 4) return b"#f8d1b2";
        // darker_orange
        if(shell_color == 5) return b"#fcba92";
        // light_green
        if(shell_color == 6) return b"#c5e8d6";
        // darker_green
        if(shell_color == 7) return b"#e5daaa";
        // bronze
        if(shell_color == 8) return b"#cd7f32";
        // silver
        if(shell_color == 9) return b"#c0c0c0";
        // gold
        if(shell_color == 10) return b"#ffd700";

        // luminous
        if(card_color == 12){
            if(card_color == 9) return b"#cd7f32";
            if(card_color == 10) return b"#c0c0c0";
            if(card_color == 11) return b"#ffd700";
            return b""
        };
        b""
    }

    public fun format_id(id: &ID):vector<u8>{
        let bytes = hex::encode(object::id_to_bytes(id));
        let res = b"0x";
        let (i, j, prefix, suffix) = (0, vec::length(&bytes) - 6, vector<u8>[], vector<u8>[]);
        while(i < 6){
            vec::push_back(&mut prefix, *vec::borrow(&bytes, i));
            vec::push_back(&mut suffix, *vec::borrow(&bytes, j + i));
            i = i + 1;
        };

        vec::append(&mut res, prefix);
        vec::append(&mut res, b"...");
        vec::append(&mut res, suffix);

        res
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
            start_time: 1684040292,
            end_time: 1684040292,
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