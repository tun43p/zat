const std = @import("std");

const ZatFile = @import("file.zig").ZatFile;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const file = try ZatFile.init(allocator, "README.md");
    defer file.deinit(allocator);

    try file.print();
}
