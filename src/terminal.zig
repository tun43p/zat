const std = @import("std");
const builtin = @import("builtin");

pub const Terminal = struct {
    stdin: std.posix.fd_t,
    stdout: std.fs.File,
    reader: std.fs.File,
    original: std.posix.termios,

    pub fn init() !Terminal {
        const stdin = std.posix.STDIN_FILENO;
        const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
        const reader = std.fs.File{ .handle = stdin };

        const original = try std.posix.tcgetattr(stdin);
        var raw = original;
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        try std.posix.tcsetattr(stdin, .FLUSH, raw);

        // Enter alternate screen
        try stdout.writeAll("\x1b[?1049h");

        return .{
            .stdin = stdin,
            .stdout = stdout,
            .reader = reader,
            .original = original,
        };
    }

    pub fn deinit(self: *const Terminal) void {
        // Leave alternate screen
        self.stdout.writeAll("\x1b[?1049l") catch {};

        // Restore terminal
        std.posix.tcsetattr(self.stdin, .FLUSH, self.original) catch {};
    }

    pub fn readKey(self: *const Terminal) ?u8 {
        var buf: [1]u8 = undefined;
        const n = self.reader.read(&buf) catch return null;
        if (n == 0) return null;
        return buf[0];
    }

    pub fn readEscapeSeq(self: *const Terminal) ?u8 {
        var seq: [2]u8 = undefined;
        const n = self.reader.read(&seq) catch return null;
        if (n == 2 and seq[0] == '[') return seq[1];
        return null;
    }
};

pub const TerminalSize = struct {
    width: u16,
    height: u16,

    pub fn get(file: std.fs.File) !?TerminalSize {
        if (!file.supportsAnsiEscapeCodes()) {
            return null;
        }

        return switch (builtin.os.tag) {
            .windows => blk: {
                var buf: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
                break :blk switch (std.os.windows.kernel32.GetConsoleScreenBufferInfo(
                    file.handle,
                    &buf,
                )) {
                    std.os.windows.TRUE => TerminalSize{
                        .width = @intCast(buf.srWindow.Right - buf.srWindow.Left + 1),
                        .height = @intCast(buf.srWindow.Bottom - buf.srWindow.Top + 1),
                    },
                    else => error.Unexpected,
                };
            },
            .linux, .macos => blk: {
                var buf: std.posix.winsize = undefined;
                break :blk switch (std.posix.errno(
                    std.posix.system.ioctl(
                        file.handle,
                        std.posix.T.IOCGWINSZ,
                        @intFromPtr(&buf),
                    ),
                )) {
                    std.posix.E.SUCCESS => TerminalSize{
                        .width = buf.col,
                        .height = buf.row,
                    },
                    else => error.IoctlError,
                };
            },
            else => error.Unsupported,
        };
    }
};
