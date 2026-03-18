const std = @import("std");
const size = @import("size.zig").Size;
const ZatFile = @import("file.zig").ZatFile;

const style = Style;
const chars = Chars;

pub const Tui = struct {
    buffer: std.ArrayList(u8),
    width: u16,
    gutter: usize,

    const default_gutter = 5;

    pub fn init() !Tui {
        const file_size = try size.get(std.fs.File.stdout()) orelse return error.TerminalSizeNotFound;

        return Tui{
            .buffer = .empty,
            .width = file_size.width,
            .gutter = default_gutter,
        };
    }

    pub fn deinit(self: *Tui, allocator: std.mem.Allocator) void {
        self.buffer.deinit(allocator);
    }

    pub fn render(self: *Tui, allocator: std.mem.Allocator, file: ZatFile) !void {
        // try self.add_top_line(allocator);
        // try self.add_header(allocator, file.name, file.path);

        try self.add_middle_line(allocator);

        var line_num: usize = 1;
        var it = std.mem.splitScalar(u8, file.content, '\n');
        while (it.next()) |line| {
            try self.add_line(allocator, line_num, line);
            line_num += 1;
        }

        try self.add_middle_line(allocator);
        try self.add_footer(
            allocator,
            file.name,
            file.path,
            file.mime,
            file.line_count,
            file.size,
            file.encoding,
        );

        try self.add_bottom_line(allocator);
        try self.write();
    }

    fn write(self: *Tui) !void {
        const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
        try stdout.writeAll(self.buffer.items);
    }

    // fn add_top_line(self: *Tui, allocator: std.mem.Allocator) !void {
    //     try self.append_color(allocator, style.red);
    //     try self.append_repeat(allocator, chars.row, self.gutter);
    //     try self.append_str(allocator, chars.up_insertion);
    //     try self.append_repeat(allocator, chars.row, self.width - self.gutter - 1);
    //     try self.append_str(allocator, style.reset ++ "\n");
    // }

    // fn add_header(self: *Tui, allocator: std.mem.Allocator, name: []const u8, path: []const u8) !void {
    //     try self.append_color(allocator, style.red);
    //     try self.append_spaces(allocator, self.gutter);
    //     try self.append_str(allocator, chars.pipe ++ " ");
    //     try self.append_color(allocator, style.cyan ++ style.bold);
    //     try self.append_str(allocator, name);
    //     try self.append_str(allocator, " " ++ style.reset ++ style.gray ++ style.italic);
    //     try self.append_str(allocator, "(");
    //     try self.append_str(allocator, path);
    //     try self.append_str(allocator, ")");
    //     try self.append_str(allocator, style.reset ++ "\n");
    // }

    fn add_middle_line(self: *Tui, allocator: std.mem.Allocator) !void {
        try self.append_color(allocator, style.red);
        try self.append_repeat(allocator, chars.row, self.gutter);
        try self.append_str(allocator, chars.cross);
        try self.append_repeat(allocator, chars.row, self.width - self.gutter - 1);
        try self.append_str(allocator, style.reset ++ "\n");
    }

    fn add_line(self: *Tui, allocator: std.mem.Allocator, line_num: usize, content: []const u8) !void {
        var num_buf: [20]u8 = undefined;
        const num_str = std.fmt.bufPrint(&num_buf, "{d: >4}", .{line_num}) catch "????";

        try self.append_color(allocator, style.red);
        try self.append_str(allocator, num_str);
        try self.append_str(allocator, " " ++ chars.pipe ++ " " ++ style.reset);
        try self.append_str(allocator, content);
        try self.append_str(allocator, "\n");
    }

    fn add_bottom_line(self: *Tui, allocator: std.mem.Allocator) !void {
        try self.append_color(allocator, style.red);
        try self.append_repeat(allocator, chars.row, self.gutter);
        try self.append_str(allocator, chars.down_insertion);
        try self.append_repeat(allocator, chars.row, self.width - self.gutter - 1);
        try self.append_str(allocator, style.reset ++ "\n");
    }

    fn add_footer(self: *Tui, allocator: std.mem.Allocator, name: []const u8, path: []const u8, mime_type: []const u8, line_count: usize, file_size: u64, encoding: []const u8) !void {
        try self.append_color(allocator, style.red);
        try self.append_spaces(allocator, self.gutter);
        try self.append_str(allocator, chars.pipe ++ " ");

        try self.append_color(allocator, style.cyan ++ style.bold);
        try self.append_str(allocator, name);

        try self.append_color(allocator, style.red);
        try self.append_str(allocator, " " ++ chars.pipe ++ " ");

        try self.append_color(allocator, style.gray);
        try self.append_str(allocator, path);

        try self.append_color(allocator, style.red);
        try self.append_str(allocator, " " ++ chars.pipe ++ " ");

        try self.append_color(allocator, style.bright_blue);
        try self.append_str(allocator, mime_type);

        try self.append_color(allocator, style.red);
        try self.append_str(allocator, " " ++ chars.pipe ++ " ");

        try self.append_color(allocator, style.bright_yellow);
        const line_str = std.fmt.allocPrint(allocator, "{d} lines", .{line_count}) catch "0 lines";
        try self.append_str(allocator, line_str);

        try self.append_color(allocator, style.red);
        try self.append_str(allocator, " " ++ chars.pipe ++ " ");

        try self.append_color(allocator, style.bright_cyan);
        const size_str = std.fmt.allocPrint(allocator, "{d} bytes", .{file_size}) catch "0 bytes";
        try self.append_str(allocator, size_str);

        try self.append_color(allocator, style.red);
        try self.append_str(allocator, " " ++ chars.pipe ++ " ");

        try self.append_color(allocator, style.bright_green);
        try self.append_str(allocator, encoding);

        try self.append_str(allocator, style.reset ++ "\n");
    }

    fn append_str(self: *Tui, allocator: std.mem.Allocator, str: []const u8) !void {
        try self.buffer.appendSlice(allocator, str);
    }

    fn append_color(self: *Tui, allocator: std.mem.Allocator, color: []const u8) !void {
        try self.buffer.appendSlice(allocator, color);
    }

    fn append_spaces(self: *Tui, allocator: std.mem.Allocator, count: usize) !void {
        for (0..count) |_| {
            try self.buffer.append(allocator, ' ');
        }
    }

    fn append_repeat(self: *Tui, allocator: std.mem.Allocator, char: []const u8, count: usize) !void {
        for (0..count) |_| {
            try self.buffer.appendSlice(allocator, char);
        }
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
