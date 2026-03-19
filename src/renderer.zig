const std = @import("std");
const File = @import("file.zig").File;

pub const Mode = enum { normal, command, search };

const gutter = 5;

const chars = Chars;
const style = Style;

const table_color = style.gray;
const number_color = style.bright_yellow;

pub const Renderer = struct {
    stdout: std.fs.File,
    width: usize,
    height: usize,

    pub fn init(stdout: std.fs.File, width: usize, height: usize) Renderer {
        return .{ .stdout = stdout, .width = width, .height = height };
    }

    pub fn render(self: *const Renderer, lines: []const []const u8, scroll: usize, visible_lines: usize, file: File, message: []const u8, mode: Mode, search: []const u8) !void {
        // Cursor to top-left + clear screen
        try self.stdout.writeAll("\x1b[H\x1b[2J");

        try self.renderTopLine();
        try self.renderHeader(scroll, file);
        try self.renderSeparator();
        try self.renderLines(lines, scroll, visible_lines, search);
        try self.renderFooter(message, mode, search);
        try self.renderBottomLine();
    }

    fn renderTopLine(self: *const Renderer) !void {
        try self.stdout.writeAll(table_color);
        for (0..gutter) |_| try self.stdout.writeAll(chars.row);
        try self.stdout.writeAll(chars.up_insertion);
        for (0..self.width - gutter - 1) |_| try self.stdout.writeAll(chars.row);
        try self.stdout.writeAll(style.reset ++ "\r\n");
    }

    fn renderHeader(self: *const Renderer, scroll: usize, file: File) !void {
        try self.stdout.writeAll(table_color);
        for (0..gutter) |_| try self.stdout.writeAll(" ");
        try self.stdout.writeAll(chars.pipe ++ " ");

        // File name
        try self.stdout.writeAll(style.cyan ++ style.bold);
        try self.stdout.writeAll(file.name);
        try self.stdout.writeAll(style.reset);

        // File mime
        try self.stdout.writeAll(table_color ++ " " ++ chars.pipe ++ " ");
        try self.stdout.writeAll(style.bright_blue);
        try self.stdout.writeAll(file.mime);

        // File lines
        try self.stdout.writeAll(table_color ++ " " ++ chars.pipe ++ " ");
        try self.stdout.writeAll(number_color);
        var lines_buf: [32]u8 = undefined;
        const lines_str = std.fmt.bufPrint(&lines_buf, "{d}/{d} lines", .{ scroll + 1, file.line_count }) catch "?";
        try self.stdout.writeAll(lines_str);

        // File size
        try self.stdout.writeAll(table_color ++ " " ++ chars.pipe ++ " ");
        try self.stdout.writeAll(style.bright_cyan);
        var size_buf: [32]u8 = undefined;
        const size_str = std.fmt.bufPrint(&size_buf, "{d} bytes", .{file.size}) catch "?";
        try self.stdout.writeAll(size_str);

        // File encoding
        try self.stdout.writeAll(table_color ++ " " ++ chars.pipe ++ " ");
        try self.stdout.writeAll(style.bright_green);
        try self.stdout.writeAll(file.encoding);
        try self.stdout.writeAll(style.reset ++ "\r\n");
    }

    fn renderSeparator(self: *const Renderer) !void {
        try self.stdout.writeAll(table_color);
        for (0..gutter) |_| try self.stdout.writeAll(chars.row);
        try self.stdout.writeAll(chars.cross);
        for (0..self.width - gutter - 1) |_| try self.stdout.writeAll(chars.row);
        try self.stdout.writeAll(style.reset ++ "\r\n");
    }

    fn renderLines(self: *const Renderer, lines: []const []const u8, scroll: usize, visible_lines: usize, search: []const u8) !void {
        const end = @min(scroll + visible_lines, lines.len);
        for (scroll..end) |i| {
            var num_buf: [32]u8 = undefined;
            const num = std.fmt.bufPrint(&num_buf, number_color ++ "{d: >4} " ++ table_color ++ chars.pipe ++ " " ++ style.reset, .{i + 1}) catch continue;
            try self.stdout.writeAll(num);
            try self.renderLineWithHighlight(lines[i], search);
            try self.stdout.writeAll("\r\n");
        }

        // Fill remaining empty lines with gutter
        const rendered = end - scroll;
        if (rendered < visible_lines) {
            for (0..visible_lines - rendered) |_| {
                try self.stdout.writeAll(table_color);
                for (0..gutter) |_| try self.stdout.writeAll(" ");
                try self.stdout.writeAll(chars.pipe ++ style.reset ++ "\r\n");
            }
        }
    }

    fn renderLineWithHighlight(self: *const Renderer, line: []const u8, search: []const u8) !void {
        if (search.len == 0) {
            try self.stdout.writeAll(line);
            return;
        }

        var pos: usize = 0;
        while (pos < line.len) {
            if (std.mem.indexOf(u8, line[pos..], search)) |match| {
                // Text before match
                try self.stdout.writeAll(line[pos .. pos + match]);
                // Highlighted match
                try self.stdout.writeAll(style.bg_yellow ++ style.black);
                try self.stdout.writeAll(line[pos + match .. pos + match + search.len]);
                try self.stdout.writeAll(style.reset);
                pos += match + search.len;
            } else {
                // Rest of line
                try self.stdout.writeAll(line[pos..]);
                break;
            }
        }
    }

    fn renderFooter(self: *const Renderer, message: []const u8, mode: Mode, search: []const u8) !void {
        // Move cursor to footer position (3 lines from bottom: separator + content + bottom line)
        var pos_buf: [32]u8 = undefined;
        const pos = std.fmt.bufPrint(&pos_buf, "\x1b[{d};1H", .{self.height - 2}) catch return;
        try self.stdout.writeAll(pos);

        // Footer separator (with gutter like header)
        try self.stdout.writeAll(table_color);
        for (0..gutter) |_| try self.stdout.writeAll(chars.row);
        try self.stdout.writeAll(chars.cross);
        for (0..self.width - gutter - 1) |_| try self.stdout.writeAll(chars.row);
        try self.stdout.writeAll(style.reset ++ "\r\n");

        // Footer content (with gutter like header)
        try self.stdout.writeAll(table_color);
        for (0..gutter) |_| try self.stdout.writeAll(" ");
        try self.stdout.writeAll(chars.pipe ++ " ");
        if (message.len > 0) {
            try self.stdout.writeAll(style.gray);
            try self.stdout.writeAll(message);
            try self.stdout.writeAll(style.reset);
        } else if (search.len > 0) {
            try self.stdout.writeAll(style.gray ++ "Search: " ++ style.reset);
            try self.stdout.writeAll(style.bg_yellow ++ style.black);
            try self.stdout.writeAll(search);
            try self.stdout.writeAll(style.reset);
            try self.stdout.writeAll(style.gray ++ " (press Esc to clear, n/N to navigate)" ++ style.reset);
        } else if (mode == .normal) {
            try self.stdout.writeAll(style.gray ++ "Press : to enter COMMAND mode or / to enter SEARCH mode" ++ style.reset);
        }
        try self.stdout.writeAll("\r\n");
    }

    fn renderBottomLine(self: *const Renderer) !void {
        try self.stdout.writeAll(table_color);
        for (0..gutter) |_| try self.stdout.writeAll(chars.row);
        try self.stdout.writeAll(chars.down_insertion);
        for (0..self.width - gutter - 1) |_| try self.stdout.writeAll(chars.row);
        try self.stdout.writeAll(style.reset);
    }

    pub fn renderCommandLine(self: *const Renderer, cmd: []const u8) !void {
        var pos_buf: [32]u8 = undefined;
        const pos = std.fmt.bufPrint(&pos_buf, "\x1b[{d};1H", .{self.height - 1}) catch return;
        try self.stdout.writeAll(pos);
        try self.stdout.writeAll("\x1b[2K");
        try self.stdout.writeAll(table_color);
        for (0..gutter) |_| try self.stdout.writeAll(" ");
        try self.stdout.writeAll(chars.pipe ++ " " ++ style.reset ++ ":");
        try self.stdout.writeAll(cmd);
    }

    pub fn renderSearchLine(self: *const Renderer, query: []const u8) !void {
        var pos_buf: [32]u8 = undefined;
        const pos = std.fmt.bufPrint(&pos_buf, "\x1b[{d};1H", .{self.height - 1}) catch return;
        try self.stdout.writeAll(pos);
        try self.stdout.writeAll("\x1b[2K");
        try self.stdout.writeAll(table_color);
        for (0..gutter) |_| try self.stdout.writeAll(" ");
        try self.stdout.writeAll(chars.pipe ++ " " ++ style.reset ++ "/");
        try self.stdout.writeAll(query);
    }
};

const Chars = struct {
    pub const pipe = "│";
    pub const row = "─";

    pub const up_insertion = "┬";
    pub const down_insertion = "┴";
    pub const left_insertion = "├";
    pub const right_insertion = "┤";

    pub const cross = "┼";
};

const Style = struct {
    // Styles
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const dim = "\x1b[2m";
    pub const italic = "\x1b[3m";
    pub const underline = "\x1b[4m";
    pub const strikethrough = "\x1b[9m";

    // Standard colors
    pub const black = "\x1b[30m";
    pub const red = "\x1b[31m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
    pub const magenta = "\x1b[35m";
    pub const cyan = "\x1b[36m";
    pub const white = "\x1b[37m";
    pub const gray = "\x1b[90m";

    // Bright colors
    pub const bright_red = "\x1b[91m";
    pub const bright_green = "\x1b[92m";
    pub const bright_yellow = "\x1b[93m";
    pub const bright_blue = "\x1b[94m";
    pub const bright_magenta = "\x1b[95m";
    pub const bright_cyan = "\x1b[96m";
    pub const bright_white = "\x1b[97m";

    // Background colors
    pub const bg_black = "\x1b[40m";
    pub const bg_red = "\x1b[41m";
    pub const bg_green = "\x1b[42m";
    pub const bg_yellow = "\x1b[43m";
    pub const bg_blue = "\x1b[44m";
    pub const bg_magenta = "\x1b[45m";
    pub const bg_cyan = "\x1b[46m";
    pub const bg_white = "\x1b[47m";
};
