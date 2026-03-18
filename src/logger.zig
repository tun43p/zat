const std = @import("std");

pub const Logger = struct {
    pub const style = Style;
    pub const chars = Chars;

    // Print text with optional color and style
    pub fn print(comptime color_: ?[]const u8, comptime style_: ?[]const u8, comptime fmt: []const u8, args: anytype) void {
        const c = color_ orelse Style.white;
        const s = style_ orelse "";

        std.debug.print(c ++ s ++ fmt ++ Style.reset, args);
    }

    // Print pipe character with optional color
    // TODO: Add a param to precise to number of spaces before and after the pipe
    pub fn print_pipe(comptime color_: ?[]const u8, comptime spaces_before: usize, comptime spaces_after: usize) void {
        const c = color_ orelse Style.red;

        var i: usize = 0;
        while (i < spaces_before) : (i += 1) {
            std.debug.print(" ", .{});
        }

        std.debug.print(c ++ Chars.pipe, .{});

        i = 0;
        while (i < spaces_after) : (i += 1) {
            std.debug.print(" ", .{});
        }

        std.debug.print(Style.reset, .{});
    }

    // Print row character with optional color
    pub fn print_row(comptime color_: ?[]const u8) void {
        const c = color_ orelse Style.red;
        std.debug.print(c ++ Chars.row ++ Style.reset, .{});
    }
};

const Chars = struct {
    pub const pipe = "|";
    pub const row = "─";

    pub const up_insertion = "┬";
    pub const down_insertion = "┴";
    pub const left_insertion = "├";
    pub const right_insertion = "┤";
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
