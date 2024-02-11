const std = @import("std");
const builtin = @import("builtin");

const Build = std.Build;
const Arch = std.Target.Cpu.Arch;
const CrossTarget = std.zig.CrossTarget;
const Target = @import("std").Target;

pub fn build(b: *Build) !void {
    const target = genTarget();

    const kernel = buildKernel(b, target);
    const iso = buildLimineIso(b, kernel);
    b.default_step.dependOn(iso);
    _ = runIsoQemu(b, iso);
}

fn genTarget() CrossTarget {
    const features = Target.x86.Feature;

    var disabled_features = Target.Cpu.Feature.Set.empty;
    var enabled_features = Target.Cpu.Feature.Set.empty;

    disabled_features.addFeature(@intFromEnum(features.mmx));
    disabled_features.addFeature(@intFromEnum(features.sse));
    disabled_features.addFeature(@intFromEnum(features.sse2));
    disabled_features.addFeature(@intFromEnum(features.avx));
    disabled_features.addFeature(@intFromEnum(features.avx2));
    enabled_features.addFeature(@intFromEnum(features.soft_float));

    const target = CrossTarget{
        .cpu_arch = Target.Cpu.Arch.x86_64,
        .os_tag = Target.Os.Tag.freestanding,
        .abi = Target.Abi.none,
        .cpu_features_sub = disabled_features,
        .cpu_features_add = enabled_features,
    };

    return target;
}

fn buildKernel(b: *Build, target: CrossTarget) *Build.Step {
    const optimize = b.standardOptimizeOption(.{});

    var kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = b.resolveTargetQuery(target),
        .optimize = optimize,
        .code_model = .kernel,
    });
    kernel.linker_script = .{ .path = "src/linker.ld" };

    const limine = b.dependency("limine", .{
        .target = target,
        .optimize = optimize,
    });
    kernel.addModule("limine", limine.module("limine"));

    const art = b.addInstallArtifact(kernel, .{}).step;
    b.getInstallStep().dependOn(art);
    return &art;
}

fn buildLimineIso(b: *Build, kernel: *Build.Step) *Build.Step {
    const limine_deploy = switch (builtin.os.tag) {
        .linux => "limine-deploy",
        .windows => "limine-deploy.exe",
        else => return error.UnsupportedOS,
    };

    // TODO: use submodules with a hardcoded path until Zig supports
    //       static assets
    const limine_path = "external/limine";

    const cmd = &[_][]const u8{
        // zig fmt: off
        "/bin/sh", "-c",
        try std.mem.concat(b.allocator, u8, &[_][]const u8{
            "mkdir -p zig-out/iso/root && ",
            "make -C " ++ limine_path ++ " && ",
            "cp zig-out/bin/", "kernel.image", " zig-out/iso/root && ",
            "cp src/limine.cfg zig-out/iso/root && ",
            "cp ", limine_path ++ "/limine.sys ",
                   limine_path ++ "/limine-cd.bin ",
                   limine_path ++ "/limine-cd-efi.bin ",
                   "zig-out/iso/root && ",
            "xorriso -as mkisofs -quiet -b limine-cd.bin ",
                "-no-emul-boot -boot-load-size 4 -boot-info-table ",
                "--efi-boot limine-cd-efi.bin ",
                "-efi-boot-part --efi-boot-image --protective-msdos-label ",
                "zig-out/iso/root -o zig-out/iso/limine-barebones.iso && ",
            limine_path ++ "/" ++ limine_deploy ++ " zig-out/iso/limine-barebones.iso",
        // zig fmt: on
        }),
    };

    const iso_cmd = b.addSystemCommand(cmd);
    iso_cmd.step.dependOn(&kernel);

    const iso_step = b.step("iso", "Generate bootable ISO file");
    iso_step.dependOn(&iso_cmd.step);

    return iso_cmd;
}

fn runIsoQemu(b: *Build, iso: *Build.Step) *Build.Step {
    const qemu_iso_args = &[_][]const u8{
        "qemu-system-x86_64",
        "-M",
        "q35,accel=kvm:whpx:tcg",
        "-m",
        "2G",
        "-cdrom",
        "zig-out/iso/limine-barebones.iso",
        "-boot",
        "d",
    };
    const qemu_iso_cmd = b.addSystemCommand(qemu_iso_args);
    qemu_iso_cmd.step.dependOn(iso);

    const qemu_iso_step = b.step("run", "Boot ISO in qemu");
    qemu_iso_step.dependOn(&qemu_iso_cmd.step);

    return qemu_iso_cmd;
}
