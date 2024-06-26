const std = @import("std");

pub fn build_nasm(comptime path: []const u8, comptime name: []const u8, exe: *std.Build.Step.Compile) !void {
    var alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const output = "./zig-cache/nasm/" ++ name ++ ".o";
    var child = std.process.Child.init(
        &[_][]const u8{ "nasm", path, "-f", "elf64", "-w+all", "-Werror", "-o", output },
        alloc.allocator(),
    );
    _ = try child.spawnAndWait();

    exe.addObjectFile(std.Build.LazyPath{ .path = output });
}

pub fn build(b: *std.build.Builder) !void {
    // Define a freestanding x86_64 cross-compilation target.
    var target: std.zig.CrossTarget = .{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    };

    // Disable CPU features that require additional initialization
    // like MMX, SSE/2 and AVX. That requires us to enable the soft-float feature.
    const Features = std.Target.x86.Feature;
    target.cpu_features_sub.addFeature(@intFromEnum(Features.mmx));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.sse));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.sse2));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.avx));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.avx2));
    target.cpu_features_add.addFeature(@intFromEnum(Features.soft_float));

    // Build the kernel itself.
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = std.builtin.OptimizeMode.Debug,
    });
    const limine = b.dependency("limine", .{});
    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    kernel.code_model = .kernel;
    kernel.addModule("limine", limine.module("limine"));
    kernel.setLinkerScriptPath(.{ .path = "linker.ld" });
    kernel.pie = false;

    std.fs.cwd().makePath("./zig-cache/nasm") catch {};
    try build_nasm("./src/interrupts.s", "interrupts", kernel);

    // Link Tamsyn font
    kernel.addObjectFile(std.Build.LazyPath{ .path = "./tamsyn.o" });

    b.installArtifact(kernel);
}
