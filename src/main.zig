const std = @import("std");

const ZatFile = @import("file.zig").ZatFile;
const Tui = @import("tui.zig").Tui;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const file = try ZatFile.init(allocator, "README.md");
    defer file.deinit(allocator);

    var tui = try Tui.init();
    defer tui.deinit(allocator);

    try tui.render(allocator, file);
}
