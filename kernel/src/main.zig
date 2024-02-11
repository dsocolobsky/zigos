const limine = @import("limine");
const std = @import("std");
const framebuffer = @import("framebuffer.zig");

// The Limine requests can be placed anywhere, but it is important that
// the compiler does not optimise them away, so, usually, they should
// be made volatile or equivalent. In Zig, `export var` is what we use.
pub export var framebuffer_request: limine.FramebufferRequest = .{};

// Set the base revision to 1, this is recommended as this is the latest
// base revision described by the Limine boot protocol specification.
// See specification for further info.
pub export var base_revision: limine.BaseRevision = .{ .revision = 1 };

inline fn done() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}

fn tries(a: *limine.FrameBuffer) void {
    const fbuffer = a.*;
    framebuffer.clear(fbuffer);
    for (0..30) |h| {
        for (0..framebuffer.width) |w| {
            const pixel_offset = h * framebuffer.pitch + w * 4;
            @as(*u32, @ptrCast(@alignCast(framebuffer.address + pixel_offset))).* = 0xFFFF0000;
        }
    }
}

// The following will be our kernel's entry point.
export fn _start() callconv(.C) noreturn {
    // Ensure the bootloader actually understands our base revision (see spec).
    if (!base_revision.is_supported()) {
        done();
    }

    // Ensure we got a framebuffer.
    if (framebuffer_request.response) |framebuffer_response| {
        if (framebuffer_response.framebuffer_count < 1) {
            done();
        }

        // Get the first framebuffer's information.
        const fbuffer = framebuffer_response.framebuffers()[0];

        framebuffer.clear(fbuffer);

        framebuffer.fillrect_naive(fbuffer, 255, 0, 0, 128, 128);
        //framebuffer.fillrect(fbuffer, 255, 0, 0, 128, 128);
    }

    // We're done, just hang...
    done();
}