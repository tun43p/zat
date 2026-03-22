//! Application controller — ties together input handling, state management,
//! and rendering.
//!
//! The `App` struct is the heart of Zat. It owns the application state
//! (scroll position, current mode, command/search buffers) and implements
//! the main event loop:
//!
//! ```
//! ┌──────────┐     ┌──────────┐     ┌──────────┐
//! │  Render  │────▶│ Wait for │────▶│ Handle   │
//! │  screen  │     │ keypress │     │ keypress │
//! └──────────┘     └──────────┘     └──────────┘
//!       ▲                                 │
//!       └─────────────────────────────────┘
//! ```
//!
//! ## Modes
//!
//! The application has three modes (see `renderer.Mode`):
//!
//! - **Normal mode**: The default. Arrow keys / `j`/`k` scroll, `g`/`G`
//!   jump to top/bottom, `d`/`u` half-page scroll, `Space` page down,
//!   `n`/`N` navigate search matches.
//!
//! - **Command mode** (`:` key): The user types a command. Supported
//!   commands: `q` (quit), `help` (show keybindings), or a number (go
//!   to line N).
//!
//! - **Search mode** (`/` key): The user types a search term. Press
//!   Enter to confirm, Escape to cancel. Once confirmed, `n`/`N` jump
//!   between matches.
//!
//! ## Architecture
//!
//! `App` delegates all rendering to `Renderer` and all terminal I/O to
//! `Terminal`. It focuses purely on state management and input dispatch.

const std = @import("std");

const File = @import("file.zig").File;
const Mode = @import("renderer.zig").Mode;
const Renderer = @import("renderer.zig").Renderer;
const Terminal = @import("terminal.zig").Terminal;
const TerminalSize = @import("terminal.zig").TerminalSize;

fn toLower(buf: []const u8, input: []const u8) []const u8 {
    const len = @min(buf.len, input.len);
    for (0..len) |i| {
        buf[i] = std.ascii.toLower(input[i]);
    }
    return buf[0..len];
}

/// The main application struct. Manages state and drives the event loop.
pub const App = struct {
    /// All lines of the loaded file (shared reference, not owned).
    lines: []const []const u8,
    /// Per-line state indicating whether each line is inside a Markdown
    /// fenced code block. Used by the renderer to skip syntax highlighting
    /// for code block content. Precomputed at init time.
    code_block_states: []const bool,
    /// The loaded file with its metadata (name, path, MIME type, size).
    file: File,
    /// The terminal handle for reading input and querying size.
    term: Terminal,
    /// The rendering engine that draws the TUI to the terminal.
    renderer: Renderer,
    /// Number of content lines that fit in the terminal (total height
    /// minus borders, header, and footer — typically `height - 6`).
    visible_lines: usize,

    /// Current scroll offset: the index of the first visible line (0-based).
    /// Ranges from 0 to `lines.len - visible_lines`.
    scroll: usize = 0,
    /// Current interaction mode (normal, command, or search).
    mode: Mode = .normal,
    /// Buffer for the command being typed in command mode (`:` prefix).
    /// Fixed-size stack buffer — commands longer than 256 chars are silently
    /// truncated.
    cmd_buf: [256]u8 = undefined,
    /// Number of valid bytes in `cmd_buf`.
    cmd_len: usize = 0,
    /// Status message displayed in the footer. Empty means no message.
    /// Set by command handlers (e.g. help text, error messages) and
    /// cleared on mode transitions.
    message: []const u8 = "",
    /// Buffer for the search term being typed in search mode (`/` prefix).
    search_buf: [256]u8 = undefined,
    /// Number of valid bytes in `search_buf`.
    search_len: usize = 0,
    /// The confirmed search term (points into `search_buf`). Empty means
    /// no active search. Set when the user presses Enter in search mode.
    search_term: []const u8 = "",

    /// Initializes the application with the given file, terminal, and writer.
    ///
    /// This function:
    /// 1. Queries the terminal size to determine how many lines are visible.
    /// 2. Precomputes code block state for each line (for Markdown files).
    /// 3. Creates the renderer with the appropriate syntax definition.
    ///
    /// ## Parameters
    ///
    /// - `allocator`: Used for the code block state array. Uses the arena
    ///   allocator from `main.zig`, so no manual freeing is needed.
    /// - `file`: The loaded file to display.
    /// - `term`: The initialized terminal (already in raw mode).
    /// - `writer`: The buffered stdout writer for rendering output.
    ///
    /// ## Errors
    ///
    /// Returns `error.TerminalSizeNotFound` if the terminal dimensions
    /// cannot be determined (e.g. stdout is not a terminal).
    pub fn init(allocator: std.mem.Allocator, file: File, term: Terminal, writer: *std.io.Writer) !App {
        const term_size = try TerminalSize.get(term.stdout) orelse return error.TerminalSizeNotFound;

        // Reserve 6 rows for the UI chrome: top border, header, header
        // separator, footer separator, footer content, bottom border.
        const visible_lines: usize = if (term_size.height > 6) term_size.height - 6 else 1;

        // Precompute whether each line is inside a Markdown fenced code
        // block. This is a simple toggle: every time we see a line
        // starting with ``` (after trimming spaces), we flip the state.
        // This state is passed to the renderer so it can skip syntax
        // highlighting inside code blocks and render them in green instead.
        var cb_states: std.ArrayList(bool) = .empty;
        var in_code_block = false;
        for (file.lines) |line| {
            const trimmed = std.mem.trimLeft(u8, line, " ");
            if (trimmed.len >= 3 and std.mem.eql(u8, trimmed[0..3], "```")) {
                in_code_block = !in_code_block;
            }
            try cb_states.append(allocator, in_code_block);
        }

        return .{
            .lines = file.lines,
            .code_block_states = try cb_states.toOwnedSlice(allocator),
            .file = file,
            .term = term,
            .renderer = Renderer.init(writer, term_size.width, term_size.height, file.mime),
            .visible_lines = visible_lines,
        };
    }

    /// Runs the main event loop.
    ///
    /// This is the core of the application. It:
    /// 1. Performs an initial render of the screen.
    /// 2. Enters a loop that reads one keypress at a time.
    /// 3. On each keypress, checks if the terminal was resized (via
    ///    `SIGWINCH`) and updates dimensions if needed.
    /// 4. Dispatches the keypress to the appropriate handler based on
    ///    the current mode (normal, command, or search).
    /// 5. Exits when the handler returns `true` (quit signal) or when
    ///    `readKey` returns `null` (EOF / error).
    pub fn run(self: *App) !void {
        // Initial render — show the file content immediately.
        try self.render();

        while (true) {
            // Block until the user presses a key (or EOF).
            const c = self.term.readKey() orelse break;

            // Check if the terminal was resized while waiting for input.
            // If so, update the renderer dimensions and visible line count,
            // then re-render to fill the new window size.
            if (self.term.checkResized()) {
                if (TerminalSize.get(self.term.stdout) catch null) |new_size| {
                    self.renderer.width = new_size.width;
                    self.renderer.height = new_size.height;
                    self.visible_lines = if (new_size.height > 6) new_size.height - 6 else 1;
                    try self.render();
                }
            }

            // Dispatch the keypress to the handler for the current mode.
            // Each handler returns `true` if the application should quit.
            const should_quit = switch (self.mode) {
                .normal => try self.handleNormalMode(c),
                .command => try self.handleCommandMode(c),
                .search => try self.handleSearchMode(c),
            };

            if (should_quit) break;
        }
    }

    /// Handles a keypress in normal mode.
    ///
    /// ## Keybindings
    ///
    /// | Key         | Action                              |
    /// |-------------|-------------------------------------|
    /// | `j` / Down  | Scroll down one line                |
    /// | `k` / Up    | Scroll up one line                  |
    /// | `g`         | Jump to the first line              |
    /// | `G`         | Jump to the last line               |
    /// | `d`         | Scroll down half a page             |
    /// | `u`         | Scroll up half a page               |
    /// | `Space`     | Scroll down one full page           |
    /// | `n`         | Jump to next search match           |
    /// | `N`         | Jump to previous search match       |
    /// | `:`         | Enter command mode                  |
    /// | `/`         | Enter search mode                   |
    /// | `Escape`    | Clear active search                 |
    ///
    /// Returns `false` (never quits from normal mode — only command mode
    /// can trigger a quit via `:q`).
    fn handleNormalMode(self: *App, c: u8) !bool {
        switch (c) {
            // Scrolling
            'j' => {
                // Scroll down one line (if not already at the bottom).
                if (self.scroll + self.visible_lines < self.lines.len) self.scroll += 1;
                try self.render();
            },
            'k' => {
                // Scroll up one line (if not already at the top).
                if (self.scroll > 0) self.scroll -= 1;
                try self.render();
            },
            'g' => {
                // Jump to the very first line.
                self.scroll = 0;
                try self.render();
            },
            'G' => {
                // Jump to the last line (so the last line is visible at
                // the bottom of the screen).
                self.scroll = if (self.lines.len > self.visible_lines) self.lines.len - self.visible_lines else 0;
                try self.render();
            },
            'd' => {
                // Scroll down by half a page. Clamped to the maximum
                // scroll position to prevent scrolling past the end.
                const half = self.visible_lines / 2;
                const max_scroll = if (self.lines.len > self.visible_lines) self.lines.len - self.visible_lines else 0;
                self.scroll = @min(self.scroll + half, max_scroll);
                try self.render();
            },
            'u' => {
                // Scroll up by half a page. Uses saturating subtraction
                // to prevent underflow (scroll is `usize`, unsigned).
                const half = self.visible_lines / 2;
                self.scroll = if (self.scroll > half) self.scroll - half else 0;
                try self.render();
            },
            'q' => return true,
            ' ' => {
                // Scroll down by one full page.
                const max_scroll = if (self.lines.len > self.visible_lines) self.lines.len - self.visible_lines else 0;
                self.scroll = @min(self.scroll + self.visible_lines, max_scroll);
                try self.render();
            },

            // Search navigation
            'n' => {
                // Jump to the next search match (forward from current scroll).
                if (self.search_term.len > 0) {
                    var i = self.scroll + 1;
                    while (i < self.lines.len) : (i += 1) {
                        var line_lower_buf: [4096]u8 = undefined;
                        var search_lower_buf: [256]u8 = undefined;
                        const line_lower = toLower(&line_lower_buf, self.lines[i]);
                        const search_lower = toLower(&search_lower_buf, self.search_term);
                        if (std.mem.indexOf(u8, line_lower, search_lower) != null) {
                            // Position the matched line at the top of the screen,
                            // but don't scroll past the end.
                            self.scroll = if (i + self.visible_lines <= self.lines.len) i else self.lines.len - self.visible_lines;
                            break;
                        }
                    }
                    try self.render();
                }
            },
            'N' => {
                // Jump to the previous search match (backward from current scroll).
                if (self.search_term.len > 0 and self.scroll > 0) {
                    var i = self.scroll - 1;
                    while (true) {
                        var line_lower_buf: [4096]u8 = undefined;
                        var search_lower_buf: [4096]u8 = undefined;
                        const line_lower = toLower(&line_lower_buf, self.lines[i]);
                        const search_lower = toLower(&search_lower_buf, self.search_term);
                        if (std.mem.indexOf(u8, line_lower, search_lower) != null) {
                            self.scroll = i;
                            break;
                        }
                        if (i == 0) break;
                        i -= 1;
                    }
                    try self.render();
                }
            },

            // Mode switching
            ':' => {
                // Enter command mode. Reset the command buffer and
                // display the `:` prompt in the footer.
                self.mode = .command;
                self.cmd_len = 0;
                self.message = "";
                try self.renderer.renderCommandLine(self.cmd_buf[0..0]);
            },
            '/' => {
                // Enter search mode. Reset the search buffer and
                // display the `/` prompt in the footer.
                self.mode = .search;
                self.search_len = 0;
                self.message = "";
                try self.renderer.renderSearchLine(self.search_buf[0..0]);
            },

            // Escape sequences (arrow keys)
            '\x1b' => {
                // The Escape byte (0x1B) can mean two things:
                // 1. The start of an ANSI escape sequence (e.g. arrow keys)
                // 2. A standalone Escape press (to clear search)
                if (self.term.readEscapeSeq()) |seq| {
                    switch (seq) {
                        'A' => {
                            // Up arrow — same as 'k'
                            if (self.scroll > 0) self.scroll -= 1;
                            try self.render();
                        },
                        'B' => {
                            // Down arrow — same as 'j'
                            if (self.scroll + self.visible_lines < self.lines.len) self.scroll += 1;
                            try self.render();
                        },
                        else => {},
                    }
                } else {
                    // Standalone Escape: clear the active search term
                    // so search highlights disappear.
                    if (self.search_term.len > 0) {
                        self.search_term = "";
                        self.search_len = 0;
                        self.message = "";
                        try self.render();
                    }
                }
            },
            else => {},
        }
        return false;
    }

    /// Handles a keypress in command mode (after pressing `:`).
    ///
    /// ## Keybindings
    ///
    /// | Key       | Action                                  |
    /// |-----------|-----------------------------------------|
    /// | `Escape`  | Cancel and return to normal mode         |
    /// | `Enter`   | Execute the command                     |
    /// | `Delete`  | Delete the last character                |
    /// | Any char  | Append to the command buffer             |
    ///
    /// ## Supported commands
    ///
    /// | Command   | Action                                  |
    /// |-----------|-----------------------------------------|
    /// | `q`       | Quit the application                    |
    /// | `help`    | Show keybinding help in the footer      |
    /// | `<number>`| Go to line number N                     |
    ///
    /// Returns `true` if the command is `:q` (quit).
    fn handleCommandMode(self: *App, c: u8) !bool {
        switch (c) {
            '\x1b' => {
                // Escape: cancel command mode and return to normal.
                self.mode = .normal;
                self.message = "";
                try self.render();
            },
            '\r', '\n' => {
                // Enter: execute the typed command.
                const cmd = self.cmd_buf[0..self.cmd_len];
                if (std.mem.eql(u8, cmd, "q")) {
                    // `:q` — quit the application.
                    return true;
                } else if (std.mem.eql(u8, cmd, "help")) {
                    // `:help` — show keybinding summary in the footer.
                    self.message = "j/k scroll | g/G top/bottom | d/u half page | space pgdn | /search | n/N match | :q :N :help";
                } else if (self.parseGotoLine(cmd)) |line_num| {
                    // `:<number>` — go to the specified line.
                    if (line_num > 0 and line_num <= self.lines.len) {
                        const target = line_num - 1; // Convert 1-based to 0-based.
                        const max_scroll = if (self.lines.len > self.visible_lines) self.lines.len - self.visible_lines else 0;
                        self.scroll = @min(target, max_scroll);
                    } else {
                        self.message = "Invalid line number.";
                    }
                } else {
                    self.message = "Unknown command. Type :help for available commands.";
                }
                self.mode = .normal;
                try self.render();
            },
            127 => {
                // Backspace (ASCII 127): delete the last character.
                if (self.cmd_len > 0) self.cmd_len -= 1;
                try self.renderer.renderCommandLine(self.cmd_buf[0..self.cmd_len]);
            },
            else => {
                // Printable character: append to the command buffer.
                if (self.cmd_len < self.cmd_buf.len and c >= 32) {
                    self.cmd_buf[self.cmd_len] = c;
                    self.cmd_len += 1;
                    try self.renderer.renderCommandLine(self.cmd_buf[0..self.cmd_len]);
                }
            },
        }
        return false;
    }

    /// Handles a keypress in search mode (after pressing `/`).
    ///
    /// ## Keybindings
    ///
    /// | Key       | Action                                         |
    /// |-----------|------------------------------------------------|
    /// | `Escape`  | Cancel search and return to normal mode         |
    /// | `Enter`   | Confirm the search term and highlight matches  |
    /// | `Delete`  | Delete the last character of the search term    |
    /// | Any char  | Append to the search buffer                    |
    ///
    /// After confirming with Enter, all occurrences of the search term
    /// are highlighted in the content area, and `n`/`N` can be used in
    /// normal mode to jump between matches.
    fn handleSearchMode(self: *App, c: u8) !bool {
        switch (c) {
            '\x1b' => {
                // Escape: cancel search, clear the search term, and
                // return to normal mode.
                self.mode = .normal;
                self.search_term = "";
                self.message = "";
                try self.render();
            },
            '\r', '\n' => {
                // Enter: confirm the search term. The renderer will now
                // highlight all occurrences in the content area.
                self.search_term = self.search_buf[0..self.search_len];
                self.mode = .normal;
                self.message = "";
                try self.render();
            },
            127 => {
                // Backspace: delete the last character of the search term.
                if (self.search_len > 0) self.search_len -= 1;
                try self.renderer.renderSearchLine(self.search_buf[0..self.search_len]);
            },
            else => {
                // Printable character: append to the search buffer.
                if (self.search_len < self.search_buf.len and c >= 32) {
                    self.search_buf[self.search_len] = c;
                    self.search_len += 1;
                    try self.renderer.renderSearchLine(self.search_buf[0..self.search_len]);
                }
            },
        }
        return false;
    }

    /// Attempts to parse a command string as a line number.
    ///
    /// Returns the parsed number (1-based) if the string is a valid
    /// decimal integer, or `null` if it's not a number.
    ///
    /// This is used by command mode to support `:42` (go to line 42).
    fn parseGotoLine(_: *App, cmd: []const u8) ?usize {
        if (cmd.len == 0) return null;
        return std.fmt.parseInt(usize, cmd, 10) catch null;
    }

    /// Triggers a full re-render of the screen.
    ///
    /// This is a convenience wrapper that passes all current state to
    /// the renderer. Called after every state change (scroll, mode change,
    /// resize, etc.).
    fn render(self: *App) !void {
        try self.renderer.render(self.lines, self.code_block_states, self.scroll, self.visible_lines, self.file, self.message, self.mode, self.search_term);
    }
};
