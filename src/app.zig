const std = @import("std");

const File = @import("file.zig").File;
const Mode = @import("renderer.zig").Mode;
const Renderer = @import("renderer.zig").Renderer;
const Terminal = @import("terminal.zig").Terminal;
const TerminalSize = @import("terminal.zig").TerminalSize;

pub const App = struct {
    lines: []const []const u8,
    file: File,
    term: Terminal,
    renderer: Renderer,
    visible_lines: usize,

    scroll: usize = 0,
    mode: Mode = .normal,
    cmd_buf: [256]u8 = undefined,
    cmd_len: usize = 0,
    message: []const u8 = "",
    search_buf: [256]u8 = undefined,
    search_len: usize = 0,
    search_term: []const u8 = "",

    pub fn init(allocator: std.mem.Allocator, file: File, term: Terminal, writer: *std.io.Writer) !App {
        const term_size = try TerminalSize.get(term.stdout) orelse return error.TerminalSizeNotFound;
        const visible_lines: usize = if (term_size.height > 6) term_size.height - 6 else 1;

        var line_list: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, file.content, '\n');
        while (it.next()) |line| {
            try line_list.append(allocator, line);
        }

        return .{
            .lines = line_list.items,
            .file = file,
            .term = term,
            .renderer = Renderer.init(writer, term_size.width, term_size.height, file.mime),
            .visible_lines = visible_lines,
        };
    }

    pub fn run(self: *App) !void {
        try self.render();

        while (true) {
            const c = self.term.readKey() orelse break;

            if (self.term.checkResized()) {
                if (TerminalSize.get(self.term.stdout) catch null) |new_size| {
                    self.renderer.width = new_size.width;
                    self.renderer.height = new_size.height;
                    self.visible_lines = if (new_size.height > 6) new_size.height - 6 else 1;
                    try self.render();
                }
            }

            const should_quit = switch (self.mode) {
                .normal => try self.handleNormalMode(c),
                .command => try self.handleCommandMode(c),
                .search => try self.handleSearchMode(c),
            };

            if (should_quit) break;
        }
    }

    fn handleNormalMode(self: *App, c: u8) !bool {
        switch (c) {
            'j' => {
                if (self.scroll + self.visible_lines < self.lines.len) self.scroll += 1;
                try self.render();
            },
            'k' => {
                if (self.scroll > 0) self.scroll -= 1;
                try self.render();
            },
            'g' => {
                self.scroll = 0;
                try self.render();
            },
            'G' => {
                self.scroll = if (self.lines.len > self.visible_lines) self.lines.len - self.visible_lines else 0;
                try self.render();
            },
            'd' => {
                const half = self.visible_lines / 2;
                const max_scroll = if (self.lines.len > self.visible_lines) self.lines.len - self.visible_lines else 0;
                self.scroll = @min(self.scroll + half, max_scroll);
                try self.render();
            },
            'u' => {
                const half = self.visible_lines / 2;
                self.scroll = if (self.scroll > half) self.scroll - half else 0;
                try self.render();
            },
            ' ' => {
                const max_scroll = if (self.lines.len > self.visible_lines) self.lines.len - self.visible_lines else 0;
                self.scroll = @min(self.scroll + self.visible_lines, max_scroll);
                try self.render();
            },
            'n' => {
                if (self.search_term.len > 0) {
                    var i = self.scroll + 1;
                    while (i < self.lines.len) : (i += 1) {
                        if (std.mem.indexOf(u8, self.lines[i], self.search_term) != null) {
                            self.scroll = if (i + self.visible_lines <= self.lines.len) i else self.lines.len - self.visible_lines;
                            break;
                        }
                    }
                    try self.render();
                }
            },
            'N' => {
                if (self.search_term.len > 0 and self.scroll > 0) {
                    var i = self.scroll - 1;
                    while (true) {
                        if (std.mem.indexOf(u8, self.lines[i], self.search_term) != null) {
                            self.scroll = i;
                            break;
                        }
                        if (i == 0) break;
                        i -= 1;
                    }
                    try self.render();
                }
            },
            ':' => {
                self.mode = .command;
                self.cmd_len = 0;
                self.message = "";
                try self.renderer.renderCommandLine(self.cmd_buf[0..0]);
            },
            '/' => {
                self.mode = .search;
                self.search_len = 0;
                self.message = "";
                try self.renderer.renderSearchLine(self.search_buf[0..0]);
            },
            '\x1b' => {
                if (self.term.readEscapeSeq()) |seq| {
                    switch (seq) {
                        'A' => {
                            if (self.scroll > 0) self.scroll -= 1;
                            try self.render();
                        },
                        'B' => {
                            if (self.scroll + self.visible_lines < self.lines.len) self.scroll += 1;
                            try self.render();
                        },
                        else => {},
                    }
                } else {
                    if (self.search_term.len > 0) {
                        self.search_term = "";
                        self.search_len = 0;
                        self.message = "";
                        try self.render();
                    }
                }
            },
            else => {},
        }
        return false;
    }

    fn handleCommandMode(self: *App, c: u8) !bool {
        switch (c) {
            '\x1b' => {
                self.mode = .normal;
                self.message = "";
                try self.render();
            },
            '\r', '\n' => {
                const cmd = self.cmd_buf[0..self.cmd_len];
                if (std.mem.eql(u8, cmd, "q")) {
                    return true;
                } else if (std.mem.eql(u8, cmd, "help")) {
                    self.message = "j/k scroll | g/G top/bottom | d/u half page | space pgdn | /search | n/N match | :q :N :help";
                } else if (self.parseGotoLine(cmd)) |line_num| {
                    if (line_num > 0 and line_num <= self.lines.len) {
                        const target = line_num - 1;
                        const max_scroll = if (self.lines.len > self.visible_lines) self.lines.len - self.visible_lines else 0;
                        self.scroll = @min(target, max_scroll);
                    } else {
                        self.message = "Invalid line number.";
                    }
                } else {
                    self.message = "Unknown command. Type :help for available commands.";
                }
                self.mode = .normal;
                try self.render();
            },
            127 => {
                if (self.cmd_len > 0) self.cmd_len -= 1;
                try self.renderer.renderCommandLine(self.cmd_buf[0..self.cmd_len]);
            },
            else => {
                if (self.cmd_len < self.cmd_buf.len and c >= 32) {
                    self.cmd_buf[self.cmd_len] = c;
                    self.cmd_len += 1;
                    try self.renderer.renderCommandLine(self.cmd_buf[0..self.cmd_len]);
                }
            },
        }
        return false;
    }

    fn handleSearchMode(self: *App, c: u8) !bool {
        switch (c) {
            '\x1b' => {
                self.mode = .normal;
                self.search_term = "";
                self.message = "";
                try self.render();
            },
            '\r', '\n' => {
                self.search_term = self.search_buf[0..self.search_len];
                self.mode = .normal;
                self.message = "";
                try self.render();
            },
            127 => {
                if (self.search_len > 0) self.search_len -= 1;
                try self.renderer.renderSearchLine(self.search_buf[0..self.search_len]);
            },
            else => {
                if (self.search_len < self.search_buf.len and c >= 32) {
                    self.search_buf[self.search_len] = c;
                    self.search_len += 1;
                    try self.renderer.renderSearchLine(self.search_buf[0..self.search_len]);
                }
            },
        }
        return false;
    }

    fn parseGotoLine(_: *App, cmd: []const u8) ?usize {
        if (cmd.len == 0) return null;
        return std.fmt.parseInt(usize, cmd, 10) catch null;
    }

    fn render(self: *App) !void {
        try self.renderer.render(self.lines, self.scroll, self.visible_lines, self.file, self.message, self.mode, self.search_term);
    }
};
