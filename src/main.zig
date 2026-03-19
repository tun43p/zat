const std = @import("std");
const size = @import("size.zig").Size;
const ZatFile = @import("file.zig").ZatFile;
const style = @import("style.zig").Style;
const chars = @import("chars.zig").Chars;

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
    const visible_lines: usize = term_size.height - 3; // -3 for separator + footer + padding
    const width: usize = term_size.width;

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

    try render(stdout, lines.items, scroll, visible_lines, width, file);

    while (true) {
        var buf: [1]u8 = undefined;
        const n = reader.read(&buf) catch break;
        if (n == 0) break;

        const c = buf[0];

        var changed = false;

        switch (c) {
            'q' => break,
            'j' => {
                scrollDown(&scroll, lines.items, visible_lines);
                changed = true;
            },
            'k' => {
                scrollUp(&scroll);
                changed = true;
            },
            '\x1b' => {
                var seq: [2]u8 = undefined;
                const seq_n = reader.read(&seq) catch break;
                if (seq_n == 2 and seq[0] == '[') {
                    switch (seq[1]) {
                        'A' => {
                            scrollUp(&scroll);
                            changed = true;
                        },
                        'B' => {
                            scrollDown(&scroll, lines.items, visible_lines);
                            changed = true;
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }

        if (changed) {
            try render(stdout, lines.items, scroll, visible_lines, width, file);
        }
    }

    // Quit alternate screen
    try stdout.writeAll("\x1b[?1049l");

    // Restore terminal
    try std.posix.tcsetattr(stdin, .FLUSH, original);
}

fn render(stdout: std.fs.File, lines: []const []const u8, scroll: usize, visible_lines: usize, width: usize, file: ZatFile) !void {
    const gutter = 5;

    // Cursor to top-left + clear screen
    try stdout.writeAll("\x1b[H\x1b[2J");

    // Header with ZatFile infos
    try stdout.writeAll(style.red);
    for (0..gutter) |_| try stdout.writeAll(" ");
    try stdout.writeAll(chars.pipe ++ " ");

    // File name
    try stdout.writeAll(style.cyan ++ style.bold);
    try stdout.writeAll(file.name);

    // File path
    try stdout.writeAll(style.red ++ " " ++ chars.pipe ++ " ");
    try stdout.writeAll(style.gray);
    try stdout.writeAll(file.path);

    // File mime
    try stdout.writeAll(style.red ++ " " ++ chars.pipe ++ " ");
    try stdout.writeAll(style.bright_blue);
    try stdout.writeAll(file.mime);

    // File lines
    try stdout.writeAll(style.red ++ " " ++ chars.pipe ++ " ");
    try stdout.writeAll(style.bright_yellow);
    var lines_buf: [32]u8 = undefined;
    const lines_str = std.fmt.bufPrint(&lines_buf, "{d}/{d} lines", .{ scroll + 1, file.line_count }) catch "?";
    try stdout.writeAll(lines_str);

    // File size
    try stdout.writeAll(style.red ++ " " ++ chars.pipe ++ " ");
    try stdout.writeAll(style.bright_cyan);
    var size_buf: [32]u8 = undefined;
    const size_str = std.fmt.bufPrint(&size_buf, "{d} bytes", .{file.size}) catch "?";
    try stdout.writeAll(size_str);

    // File encoding
    try stdout.writeAll(style.red ++ " " ++ chars.pipe ++ " ");
    try stdout.writeAll(style.bright_green);
    try stdout.writeAll(file.encoding);
    try stdout.writeAll(style.reset ++ "\r\n");

    // Separator line below header
    try stdout.writeAll(style.red);
    for (0..gutter) |_| try stdout.writeAll(chars.row);
    try stdout.writeAll(chars.cross);
    for (0..width - gutter - 1) |_| try stdout.writeAll(chars.row);
    try stdout.writeAll(style.reset ++ "\r\n");

    // Display visible lines
    const end = @min(scroll + visible_lines, lines.len);
    for (scroll..end) |i| {
        var num_buf: [32]u8 = undefined;
        const num = std.fmt.bufPrint(&num_buf, style.red ++ "{d: >4} " ++ chars.pipe ++ " " ++ style.reset, .{i + 1}) catch continue;
        try stdout.writeAll(num);
        try stdout.writeAll(lines[i]);
        try stdout.writeAll("\r\n");
    }
}

fn scrollDown(scroll: *usize, lines: []const []const u8, visible_lines: usize) void {
    if (scroll.* + visible_lines < lines.len) {
        scroll.* += 1;
    }
}

fn scrollUp(scroll: *usize) void {
    if (scroll.* > 0) {
        scroll.* -= 1;
    }
}
