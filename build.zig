//! Build configuration for the Zat project.
//!
//! This file defines how Zig compiles the `zat` executable, including:
//! - Target platform and optimization level selection
//! - Version string injection via build options
//! - A `run` step to build and execute the binary (e.g. `zig build run -- myfile.txt`)
//! - A `test` step to compile and run the test suite (e.g. `zig build test`)
//!
//! ## Quick reference
//!
//! ```sh
//! zig build                        # Debug build → zig-out/bin/zat
//! zig build -Doptimize=ReleaseFast # Optimized build
//! zig build run -- src/main.zig    # Build + run with a file argument
//! zig build test                   # Run all unit tests
//! ```

const std = @import("std");

/// Entry point called by the Zig build system.
///
/// `b` is a `*std.Build` — the build graph handle that lets us declare
/// compile targets, steps, and their dependencies.
pub fn build(b: *std.Build) void {
    // Allow the user to override the target triple (e.g. cross-compile for Linux
    // from macOS) and the optimization level (Debug, ReleaseSafe, ReleaseFast,
    // ReleaseSmall). When nothing is specified, defaults to native + Debug.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The version string is injected at compile time via `build_options`.
    // It defaults to "dev" but can be overridden with `-Dversion=x.y.z`
    // (used by CI/CD release pipelines).
    const version = b.option([]const u8, "version", "Override version string") orelse "dev";

    // `addOptions()` creates a special module ("build_options") whose values
    // are available at comptime in source code via `@import("build_options")`.
    const options = b.addOptions();
    options.addOption([]const u8, "version", version);

    // Main executable
    const exe = b.addExecutable(.{
        .name = "zat",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "build_options", .module = options.createModule() },
            },
        }),
    });

    // Register the executable so `zig build install` copies it to the
    // output directory (zig-out/bin/zat by default).
    b.installArtifact(exe);

    // Run step
    // `zig build run -- <args>` builds the binary first, then executes it
    // with the provided arguments forwarded to the process.
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Test step
    // `zig build test` compiles and runs every `test` block found in the
    // source tree (starting from the root module and following `@import`s).
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
