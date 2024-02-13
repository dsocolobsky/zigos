const std = @import("std");

const serial = @import("serial.zig");

const GDT_COUNT = 5;

const GDT_IDX_NULL_DESC = 0;
const GDT_IDX_KERN_CODE = 1;
const GDT_IDX_KERN_DATA = 2;
const GDT_IDX_USER_CODE = 3;
const GDT_IDX_USER_DATA = 4;
const GDT_IDX_TSS = 5;

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
        .base_0_15 = 0x0000,
        .base_16_23 = 0x0000,
        .base_24_31 = 0x00,
        .limit_0_15 = 0x0000,
        .limit_16_19 = 0x0,
        .type = 0x0,
        .s = 0x0,
        .dpl = 0x0,
        .p = 0x0,
        .avl = 0x0,
        .l = 0x0,
        .db = 0x0,
        .g = 0x0,
    });

    // Obs we don't need to set the null descriptor, as it's already zeroed out

    output[GDT_IDX_KERN_CODE] = Entry{
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
    };

    output[GDT_IDX_KERN_DATA] = Entry{
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
        .l = 1,
        .db = 0,
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
        .l = 1,
        .db = 0,
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
    //     .l = 1,
    //     .db = 0,
    //     .g = 0,
    // };

    break :blk output;
};

// Comptime test
comptime {
    if (GDT_COUNT * @sizeOf(Entry) != 5 * 8) {
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

    asm volatile (
        \\lgdt %[gdt]
        // \\mov %[ds], %rax
        // \\movq %rax, %ds
        // \\movq %rax, %es
        // \\movq %rax, %fs
        // \\movq %rax, %gs
        // \\movq %rax, %ss
        // \\pushq %[cs]
        // \\lea 1f(%rip), %rax
        // \\pushq %rax
        // \\lretq
        // \\1:
        :
        : [gdt] "*p" (&descriptor),
          [ds] "i" (GDT_IDX_KERN_DATA << 3),
          [cs] "i" (GDT_IDX_KERN_CODE << 3),
        : "memory"
    );
}
