module suiDouBashi::string{
    use std::string::{Self, String};
    use std::vector as vec;

    public fun to_string(value: u256): String {
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

            vec::push_back(&mut retval, ((value % 10+ 48) as u8));
            value = value / 10;

        };
        vec::reverse(&mut retval);
        return string::utf8(retval)
    }

        #[test] fun test_toString(){
        let str = to_string(123123124312);
        assert!(string::bytes(&str) == &b"123123124312",1);
    }
}

