const std = @import("std");
const FileSource = std.build.FileSource;
const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const optimize = b.standardOptimizeOption(.{});
    const lib = b.addStaticLibrary(.{ .name = "ssz.zig", .root_source_file = FileSource{ .path = "src/main.zig" }, .optimize = optimize, .target = .{} });
    b.installArtifact(lib);

    var main_tests = b.addTest(std.Build.TestOptions{ .root_source_file = FileSource{ .path = "src/tests.zig" }, .optimize = optimize });

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
