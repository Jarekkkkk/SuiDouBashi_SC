module suiDouBashi_vsdb::art{
    use std::option;

    use sui::object::ID;

    use suiDouBashi_vsdb::sdb;
    use suiDouBashi_vsdb::art_trait;

    const SCALING: u64 = 10_000;

    const EGG_SIZE: vector<vector<u8>> = vector[
        b"tiny",
        b"small",
        b"normal",
        b"big"
    ];

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

    fun get_egg_size(sdb_amount: u64):u8{
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

    /// DNA can be splited into 3
    fun cut_dna(dna: u128, start_bit: u8, num_bites: u8):u64{
        let max = 1 << num_bites;
        let value = ( dna >> start_bit) & ( max - 1);
        (value as u64) * SCALING / (max as u64)
    }

    fun calc_attributes(bond: &mut BondData){
        let dna = bond.dna_1;

        bond.border_color = art_trait::get_border_color(cut_dna(dna, 0, 26));
        bond.card_color = art_trait::get_card_color(cut_dna(dna, 26, 27), bond.border_color);
        bond.shell_color = art_trait::get_shell_color(cut_dna(dna, 53, 27), bond.border_color);
        bond.egg_size = get_egg_size(bond.sdb_amount);
    }

    public fun calc_derived_data(bond: &mut BondData){
        bond.solid_border_color = art_trait::get_solid_border_color(bond.border_color);
        bond.solid_card_color = art_trait::get_solid_card_color(bond.border_color);
        bond.solid_shell_color = art_trait::get_solid_shell_color(bond.shell_color, bond.border_color);

        // shell == luminous && card_color doesn't have affinity
        bond.is_blended_shell = bond.shell_color == 12 && !(
            bond.card_color == 9
            || bond.card_color == 10
            || bond.card_color == 11
            || bond.card_color == 12
        );

        let card_gradient = art_trait::get_card_gradient(bond.card_color);
        if(option::is_some(&card_gradient)){
            bond.card_gradient = option::extract(&mut card_gradient);
            bond.has_card_gradient = true;
        }else{
            bond.card_gradient = vector[b"", b""];
            bond.has_card_gradient = false;
        };

        option::destroy_none(card_gradient);
    }
}