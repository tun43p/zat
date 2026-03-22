//! Terminal rendering engine for Zat.
//!
//! This module is responsible for drawing the entire TUI (Text User
//! Interface) to the terminal. It produces ANSI escape sequences to
//! control cursor position, colors, and text styling.
//!
//! ## Screen layout
//!
//! The rendered screen has this structure (each section is drawn by a
//! dedicated method):
//!
//! ```
//! ─────┬──────────────────────────────   ← top line    (renderTopLine)
//!      │ main.zig │ text/x-zig │ ...     ← header      (renderHeader)
//! ─────┼──────────────────────────────   ← separator   (renderSeparator)
//!    1 │ const std = @import("std");     ← content     (renderLines)
//!    2 │ ...                             │
//!    … │                                 │
//! ─────┼──────────────────────────────   ← footer sep  (renderFooter)
//!      │ Press : for COMMAND or / ...    ← footer      (renderFooter)
//! ─────┴──────────────────────────────   ← bottom line (renderBottomLine)
//! ```
//!
//! ## ANSI escape sequences
//!
//! The renderer communicates with the terminal emulator via ANSI escape
//! codes (also called VT100 sequences). Key sequences used:
//!
//! - `\x1b[H`      — move cursor to top-left (home position)
//! - `\x1b[2J`     — clear entire screen
//! - `\x1b[{n};1H` — move cursor to row `n`, column 1
//! - `\x1b[2K`     — clear the current line
//! - `\x1b[0m`     — reset all text attributes (colors, bold, etc.)
//! - `\x1b[31m`    — set text color to red (30-37 = standard, 90-97 = bright)
//! - `\x1b[1m`     — set bold text
//! - `\x1b[43m`    — set background color to yellow (40-47 = standard)
//!
//! ## Word wrapping
//!
//! Long lines are word-wrapped to fit the terminal width. The wrapping
//! algorithm tries to break at spaces; if no space is found, it breaks
//! at the column limit. Continuation lines share the same gutter but
//! show no line number.
//!
//! ## Syntax highlighting
//!
//! Each line is tokenized and colorized by `renderLineWithHighlight`:
//! 1. Comments (gray) — detected by the language's `line_comment` prefix
//! 2. Strings (green) — detected by matching `string_delims`
//! 3. Builtins (bright blue) — looked up in the language's builtin set
//! 4. Keywords (bold magenta) — looked up in the language's keyword set
//! 5. Types (bright yellow) — looked up in the language's type set
//! 6. Number literals (bright cyan) — words starting with a digit
//! 7. Everything else — default terminal color
//!
//! ## Search highlighting
//!
//! When the user has an active search term, all occurrences are rendered
//! with a yellow background and black text, regardless of syntax colors.

const std = @import("std");
const File = @import("file.zig").File;
const syntax = @import("syntax.zig");

/// The three interaction modes of the application.
///
/// - `normal`: Default mode. The user can scroll, navigate, and enter
///   other modes via `:` (command) or `/` (search).
/// - `command`: Activated by pressing `:`. The user types a command
///   (e.g. `q` to quit, a line number to jump to, `help` for help).
/// - `search`: Activated by pressing `/`. The user types a search term.
///   Pressing Enter confirms the search; Escape cancels it.
pub const Mode = enum { normal, command, search };

/// Width of the line number gutter in characters.
/// Line numbers are right-aligned within this space (e.g. "   1 ").
const gutter = 5;

/// Shorthand aliases for the box-drawing character and ANSI style
/// namespaces, to keep rendering code concise.
const chars = Chars;
const style = Style;

// Color constants for syntax highlighting
//
// These map semantic token types to specific ANSI color codes. Changing
// these constants will change the color scheme for all languages.

/// Color for box-drawing characters and the gutter separator.
const table_color = style.gray;
/// Color for line numbers in the gutter.
const number_color = style.bright_yellow;
/// Color for comments (everything after a line comment prefix).
const comment_color = style.gray;
/// Color for string literals (text between matching delimiters).
const string_color = style.green;
/// Color for language keywords (e.g. `fn`, `if`, `return`).
const keyword_color = style.magenta;
/// Color for type names (e.g. `u8`, `bool`, `String`).
const type_color = style.bright_yellow;
/// Color for numeric literals (e.g. `42`, `3.14`, `0xFF`).
const number_literal_color = style.bright_cyan;
/// Color for built-in functions (e.g. Zig's `@import`, Python's `print`).
const builtin_color = style.bright_blue;

/// The main rendering engine. Holds a reference to the output writer
/// and the current terminal dimensions.
///
/// The renderer is stateless with respect to content — it does not cache
/// any rendered output. Each call to `render` redraws the entire screen
/// from scratch. This simplifies the code and avoids synchronization
/// issues, at the cost of redrawing everything on each keypress (which
/// is fast enough for text files).
fn toLowerBuf(buf: []u8, input: []const u8) []const u8 {
    const len = @min(buf.len, input.len);
    for (0..len) |i| {
        buf[i] = std.ascii.toLower(input[i]);
    }
    return buf[0..len];
}
pub const Renderer = struct {
    /// The buffered writer that receives all ANSI output. Writes are
    /// accumulated in a buffer and sent to the terminal in one `flush`
    /// call, which reduces syscalls and prevents visual tearing.
    writer: *std.io.Writer,
    /// Current terminal width in columns. Updated when the terminal
    /// is resized (via `SIGWINCH`).
    width: usize,
    /// Current terminal height in rows. Updated on resize.
    height: usize,
    /// The syntax definition for the current file, or `null` if no
    /// highlighting is available for this file type.
    syntax_def: ?syntax.SyntaxDef,

    /// Creates a new renderer for the given writer and terminal dimensions.
    ///
    /// The `mime_type` is used to look up the appropriate syntax
    /// definition via `syntax.fromMime`. If the MIME type is not
    /// recognized, `syntax_def` will be `null` and the file will be
    /// displayed without syntax highlighting.
    pub fn init(writer: *std.io.Writer, width: usize, height: usize, mime_type: []const u8) Renderer {
        return .{ .writer = writer, .width = width, .height = height, .syntax_def = syntax.fromMime(mime_type) };
    }

    /// Writes raw bytes to the output buffer (without flushing).
    fn write(self: *Renderer, bytes: []const u8) !void {
        try self.writer.writeAll(bytes);
    }

    /// Flushes the output buffer to the terminal.
    /// This triggers the actual write syscall and makes all pending
    /// output visible on screen.
    fn flush(self: *Renderer) !void {
        try self.writer.flush();
    }

    /// Returns the usable content width (total width minus gutter and
    /// the separator column). This is how many characters of file
    /// content can fit on a single line.
    fn contentWidth(self: *Renderer) usize {
        return if (self.width > gutter + 2) self.width - gutter - 2 else 0;
    }

    /// Renders the entire screen: top border, header, separator, file
    /// content lines, footer, and bottom border.
    ///
    /// This is the main entry point called by `App` whenever the display
    /// needs to be refreshed (on scroll, resize, mode change, etc.).
    ///
    /// ## Parameters
    ///
    /// - `lines`: All lines of the file.
    /// - `code_block_states`: Per-line boolean indicating whether the line
    ///   is inside a Markdown code block (used to skip syntax highlighting
    ///   for fenced code blocks).
    /// - `scroll`: Index of the first visible line (0-based).
    /// - `visible_lines`: How many lines fit in the content area.
    /// - `file`: The file metadata (name, MIME type, size, line count).
    /// - `message`: A status message to display in the footer (e.g. error
    ///   messages, help text). Empty string means no message.
    /// - `mode`: The current interaction mode (normal, command, search).
    /// - `search`: The active search term. Empty string means no search.
    pub fn render(self: *Renderer, lines: []const []const u8, code_block_states: []const bool, scroll: usize, visible_lines: usize, file: File, message: []const u8, mode: Mode, search: []const u8) !void {
        // Move cursor to top-left corner and clear the entire screen.
        // This ensures we start from a clean state on every render.
        try self.write("\x1b[H\x1b[2J");

        try self.renderTopLine();
        try self.renderHeader(scroll, file);
        try self.renderSeparator();
        try self.renderLines(lines, code_block_states, scroll, visible_lines, search);
        try self.renderFooter(message, mode, search);
        try self.renderBottomLine();

        // Flush all buffered output to the terminal in one write syscall.
        try self.flush();
    }

    /// Draws the top border line of the UI frame.
    ///
    /// ```
    /// ─────┬──────────────────────────
    /// ```
    ///
    /// The `┬` character sits at the junction between the gutter and the
    /// content area.
    fn renderTopLine(self: *Renderer) !void {
        try self.write(table_color);
        for (0..gutter) |_| try self.write(chars.row);
        try self.write(chars.up_insertion);
        for (0..self.contentWidth()) |_| try self.write(chars.row);
        try self.write(style.reset ++ "\r\n");
    }

    /// Draws the header row showing file metadata.
    ///
    /// ```
    ///      │ main.zig │ text/x-zig │ 1/54 lines │ 1234 bytes
    /// ```
    ///
    /// Fields are displayed left-to-right and truncated if the terminal
    /// is too narrow. Each field has its own color for visual distinction.
    fn renderHeader(self: *Renderer, scroll: usize, file: File) !void {
        try self.write(table_color);
        for (0..gutter) |_| try self.write(" ");
        try self.write(chars.pipe ++ " ");
        var col: usize = gutter + 2;

        // Format dynamic values into stack-allocated buffers.
        var lines_buf: [32]u8 = undefined;
        const lines_str = std.fmt.bufPrint(&lines_buf, "{d}/{d} lines", .{ scroll + 1, file.line_count }) catch "?";
        var size_buf: [32]u8 = undefined;
        const size_str = std.fmt.bufPrint(&size_buf, "{d} bytes", .{file.size}) catch "?";

        // The four header fields with their respective colors.
        // Fields that don't fit in the remaining terminal width are skipped.
        const fields = [_]struct { color: []const u8, text: []const u8 }{
            .{ .color = style.cyan ++ style.bold, .text = file.name },
            .{ .color = style.bright_blue, .text = file.mime },
            .{ .color = number_color, .text = lines_str },
            .{ .color = style.bright_cyan, .text = size_str },
        };

        for (fields, 0..) |field, fi| {
            const sep_len: usize = if (fi > 0) 3 else 0; // " │ " separator between fields
            const needed = sep_len + field.text.len;
            if (col + needed > self.width) break; // not enough room for this field
            if (fi > 0) try self.write(table_color ++ " " ++ chars.pipe ++ " ");
            try self.write(field.color);
            try self.write(field.text);
            try self.write(style.reset);
            col += needed;
        }

        try self.write(style.reset ++ "\r\n");
    }

    /// Draws the separator line between the header and the content area.
    ///
    /// ```
    /// ─────┼──────────────────────────
    /// ```
    fn renderSeparator(self: *Renderer) !void {
        try self.write(table_color);
        for (0..gutter) |_| try self.write(chars.row);
        try self.write(chars.cross);
        for (0..self.contentWidth()) |_| try self.write(chars.row);
        try self.write(style.reset ++ "\r\n");
    }

    /// Renders the visible file content lines with line numbers, word
    /// wrapping, syntax highlighting, and search highlighting.
    ///
    /// This is the most complex rendering function. For each visible line:
    ///
    /// 1. **Word wrapping**: If the line exceeds `contentWidth`, it is
    ///    split into chunks. The algorithm tries to break at spaces; if
    ///    no space is found within the width, it breaks mid-word.
    ///
    /// 2. **Line numbers**: The first chunk of each line shows the line
    ///    number in the gutter. Continuation chunks show an empty gutter.
    ///
    /// 3. **Markdown code blocks**: Lines inside fenced code blocks
    ///    (between ``` markers) are rendered entirely in green, bypassing
    ///    the normal syntax highlighter.
    ///
    /// 4. **Syntax highlighting**: Non-code-block lines are passed to
    ///    `renderLineWithHighlight` for token-based coloring.
    ///
    /// 5. **Empty line padding**: If the file has fewer lines than the
    ///    visible area, empty gutter lines are drawn to fill the space.
    fn renderLines(self: *Renderer, lines: []const []const u8, code_block_states: []const bool, scroll: usize, visible_lines: usize, search: []const u8) !void {
        const max_w = self.contentWidth();
        var visual_rows: usize = 0;
        var i = scroll;
        while (i < lines.len and visual_rows < visible_lines) {
            const full_line = lines[i];

            // Check if this line is a code fence (```) or inside a code block.
            // Fenced content is rendered in string_color (green) without
            // language-specific syntax highlighting.
            const trimmed_full = std.mem.trimLeft(u8, full_line, " ");
            const is_fence = trimmed_full.len >= 3 and std.mem.eql(u8, trimmed_full[0..3], "```");
            const in_code_block = if (i < code_block_states.len) code_block_states[i] else false;

            // Word wrapping
            // Split the line into chunks that fit within max_w columns.
            var start: usize = 0;
            var is_first_chunk = true;
            while (start < full_line.len and visual_rows < visible_lines) {
                var end = @min(start + max_w, full_line.len);
                if (end < full_line.len) {
                    // Try to find a space to break at (word boundary).
                    var break_at = end;
                    while (break_at > start and full_line[break_at] != ' ') break_at -= 1;
                    if (break_at > start) {
                        end = break_at + 1; // include the space, wrap after it
                    }
                }
                const chunk = full_line[start..end];

                // Gutter (line number or continuation)
                if (is_first_chunk) {
                    // First chunk: show the line number right-aligned in the gutter.
                    var num_buf: [32]u8 = undefined;
                    const num = std.fmt.bufPrint(&num_buf, number_color ++ "{d: >4} " ++ table_color ++ chars.pipe ++ " " ++ style.reset, .{i + 1}) catch break;
                    try self.write(num);
                    is_first_chunk = false;
                } else {
                    // Continuation chunk: empty gutter with just the separator.
                    try self.write(table_color);
                    for (0..gutter) |_| try self.write(" ");
                    try self.write(chars.pipe ++ " " ++ style.reset);
                }

                // Content rendering
                if (is_fence or in_code_block) {
                    // Inside a Markdown code block: render in green.
                    try self.write(string_color);
                    try self.renderWithSearch(chunk, search);
                    try self.write(style.reset);
                } else {
                    // Normal line: apply full syntax highlighting.
                    try self.renderLineWithHighlight(chunk, search);
                }
                try self.write("\r\n");
                visual_rows += 1;
                start = end;
            }

            // Handle short/empty lines that fit entirely without wrapping.
            if (is_first_chunk and visual_rows < visible_lines) {
                var num_buf: [32]u8 = undefined;
                const num = std.fmt.bufPrint(&num_buf, number_color ++ "{d: >4} " ++ table_color ++ chars.pipe ++ " " ++ style.reset, .{i + 1}) catch {
                    i += 1;
                    continue;
                };
                try self.write(num);
                if (is_fence or in_code_block) {
                    try self.write(string_color);
                    try self.renderWithSearch(full_line, search);
                    try self.write(style.reset);
                } else {
                    try self.renderLineWithHighlight(full_line, search);
                }
                try self.write("\r\n");
                visual_rows += 1;
            }
            i += 1;
        }

        // Fill remaining space with empty gutter lines so the frame
        // extends to the bottom of the visible area.
        if (visual_rows < visible_lines) {
            for (0..visible_lines - visual_rows) |_| {
                try self.write(table_color);
                for (0..gutter) |_| try self.write(" ");
                try self.write(chars.pipe ++ style.reset ++ "\r\n");
            }
        }
    }

    /// Renders a single line with syntax highlighting and search term
    /// highlighting.
    ///
    /// This function tokenizes the line character by character and applies
    /// colors based on the current file's `SyntaxDef`. The processing
    /// order is:
    ///
    /// 1. **Line prefixes** (Markdown only): if the trimmed line starts
    ///    with a known prefix (e.g. `#`, `>`, `- `), the entire line is
    ///    colored and we return early.
    /// 2. **Line comments**: if we encounter the comment prefix, the rest
    ///    of the line is rendered in gray.
    /// 3. **String literals**: characters between matching delimiters are
    ///    rendered in green. Backslash escapes are handled.
    /// 4. **Words**: sequences of alphanumeric characters, underscores,
    ///    and `@` are extracted and checked against builtin/keyword/type
    ///    sets.
    /// 5. **Number literals**: words starting with a digit.
    /// 6. **Everything else**: rendered without coloring.
    fn renderLineWithHighlight(self: *Renderer, line: []const u8, search: []const u8) !void {
        const syn = self.syntax_def orelse {
            // No syntax definition for this file type: just render the
            // raw text with search highlighting only.
            try self.renderWithSearch(line, search);
            return;
        };

        // Check for line prefixes (e.g. Markdown headings, blockquotes).
        // If a prefix matches, the entire line is colored with that
        // prefix's color.
        const trimmed = std.mem.trimLeft(u8, line, " ");
        for (syn.line_prefixes) |lp| {
            if (trimmed.len >= lp.prefix.len and std.mem.eql(u8, trimmed[0..lp.prefix.len], lp.prefix)) {
                try self.write(lp.color);
                try self.renderWithSearch(line, search);
                try self.write(style.reset);
                return;
            }
        }

        // Token-by-token processing of the line.
        var pos: usize = 0;
        while (pos < line.len) {
            // Comment detection
            // If the remaining text starts with the line comment prefix,
            // render everything from here to the end of the line in gray.
            if (syn.line_comment.len > 0 and pos + syn.line_comment.len <= line.len and std.mem.eql(u8, line[pos .. pos + syn.line_comment.len], syn.line_comment)) {
                try self.write(comment_color);
                try self.renderWithSearch(line[pos..], search);
                try self.write(style.reset);
                return;
            }

            // String literal detection
            // If the current character is a string delimiter (e.g. " or '),
            // scan forward to find the matching closing delimiter, handling
            // backslash escapes along the way.
            if (isStringDelim(syn, line[pos])) {
                const delim = line[pos];
                var end = pos + 1;
                while (end < line.len) {
                    if (line[end] == '\\') {
                        end += 2; // skip the escaped character
                        continue;
                    }
                    if (line[end] == delim) {
                        end += 1; // include the closing delimiter
                        break;
                    }
                    end += 1;
                }
                try self.write(string_color);
                try self.renderWithSearch(line[pos..end], search);
                try self.write(style.reset);
                pos = end;
                continue;
            }

            // Word detection (keywords, types, builtins)
            // If the current character can start a word, extract the full
            // word and check it against the language's builtin, keyword,
            // and type sets.
            if (isWordChar(line[pos])) {
                var end = pos;
                while (end < line.len and isWordChar(line[end])) : (end += 1) {}
                const word = line[pos..end];

                // A word is only matched against keyword/type/builtin sets
                // if it's at a word boundary (not part of a larger identifier).
                const is_at_boundary = (pos == 0 or !isWordChar(line[pos - 1])) and (end >= line.len or !isWordChar(line[end]));

                if (is_at_boundary and isBuiltin(syn, word)) {
                    try self.write(builtin_color);
                    try self.renderWithSearch(word, search);
                    try self.write(style.reset);
                } else if (is_at_boundary and isKeyword(syn, word)) {
                    try self.write(keyword_color ++ style.bold);
                    try self.renderWithSearch(word, search);
                    try self.write(style.reset);
                } else if (is_at_boundary and isType(syn, word)) {
                    try self.write(type_color);
                    try self.renderWithSearch(word, search);
                    try self.write(style.reset);
                } else if (is_at_boundary and isNumberLiteral(word)) {
                    try self.write(number_literal_color);
                    try self.renderWithSearch(word, search);
                    try self.write(style.reset);
                } else {
                    // Regular identifier — no special coloring.
                    try self.renderWithSearch(word, search);
                }
                pos = end;
                continue;
            }

            // Single character (operator, punctuation, whitespace)
            try self.renderWithSearch(line[pos .. pos + 1], search);
            pos += 1;
        }
    }

    /// Renders a text fragment, highlighting all occurrences of the search
    /// term with a yellow background and black text.
    ///
    /// If there is no active search (`search.len == 0`), the text is
    /// written as-is without any modification.
    ///
    /// This function is called by all rendering functions (syntax
    /// highlighting, comment rendering, string rendering, etc.) as the
    /// final step before writing text. This ensures search highlights
    /// appear on top of any syntax coloring.
    fn renderWithSearch(self: *Renderer, text: []const u8, search: []const u8) !void {
        if (search.len == 0) {
            try self.write(text);
            return;
        }

        // Scan through the text looking for search matches.
        var pos: usize = 0;
        while (pos < text.len) {
            var text_lower_buf: [4096]u8 = undefined;
            var search_lower_buf: [256]u8 = undefined;
            const text_lower = toLowerBuf(&text_lower_buf, text[pos..]);
            const search_lower = toLowerBuf(&search_lower_buf, search);
            if (std.mem.indexOf(u8, text_lower, search_lower)) |match| {
                // Write the text before the match.
                try self.write(text[pos .. pos + match]);
                // Write the match with yellow background + black text.
                try self.write(style.bg_yellow ++ style.black);
                try self.write(text[pos + match .. pos + match + search.len]);
                try self.write(style.reset);
                pos += match + search.len;
            } else {
                // No more matches — write the rest of the text.
                try self.write(text[pos..]);
                break;
            }
        }
    }

    /// Checks if a character is a valid string delimiter for the current
    /// language (e.g. `"`, `'`, or backtick).
    fn isStringDelim(syn: syntax.SyntaxDef, c: u8) bool {
        for (syn.string_delims) |d| {
            if (c == d) return true;
        }
        return false;
    }

    /// Checks if a word is a built-in function/identifier for the current
    /// language. Uses the O(1) `StaticStringMap` lookup.
    fn isBuiltin(syn: syntax.SyntaxDef, word: []const u8) bool {
        return syn.builtins.has(word);
    }

    /// Checks if a word is a keyword for the current language.
    /// Uses the O(1) `StaticStringMap` lookup.
    fn isKeyword(syn: syntax.SyntaxDef, word: []const u8) bool {
        return syn.keywords.has(word);
    }

    /// Checks if a word is a type name for the current language.
    /// Uses the O(1) `StaticStringMap` lookup.
    fn isType(syn: syntax.SyntaxDef, word: []const u8) bool {
        return syn.types.has(word);
    }

    /// Checks if a character can be part of a word token.
    /// Word characters are: letters, digits, underscore, and `@` (for
    /// Zig's built-in functions like `@import`).
    fn isWordChar(c: u8) bool {
        return std.ascii.isAlphanumeric(c) or c == '_' or c == '@';
    }

    /// Checks if a word is a numeric literal.
    /// A word is considered numeric if it starts with a digit, or if it
    /// starts with `-` followed by a digit (negative number).
    fn isNumberLiteral(word: []const u8) bool {
        if (word.len == 0) return false;
        if (std.ascii.isDigit(word[0])) return true;
        // Negative numbers (e.g. "-42")
        if (word[0] == '-' and word.len > 1 and std.ascii.isDigit(word[1])) return true;
        return false;
    }

    /// Renders the footer area: a separator line, then a content line
    /// showing either a status message, the active search term, or a
    /// hint about available keyboard shortcuts.
    ///
    /// The footer is positioned at a fixed location (3 lines from the
    /// bottom) using an absolute cursor movement escape sequence.
    fn renderFooter(self: *Renderer, message: []const u8, mode: Mode, search: []const u8) !void {
        // Position the cursor at the footer row using an absolute
        // cursor movement escape sequence.
        var pos_buf: [32]u8 = undefined;
        const pos = std.fmt.bufPrint(&pos_buf, "\x1b[{d};1H", .{self.height - 2}) catch return;
        try self.write(pos);

        // Footer separator line (same style as the header separator).
        try self.write(table_color);
        for (0..gutter) |_| try self.write(chars.row);
        try self.write(chars.cross);
        for (0..self.contentWidth()) |_| try self.write(chars.row);
        try self.write(style.reset ++ "\r\n");

        // Footer content line — shows one of three things:
        try self.write(table_color);
        for (0..gutter) |_| try self.write(" ");
        try self.write(chars.pipe ++ " ");
        const max_footer = self.contentWidth();
        if (message.len > 0) {
            // 1. A status message (e.g. help text, error message).
            const msg = if (message.len > max_footer) message[0..max_footer] else message;
            try self.write(style.gray);
            try self.write(msg);
            try self.write(style.reset);
        } else if (search.len > 0) {
            // 2. The active search term with highlighted styling.
            try self.write(style.gray ++ "Search: " ++ style.reset);
            try self.write(style.bg_yellow ++ style.black);
            const max_search = if (max_footer > 8) max_footer - 8 else 0;
            const s = if (search.len > max_search) search[0..max_search] else search;
            try self.write(s);
            try self.write(style.reset);
        } else if (mode == .normal) {
            // 3. A keyboard shortcut hint (only in normal mode).
            const hint = "Press : for COMMAND or / for SEARCH mode";
            const h = if (hint.len > max_footer) hint[0..max_footer] else hint;
            try self.write(style.gray);
            try self.write(h);
            try self.write(style.reset);
        }
        try self.write("\r\n");
    }

    /// Draws the bottom border line of the UI frame.
    ///
    /// ```
    /// ─────┴──────────────────────────
    /// ```
    fn renderBottomLine(self: *Renderer) !void {
        try self.write(table_color);
        for (0..gutter) |_| try self.write(chars.row);
        try self.write(chars.down_insertion);
        for (0..self.contentWidth()) |_| try self.write(chars.row);
        try self.write(style.reset);
    }

    /// Renders the command mode input line at the footer position.
    ///
    /// Shows `:` followed by what the user has typed so far. Called on
    /// every keypress while in command mode to update the display.
    pub fn renderCommandLine(self: *Renderer, cmd: []const u8) !void {
        // Move cursor to the footer content row.
        var pos_buf: [32]u8 = undefined;
        const pos = std.fmt.bufPrint(&pos_buf, "\x1b[{d};1H", .{self.height - 1}) catch return;
        try self.write(pos);
        // Clear the entire line before writing new content.
        try self.write("\x1b[2K");
        try self.write(table_color);
        for (0..gutter) |_| try self.write(" ");
        try self.write(chars.pipe ++ " " ++ style.reset ++ ":");
        try self.write(cmd);
        try self.flush();
    }

    /// Renders the search mode input line at the footer position.
    ///
    /// Shows `/` followed by what the user has typed so far. Called on
    /// every keypress while in search mode to update the display.
    pub fn renderSearchLine(self: *Renderer, query: []const u8) !void {
        // Move cursor to the footer content row.
        var pos_buf: [32]u8 = undefined;
        const pos = std.fmt.bufPrint(&pos_buf, "\x1b[{d};1H", .{self.height - 1}) catch return;
        try self.write(pos);
        // Clear the entire line before writing new content.
        try self.write("\x1b[2K");
        try self.write(table_color);
        for (0..gutter) |_| try self.write(" ");
        try self.write(chars.pipe ++ " " ++ style.reset ++ "/");
        try self.write(query);
        try self.flush();
    }
};

// Box-drawing characters
//
// Unicode box-drawing characters used to build the TUI frame around the
// content area. These create clean borders and intersections.

/// Box-drawing characters for the TUI frame.
const Chars = struct {
    /// Vertical line: `│` — used for the gutter separator.
    pub const pipe = "│";
    /// Horizontal line: `─` — used for top/bottom borders and separators.
    pub const row = "─";

    /// Top T-junction: `┬` — used at the top border where the gutter
    /// separator meets the horizontal line.
    pub const up_insertion = "┬";
    /// Bottom T-junction: `┴` — used at the bottom border.
    pub const down_insertion = "┴";
    /// Left T-junction: `├` — available for future use.
    pub const left_insertion = "├";
    /// Right T-junction: `┤` — available for future use.
    pub const right_insertion = "┤";

    /// Cross junction: `┼` — used at separator lines where the gutter
    /// separator intersects a horizontal line.
    pub const cross = "┼";
};

// ANSI escape code constants
//
// These are the ANSI SGR (Select Graphic Rendition) escape sequences used
// to control text appearance in the terminal. Each sequence starts with
// `\x1b[` (ESC + `[`) and ends with `m`.
//
// Documentation: https://en.wikipedia.org/wiki/ANSI_escape_code#SGR

/// ANSI SGR escape sequences for text styling and coloring.
const Style = struct {
    // Text styles
    /// Reset all attributes to default.
    pub const reset = "\x1b[0m";
    /// Bold / increased intensity.
    pub const bold = "\x1b[1m";
    /// Dim / decreased intensity.
    pub const dim = "\x1b[2m";
    /// Italic (not supported by all terminals).
    pub const italic = "\x1b[3m";
    /// Underline.
    pub const underline = "\x1b[4m";
    /// Strikethrough (not supported by all terminals).
    pub const strikethrough = "\x1b[9m";

    // Standard foreground colors (30–37)
    pub const black = "\x1b[30m";
    pub const red = "\x1b[31m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
    pub const magenta = "\x1b[35m";
    pub const cyan = "\x1b[36m";
    pub const white = "\x1b[37m";

    /// Dark gray (bright black).
    pub const gray = "\x1b[90m";

    // Bright foreground colors (91–97)
    pub const bright_red = "\x1b[91m";
    pub const bright_green = "\x1b[92m";
    pub const bright_yellow = "\x1b[93m";
    pub const bright_blue = "\x1b[94m";
    pub const bright_magenta = "\x1b[95m";
    pub const bright_cyan = "\x1b[96m";
    pub const bright_white = "\x1b[97m";

    // Background colors (40–47)
    pub const bg_black = "\x1b[40m";
    pub const bg_red = "\x1b[41m";
    pub const bg_green = "\x1b[42m";
    pub const bg_yellow = "\x1b[43m";
    pub const bg_blue = "\x1b[44m";
    pub const bg_magenta = "\x1b[45m";
    pub const bg_cyan = "\x1b[46m";
    pub const bg_white = "\x1b[47m";
};
