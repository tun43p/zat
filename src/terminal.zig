//! Low-level terminal management (raw mode, alternate screen, signals, input).
//!
//! This module handles everything related to the terminal itself:
//!
//! - **Raw mode**: disables line buffering and echo so we can read
//!   individual keypresses without the user having to press Enter.
//! - **Alternate screen**: uses the xterm alternate screen buffer
//!   (`\x1b[?1049h`) so the user's scrollback history is preserved
//!   when Zat exits.
//! - **Signal handling**: intercepts `SIGINT` (Ctrl+C) and `SIGTERM`
//!   to restore the terminal before exiting, and `SIGWINCH` to detect
//!   terminal resizes.
//! - **Input reading**: provides methods to read single bytes and
//!   ANSI escape sequences from stdin.
//!
//! ## Important: terminal restoration
//!
//! If the terminal is not restored (raw mode disabled, alternate screen
//! exited), the user's shell will be unusable. That's why:
//! - `deinit` restores everything and is called via `defer` in `main.zig`.
//! - Signal handlers also restore the terminal before calling `exit(1)`.
//!
//! ## Platform support
//!
//! This module uses POSIX APIs (`termios`, `ioctl`) and is compatible with
//! Linux and macOS. Windows support uses the Win32 Console API for size
//! detection only.

const std = @import("std");
const builtin = @import("builtin");

// Module-level state for signal handlers
//
// Signal handlers in C/POSIX cannot capture closures or access struct
// fields — they can only access global/static state. These module-level
// variables store the original terminal settings and resize flag so the
// signal handlers can access them.

/// Backup of the original terminal settings, used to restore the terminal
/// in signal handlers and in `deinit`.
var saved_termios: std.posix.termios = undefined;

/// Whether `saved_termios` has been populated. Prevents the signal handler
/// from restoring garbage state if a signal arrives before `init`.
var termios_saved: bool = false;

/// Flag set by the `SIGWINCH` handler when the terminal is resized.
/// The main loop polls this via `checkResized()` to trigger a re-render.
var terminal_resized: bool = false;

/// Signal handler for `SIGINT` (Ctrl+C) and `SIGTERM`.
///
/// Restores the terminal to its original state (exits alternate screen,
/// restores termios settings) before terminating the process. Without
/// this, the user's shell would remain in raw mode after a Ctrl+C.
///
/// The `callconv(.c)` annotation is required because POSIX signal
/// handlers must follow the C calling convention.
fn signalHandler(_: c_int) callconv(.c) void {
    if (termios_saved) {
        // Exit the alternate screen buffer so the user's scrollback
        // is visible again.
        const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
        stdout.writeAll("\x1b[?1049l") catch {};
        // Restore the original terminal settings (echo, canonical mode, etc.).
        std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, saved_termios) catch {};
    }
    std.posix.exit(1);
}

/// Signal handler for `SIGWINCH` (window size change).
///
/// Simply sets a flag that the main loop will check. We cannot do any
/// complex work in a signal handler (no allocations, no I/O), so we
/// defer the actual resize handling to the main loop.
fn winchHandler(_: c_int) callconv(.c) void {
    terminal_resized = true;
}

/// Manages the terminal state for interactive use.
///
/// On creation (`init`), it:
/// 1. Saves the current terminal settings (so they can be restored later)
/// 2. Switches stdin to **raw mode** (no echo, no line buffering)
/// 3. Installs signal handlers for clean shutdown
/// 4. Enters the **alternate screen buffer**
///
/// On destruction (`deinit`), it reverses all of the above.
pub const Terminal = struct {
    /// File descriptor for stdin (typically 0). Used to read keypresses
    /// and to restore terminal settings.
    stdin: std.posix.fd_t,
    /// Handle to stdout as a `std.fs.File`. Used for writing output and
    /// querying the terminal size.
    stdout: std.fs.File,
    /// Handle to stdin as a `std.fs.File`. Used by `readKey` and
    /// `readEscapeSeq` to read individual bytes from the input stream.
    reader: std.fs.File,
    /// The original terminal settings saved at init time. Restored by
    /// `deinit` and by the signal handlers.
    original: std.posix.termios,

    /// Initializes the terminal for interactive use.
    ///
    /// This function:
    /// 1. Reads the current terminal attributes via `tcgetattr`.
    /// 2. Creates a copy with `ECHO` and `ICANON` disabled (raw mode).
    /// 3. Applies the raw settings via `tcsetattr`.
    /// 4. Saves the original settings for signal handlers.
    /// 5. Installs `SIGINT`/`SIGTERM` handlers to ensure clean shutdown.
    /// 6. Installs a `SIGWINCH` handler to detect terminal resizes.
    /// 7. Enters the alternate screen buffer via the ANSI escape `\x1b[?1049h`.
    ///
    /// ## Errors
    ///
    /// Returns an error if `tcgetattr` or `tcsetattr` fails (e.g. if
    /// stdin is not a terminal).
    pub fn init() !Terminal {
        const stdin = std.posix.STDIN_FILENO;
        const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
        const reader = std.fs.File{ .handle = stdin };

        // Read the current terminal attributes. This captures settings like
        // echo mode, canonical mode, baud rate, etc.
        const original = try std.posix.tcgetattr(stdin);

        // Create a modified copy with:
        // - ECHO disabled: typed characters are not printed back to the screen
        //   (we handle display ourselves)
        // - ICANON disabled: input is available byte-by-byte instead of
        //   line-by-line (no need to press Enter)
        var raw = original;
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        try std.posix.tcsetattr(stdin, .FLUSH, raw);

        // Save the original settings in module-level state so the signal
        // handler can restore them if the process is interrupted.
        saved_termios = original;
        termios_saved = true;

        // Signal handlers
        // Install a handler for SIGINT (Ctrl+C) and SIGTERM (kill) that
        // restores the terminal before exiting.
        const sigact = std.posix.Sigaction{
            .handler = .{ .handler = signalHandler },
            .mask = std.posix.sigemptyset(),
            .flags = 0,
        };
        std.posix.sigaction(std.posix.SIG.INT, &sigact, null);
        std.posix.sigaction(std.posix.SIG.TERM, &sigact, null);

        // Install a handler for SIGWINCH (terminal resize). This signal
        // is sent by the terminal emulator whenever the window size changes.
        const winch_act = std.posix.Sigaction{
            .handler = .{ .handler = winchHandler },
            .mask = std.posix.sigemptyset(),
            .flags = 0,
        };
        std.posix.sigaction(std.posix.SIG.WINCH, &winch_act, null);

        // Enter the alternate screen buffer. This is the same mechanism
        // used by programs like `vim`, `less`, and `htop`. When we exit
        // the alternate screen, the user's previous terminal content
        // (command history, etc.) reappears untouched.
        try stdout.writeAll("\x1b[?1049h");

        return .{
            .stdin = stdin,
            .stdout = stdout,
            .reader = reader,
            .original = original,
        };
    }

    /// Restores the terminal to its original state.
    ///
    /// This must be called when the application exits (typically via
    /// `defer` in `main.zig`). It:
    /// 1. Exits the alternate screen buffer (`\x1b[?1049l`)
    /// 2. Restores the original terminal attributes (echo, canonical mode)
    ///
    /// Errors are silently ignored because this runs during cleanup —
    /// there's nothing useful we can do if restoration fails.
    pub fn deinit(self: *const Terminal) void {
        // Leave the alternate screen buffer, restoring the user's
        // previous terminal content.
        self.stdout.writeAll("\x1b[?1049l") catch {};

        // Restore the original terminal settings (re-enables echo,
        // canonical mode, etc.).
        std.posix.tcsetattr(self.stdin, .FLUSH, self.original) catch {};
    }

    /// Checks whether the terminal has been resized since the last call.
    ///
    /// This polls the `terminal_resized` flag set by the `SIGWINCH`
    /// signal handler. The flag is reset after reading, so subsequent
    /// calls return `false` until the next resize event.
    ///
    /// The main loop calls this on every iteration to decide whether
    /// to query the new terminal size and re-render.
    pub fn checkResized(_: *const Terminal) bool {
        if (terminal_resized) {
            terminal_resized = false;
            return true;
        }
        return false;
    }

    /// Reads a single byte from stdin (blocking).
    ///
    /// Returns the byte read, or `null` if the read fails or returns
    /// zero bytes (EOF). In raw mode, each keypress produces one or
    /// more bytes immediately — no Enter key needed.
    ///
    /// For regular ASCII keys, this returns the character directly.
    /// For special keys (arrows, function keys, etc.), the terminal
    /// sends a multi-byte **escape sequence** starting with `\x1b` (ESC).
    /// The caller should check for `\x1b` and then call `readEscapeSeq`
    /// to decode the rest.
    pub fn readKey(self: *const Terminal) ?u8 {
        var buf: [1]u8 = undefined;
        const n = self.reader.read(&buf) catch return null;
        if (n == 0) return null;
        return buf[0];
    }

    /// Reads and decodes a 2-byte ANSI escape sequence after the initial
    /// `\x1b` (ESC) byte has already been consumed by `readKey`.
    ///
    /// ANSI escape sequences for arrow keys follow the pattern:
    /// `\x1b [ <code>`, where `<code>` is:
    /// - `'A'` = Up arrow
    /// - `'B'` = Down arrow
    /// - `'C'` = Right arrow
    /// - `'D'` = Left arrow
    ///
    /// This function reads the `[` and `<code>` bytes and returns the
    /// code byte. Returns `null` if the sequence is malformed or if the
    /// read fails.
    pub fn readEscapeSeq(self: *const Terminal) ?u8 {
        // Read the first byte after ESC — it should be '[' for CSI
        // (Control Sequence Introducer) sequences.
        var b1: [1]u8 = undefined;
        const n1 = self.reader.read(&b1) catch return null;
        if (n1 == 0 or b1[0] != '[') return null;

        // Read the actual command byte (e.g. 'A' for up arrow).
        var b2: [1]u8 = undefined;
        const n2 = self.reader.read(&b2) catch return null;
        if (n2 == 0) return null;
        return b2[0];
    }
};

/// Represents the dimensions of the terminal window in character cells.
pub const TerminalSize = struct {
    /// Number of columns (characters per line).
    width: u16,
    /// Number of rows (lines visible on screen).
    height: u16,

    /// Queries the current terminal size from the operating system.
    ///
    /// ## Platform behavior
    ///
    /// - **Linux / macOS**: Uses the `TIOCGWINSZ` ioctl to query the
    ///   kernel for the window size.
    /// - **Windows**: Uses `GetConsoleScreenBufferInfo` from the Win32 API.
    ///
    /// ## Returns
    ///
    /// - A `TerminalSize` with the current dimensions on success.
    /// - `null` if the file handle does not support ANSI escape codes
    ///   (e.g. when stdout is redirected to a file or pipe).
    /// - An error if the underlying system call fails.
    pub fn get(file: std.fs.File) !?TerminalSize {
        // If the output is not a terminal (e.g. piped to a file), there
        // is no meaningful window size to query.
        if (!file.supportsAnsiEscapeCodes()) {
            return null;
        }

        return switch (builtin.os.tag) {
            .windows => blk: {
                // Windows uses the Console API to get screen buffer info.
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
                // On Unix, TIOCGWINSZ is an ioctl that fills a `winsize`
                // struct with the terminal's column and row count.
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
