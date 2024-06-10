const Builder = @import("std").Build;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const lib = b.addStaticLibrary(.{
        .name = "ssz",
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .optimize = optimize,
        .target = target,
    });
    b.installArtifact(lib);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .optimize = optimize,
        .target = target,
    });
    const run_main_tests = b.addRunArtifact(main_tests);
    const tests_tests = b.addTest(.{
        .root_source_file = .{ .cwd_relative = "src/tests.zig" },
        .optimize = optimize,
        .target = target,
    });
    const run_tests_tests = b.addRunArtifact(tests_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
    test_step.dependOn(&run_tests_tests.step);
}
