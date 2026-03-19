const std = @import("std");
const mime = @import("mime");

pub const File = struct {
    path: []const u8,
    name: []const u8,
    encoding: []const u8,
    mime: []const u8,
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
        const mime_type = mime.extension_map.get(file_ext) orelse mime.Type.@"text/plain";
        var mime_type_str = @tagName(mime_type);

        // TODO: Add more file types
        if (std.mem.eql(u8, mime_type_str, "text/plain") and std.mem.eql(u8, file_ext, ".md")) {
            mime_type_str = "text/markdown";
        } else if (std.mem.eql(u8, mime_type_str, "text/plain") and std.mem.eql(u8, file_ext, ".zig")) {
            mime_type_str = "text/zig";
        }

        const buffer = try allocator.alloc(u8, file_size);

        _ = try file.readAll(buffer);

        var line_count: usize = 0;
        var it = std.mem.splitScalar(u8, buffer, '\n');
        while (it.next()) |line| {
            _ = line;
            line_count += 1;
        }

        return File{
            .path = file_path,
            .name = file_name,
            .encoding = "UTF-8", // TODO: Detect encoding
            .mime = mime_type_str,
            .size = file_size,
            .line_count = line_count,
            .content = buffer,
        };
    }

    pub fn deinit(self: File, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
    }
};
