pub const TSS = packed struct(u416) {
    reserved0: u16,
    rsp0: u32,
    rsp1: u32,
    rsp2: u32,
    reserved1: u32,
    ist1: u32,
    ist2: u32,
    ist3: u32,
    ist4: u32,
    ist5: u32,
    ist6: u32,
    ist7: u32,
    reserved2: u40,
    iomap_base: u8,
};

pub const tss = TSS{
    .reserved0 = 0,
    .rsp0 = 0,
    .rsp1 = 0,
    .rsp2 = 0,
    .reserved1 = 0,
    .ist1 = 0,
    .ist2 = 0,
    .ist3 = 0,
    .ist4 = 0,
    .ist5 = 0,
    .ist6 = 0,
    .ist7 = 0,
    .reserved2 = 0,
    .iomap_base = 0,
};
