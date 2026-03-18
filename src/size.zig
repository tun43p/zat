const std = @import("std");
const builtin = @import("builtin");

pub const TermSize = struct {
    width: u16,
    height: u16,

    pub fn get(file: std.fs.File) !?TermSize {
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
                    std.os.windows.TRUE => TermSize{
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
                    std.posix.E.SUCCESS => TermSize{
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

test "get" {
    std.debug.print("termsize {any}", .{TermSize.get(std.io.getStdOut())});
}
