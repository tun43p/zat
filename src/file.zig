const std = @import("std");
const mime = @import("mime");

const logger = @import("logger.zig").Logger;
const size = @import("size.zig").Size;

const chars = logger.chars;
const style = logger.style;

pub const ZatFile = struct {
    path: []const u8,
    name: []const u8,
    encoding: []const u8,
    mime: []const u8,
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

        const file_ext = std.fs.path.extension(file_path);
        const mime_type = mime.extension_map.get(file_ext) orelse mime.Type.@"text/plain";
        const mime_type_str = @tagName(mime_type);

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
            .encoding = "UTF-8", // TODO: Detect encoding
            .mime = mime_type_str,
            .size = file_size,
            .line_count = line_count,
            .content = buffer,
        };
    }

    pub fn print(self: ZatFile) !void {
        const term_size = size.get(std.fs.File.stdout()) catch |err| {
            std.debug.print("Error getting terminal size: {s}\n", .{@errorName(err)});
            return err;
        };

        if (term_size == null) return error.TerminalSizeNotFound;

        logger.print_pipe(style.red, 5, 1);
        logger.print(style.cyan, style.bold, "{s}", .{self.name});
        logger.print_pipe(style.red, 1, 1);
        logger.print(style.magenta, style.italic, "{s}", .{self.path});
        logger.print(style.reset, null, "\n", .{});

        for (0..term_size.?.width) |_| {
            logger.print_row(style.red);
        }

        var line_num: usize = 1;
        logger.print(style.red, null, "{d: >4} │ ", .{line_num});

        for (self.content) |byte| {
            std.debug.print("{c}", .{byte});
            if (byte == '\n') {
                line_num += 1;
                logger.print(style.red, null, "{d: >4} │ ", .{line_num});
            }
        }

        logger.print(style.reset, null, "\n\n", .{});
        logger.print(style.gray, null, "       {s}", .{self.path});
        logger.print(style.gray, null, " | {s}", .{self.mime});
        logger.print(style.gray, null, " | {d} lines", .{self.line_count});
        logger.print(style.gray, null, " | {d} bytes", .{self.size});
        logger.print(style.gray, null, " | {s}", .{self.encoding});
        logger.print(style.reset, null, "\n", .{});
    }

    pub fn deinit(self: ZatFile, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
    }
};
