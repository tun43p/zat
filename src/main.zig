const std = @import("std");

const ZatFile = @import("file.zig").ZatFile;
const Tui = @import("tui.zig").Tui;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip();

    const file_path = args.next() orelse {
        std.debug.print("Usage: zat <file>\n", .{});
        return error.MissingArgument;
    };

    const file = try ZatFile.init(allocator, file_path);
    defer file.deinit(allocator);

    var tui = try Tui.init();
    defer tui.deinit(allocator);

    try tui.render(allocator, file);
}
