#[allow(unused_function)]
module suiDouBashi_vsdb::art_trait{
    use std::vector as vec;
    use std::ascii::{Self, String};
    use std::option::{Self, Option};

    use sui::object::{Self, ID};
    use sui::hex;

    use suiDouBashi_vsdb::to_string::to_string;
    use suiDouBashi_vsdb::date;
    use suiDouBashi_vsdb::sdb;
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

    /// 4 different egg size
    const EGG_SIZE: vector<vector<u8>> = vector[
        b"tiny",
        b"small",
        b"normal",
        b"big"
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
        dna_1: u128, // u80
        dna_2: u128, // u80
        status: u8,

        // Attributes derived from the DNA
        border_color: u8,
        card_color: u8,
        shell_color: u8,
        egg_size: u8,

        // Further data derived from the attributes
        solid_border_color: vector<u8>,
        solid_card_color: vector<u8>,
        solid_shell_color: vector<u8>,
        is_blended_shell: bool,
        has_card_gradient: bool,
        card_gradient: vector<vector<u8>> // 2 string
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

    // ====== dynamic attributes ======
    fun calc_attributes(bond: &mut BondData){
        let dna = bond.dna_1;
        bond.border_color = get_border_color(cut_dna(dna, 0, 32));
        bond.card_color = get_card_color(cut_dna(dna, 32, 32), bond.border_color);
        bond.shell_color = get_shell_color(cut_dna(dna, 64, 32), bond.border_color);
        bond.egg_size = get_egg_size(bond.sdb_amount);
    }

    public fun calc_derived_data(bond: &mut BondData){
        bond.solid_border_color = get_solid_border_color(bond.border_color);
        bond.solid_card_color = get_solid_card_color(bond.border_color);
        bond.solid_shell_color = get_solid_shell_color(bond.shell_color, bond.border_color);

        // shell == luminous && card_color doesn't have affinity
        bond.is_blended_shell = bond.shell_color == 12 && !(
            bond.card_color == 9
            || bond.card_color == 10
            || bond.card_color == 11
            || bond.card_color == 12
        );

        let card_gradient = get_card_gradient(bond.card_color);
        if(option::is_some(&card_gradient)){
            bond.card_gradient = option::extract(&mut card_gradient);
            bond.has_card_gradient = true;
        }else{
            bond.card_gradient = vector[b"", b""];
            bond.has_card_gradient = false;
        };

        option::destroy_none(card_gradient);
    }

    public fun get_metadata_json(bond_data: &BondData): String{
        let url = SVG_PREFIX;
        vec::append(&mut url, encode(get_svg(bond_data)));

        ascii::string(url)
    }

    public fun get_svg(bond: &BondData):vector<u8>{
        let svg = b"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 750 1050'>";
        vec::append(&mut svg, get_svg_style(bond));
        vec::append(&mut svg, get_svg_defs(bond));
        vec::append(&mut svg, get_svg_main(bond));
        vec::append(&mut svg, b"</svg>");

        svg
    }

    // ====== SVG <style> ======
    public fun get_svg_style(bond: &BondData):vector<u8>{
        let style = b"<style> #cb-egg-";
        vec::append(&mut style, hex::encode(object::id_to_bytes(&bond.id)));
        vec::append(&mut style, b" .cb-egg path { animation: shake 3s infinite ease-out; transform-origin: 50%; }@keyframes shake { 0% {transform: rotate(0deg);} 65% { transform: rotate(0deg);} 70% { transform: rotate(3deg);} 75% { transform: rotate(0deg); } 80% { transform: rotate(-3deg); } 85% { transform: rotate(0deg); } 90% { transform: rotate(3deg);} 100% { transform: rotate(0deg); }} </style>");

        style
    }

    // ====== SVG <style> ======

    // ====== SVG <Defs> ======
    public fun get_svg_defs(bond: &BondData):vector<u8>{
        let defs = b"<defs>";
        vec::append(&mut defs, get_svg_def_card_diagonal_gradient_(bond));
        vec::append(&mut defs, get_svg_def_card_radial_gradient_(bond));
        vec::append(&mut defs, get_svg_def_card_rainbow_gradient_(bond));
        vec::append(&mut defs, get_svg_def_shell_rainbow_gradient_(bond));
        vec::append(&mut defs, b"</defs>");
        defs
    }

    fun get_svg_def_card_diagonal_gradient_(bond: &BondData):vector<u8>{
        if(!bond.has_card_gradient) return b"";

        let def = b"<linearGradient id='cb-egg-";
        vec::append(&mut def, hex::encode(object::id_to_bytes(&bond.id)));
        vec::append(&mut def, b"-card-diagonal-gradient' y1='100%' gradientUnits='userSpaceOnUse'>");
        vec::append(&mut def, b"<stop offset='0' stop-color='");
        vec::append(&mut def, *vec::borrow(&bond.card_gradient, 0));
        vec::append(&mut def, b"'/>");

        vec::append(&mut def, b"<stop offset='1' stop-color='");
        vec::append(&mut def, *vec::borrow(&bond.card_gradient, 1));
        vec::append(&mut def, b"'/>");
        vec::append(&mut def, b"</linearGradient>");

        def
    }

    fun get_svg_def_card_radial_gradient_(bond: &BondData):vector<u8>{
        // shell_color == luminous
        if(bond.shell_color != 12 ) return b"";

        let def = b"<radialGradient id='cb-egg-";
        vec::append(&mut def, hex::encode(object::id_to_bytes(&bond.id)));
        vec::append(&mut def, b"-card-radial-gradient' cx='50%' cy='45%' r='38%' gradientUnits='userSpaceOnUse'>");
        vec::append(&mut def, b"<stop offset='0' stop-opacity='0'/><stop offset='0.25' stop-opacity='0'/><stop offset='1' stop-color='#000' stop-opacity='1'/></radialGradient>");

        def
    }

    fun get_svg_def_card_rainbow_gradient_(bond: &BondData):vector<u8>{
        // card_color != rainbow && border_color != rainbow
        if(bond.card_color != 12 && bond.border_color != 5 ) return b"";

        let def = b"<linearGradient id='cb-egg-";
        vec::append(&mut def, hex::encode(object::id_to_bytes(&bond.id)));
        vec::append(&mut def, b"-card-rainbow-gradient' y1='100%' gradientUnits='userSpaceOnUse'>");
        vec::append(&mut def, b"<stop offset='0' stop-color='#93278f'/><stop offset='0.2' stop-color='#662d91'/><stop offset='0.4' stop-color='#3395d4'/><stop offset='0.5' stop-color='#39b54a'/><stop offset='0.6' stop-color='#fcee21'/><stop offset='0.8' stop-color='#fbb03b'/><stop offset='1' stop-color='#ed1c24'/></linearGradient>");

        def
    }

    fun get_svg_def_shell_rainbow_gradient_(bond: &BondData):vector<u8>{
        // shell_color != rainbow && !(shell == luminous || card == rainbow)
        if(bond.shell_color != 11 && !(bond.shell_color == 12 && bond.card_color == 12)) return b"";

        let def = b"<linearGradient id='cb-egg-";
        vec::append(&mut def, hex::encode(object::id_to_bytes(&bond.id)));
        vec::append(&mut def, b"-shell-rainbow-gradient' x1='39%' y1='59%' x2='62%' y2='35%' gradientUnits='userSpaceOnUse'>");
        vec::append(&mut def, b"<stop offset='0' stop-color='#3fa9f5'/><stop offset='0.38' stop-color='#39b54a'/><stop offset='0.82' stop-color='#fcee21'/><stop offset='1' stop-color='#fbb03b'/></linearGradient>");

        def
    }

    // ====== SVG <Defs> ======

    // ====== SVG <Main> ======
    public fun get_svg_main(bond: &BondData):vector<u8>{
        let svg_main = b"<g id='cb-egg-";
        vec::append(&mut svg_main, hex::encode(object::id_to_bytes(&bond.id)));
        vec::append(&mut svg_main, b"'>");

        vec::append(&mut svg_main, get_svg_border(bond));
        vec::append(&mut svg_main, get_svg_card(bond));
        vec::append(&mut svg_main, get_svg_card_radial_gradient(bond));
        vec::append(&mut svg_main, get_svg_shadow_below_egg(bond));
        //vec::append(&mut svg_main, get_svg_egg(bond));
        //vec::append(&mut svg_main, get_svg_text(bond));
        vec::append(&mut svg_main, b"</g>");

        svg_main
    }

    public fun get_svg_border(bond: &BondData):vector<u8>{
        // shell == luminous && border == black
        if(bond.shell_color == 12 && bond.border_color == 1 ) return b"";

        let def = b"<rect ";
        if(bond.border_color == 5){
            // border_color == rainbow
            vec::append(&mut def, b"style='fill: url(#cb-egg-");
            vec::append(&mut def, hex::encode(object::id_to_bytes(&bond.id)));
            vec::append(&mut def, b"-card-rainbow-gradient)' ");
        }else{
            vec::append(&mut def, b"fill='");
            vec::append(&mut def, bond.solid_border_color);
            vec::append(&mut def, b"' ");
        };
        vec::append(&mut def, b"width='100%' height='100%' rx='37.5'/>");

        def
    }

    public fun get_svg_card(bond: &BondData):vector<u8>{
        let style = vector[];
        if(bond.card_color != 12 || bond.border_color != 5){
            vec::append(&mut style, b"<rect ");
            if(bond.card_color == 12){
                vec::append(&mut style, b"style='fill: url(#cb-egg-");
                vec::append(&mut style, hex::encode(object::id_to_bytes(&bond.id)));
                vec::append(&mut style, b"-card-rainbow-gradient)'");
            }else if(bond.has_card_gradient){
                vec::append(&mut style, b"style='fill: url(#cb-egg-");
                vec::append(&mut style, hex::encode(object::id_to_bytes(&bond.id)));
                vec::append(&mut style, b"-card-rainbow-gradient)'");
            }else{
                vec::append(&mut style, b"fill='");
                vec::append(&mut style, bond.solid_card_color);
                vec::append(&mut style, b"' ");
            };
            vec::append(&mut style, b"x='30' y='30' width='690' height='990' rx='37.5'/>");
        };
        if(bond.card_color == 12){
            vec::append(&mut style, b"<rect fill='#000' opacity='0.05' x='30' y='30' width='690' height='990' rx='37.5'/>");
        };

        style
    }

    public fun get_svg_card_radial_gradient(bond: &BondData):vector<u8>{
        if(bond.shell_color != 12) return b"";

        let gradient = b"<rect style='fill: url(#cb-egg-";
        vec::append(&mut gradient, hex::encode(object::id_to_bytes(&bond.id)));
        vec::append(&mut gradient, b"-card-radial-gradient); mix-blend-mode: hard-light' ");

        if(bond.border_color == 1){
            vec::append(&mut gradient, b"width='100%' height='100%' ");
        }else{
            vec::append(&mut gradient, b"x='30' y='30' width='690' height='990' ");
        };

        vec::append(&mut gradient, b"rx='37.5'/>");

        gradient
    }

    public fun get_shadow_below_egg(bond: &BondData):vector<u8>{
        let shadow = b"<ellipse ";

        if(bond.shell_color == 12) vec::append(&mut shadow, b"style='mix-blend-mode: luminosity' ");
        vec::append(&mut shadow, b"fill='#0a102e' ");
        if(bond.egg_size == 0){
            vec::append(&mut shadow, b"cx='375' cy='560.25' rx='60' ry='11.4' ");
        }else if(bond.egg_size == 1){
            vec::append(&mut shadow, b"cx='375' cy='589.5' rx='80' ry='15.2' ");
        }else if(bond.egg_size == 2){
            vec::append(&mut shadow, b"cx='375' cy='648' rx='120' ry='22.8' ");
        }else{
            vec::append(&mut shadow, b"cx='375' cy='618.75' rx='100' ry='19' ");
        };
        vec::append(&mut shadow, b"/>");

        shadow
    }

    public fun get_svg_shell_path_data(bond: &BondData):vector<u8>{
        let shell_path = b"";
        if(bond.egg_size == 0){
            vec::append(&mut shell_path, b"M293.86 478.12c0 45.36 36.4 82.13 81.29 82.13s81.29-36.77 81.29-82.13S420.05 365.85 375.15 365.85C332.74 365.85 293.86 432.76 293.86 478.12Z");
        }else if(bond.egg_size == 1){
            vec::append(&mut shell_path, b"M266.81 480c0 60.48 48.53 109.5 108.39 109.5s108.39-49.02 108.39-109.5S435.06 330.3 375.2 330.3C318.65 330.3 266.81 419.52 266.81 480Z");
        }else if(bond.egg_size == 2){
            vec::append(&mut shell_path, b"M212.71 483.74c0 90.72 72.79 164.26 162.59 164.26s162.59-73.54 162.59-164.26S465.1 259.2 375.3 259.2C290.47 259.2 212.71 393.02 212.71 483.74Z");
        }else{
            vec::append(&mut shell_path, b"M239.76 481.87c0 75.6 60.66 136.88 135.49 136.88s135.49-61.28 135.49-136.88S450.08 294.75 375.25 294.75C304.56 294.75 239.76 406.27 239.76 481.87Z");
        };
        shell_path
    }

    public fun get_svg_highlight_path_data(bond: &BondData):vector<u8>{
        let highlight_path = b"";
        if(bond.egg_size == 0){
            vec::append(&mut highlight_path, b"M328.96 409.4c-6 13.59-5.48 29.53 3.25 36.11 9.76 7.35 23.89 9 36.98-3.13 12.57-11.66 23.48-43.94 1.24-55.5C358.25 380.55 335.59 394.35 328.96 409.4Z");
        }else if(bond.egg_size == 1){
            vec::append(&mut highlight_path, b"M313.61 388.36c-8 18.12-7.3 39.38 4.33 48.16 13.01 9.8 31.85 12 49.31-4.18 16.76-15.54 31.3-58.59 1.65-74C352.66 349.9 322.45 368.3 313.61 388.36Z");
        }else if(bond.egg_size == 2){
            vec::append(&mut highlight_path, b"M282.91 346.3c-12 27.18-10.96 59.06 6.51 72.22 19.51 14.7 47.77 18 73.95-6.26 25.14-23.32 46.96-87.89 2.49-111C341.5 288.6 296.17 316.2 282.91 346.3Z");
        }else{
            vec::append(&mut highlight_path, b"M298.26 367.33c-10 22.65-9.13 49.22 5.42 60.19 16.26 12.25 39.81 15 61.63-5.22 20.95-19.43 39.13-73.24 2.07-92.5C347.08 319.25 309.31 342.25 298.26 367.33Z");
        };
        highlight_path
    }

    // shadow
    public fun get_svg_shadow_below_egg(bond: &BondData):vector<u8>{
        let shadow = b"<ellipse ";
        if(bond.shell_color == 12) vec::append(&mut shadow, b"style='mix-blend-mode: luminosity' ");
        vec::append(&mut shadow, b"fill='#0a102e' ");

        if(bond.egg_size == 0){
            vec::append(&mut shadow, b"cx='375' cy='560.25' rx='60' ry='11.4' ");
        }else if(bond.egg_size == 1){
            vec::append(&mut shadow, b"cx=;375; cy=;589.5; rx=;80; ry=;15.2; ");
        }else if(bond.egg_size == 2){
            vec::append(&mut shadow, b"cx='375' cy='648' rx='120' ry='22.8' ");
        }else{
            vec::append(&mut shadow, b"cx='375' cy='618.75' rx='100' ry='19' ");
        };
        vec::append(&mut shadow, b"/>");

        shadow
    }

    public fun get_svg_self_shadow_path_data(bond: &BondData):vector<u8>{
        let highlight_path = b"";
        if(bond.egg_size == 0){
            vec::append(&mut highlight_path, b"M416.17 385.02c11.94 20.92 19.15 45.35 19.14 65.52 0 45.36-36.4 82.13-81.3 82.13a80.45 80.45 0 0 1-52.52-19.45C314.52 541.03 342.54 560.27 375 560.27c44.9 0 81.3-36.77 81.3-82.13C456.31 447.95 440.18 408.22 416.17 385.02Z");
        }else if(bond.egg_size == 1){
            vec::append(&mut highlight_path, b"M429.89 355.86c15.92 27.89 25.53 60.46 25.53 87.36 0 60.48-48.54 109.5-108.4 109.5a107.26 107.26 0 0 1-70.03-25.92C294.36 563.88 331.72 589.52 375 589.52c59.86 0 108.4-49.02 108.4-109.5C483.42 439.76 461.91 386.8 429.89 355.86Z");
        }else if(bond.egg_size == 2){
            vec::append(&mut highlight_path, b"M457.33 297.54c23.88 41.83 38.29 90.7 38.29 131.04 0 90.72-72.8 164.26-162.6 164.26a160.9 160.9 0 0 1-105.03-38.9C254.04 609.56 310.08 648.04 375 648.04c89.8 0 162.6-73.54 162.6-164.26C537.62 423.4 505.37 343.94 457.33 297.54Z");
        }else{
            vec::append(&mut highlight_path, b"M443.61 326.7c19.9 34.86 31.91 75.58 31.91 109.2 0 75.6-60.67 136.88-135.5 136.88a134.08 134.08 0 0 1-87.53-32.41C274.2 586.72 320.9 618.78 375 618.78c74.83 0 135.5-61.28 135.5-136.88C510.52 431.58 483.64 365.37 443.61 326.7Z");
        };
        highlight_path
    }

    public fun get_svg_egg(bond: &BondData):vector<u8>{
        let egg = b"<g class='cb-egg'><path ";
        if(bond.shell_color == 11 || bond.shell_color == 12 && bond.card_color == 12 ){
            vec::append(&mut egg, b"style='fill: url(#cb-egg-");
            vec::append(&mut egg, hex::encode(object::id_to_bytes(&bond.id)));
            vec::append(&mut egg, b"-shell-rainbow-gradient)' ");
        }else if(bond.is_blended_shell){
            vec::append(&mut egg, b"style='mix-blend-mode: luminosity' fill='#e5eff9' ");
        }else{
            vec::append(&mut egg, b"fill='");
            vec::append(&mut egg, bond.solid_shell_color);
            vec::append(&mut egg, b"' ");
        };
        vec::append(&mut egg, b"d='");
        vec::append(&mut egg, get_svg_shell_path_data(bond));
        vec::append(&mut egg, b"' />");

        vec::append(&mut egg, b"<path style='mix-blend-mode: soft-light' fill='#fff' d='");
        vec::append(&mut egg, get_svg_highlight_path_data(bond));
        vec::append(&mut egg, b"'/>");

        vec::append(&mut egg, b"<path style='mix-blend-mode: soft-light' fill='#fff' d='");
        vec::append(&mut egg, get_svg_self_shadow_path_data(bond));
        vec::append(&mut egg, b"'/>");
        vec::append(&mut egg, b"</g>");
        egg
    }

    fun get_svg_text(bond: &BondData):vector<u8>{
        let text = b"<text fill='#fff' font-family='Arial Black, Arial' font-size='72px' font-weight='800' text-anchor='middle' x='50%' y='14%'>VSDB</text>";
        vec::append(&mut text, b"<text fill='#fff' font-family='Arial Black, Arial' font-size='30px' font-weight='800' text-anchor='middle' x='50%' y='19%'>");
        vec::append(&mut text, b"ID: ");
        vec::append(&mut text, format_id(&bond.id));
        vec::append(&mut text, b"</text> <text fill='#fff' font-family='Arial Black, Arial' font-size='40px' font-weight='800' text-anchor='middle' x='50%' y='72%'>LEVEL</text>");
        vec::append(&mut text, b"<text fill='#fff' font-family='Arial Black, Arial' font-size='64px' font-weight='800' text-anchor='middle' x='50%' y='81%'>");
        vec::append(&mut text, ascii::into_bytes(format_value(bond.sdb_amount)));
        vec::append(&mut text, b"</text> <text fill='#fff' font-family='Arial Black, Arial' font-size='30px' font-weight='800' text-anchor='middle' x='50%' y='91%' opacity='0.6'>");
        vec::append(&mut text, format_date(bond.start_time));
        vec::append(&mut text, b"</text>");
        text
    }

    public fun get_svg_bond_data(bond: &BondData):vector<u8>{
        let style = b"<text fill='#fff' font-family='Arial Black, Arial' font-size='40px' font-weight='800' text-anchor='middle' x='50%' y='755'>Level</text> <text fill='#fff' font-family='Arial Black, Arial' font-size='64px' font-weight='800' text-anchor='middle' x='50%' y='848'>";
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
                *vec::borrow_mut(&mut shell_weights, i) = *vec::borrow(&shell_weights, i) * (100 * SCALING - weights)/ (100 * SCALING - 2 * weights);
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

    public fun get_egg_size(sdb_amount: u64):u8{
        let decimals = (sdb::decimals() as u64);
        if(sdb_amount < 1_000 * decimals){
            0
        }else if(sdb_amount < 10_000 * decimals){
            1
        }else if(sdb_amount < 100_000 * decimals){
            2
        }else{
            3
        }
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

    public fun format_value(value: u64):String{
        let decimals = (sdb::decimals() as u256);
        to_string((((value as u256) + 5 * decimals / 10)/ decimals))
    }

    public fun format_date(timestamp: u64):vector<u8>{
        let date = b"";
        vec::append(&mut date, get_month_string(date::get_month(timestamp)));
        vec::append(&mut date, b" ");
        vec::append(&mut date, ascii::into_bytes(to_string((date::get_day(timestamp)as u256))));
        vec::append(&mut date, b" ");
        vec::append(&mut date, ascii::into_bytes(to_string((date::get_year(timestamp) as u256))));
        date
    }

    /// DNA determine weghts of `[BORDER, CARD, SHELL]`
    fun cut_dna(dna: u128, start_bit: u8, num_bites: u8):u64{
        let max = 1 << num_bites;
        let value = (dna >> start_bit) & (max - 1);
        (value as u64) * 100 * SCALING / (max as u64)
    }


    #[test]
    fun test_img(){
        let _url = img_url(b"0x1234", 100, 1000, 1000);
        //std::debug::print(&url);
    }

    #[test]
    fun test_egg_img(){
        let ctx = sui::tx_context::dummy();
        let id = object::new(&mut ctx);
        let bond = BondData{
            id: object::uid_to_inner(&id),
            sdb_amount: 100,
            claimed_sdb: 53,
            start_time: 1684040292,
            end_time: 1684040292,
            dna_1: 103123123123,
            dna_2: 1235453543123,
            status: 124,

            border_color: 1,
            card_color: 1,
            shell_color: 1,
            egg_size: 1,

            solid_border_color: b"",
            solid_card_color: b"",
            solid_shell_color: b"",
            is_blended_shell: true,
            has_card_gradient: true,
            card_gradient: vector[b"", b""]
        };
        let border_dna = ( 100 * ((1 << 32) - 1) / 100);
        let card_dna = ( 100 * ((1 << 32) - 1) / 100) << 32;
        let shell_dna = ( 100 * ((1 << 32) - 1) / 100) << 64;
        let dna = border_dna | card_dna | shell_dna;

        bond.dna_1 = dna;
        calc_attributes(&mut bond);
        calc_derived_data(&mut bond);
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
            *vec::borrow_mut(&mut card_weights, i) = *vec::borrow(&card_weights, i);

            i = i + 1;
        };
        assert!(weights == card_weights, 404);

        // With Affinity Bonus
        weights = get_card_affinity_weights(5);
        let (exist, idx) = vec::index_of(&CARD_COLOR, &b"rainbow");
        assert!(exist, 404);
        assert!(*vec::borrow(&CARD_WEIGHTS, idx) * 2 == *vec::borrow(&weights, idx), 404);
     }

    #[test]
     fun test_weights_shell(){
        let weights = get_shell_affinity_weights(0);
        // no affinity bonus
        let i = 0;
        let shell_weights = SHELL_WEIGHTS;
        while( i < vec::length(&SHELL_WEIGHTS)){
            *vec::borrow_mut(&mut shell_weights, i) = *vec::borrow(&shell_weights, i);

            i = i + 1;
        };
        assert!(weights == shell_weights, 404);

        // With Affinity Bonus
        weights = get_shell_affinity_weights(5);
        let (exist, idx) = vec::index_of(&SHELL_COLOR, &b"rainbow");
        assert!(exist, 404);
        assert!(*vec::borrow(&SHELL_WEIGHTS, idx) * 2 == *vec::borrow(&weights, idx), 404);
     }
}