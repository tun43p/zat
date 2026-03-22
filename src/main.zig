//! Entry point of the Zat application.
//!
//! Zat is an interactive terminal file viewer with syntax highlighting and
//! vim-like keybindings. This module handles:
//!
//! 1. **Argument parsing** — reads the file path from the command line.
//! 2. **File loading** — opens and reads the file into memory via `File`.
//! 3. **Terminal setup** — switches to raw mode and an alternate screen via `Terminal`.
//! 4. **Application loop** — hands control to `App`, which manages rendering and input.
//!
//! ## Memory management
//!
//! Zat uses a single `ArenaAllocator` backed by the page allocator. Because
//! the program exits when the viewer closes, there is no need to free
//! individual allocations — the entire arena is released at once on exit via
//! `defer arena.deinit()`.

const std = @import("std");
const build_options = @import("build_options");

const App = @import("app.zig").App;
const File = @import("file.zig").File;
const Terminal = @import("terminal.zig").Terminal;

/// The version string injected at compile time by `build.zig`.
/// Defaults to `"dev"` for local builds; CI sets it to a semver tag.
const version = build_options.version;

pub fn main() !void {
    // Create an arena allocator. All allocations made during the lifetime of
    // the program go through this arena, which is freed in one shot at exit.
    // This avoids the overhead of tracking individual allocations.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    // Obtain a handle to stdout. In Zig, stdout is represented as a
    // `std.fs.File` wrapping the POSIX file descriptor for standard output.
    const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };

    // Skip the first argument (program name) and read the file path.
    // If no argument is provided, print usage and exit.
    var args = try std.process.argsWithAllocator(allocator);
    _ = args.skip();
    const file_path = args.next() orelse {
        try stdout.writeAll("Usage: zat <file>\n");
        return;
    };

    // Handle `--version` / `-v` flags before doing any file I/O.
    if (std.mem.eql(u8, file_path, "--version") or std.mem.eql(u8, file_path, "-v")) {
        try stdout.writeAll("zat " ++ version ++ "\n");
        return;
    }

    // `File.init` opens the file, detects its MIME type, reads its content
    // into memory, and splits it into lines. If any step fails (e.g. file
    // not found, permission denied), we print a human-readable error.
    const file = File.init(allocator, file_path) catch |err| {
        var err_buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&err_buf, "Error: could not open '{s}': {s}\n", .{ file_path, @errorName(err) }) catch "Error: could not open file\n";
        try stdout.writeAll(msg);
        return;
    };

    // Binary files (images, archives, etc.) are detected via MIME type.
    // We refuse to display them and print the MIME type so the user
    // understands why.
    if (!file.readable) {
        try stdout.writeAll("Error: cannot display file of type ");
        try stdout.writeAll(file.mime);
        try stdout.writeAll("\n");
        return;
    }

    // `Terminal.init` switches stdin to raw mode (no echo, no line
    // buffering) and enters the alternate screen buffer so the user's
    // scrollback is preserved. `defer term.deinit()` restores everything
    // on exit — even if the program panics or encounters an error.
    const term = try Terminal.init();
    defer term.deinit();

    // Create a stack-allocated write buffer for stdout. The `Renderer`
    // batches ANSI escape sequences and content into this buffer before
    // flushing, which reduces the number of syscalls and avoids flicker.
    var write_buf: [4096]u8 = undefined;
    var stdout_writer = term.stdout.writer(&write_buf);

    // `App` ties together the file data, terminal, and renderer.
    // `app.run()` enters the main event loop: render → wait for key →
    // handle key → re-render, until the user quits.
    var app = try App.init(allocator, file, term, &stdout_writer.interface);
    try app.run();
}
