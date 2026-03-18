const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const file = try ZatFile.init(allocator, "LICENSE");
    defer file.deinit(allocator);

    std.debug.print("Path: {s}\n", .{file.path});
    std.debug.print("Size: {}\n", .{file.size});
    std.debug.print("Line count: {}\n", .{file.line_count});

    for (file.content) |byte| {
        std.debug.print("{c}", .{byte});
    }
}

const ZatFile = struct {
    path: []const u8,
    size: u64,
    line_count: usize,
    content: []const u8,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !ZatFile {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const buffer = try allocator.alloc(u8, file_size);

        _ = try file.readAll(buffer);

        var line_count: usize = 0;
        var it = std.mem.splitScalar(u8, buffer, '\n');
        while (it.next()) |line| {
            _ = line;
            line_count += 1;
        }

        return ZatFile{
            .path = path,
            .size = file_size,
            .line_count = line_count,
            .content = buffer,
        };
    }

    pub fn deinit(self: ZatFile, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
    }
};
