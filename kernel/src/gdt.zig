const serial = @import("serial.zig");

const GDT_COUNT = 30;

const GDT_IDX_NULL_DESC = 0x0000;
const GDT_IDX_KERN_CODE = 0x0001;
const GDT_IDX_KERN_DATA = 0x0001;
const GDT_IDX_USER_CODE = 0x0003;
const GDT_IDX_USER_DATA = 0x0004;
const GDT_IDX_TSS = 0x0005;

const Descriptor = packed struct {
    length: u16,
    address: u64,
};

const Entry = packed struct(u64) {
    limit_0_15: u16,
    base_0_15: u16,
    base_16_23: u8,
    type: u4,
    s: u1,
    dpl: u2,
    p: u1,
    limit_16_19: u4,
    avl: u1,
    l: u1,
    db: u1,
    g: u1,
    base_24_31: u8,
};

pub const gdt: [GDT_COUNT]Entry = blk: {
    var output: [GDT_COUNT]Entry = undefined;
    @memset(&output, Entry{
        .limit_0_15 = 0x0000,
        .base_0_15 = 0x0000,
        .base_16_23 = 0x0000,
        .type = 0x0,
        .s = 0x0,
        .dpl = 0x0,
        .p = 0x0,
        .limit_16_19 = 0x0,
        .avl = 0x0,
        .l = 0x0,
        .db = 0x0,
        .g = 0x0,
        .base_24_31 = 0x00,
    });

    // Obs we don't need to set the null descriptor, as it's already zeroed out

    output[GDT_IDX_KERN_CODE] = Entry{
        .limit_0_15 = 0xFFFF,
        .limit_16_19 = 0xF,
        .base_0_15 = 0x0000,
        .base_16_23 = 0x0000,
        .base_24_31 = 0x00,
        .type = 0xA,
        .s = 1,
        .dpl = 0,
        .p = 1,
        .avl = 1,
        .l = 0,
        .db = 1,
        .g = 1,
    };

    output[GDT_IDX_KERN_DATA] = Entry{
        .limit_0_15 = 0xFFFF,
        .limit_16_19 = 0xF,
        .base_0_15 = 0x0000,
        .base_16_23 = 0x0000,
        .base_24_31 = 0x00,
        .type = 0x2,
        .s = 1,
        .dpl = 0,
        .p = 1,
        .avl = 1,
        .l = 0,
        .db = 1,
        .g = 1,
    };

    output[GDT_IDX_USER_CODE] = Entry{
        .limit_0_15 = 0xFFFF,
        .limit_16_19 = 0xF,
        .base_0_15 = 0x0000,
        .base_16_23 = 0x0000,
        .base_24_31 = 0x00,
        .type = 0xA,
        .s = 1,
        .dpl = 3,
        .p = 1,
        .avl = 1,
        .l = 0,
        .db = 1,
        .g = 1,
    };

    output[GDT_IDX_USER_DATA] = Entry{
        .limit_0_15 = 0xFFFF,
        .limit_16_19 = 0xF,
        .base_0_15 = 0x0000,
        .base_16_23 = 0x0000,
        .base_24_31 = 0x00,
        .type = 0x2,
        .s = 1,
        .dpl = 3,
        .p = 1,
        .avl = 1,
        .l = 0,
        .db = 1,
        .g = 1,
    };

    // output[GDT_IDX_TSS] = Entry{
    //     .limit_0_15 = 0x0067, // Should be sizeof(TSS)
    //     .limit_16_19 = 0x0,
    //     .base_0_15 = 0x0000, // Should be &TSS
    //     .base_16_23 = 0x0000,
    //     .base_24_31 = 0x00,
    //     .type = 0x9,
    //     .s = 0,
    //     .dpl = 0,
    //     .p = 1,
    //     .avl = 0,
    //     .l = 0,
    //     .db = 0,
    //     .g = 0,
    // };

    break :blk output;
};

pub fn load_gdt(gdtr: Descriptor) void {
    const gdt_addr = @as(u64, @intFromPtr(&gdt));
    serial.println("GDT address:");
    serial.print_hex(gdt_addr);
    asm volatile (
        \\lgdt %[gdtr]
        :
        : [gdtr] "*p" (&gdtr),
        : "rax", "rcx", "memory"
    );
}

pub fn init() void {
    const descriptor = Descriptor{
        .length = (GDT_COUNT * @sizeOf(Entry)) - 1,
        .address = @as(u32, @truncate(@intFromPtr(&gdt))),
    };

    load_gdt(descriptor);
}
