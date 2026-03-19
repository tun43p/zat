const std = @import("std");
const mime = @import("mime.zig");

pub const File = struct {
    path: []const u8,
    name: []const u8,
    encoding: []const u8,
    mime: []const u8,
    readable: bool,
    size: u64,
    line_count: usize,
    content: []const u8,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !File {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const file_info = try file.stat();
        const file_size = file_info.size;
        const file_path = try std.fs.cwd().realpathAlloc(allocator, path);
        const file_name = std.fs.path.basename(file_path);
        const file_ext = std.fs.path.extension(file_path);
        const mime_info = mime.fromExtension(file_ext);

        const max_file_size = 50 * 1024 * 1024; // 50 MB
        if (file_size > max_file_size) return error.FileTooLarge;

        if (!mime_info.readable) {
            return File{
                .path = file_path,
                .name = file_name,
                .encoding = "UTF-8",
                .mime = mime_info.mime,
                .readable = false,
                .size = file_size,
                .line_count = 0,
                .content = "",
            };
        }

        const buffer = try allocator.alloc(u8, file_size);
        _ = try file.readAll(buffer);

        var line_count: usize = 0;
        var it = std.mem.splitScalar(u8, buffer, '\n');
        while (it.next()) |_| {
            line_count += 1;
        }

        return File{
            .path = file_path,
            .name = file_name,
            .encoding = "UTF-8",
            .mime = mime_info.mime,
            .readable = true,
            .size = file_size,
            .line_count = line_count,
            .content = buffer,
        };
    }
};

test "File.init returns error for non-existent file" {
    const allocator = std.testing.allocator;
    const result = File.init(allocator, "/tmp/zat_nonexistent_test_file_12345.txt");
    try std.testing.expectError(error.FileNotFound, result);
}
