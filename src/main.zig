const std = @import("std");

const ZatFile = @import("file.zig").ZatFile;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const file = try ZatFile.init(allocator, "LICENSE");
    defer file.deinit(allocator);

    std.debug.print("Path: {s}\n", .{file.path});
    std.debug.print("Name: {s}\n", .{file.name});
    std.debug.print("Size: {}\n", .{file.size});
    std.debug.print("Line count: {}\n", .{file.line_count});

    for (file.content) |byte| {
        std.debug.print("{c}", .{byte});
    }
}
