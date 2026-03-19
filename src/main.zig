const std = @import("std");
const size = @import("size.zig").Size;
const ZatFile = @import("file.zig").ZatFile;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const stdin = std.posix.STDIN_FILENO;
    const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    const reader = std.fs.File{ .handle = stdin };

    // Get file path from arguments
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip();
    const file_path = args.next() orelse {
        try stdout.writeAll("Usage: zig run src/raw.zig -- <fichier>\n");
        return;
    };

    // Load file via ZatFile (contains path, name, mime, size, encoding, etc.)
    const file = try ZatFile.init(allocator, file_path);
    defer file.deinit(allocator);

    // Split content into lines
    var lines: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, file.content, '\n');
    while (it.next()) |line| {
        try lines.append(allocator, line);
    }

    // Get terminal size
    const term_size = try size.get(stdout) orelse return error.TerminalSizeNotFound;
    const visible_lines: usize = term_size.height - 2; // -2 for status bar

    // Raw mode
    const original = try std.posix.tcgetattr(stdin);
    var raw = original;
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    try std.posix.tcsetattr(stdin, .FLUSH, raw);

    // Alternate screen
    try stdout.writeAll("\x1b[?1049h");

    // Main loop
    var scroll: usize = 0;

    try render(stdout, lines.items, scroll, visible_lines, file);

    while (true) {
        var buf: [1]u8 = undefined;
        const n = reader.read(&buf) catch break;
        if (n == 0) break;

        const c = buf[0];

        var changed = false;

        switch (c) {
            'q' => break,
            'j' => { // TODO: handle down arrow
                if (scroll + visible_lines < lines.items.len) {
                    scroll += 1;
                    changed = true;
                }
            },
            'k' => { // TODO: handle up arrow
                if (scroll > 0) {
                    scroll -= 1;
                    changed = true;
                }
            },
            else => {},
        }

        if (changed) {
            try render(stdout, lines.items, scroll, visible_lines, file);
        }
    }

    // Quit alternate screen
    try stdout.writeAll("\x1b[?1049l");

    // Restore terminal
    try std.posix.tcsetattr(stdin, .FLUSH, original);
}

fn render(stdout: std.fs.File, lines: []const []const u8, scroll: usize, visible_lines: usize, file: ZatFile) !void {
    // Cursor to top-left
    try stdout.writeAll("\x1b[H");

    // Clear screen
    try stdout.writeAll("\x1b[2J");

    // Display visible lines
    const end = @min(scroll + visible_lines, lines.len);
    for (scroll..end) |i| {
        var num_buf: [32]u8 = undefined;
        const num = std.fmt.bufPrint(&num_buf, "\x1b[31m{d: >4}\x1b[0m │ ", .{i + 1}) catch continue;
        try stdout.writeAll(num);
        try stdout.writeAll(lines[i]);
        try stdout.writeAll("\r\n");
    }

    // Status bar with ZatFile infos
    var status_buf: [256]u8 = undefined;
    const status = std.fmt.bufPrint(&status_buf, "\x1b[7m {s} | {s} | {s} | {d}/{d} lines | {d} bytes | {s} \x1b[0m", .{
        file.name,
        file.path,
        file.mime,
        scroll + 1,
        file.line_count,
        file.size,
        file.encoding,
    }) catch "";

    try stdout.writeAll(status);
}
