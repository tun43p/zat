const std = @import("std");

const File = @import("file.zig").File;
const Mode = @import("renderer.zig").Mode;
const Renderer = @import("renderer.zig").Renderer;
const Terminal = @import("terminal.zig").Terminal;
const TerminalSize = @import("terminal.zig").TerminalSize;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Get file path from arguments
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip();
    const file_path = args.next() orelse {
        const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
        try stdout.writeAll("Usage: zat <file>\n");
        return;
    };

    // Load file
    const file = try File.init(allocator, file_path);
    defer file.deinit(allocator);

    // Split content into lines
    var lines: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, file.content, '\n');
    while (it.next()) |line| {
        try lines.append(allocator, line);
    }

    // Setup terminal
    const term = try Terminal.init();
    defer term.deinit();

    // Setup renderer
    const term_size = try TerminalSize.get(term.stdout) orelse return error.TerminalSizeNotFound;
    const visible_lines: usize = term_size.height - 6; // top + header + sep + footer sep + footer + bottom
    const renderer = Renderer.init(term.stdout, term_size.width, term_size.height);

    // State
    var scroll: usize = 0;
    var mode: Mode = .normal;
    var cmd_buf: [256]u8 = undefined;
    var cmd_len: usize = 0;
    var message: []const u8 = "";

    try renderer.render(lines.items, scroll, visible_lines, file, message, mode);

    while (true) {
        const c = term.readKey() orelse break;

        switch (mode) {
            .normal => {
                switch (c) {
                    'j' => {
                        if (scroll + visible_lines < lines.items.len) scroll += 1;
                        try renderer.render(lines.items, scroll, visible_lines, file, message, mode);
                    },
                    'k' => {
                        if (scroll > 0) scroll -= 1;
                        try renderer.render(lines.items, scroll, visible_lines, file, message, mode);
                    },
                    ':' => {
                        mode = .command;
                        cmd_len = 0;
                        message = "";
                        try renderer.renderCommandLine(cmd_buf[0..0]);
                    },
                    '/' => {
                        mode = .search;
                        // TODO: Implement search mode
                    },
                    '\x1b' => {
                        if (term.readEscapeSeq()) |seq| {
                            switch (seq) {
                                'A' => {
                                    if (scroll > 0) scroll -= 1;
                                    try renderer.render(lines.items, scroll, visible_lines, file, message, mode);
                                },
                                'B' => {
                                    if (scroll + visible_lines < lines.items.len) scroll += 1;
                                    try renderer.render(lines.items, scroll, visible_lines, file, message, mode);
                                },
                                else => {},
                            }
                        }
                    },
                    else => {},
                }
            },
            .command => {
                switch (c) {
                    '\x1b' => {
                        mode = .normal;
                        message = "";
                        try renderer.render(lines.items, scroll, visible_lines, file, message, mode);
                    },
                    '\r', '\n' => {
                        const cmd = cmd_buf[0..cmd_len];
                        if (std.mem.eql(u8, cmd, "q")) {
                            break;
                        } else if (std.mem.eql(u8, cmd, "help")) {
                            message = "Commands: :q quit | :help this message | j/k or arrows to scroll";
                        } else {
                            message = "Unknown command. Type :help for available commands.";
                        }
                        mode = .normal;
                        try renderer.render(lines.items, scroll, visible_lines, file, message, mode);
                    },
                    127 => {
                        if (cmd_len > 0) cmd_len -= 1;
                        try renderer.renderCommandLine(cmd_buf[0..cmd_len]);
                    },
                    else => {
                        if (cmd_len < cmd_buf.len and c >= 32) {
                            cmd_buf[cmd_len] = c;
                            cmd_len += 1;
                            try renderer.renderCommandLine(cmd_buf[0..cmd_len]);
                        }
                    },
                }
            },
            .search => {
                // TODO: Implement search mode
            },
        }
    }
}
