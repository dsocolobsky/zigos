const limine = @import("limine");
const std = @import("std");
const framebuffer = @import("framebuffer.zig");
const serial = @import("serial.zig");
const gdt = @import("gdt.zig");
const interrupts = @import("interrupts.zig");
const hlt = @import("asm.zig").hlt;
const pmm = @import("pmm.zig");
const vmm = @import("vmm.zig");

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
    if (!base_revision.isSupported()) {
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

    framebuffer.init();

    framebuffer.global_framebuffer.println("Hello Framebuffer");
    framebuffer.global_framebuffer.set_color(framebuffer.COLOR_GREEN, framebuffer.COLOR_BLACK);
    framebuffer.global_framebuffer.println("Colored text test");

    pmm.init();

    vmm.init() catch {
        serial.print_err("Failed to initialize VMM", .{});
        halt();
    };

    // We're done, just hang...
    halt();
}
