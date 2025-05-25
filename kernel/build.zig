const std = @import("std");

pub fn build_nasm(comptime path: []const u8, comptime name: []const u8, exe: *std.Build.Step.Compile, b: *std.Build) !void {
    var alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const output = "./zig-cache/nasm/" ++ name ++ ".o";
    var child = std.process.Child.init(
        &[_][]const u8{ "nasm", path, "-f", "elf64", "-w+all", "-Werror", "-o", output },
        alloc.allocator(),
    );
    _ = try child.spawnAndWait();

    exe.addObjectFile(b.path(output));
}

pub fn build(b: *std.Build) !void {
    // Define a freestanding x86_64 cross-compilation target.
    var target_query: std.Target.Query = .{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    };

    // Disable CPU features that require additional initialization
    // like MMX, SSE/2 and AVX. That requires us to enable the soft-float feature.
    const Features = std.Target.x86.Feature;
    target_query.cpu_features_sub.addFeature(@intFromEnum(Features.mmx));
    target_query.cpu_features_sub.addFeature(@intFromEnum(Features.sse));
    target_query.cpu_features_sub.addFeature(@intFromEnum(Features.sse2));
    target_query.cpu_features_sub.addFeature(@intFromEnum(Features.avx));
    target_query.cpu_features_sub.addFeature(@intFromEnum(Features.avx2));
    target_query.cpu_features_add.addFeature(@intFromEnum(Features.soft_float));
    const target = b.resolveTargetQuery(target_query);

    // Build the kernel itself.
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = std.builtin.OptimizeMode.Debug,
    });

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .kernel,
    });

    // Add the Limine library as a dependency.
    const limine = b.dependency("limine_zig", .{});
    kernel.root_module.addImport("limine", limine.module("limine"));

    //const limine_mod = b.addModule("limine", .{
    //    .root_source_file = b.path("../external/limine-zig/limine.zig"),
    //    .target = target,
    //    .optimize = optimize,
    //    .code_model = .kernel,
    //});
    //kernel.root_module.addImport("limine", limine_mod);

    kernel.setLinkerScript(b.path("linker.ld"));
    kernel.pie = false;
    kernel.root_module.stack_protector = false;
    kernel.root_module.stack_check = false;
    kernel.root_module.red_zone = false;
    kernel.entry = std.Build.Step.Compile.Entry.disabled;

    std.fs.cwd().makePath("./zig-cache/nasm") catch {};
    try build_nasm("./src/interrupts.s", "interrupts", kernel, b);

    // Link Tamsyn font
    kernel.addObjectFile(b.path("./tamsyn.o"));
    b.installArtifact(kernel);
}
