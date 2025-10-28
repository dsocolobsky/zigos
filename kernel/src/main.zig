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

    framebuffer.init();

    framebuffer.global_framebuffer.print("Initializing GDT...");
    gdt.init();
    framebuffer.global_framebuffer.println_color(" OK", framebuffer.COLOR_GREEN);

    framebuffer.global_framebuffer.print("Initializing Interrupts...");
    interrupts.init();
    framebuffer.global_framebuffer.println_color(" OK", framebuffer.COLOR_GREEN);

    framebuffer.global_framebuffer.print("Initializing PMM...");
    pmm.init();
    framebuffer.global_framebuffer.println_color(" OK", framebuffer.COLOR_GREEN);

    framebuffer.global_framebuffer.print("Initializing VMM...");
    if (vmm.init()) |_| {
        framebuffer.global_framebuffer.println_color(" OK", framebuffer.COLOR_GREEN);
    } else |_| {
        framebuffer.global_framebuffer.println_color(" ERROR", framebuffer.COLOR_RED);
        serial.print_err("Failed to initialize VMM", .{});
        halt();
    }

    framebuffer.global_framebuffer.println_color("\nInitialization OK", framebuffer.COLOR_GREEN);
    framebuffer.global_framebuffer.print("> ");
    framebuffer.global_framebuffer.draw_cursor();

    // Enable interrupts and loop
    asm volatile ("sti");
    halt();
}
