const std = @import("std");
const build_options = @import("build_options");

const App = @import("app.zig").App;
const File = @import("file.zig").File;
const Terminal = @import("terminal.zig").Terminal;

const version = build_options.version;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };

    // Get file path from arguments
    var args = try std.process.argsWithAllocator(allocator);
    _ = args.skip();
    const file_path = args.next() orelse {
        try stdout.writeAll("Usage: zat <file>\n");
        return;
    };

    if (std.mem.eql(u8, file_path, "--version") or std.mem.eql(u8, file_path, "-v")) {
        try stdout.writeAll("zat " ++ version ++ "\n");
        return;
    }

    // Load file
    const file = File.init(allocator, file_path) catch |err| {
        var err_buf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&err_buf, "Error: could not open '{s}': {s}\n", .{ file_path, @errorName(err) }) catch "Error: could not open file\n";
        try stdout.writeAll(msg);
        return;
    };

    if (!file.readable) {
        try stdout.writeAll("Error: cannot display file of type ");
        try stdout.writeAll(file.mime);
        try stdout.writeAll("\n");
        return;
    }

    // Setup terminal
    const term = try Terminal.init();
    defer term.deinit();

    // Setup writer and app
    var write_buf: [4096]u8 = undefined;
    var stdout_writer = term.stdout.writer(&write_buf);
    var app = try App.init(allocator, file, term, &stdout_writer.interface);
    try app.run();
}
