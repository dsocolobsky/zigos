const std = @import("std");
const builtin = @import("builtin");

// The Limine requests can be placed anywhere, but it is important that
// the compiler does not optimise them away, so, usually, they should
// be made volatile or equivalent.

const LimineVideoMode = extern struct {
    pitch: u64,
    width: u64,
    height: u64,
    bpp: u16,
    memory_model: u8,
    red_mask_size: u8,
    red_mask_shift: u8,
    green_mask_size: u8,
    green_mask_shift: u8,
    blue_mask_size: u8,
    blue_mask_shift: u8,
};

const LimineFramebuffer = extern struct {
    address: *anyopaque,
    width: u64,
    height: u64,
    pitch: u64,
    bpp: u64,
    memory_model: u8,
    red_mask_size: u8,
    red_mask_shift: u8,
    green_mask_size: u8,
    green_mask_shift: u8,
    blue_mask_size: u8,
    blue_mask_shift: u8,
    unused: [7]u8,
    edid_size: u64,
    edid: *anyopaque,
    mode_count: u64,
    modes: **LimineVideoMode,
};

const LimineFramebufferResponse = extern struct {
    revision: u64,
    framebuffer_count: u64,
    framebuffers: **LimineFramebuffer,
};

const LimineFramebufferRequest = extern struct {
    id: [4]u64,
    revision: u64,
    response: ?*LimineFramebufferResponse,
};

pub export var framebuffer_request: LimineFramebufferRequest = .{
    .id = [4]u64{ 0x4c, 0x49, 0x4d, 0x49 },
    .revision = 0,
    .response = null,
};

// Halt and catch fire function
fn hcf() void {
    switch (builtin.target.cpu.arch) {
        .x86_64 => {
            asm volatile ("cli");
            while (true) {
                asm volatile ("hlt");
            }
        },
        .aarch64, .riscv64 => {
            while (true) {
                asm volatile ("wfi");
            }
        },
        else => @compileError("unsupported architecture"),
    }
}

// The following will be our kernel's entry point.
// If renaming _start() to something else, make sure to change the
// linker script accordingly.
pub export fn _start() callconv(.C) void {
    // Ensure we got a framebuffer
    if (framebuffer_request.response) |framebuffer_response| {
        if (framebuffer_response.framebuffer_count < 1) {
            hcf();
        }

        // Fetch the first framebuffer
        const framebuffer = *framebuffer_response.framebuffers[0];

        // Note: we assume the framebuffer model is RGB with 32-bit pixels.
        for (0..100) |i| {
            framebuffer.getSlice(u32)[i * (framebuffer.pitch / 4) + i] = 0xffffff;
        }
    }

    // We're done, just hang...
    hcf();
}
