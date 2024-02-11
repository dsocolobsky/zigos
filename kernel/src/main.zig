const limine = @import("limine");
const std = @import("std");
const framebuffer = @import("framebuffer.zig");
const serial = @import("serial.zig");

// The Limine requests can be placed anywhere, but it is important that
// the compiler does not optimise them away, so, usually, they should
// be made volatile or equivalent. In Zig, `export var` is what we use.
pub export var framebuffer_request: limine.FramebufferRequest = .{};

// Set the base revision to 1, this is recommended as this is the latest
// base revision described by the Limine boot protocol specification.
// See specification for further info.
pub export var base_revision: limine.BaseRevision = .{ .revision = 1 };

inline fn halt() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}

// The following will be our kernel's entry point.
export fn _start() callconv(.C) noreturn {
    // Ensure the bootloader actually understands our base revision (see spec).
    if (!base_revision.is_supported()) {
        halt();
    }

    // Serial Port
    serial.initialize();
    serial.println("Serial Port Initialized");

    // Framebuffer
    if (framebuffer_request.response) |framebuffer_response| {
        if (framebuffer_response.framebuffer_count < 1) {
            halt();
        }
        serial.println("Framebuffer Initialized");

        // Get the first framebuffer's information.
        const fbuffer = framebuffer_response.framebuffers()[0];

        framebuffer.clear(fbuffer);
        framebuffer.fillrect(fbuffer, framebuffer.COLOR_RED, .{ .width = 128, .height = 128 });
    }

    // We're done, just hang...
    halt();
}
