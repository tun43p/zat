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

    if (!file.readable) {
        const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
        try stdout.writeAll("Error: cannot display file of type ");
        try stdout.writeAll(file.mime);
        try stdout.writeAll("\n");
        return;
    }

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
    const renderer = Renderer.init(term.stdout, term_size.width, term_size.height, file.mime);

    // State
    var scroll: usize = 0;
    var mode: Mode = .normal;
    var cmd_buf: [256]u8 = undefined;
    var cmd_len: usize = 0;
    var message: []const u8 = "";
    var search_buf: [256]u8 = undefined;
    var search_len: usize = 0;
    var search_term: []const u8 = "";

    try renderer.render(lines.items, scroll, visible_lines, file, message, mode, search_term);

    while (true) {
        const c = term.readKey() orelse break;

        switch (mode) {
            .normal => {
                switch (c) {
                    'j' => {
                        if (scroll + visible_lines < lines.items.len) scroll += 1;
                        try renderer.render(lines.items, scroll, visible_lines, file, message, mode, search_term);
                    },
                    'k' => {
                        if (scroll > 0) scroll -= 1;
                        try renderer.render(lines.items, scroll, visible_lines, file, message, mode, search_term);
                    },
                    'n' => {
                        if (search_term.len > 0) {
                            // Find next match starting from current scroll + 1
                            var i = scroll + 1;
                            while (i < lines.items.len) : (i += 1) {
                                if (std.mem.indexOf(u8, lines.items[i], search_term) != null) {
                                    scroll = if (i + visible_lines <= lines.items.len) i else lines.items.len - visible_lines;
                                    break;
                                }
                            }
                            try renderer.render(lines.items, scroll, visible_lines, file, message, mode, search_term);
                        }
                    },
                    'N' => {
                        if (search_term.len > 0) {
                            // Find previous match starting from current scroll - 1
                            if (scroll > 0) {
                                var i = scroll - 1;
                                while (true) {
                                    if (std.mem.indexOf(u8, lines.items[i], search_term) != null) {
                                        scroll = i;
                                        break;
                                    }
                                    if (i == 0) break;
                                    i -= 1;
                                }
                                try renderer.render(lines.items, scroll, visible_lines, file, message, mode, search_term);
                            }
                        }
                    },
                    ':' => {
                        mode = .command;
                        cmd_len = 0;
                        message = "";
                        try renderer.renderCommandLine(cmd_buf[0..0]);
                    },
                    '/' => {
                        mode = .search;
                        search_len = 0;
                        message = "";
                        try renderer.renderSearchLine(search_buf[0..0]);
                    },
                    '\x1b' => {
                        if (term.readEscapeSeq()) |seq| {
                            switch (seq) {
                                'A' => {
                                    if (scroll > 0) scroll -= 1;
                                    try renderer.render(lines.items, scroll, visible_lines, file, message, mode, search_term);
                                },
                                'B' => {
                                    if (scroll + visible_lines < lines.items.len) scroll += 1;
                                    try renderer.render(lines.items, scroll, visible_lines, file, message, mode, search_term);
                                },
                                else => {},
                            }
                        } else {
                            // Esc without sequence: clear search
                            if (search_term.len > 0) {
                                search_term = "";
                                search_len = 0;
                                message = "";
                                try renderer.render(lines.items, scroll, visible_lines, file, message, mode, search_term);
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
                        try renderer.render(lines.items, scroll, visible_lines, file, message, mode, search_term);
                    },
                    '\r', '\n' => {
                        const cmd = cmd_buf[0..cmd_len];
                        if (std.mem.eql(u8, cmd, "q")) {
                            break;
                        } else if (std.mem.eql(u8, cmd, "help")) {
                            message = ":q quit | :help this message | j/k scroll | / search | n/N next/prev match";
                        } else {
                            message = "Unknown command. Type :help for available commands.";
                        }
                        mode = .normal;
                        try renderer.render(lines.items, scroll, visible_lines, file, message, mode, search_term);
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
                switch (c) {
                    '\x1b' => {
                        mode = .normal;
                        search_term = "";
                        message = "";
                        try renderer.render(lines.items, scroll, visible_lines, file, message, mode, search_term);
                    },
                    '\r', '\n' => {
                        search_term = search_buf[0..search_len];
                        mode = .normal;
                        message = "";
                        try renderer.render(lines.items, scroll, visible_lines, file, message, mode, search_term);
                    },
                    127 => {
                        if (search_len > 0) search_len -= 1;
                        try renderer.renderSearchLine(search_buf[0..search_len]);
                    },
                    else => {
                        if (search_len < search_buf.len and c >= 32) {
                            search_buf[search_len] = c;
                            search_len += 1;
                            try renderer.renderSearchLine(search_buf[0..search_len]);
                        }
                    },
                }
            },
        }
    }
}
