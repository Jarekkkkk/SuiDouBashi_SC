module suiDouBashi::string{
    use std::string::{Self, String};
    use std::vector as vec;
    use std::bcs;

    public fun to_string(value: u64): String {
        if(value == 0) {
            return string::utf8(b"0")
         };
        let temp = value;
        let digits = 0;
        while (temp != 0) {
            digits = digits + 1;
            temp = temp / 10;
        };
        let retval = vec::empty<u8>();
        while (value != 0) {
            digits = digits - 1;

            let c = vec::borrow(&bcs::to_bytes(&(value % 10+ 48)), 0);
            vec::push_back(&mut retval, *c);
            value = value / 10;
        };
        vec::reverse(&mut retval);
        return string::utf8(retval)
    }
}