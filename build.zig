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

    const exe = b.addExecutable(.{
        .name = "ZigString",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zg = b.dependency("zg", .{});
    exe.root_module.addImport("code_point", zg.module("code_point"));
    exe.root_module.addImport("grapheme", zg.module("grapheme"));
    exe.root_module.addImport("CaseData", zg.module("CaseData"));
    exe.root_module.addImport("GenCatData", zg.module("GenCatData"));
    exe.root_module.addImport("PropsData", zg.module("PropsData"));
    exe.root_module.addImport("Normalize", zg.module("Normalize"));
    exe.root_module.addImport("CaseFold", zg.module("CaseFold"));

    const installAssembly = b.addInstallBinFile(exe.getEmittedAsm(), "assembly.s");
    b.getInstallStep().dependOn(&installAssembly.step);

    // const zigstr = b.dependency("zigstr", .{
    //     .target = target,
    //     .optimize = optimize,
    // });
    // exe.root_module.addImport("zigstr", zigstr.module("zigstr"));

     // Module
    _ = b.addModule("zigstring", .{
        .root_source_file = b.path("src/String.zig"),
        .imports = &.{
            .{ .name = "grapheme", .module = zg.module("grapheme") },
            .{ .name = "code_point", .module = zg.module("code_point") },
            .{ .name = "grapheme", .module = zg.module("grapheme") },
            .{ .name = "PropsData", .module = zg.module("PropsData") },
            .{ .name = "CaseData", .module = zg.module("CaseData") },
            .{ .name = "Normalize", .module = zg.module("Normalize") },
            .{ .name = "CaseFold", .module = zg.module("CaseFold") },
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
        .root_source_file = b.path("src/test_default.zig"),
        .target = target,
        .optimize = optimize,
    });
    default_test.root_module.addImport("code_point", zg.module("code_point"));
    default_test.root_module.addImport("grapheme", zg.module("grapheme"));
    default_test.root_module.addImport("CaseData", zg.module("CaseData"));
    default_test.root_module.addImport("GenCatData", zg.module("GenCatData"));
    default_test.root_module.addImport("PropsData", zg.module("PropsData"));
    default_test.root_module.addImport("Normalize", zg.module("Normalize"));
    default_test.root_module.addImport("CaseFold", zg.module("CaseFold"));
    const run1 = b.addRunArtifact(default_test);
    const test_step = b.step("test", "Run default tests");
    test_step.dependOn(&run1.step);

    const speed_test = b.addTest(.{
        .root_source_file = b.path("src/test_speed.zig"),
        .target = target,
        .optimize = optimize,
    });
    // speed_test.root_module.addImport("zigstr", zigstr.module("zigstr"));
    speed_test.root_module.addImport("code_point", zg.module("code_point"));
    speed_test.root_module.addImport("grapheme", zg.module("grapheme"));
    speed_test.root_module.addImport("CaseData", zg.module("CaseData"));
    speed_test.root_module.addImport("GenCatData", zg.module("GenCatData"));
    speed_test.root_module.addImport("PropsData", zg.module("PropsData"));
    speed_test.root_module.addImport("Normalize", zg.module("Normalize"));
    speed_test.root_module.addImport("CaseFold", zg.module("CaseFold"));
    const speed_run = b.addRunArtifact(speed_test);
    const speed_test_step = b.step("test_speed", "Test Speed");
    speed_test_step.dependOn(&speed_run.step);

    const irl_test = b.addTest(.{
        .root_source_file = b.path("src/test_irl.zig"),
        .target = target,
        .optimize = optimize,
    });
    irl_test.linkLibC();
    irl_test.root_module.addImport("code_point", zg.module("code_point"));
    irl_test.root_module.addImport("grapheme", zg.module("grapheme"));
    irl_test.root_module.addImport("CaseData", zg.module("CaseData"));
    irl_test.root_module.addImport("GenCatData", zg.module("GenCatData"));
    irl_test.root_module.addImport("PropsData", zg.module("PropsData"));
    irl_test.root_module.addImport("Normalize", zg.module("Normalize"));
    irl_test.root_module.addImport("CaseFold", zg.module("CaseFold"));
    const irl_run = b.addRunArtifact(irl_test);
    const irl_step = b.step("test_irl", "Test IRL");
    irl_step.dependOn(&irl_run.step);


     const test_regexp = b.addTest(.{
        .root_source_file = b.path("src/Regex.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_regexp.linkLibC();
    test_regexp.root_module.addImport("code_point", zg.module("code_point"));
    test_regexp.root_module.addImport("grapheme", zg.module("grapheme"));
    test_regexp.root_module.addImport("CaseData", zg.module("CaseData"));
    test_regexp.root_module.addImport("GenCatData", zg.module("GenCatData"));
    test_regexp.root_module.addImport("PropsData", zg.module("PropsData"));
    test_regexp.root_module.addImport("Normalize", zg.module("Normalize"));
    test_regexp.root_module.addImport("CaseFold", zg.module("CaseFold"));
    const regexp_run = b.addRunArtifact(test_regexp);
    const regexp_step = b.step("test_regex", "Test Regex");
    regexp_step.dependOn(&regexp_run.step);
}
