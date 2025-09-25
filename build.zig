const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    const zg = b.dependency("zg", .{});

    const exe = b.addExecutable(.{
        .name = "main",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    addZgImport(exe, zg);

    const installAssembly = b.addInstallBinFile(exe.getEmittedAsm(), "assembly.s");
    b.getInstallStep().dependOn(&installAssembly.step);

     // Module
    _ = b.addModule("zigstring", .{
        .root_source_file = b.path("src/String.zig"),
        .imports = &.{
            .{ .name = "grapheme", .module = zg.module("Graphemes") },
            .{ .name = "code_point", .module = zg.module("code_point") },
            .{ .name = "Normalize", .module = zg.module("Normalize") },
            .{ .name = "CaseFolding", .module = zg.module("CaseFolding") },
            .{ .name = "LetterCasing", .module = zg.module("LetterCasing") },
        },
    });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);
    // exe.emit_asm = .emit;

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const default_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_default.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    addZgImport(default_test, zg);
    const run1 = b.addRunArtifact(default_test);
    const test_step = b.step("test", "Run default tests");
    test_step.dependOn(&run1.step);

    const speed_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_speed.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    // speed_test.root_module.addImport("zigstr", zigstr.module("zigstr"));
    addZgImport(speed_test, zg);
    const speed_run = b.addRunArtifact(speed_test);
    const speed_test_step = b.step("test_speed", "Test Speed");
    speed_test_step.dependOn(&speed_run.step);

    const irl_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_irl.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    irl_test.linkLibC();
    addZgImport(irl_test, zg);
    const irl_run = b.addRunArtifact(irl_test);
    const irl_step = b.step("test_irl", "Test IRL");
    irl_step.dependOn(&irl_run.step);

    const test_regexp = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/Regex.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_regexp.linkLibC();
    addZgImport(test_regexp, zg);
    const regexp_run = b.addRunArtifact(test_regexp);
    const regexp_step = b.step("test_regex", "Test Regex");
    regexp_step.dependOn(&regexp_run.step);
}

fn addZgImport(target: anytype, zg: *std.Build.Dependency) void {
    target.root_module.addImport("code_point", zg.module("code_point"));
    target.root_module.addImport("grapheme", zg.module("Graphemes")); // 
    target.root_module.addImport("LetterCasing", zg.module("LetterCasing"));//
    target.root_module.addImport("GenCatData", zg.module("GeneralCategories"));//GenCatData
    // target.root_module.addImport("PropsData", zg.module("PropsData"));
    target.root_module.addImport("Normalize", zg.module("Normalize"));
    target.root_module.addImport("CaseFolding", zg.module("CaseFolding")); // CaseFold
}