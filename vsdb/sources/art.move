module suiDouBashi_vsdb::art{
    use std::vector as vec;
    use std::ascii::{Self, String};

    use suiDouBashi_vsdb::to_string::to_string;
    use suiDouBashi_vsdb::encode::base64_encode as encode;

    const SVG_PREFIX: vector<u8> = b"data:image/svg+xml;base64,";

    fun img_url(id: vector<u8>, voting_weight: u256, locked_end: u256, locked_amount: u256): String {
        let vesdb = SVG_PREFIX;
        let encoded_b = vec::empty<u8>();

        vec::append(&mut encoded_b, b"<svg xmlns='http://www.w3.org/2000/svg' preserveAspectRatio='xMinYMin meet' viewBox='0 0 350 350'><style>.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width='100%' height='100%' fill='#93c5fd' /><text x='10' y='20' class='base'>Token ");
        vec::append(&mut encoded_b,id);
        vec::append(&mut encoded_b,b"</text><text x='10' y='40' class='base'>Voting Weight: ");
        vec::append(&mut encoded_b,ascii::into_bytes(to_string(voting_weight)));
        vec::append(&mut encoded_b,b"</text><text x='10' y='60' class='base'>Locked end: ");
        vec::append(&mut encoded_b,ascii::into_bytes(to_string(locked_end)));
        vec::append(&mut encoded_b,b"</text><text x='10' y='80' class='base'>Locked_amount: ");
        vec::append(&mut encoded_b,ascii::into_bytes(to_string(locked_amount)));
        vec::append(&mut encoded_b,b"</text></svg>");

        vec::append(&mut vesdb,encode(encoded_b));
        ascii::string(vesdb)
    }

    public fun get_svg(){
        let svg = b"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 750 1050'>";

        vec::append(&mut svg, b"</svg>");
    }

    public fun get_svg_style(){
        let style = b"<style>";
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
        abort 0
    }

    #[test]
    fun test_img(){
        let url = img_url(b"0x1234", 100, 1000, 1000);
        std::debug::print(&url);
    }

}