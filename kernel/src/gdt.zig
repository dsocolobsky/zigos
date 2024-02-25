const std = @import("std");

const serial = @import("serial.zig");
const tss = @import("tss.zig");

const GDT_COUNT = 7;

const GDT_IDX_NULL_DESC = 0;
const GDT_IDX_KERN_CODE = 1;
const GDT_IDX_KERN_DATA = 2;
const GDT_IDX_USER_CODE = 3;
const GDT_IDX_USER_DATA = 4;
const GDT_IDX_TSS_LO = 5;
const GDT_IDX_TSS_HI = 6;

const Descriptor = packed struct(u80) {
    length: u16,
    address: u64,
};

// A GDT entry, 64 bits (8 bytes)
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

// This has the size of two GDT Entries: 128 bits (16 bytes)
const TSSEntry = packed struct(u128) {
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
    base_32_63: u32,
    reserved: u32,
};

// We store the GDT as an array of u64 not of structs, this is because the
// TSS segment actually occupies two entries in the GDT (128 bits), and we can't have
// arrays of different types in Zig.
// Thus we use @bitCast which gives us the u64 representation of a packed struct.
pub var gdt: [GDT_COUNT]u64 = blk: {
    var output: [GDT_COUNT]u64 = undefined;
    @memset(&output, 0x000000000000);

    // Obs we don't need to set the null descriptor, as it's already zeroed out

    output[GDT_IDX_KERN_CODE] = @bitCast(Entry{
        .base_0_15 = 0x0000,
        .base_16_23 = 0x0000,
        .base_24_31 = 0x00,
        .limit_0_15 = 0xFFFF,
        .limit_16_19 = 0xF,
        .type = 0xA,
        .s = 1,
        .dpl = 0,
        .p = 1,
        .avl = 1,
        .l = 1,
        .db = 0,
        .g = 1,
    });

    output[GDT_IDX_KERN_DATA] = @bitCast(Entry{
        .base_0_15 = 0x0000,
        .base_16_23 = 0x0000,
        .base_24_31 = 0x00,
        .limit_0_15 = 0xFFFF,
        .limit_16_19 = 0xF,
        .type = 0x2,
        .s = 1,
        .dpl = 0,
        .p = 1,
        .avl = 1,
        .l = 1,
        .db = 0,
        .g = 1,
    });

    output[GDT_IDX_USER_CODE] = @bitCast(Entry{
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
        .l = 1,
        .db = 0,
        .g = 1,
    });

    output[GDT_IDX_USER_DATA] = @bitCast(Entry{
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
        .l = 1,
        .db = 0,
        .g = 1,
    });

    // zero for now and we will load this segment in runtime
    output[GDT_IDX_TSS_LO] = 0x000000000000;
    output[GDT_IDX_TSS_HI] = 0x000000000000;

    break :blk output;
};

// Comptime test
comptime {
    if (GDT_COUNT * @sizeOf(Entry) != 7 * 8) {
        @compileError("size of GDT is wrong");
    }
}

pub fn get_gdt_value() Descriptor {
    var ret: Descriptor = undefined;
    asm volatile ("sgdt %[ret]"
        : [ret] "=m" (ret),
    );
    return ret;
}

pub fn init() void {
    const descriptor = Descriptor{
        .length = (GDT_COUNT * @sizeOf(Entry)) - 1,
        .address = @as(u64, @intFromPtr(&gdt)),
    };

    const tss_base_addr: u64 = @intFromPtr(&tss.tss);
    const tss_size = @sizeOf(tss.TSS) - 1;
    const tss_entry = TSSEntry{
        .limit_0_15 = tss_size & 0xFFFF,
        .limit_16_19 = tss_size >> 16 & 0xF,
        .base_0_15 = @as(u16, @truncate(tss_base_addr & 0xFFFF)),
        .base_16_23 = @as(u8, @truncate(tss_base_addr >> 16 & 0xFF)),
        .base_24_31 = @as(u8, @truncate(tss_base_addr >> 24 & 0xFF)),
        .base_32_63 = @as(u32, @truncate(tss_base_addr >> 32)),
        .reserved = 0x0,
        .type = 0x9,
        .s = 0,
        .dpl = 0,
        .p = 1,
        .avl = 0,
        .l = 1,
        .db = 0,
        .g = 0,
    };

    const tss_as_u128: u128 = @bitCast(tss_entry);
    gdt[GDT_IDX_TSS_LO] = @as(u64, @truncate(tss_as_u128));
    gdt[GDT_IDX_TSS_HI] = @as(u64, @truncate(tss_as_u128 >> 64));

    asm volatile (
        \\lgdt %[gdt]
        \\xor %rax, %rax
        //\\mov %[ds], %rax
        \\mov %rax, %ds
        \\movq %rax, %es
        \\movq %rax, %fs
        \\movq %rax, %gs
        \\movq %rax, %ss
        \\pushq %[cs]
        \\lea 1f(%rip), %rax
        \\pushq %rax
        \\lretq
        \\1:
        :
        : [gdt] "*p" (&descriptor),
          //[ds] "i" (GDT_IDX_USER_DATA << 3),
          [cs] "i" (GDT_IDX_KERN_CODE << 3),
        : "memory"
    );

    // Load the TSS segment
    asm volatile (
        \\mov %[tss_sel], %ax
        \\ltr %ax
        :
        : [tss_sel] "i" (GDT_IDX_TSS_LO << 3),
        : "memory"
    );
}
