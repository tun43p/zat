//! File loading and representation.
//!
//! This module is responsible for opening a file from disk, reading its
//! entire content into memory, detecting its MIME type, and splitting the
//! content into individual lines for the renderer.
//!
//! ## Design decisions
//!
//! - The whole file is read at once into a contiguous buffer. This is
//!   simpler and faster than streaming for the typical files Zat is
//!   designed to view (source code, config files, etc.).
//! - A hard limit of **50 MB** prevents accidentally loading huge files
//!   that would consume too much memory.
//! - Binary files (images, archives, etc.) are detected via their MIME
//!   type and flagged as non-readable so the caller can refuse to
//!   display them.

const std = @import("std");
const mime = @import("mime.zig");

/// Represents a loaded file with its metadata and content.
///
/// After calling `File.init`, all fields are populated. If the file is
/// binary (`readable == false`), the `content` and `lines` fields are
/// empty — only the metadata (path, name, MIME type, size) is available.
pub const File = struct {
    /// Absolute path to the file on disk (e.g. "/home/user/project/main.zig").
    path: []const u8,
    /// Base name of the file without directory components (e.g. "main.zig").
    name: []const u8,
    /// Detected MIME type string (e.g. "text/x-zig", "image/png").
    /// Used by the renderer to select the appropriate syntax highlighter.
    mime: []const u8,
    /// Whether the file can be displayed as text. Binary files (images,
    /// archives, executables, etc.) have this set to `false`.
    readable: bool,
    /// File size in bytes, as reported by the filesystem.
    size: u64,
    /// Total number of lines in the file. Zero for binary files.
    line_count: usize,
    /// Raw file content as a single contiguous byte slice.
    /// Empty for binary files.
    content: []const u8,
    /// The file content split into individual lines. Each element is a
    /// slice pointing into `content` — no copies are made.
    /// Empty for binary files.
    lines: []const []const u8,

    /// Opens a file, reads its content, detects its MIME type, and splits
    /// the content into lines.
    ///
    /// ## Parameters
    ///
    /// - `allocator`: The allocator used for all memory allocations (file
    ///   content buffer, lines array, resolved path). Zat uses an arena
    ///   allocator so nothing needs to be freed individually.
    /// - `path`: Relative or absolute path to the file to open.
    ///
    /// ## Errors
    ///
    /// Returns an error if:
    /// - The file cannot be opened (`error.FileNotFound`, `error.AccessDenied`, etc.)
    /// - The file exceeds the 50 MB size limit (`error.FileTooLarge`)
    /// - Memory allocation fails (`error.OutOfMemory`)
    ///
    /// ## Example
    ///
    /// ```zig
    /// const file = try File.init(allocator, "src/main.zig");
    /// // file.lines now contains each line of the file
    /// // file.mime is "text/x-zig"
    /// ```
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !File {
        // Open the file with read-only permissions. The `defer file.close()`
        // ensures the file descriptor is released as soon as we're done
        // reading, even if an error occurs below.
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        // `stat()` retrieves file metadata (size, timestamps, etc.) without
        // reading the content. We use it to know how much memory to allocate.
        const file_info = try file.stat();
        const file_size = file_info.size;

        // Resolve the path to an absolute path so it can be displayed in
        // the header bar regardless of the working directory.
        const file_path = try std.fs.cwd().realpathAlloc(allocator, path);

        // Extract the file name (last path component) and extension for
        // MIME type detection.
        const file_name = std.fs.path.basename(file_path);
        const file_ext = std.fs.path.extension(file_path);

        // Detect the MIME type. Some files without extensions (e.g.
        // "Makefile", "Dockerfile") are identified by their full name.
        // If the name doesn't match, we fall back to extension-based lookup.
        const mime_info = if (file_ext.len == 0)
            mime.fromFilename(file_name) orelse mime.fromExtension(file_ext)
        else
            mime.fromExtension(file_ext);

        // Reject files larger than 50 MB to avoid excessive memory usage.
        const max_file_size = 50 * 1024 * 1024; // 50 MB
        if (file_size > max_file_size) return error.FileTooLarge;

        // For binary files (images, archives, etc.), return early with
        // empty content — we only need the metadata to show the error
        // message to the user.
        if (!mime_info.readable) {
            return File{
                .path = file_path,
                .name = file_name,
                .mime = mime_info.mime,
                .readable = false,
                .size = file_size,
                .line_count = 0,
                .content = "",
                .lines = &.{},
            };
        }

        // Allocate a buffer exactly the size of the file and read the
        // entire content into it in one syscall.
        const buffer = try allocator.alloc(u8, file_size);
        _ = try file.readAll(buffer);

        // Split the content into lines by splitting on newline characters.
        // Each resulting slice points directly into `buffer` — no copies
        // are made, which saves both memory and CPU time.
        var line_list: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, buffer, '\n');
        while (it.next()) |line| {
            try line_list.append(allocator, line);
        }
        const lines = try line_list.toOwnedSlice(allocator);

        return File{
            .path = file_path,
            .name = file_name,
            .mime = mime_info.mime,
            .readable = true,
            .size = file_size,
            .line_count = lines.len,
            .content = buffer,
            .lines = lines,
        };
    }
};

test "File.init returns error for non-existent file" {
    const allocator = std.testing.allocator;
    const result = File.init(allocator, "/tmp/zat_nonexistent_test_file_12345.txt");
    try std.testing.expectError(error.FileNotFound, result);
}
