const std = @import("std");
const File = @import("file.zig").File;
const syntax = @import("syntax.zig");

pub const Mode = enum { normal, command, search };

const gutter = 5;

const chars = Chars;
const style = Style;

const table_color = style.gray;
const number_color = style.bright_yellow;

// Syntax highlight colors
const comment_color = style.gray;
const string_color = style.green;
const keyword_color = style.magenta;
const type_color = style.bright_yellow;
const number_literal_color = style.bright_cyan;
const builtin_color = style.bright_blue;

pub const Renderer = struct {
    stdout: std.fs.File,
    width: usize,
    height: usize,
    syntax_def: ?syntax.SyntaxDef,

    pub fn init(stdout: std.fs.File, width: usize, height: usize, mime_type: []const u8) Renderer {
        return .{ .stdout = stdout, .width = width, .height = height, .syntax_def = syntax.fromMime(mime_type) };
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

        // Compute code block state from start of file to scroll position
        var in_code_block = false;
        for (0..scroll) |i| {
            const trimmed = std.mem.trimLeft(u8, lines[i], " ");
            if (trimmed.len >= 3 and std.mem.eql(u8, trimmed[0..3], "```")) {
                in_code_block = !in_code_block;
            }
        }

        for (scroll..end) |i| {
            var num_buf: [32]u8 = undefined;
            const num = std.fmt.bufPrint(&num_buf, number_color ++ "{d: >4} " ++ table_color ++ chars.pipe ++ " " ++ style.reset, .{i + 1}) catch continue;
            try self.stdout.writeAll(num);

            const trimmed = std.mem.trimLeft(u8, lines[i], " ");
            const is_fence = trimmed.len >= 3 and std.mem.eql(u8, trimmed[0..3], "```");

            if (is_fence) {
                // The fence line itself is green
                try self.stdout.writeAll(string_color);
                try self.renderWithSearch(lines[i], search);
                try self.stdout.writeAll(style.reset);
                in_code_block = !in_code_block;
            } else if (in_code_block) {
                // Inside code block: all green
                try self.stdout.writeAll(string_color);
                try self.renderWithSearch(lines[i], search);
                try self.stdout.writeAll(style.reset);
            } else {
                try self.renderLineWithHighlight(lines[i], search);
            }
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
        const syn = self.syntax_def orelse {
            // No syntax: just handle search highlight
            try self.renderWithSearch(line, search);
            return;
        };

        // Check for line prefixes (markdown headings, lists, etc.)
        const trimmed = std.mem.trimLeft(u8, line, " ");
        for (syn.line_prefixes) |lp| {
            if (trimmed.len >= lp.prefix.len and std.mem.eql(u8, trimmed[0..lp.prefix.len], lp.prefix)) {
                try self.stdout.writeAll(lp.color);
                try self.renderWithSearch(line, search);
                try self.stdout.writeAll(style.reset);
                return;
            }
        }

        var pos: usize = 0;
        while (pos < line.len) {
            // Check for line comment
            if (syn.line_comment.len > 0 and pos + syn.line_comment.len <= line.len and std.mem.eql(u8, line[pos .. pos + syn.line_comment.len], syn.line_comment)) {
                try self.stdout.writeAll(comment_color);
                try self.renderWithSearch(line[pos..], search);
                try self.stdout.writeAll(style.reset);
                return;
            }

            // Check for string
            if (self.isStringDelim(syn, line[pos])) {
                const delim = line[pos];
                var end = pos + 1;
                while (end < line.len) {
                    if (line[end] == '\\') {
                        end += 2;
                        continue;
                    }
                    if (line[end] == delim) {
                        end += 1;
                        break;
                    }
                    end += 1;
                }
                try self.stdout.writeAll(string_color);
                try self.renderWithSearch(line[pos..end], search);
                try self.stdout.writeAll(style.reset);
                pos = end;
                continue;
            }

            // Check for word (keyword, type, or identifier)
            if (isWordChar(line[pos])) {
                var end = pos;
                while (end < line.len and isWordChar(line[end])) : (end += 1) {}
                const word = line[pos..end];

                const is_at_boundary = (pos == 0 or !isWordChar(line[pos - 1])) and (end >= line.len or !isWordChar(line[end]));

                if (is_at_boundary and self.isBuiltin(syn, word)) {
                    try self.stdout.writeAll(builtin_color);
                    try self.renderWithSearch(word, search);
                    try self.stdout.writeAll(style.reset);
                } else if (is_at_boundary and self.isKeyword(syn, word)) {
                    try self.stdout.writeAll(keyword_color ++ style.bold);
                    try self.renderWithSearch(word, search);
                    try self.stdout.writeAll(style.reset);
                } else if (is_at_boundary and self.isType(syn, word)) {
                    try self.stdout.writeAll(type_color);
                    try self.renderWithSearch(word, search);
                    try self.stdout.writeAll(style.reset);
                } else if (is_at_boundary and isNumberLiteral(word)) {
                    try self.stdout.writeAll(number_literal_color);
                    try self.renderWithSearch(word, search);
                    try self.stdout.writeAll(style.reset);
                } else {
                    try self.renderWithSearch(word, search);
                }
                pos = end;
                continue;
            }

            // Single character (operator, punctuation, etc.)
            try self.renderWithSearch(line[pos .. pos + 1], search);
            pos += 1;
        }
    }

    fn renderWithSearch(self: *const Renderer, text: []const u8, search: []const u8) !void {
        if (search.len == 0) {
            try self.stdout.writeAll(text);
            return;
        }

        var pos: usize = 0;
        while (pos < text.len) {
            if (std.mem.indexOf(u8, text[pos..], search)) |match| {
                try self.stdout.writeAll(text[pos .. pos + match]);
                try self.stdout.writeAll(style.bg_yellow ++ style.black);
                try self.stdout.writeAll(text[pos + match .. pos + match + search.len]);
                try self.stdout.writeAll(style.reset);
                pos += match + search.len;
            } else {
                try self.stdout.writeAll(text[pos..]);
                break;
            }
        }
    }

    fn isStringDelim(_: *const Renderer, syn: syntax.SyntaxDef, c: u8) bool {
        for (syn.string_delims) |d| {
            if (c == d) return true;
        }
        return false;
    }

    fn isBuiltin(_: *const Renderer, syn: syntax.SyntaxDef, word: []const u8) bool {
        for (syn.builtins) |b| {
            if (std.mem.eql(u8, word, b)) return true;
        }
        return false;
    }

    fn isKeyword(_: *const Renderer, syn: syntax.SyntaxDef, word: []const u8) bool {
        for (syn.keywords) |kw| {
            if (std.mem.eql(u8, word, kw)) return true;
        }
        return false;
    }

    fn isType(_: *const Renderer, syn: syntax.SyntaxDef, word: []const u8) bool {
        for (syn.types) |t| {
            if (std.mem.eql(u8, word, t)) return true;
        }
        return false;
    }

    fn isWordChar(c: u8) bool {
        return std.ascii.isAlphanumeric(c) or c == '_' or c == '@';
    }

    fn isNumberLiteral(word: []const u8) bool {
        if (word.len == 0) return false;
        if (std.ascii.isDigit(word[0])) return true;
        // Negative numbers
        if (word[0] == '-' and word.len > 1 and std.ascii.isDigit(word[1])) return true;
        return false;
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
