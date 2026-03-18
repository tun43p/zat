const std = @import("std");

pub const ZatFile = struct {
    path: []const u8,
    name: []const u8,
    size: u64,
    line_count: usize,
    content: []const u8,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !ZatFile {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const file_info = try file.stat();
        const file_size = file_info.size;
        const file_path = try std.fs.cwd().realpathAlloc(allocator, path);
        const file_name = std.fs.path.basename(file_path);

        const buffer = try allocator.alloc(u8, file_size);

        _ = try file.readAll(buffer);

        var line_count: usize = 0;
        var it = std.mem.splitScalar(u8, buffer, '\n');
        while (it.next()) |line| {
            _ = line;
            line_count += 1;
        }

        return ZatFile{
            .path = file_path,
            .name = file_name,
            .size = file_size,
            .line_count = line_count,
            .content = buffer,
        };
    }

    pub fn deinit(self: ZatFile, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
    }
};
