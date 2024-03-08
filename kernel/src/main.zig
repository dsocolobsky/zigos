const limine = @import("limine");
const std = @import("std");
const framebuffer = @import("framebuffer.zig");
const serial = @import("serial.zig");
const gdt = @import("gdt.zig");
const interrupts = @import("interrupts.zig");
const font = @import("font.zig");
const hlt = @import("asm.zig").hlt;
const pmm = @import("pmm.zig");

// Set the base revision to 1, this is recommended as this is the latest
// base revision described by the Limine boot protocol specification.
// See specification for further info.
pub export var base_revision: limine.BaseRevision = .{ .revision = 1 };

pub export var kernel_address_request: limine.KernelAddressRequest = .{};

inline fn halt() noreturn {
    while (true) {
        hlt();
    }
}

// The following will be our kernel's entry point.
export fn _start() callconv(.C) noreturn {
    // Ensure the bootloader actually understands our base revision (see spec).
    if (!base_revision.is_supported()) {
        halt();
    }

    _ = serial.Serial.init() catch {
        halt();
    };

    if (kernel_address_request.response) |response| {
        serial.println("kernel phy: 0x{x}", .{response.physical_base});
    } else {
        serial.puts("Could not get Kernel Address Response");
    }

    gdt.init();

    interrupts.init();

    const fnt = font.init();
    fnt.log();

    framebuffer.init(fnt);

    framebuffer.puts(
        &framebuffer.global_framebuffer,
        "Hello Framebuffer",
        3,
        3,
        framebuffer.COLOR_RED,
        framebuffer.COLOR_WHITE,
    );

    pmm.init();

    // We're done, just hang...
    halt();
}
