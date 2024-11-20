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
    exe.root_module.addImport("Normalize", zg.module("Normalize"));
    exe.root_module.addImport("CaseFold", zg.module("CaseFold"));

    const zigstr = b.dependency("zigstr", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zigstr", zigstr.module("zigstr"));

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

    const tests1 = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests1.root_module.addImport("code_point", zg.module("code_point"));
    tests1.root_module.addImport("grapheme", zg.module("grapheme"));
    tests1.root_module.addImport("CaseData", zg.module("CaseData"));
    tests1.root_module.addImport("GenCatData", zg.module("GenCatData"));
    tests1.root_module.addImport("PropsData", zg.module("PropsData"));
    tests1.root_module.addImport("Normalize", zg.module("Normalize"));
    tests1.root_module.addImport("CaseFold", zg.module("CaseFold"));
    const run1 = b.addRunArtifact(tests1);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run1.step);

    const speed_tests = b.addTest(.{
        .root_source_file = b.path("src/test_speed.zig"),
        .target = target,
        .optimize = optimize,
    });
    speed_tests.root_module.addImport("zigstr", zigstr.module("zigstr"));
    speed_tests.root_module.addImport("code_point", zg.module("code_point"));
    speed_tests.root_module.addImport("grapheme", zg.module("grapheme"));
    speed_tests.root_module.addImport("CaseData", zg.module("CaseData"));
    speed_tests.root_module.addImport("GenCatData", zg.module("GenCatData"));
    speed_tests.root_module.addImport("PropsData", zg.module("PropsData"));
    speed_tests.root_module.addImport("Normalize", zg.module("Normalize"));
    speed_tests.root_module.addImport("CaseFold", zg.module("CaseFold"));
    const speed_run = b.addRunArtifact(speed_tests);
    const speed_test_step = b.step("speed", "Run unit tests");
    speed_test_step.dependOn(&speed_run.step);

    const test_irl = b.addTest(.{
        .root_source_file = b.path("src/test_irl.zig"),
        .target = target,
        .optimize = optimize,
    });
    //test_irl.root_module.addImport("zigstr", zigstr.module("zigstr"));
    test_irl.root_module.addImport("code_point", zg.module("code_point"));
    test_irl.root_module.addImport("grapheme", zg.module("grapheme"));
    test_irl.root_module.addImport("CaseData", zg.module("CaseData"));
    test_irl.root_module.addImport("GenCatData", zg.module("GenCatData"));
    test_irl.root_module.addImport("PropsData", zg.module("PropsData"));
    test_irl.root_module.addImport("Normalize", zg.module("Normalize"));
    test_irl.root_module.addImport("CaseFold", zg.module("CaseFold"));
    const irl_run = b.addRunArtifact(test_irl);
    const irl_step = b.step("irl", "Run unit tests");
    irl_step.dependOn(&irl_run.step);
}
