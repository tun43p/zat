//! MIME type detection based on file extensions and special filenames.
//!
//! Zat needs to know the MIME type of a file for two reasons:
//!
//! 1. **Syntax highlighting** — the `syntax` module maps MIME types to
//!    language-specific keyword/type definitions (e.g. `"text/x-zig"` →
//!    Zig keywords). See `syntax.zig` for details.
//! 2. **Binary detection** — files with non-text MIME types (images,
//!    archives, etc.) are flagged as non-readable so Zat can refuse to
//!    display them instead of showing garbage.
//!
//! ## How detection works
//!
//! Detection is purely based on the filename/extension — we do **not**
//! inspect file content (no magic bytes). The lookup order is:
//!
//! 1. If the file has no extension, try matching the full filename
//!    (e.g. `Makefile`, `Dockerfile`, `.bashrc`) via `fromFilename`.
//! 2. Otherwise, match the extension (e.g. `.zig`, `.py`) via `fromExtension`.
//! 3. If nothing matches, default to `"text/plain"` (assumed readable).
//!
//! Both lookup functions use `inline for` over compile-time tuples, which
//! the compiler unrolls into a fast sequence of comparisons.

const std = @import("std");

/// Holds the result of a MIME type lookup.
pub const MimeInfo = struct {
    /// The MIME type string (e.g. "text/x-zig", "image/png").
    mime: []const u8,
    /// Whether the file can be displayed as text. Binary formats
    /// (images, audio, video, archives, fonts, etc.) have this set to `false`.
    readable: bool,
};

/// Detects the MIME type from a file extension (including the leading dot).
///
/// Covers 100+ extensions across these categories:
/// - **Web**: `.html`, `.css`, `.js`, `.ts`, `.tsx`, `.jsx`, `.vue`, `.svelte`, `.astro`
/// - **Data/Config**: `.json`, `.yaml`, `.toml`, `.ini`, `.env`, `.csv`, `.graphql`, `.proto`
/// - **Markdown/Docs**: `.md`, `.mdx`, `.rst`, `.tex`, `.txt`
/// - **Shell/Scripts**: `.sh`, `.bash`, `.zsh`, `.fish`, `.nu`, `.ps1`, `.bat`
/// - **Systems**: `.zig`, `.c`, `.h`, `.cpp`, `.rs`, `.go`, `.asm`, `.nim`, `.v`, `.odin`
/// - **JVM**: `.java`, `.kt`, `.scala`, `.groovy`, `.clj`
/// - **.NET**: `.cs`, `.fs`, `.vb`
/// - **Scripting**: `.py`, `.rb`, `.php`, `.pl`, `.lua`, `.r`, `.jl`, `.ex`, `.erl`
/// - **Functional**: `.hs`, `.ml`, `.elm`, `.rkt`, `.lisp`
/// - **Apple/Mobile**: `.swift`, `.m`, `.dart`
/// - **Binary**: images, audio, video, archives, documents, fonts, wasm
///
/// Returns `{ .mime = "text/plain", .readable = true }` for unknown extensions.
///
/// ## Parameters
///
/// - `ext`: The file extension **with** the leading dot (e.g. `".zig"`).
///          An empty string is allowed and will match the default.
pub fn fromExtension(ext: []const u8) MimeInfo {
    // Each entry is a tuple of (extension, MIME type, is_readable).
    // `inline for` unrolls this at compile time into a chain of comparisons,
    // so there is no runtime loop overhead.
    const map = .{
        // Web
        .{ ".html", "text/html", true },
        .{ ".htm", "text/html", true },
        .{ ".css", "text/css", true },
        .{ ".js", "text/javascript", true },
        .{ ".mjs", "text/javascript", true },
        .{ ".ts", "text/typescript", true },
        .{ ".tsx", "text/tsx", true },
        .{ ".jsx", "text/jsx", true },
        .{ ".vue", "text/vue", true },
        .{ ".svelte", "text/svelte", true },
        .{ ".astro", "text/astro", true },

        // Data / Config
        .{ ".json", "application/json", true },
        .{ ".jsonc", "application/jsonc", true },
        .{ ".xml", "application/xml", true },
        .{ ".yaml", "text/yaml", true },
        .{ ".yml", "text/yaml", true },
        .{ ".toml", "text/toml", true },
        .{ ".ini", "text/ini", true },
        .{ ".env", "text/env", true },
        .{ ".csv", "text/csv", true },
        .{ ".tsv", "text/tsv", true },
        .{ ".graphql", "text/graphql", true },
        .{ ".gql", "text/graphql", true },
        .{ ".proto", "text/protobuf", true },

        // Markdown / Docs
        .{ ".md", "text/markdown", true },
        .{ ".mdx", "text/mdx", true },
        .{ ".rst", "text/restructuredtext", true },
        .{ ".tex", "text/latex", true },
        .{ ".txt", "text/plain", true },

        // Shell / Scripts
        .{ ".sh", "text/x-shellscript", true },
        .{ ".bash", "text/x-shellscript", true },
        .{ ".zsh", "text/x-shellscript", true },
        .{ ".fish", "text/x-shellscript", true },
        .{ ".nu", "text/x-nushell", true },
        .{ ".ps1", "text/x-powershell", true },
        .{ ".bat", "text/x-batch", true },
        .{ ".cmd", "text/x-batch", true },

        // Systems programming
        .{ ".zig", "text/x-zig", true },
        .{ ".c", "text/x-c", true },
        .{ ".h", "text/x-c", true },
        .{ ".cpp", "text/x-c++", true },
        .{ ".cc", "text/x-c++", true },
        .{ ".cxx", "text/x-c++", true },
        .{ ".hpp", "text/x-c++", true },
        .{ ".hh", "text/x-c++", true },
        .{ ".rs", "text/x-rust", true },
        .{ ".go", "text/x-go", true },
        .{ ".asm", "text/x-asm", true },
        .{ ".s", "text/x-asm", true },
        .{ ".nim", "text/x-nim", true },
        .{ ".v", "text/x-vlang", true },
        .{ ".odin", "text/x-odin", true },

        // JVM
        .{ ".java", "text/x-java", true },
        .{ ".kt", "text/x-kotlin", true },
        .{ ".kts", "text/x-kotlin", true },
        .{ ".scala", "text/x-scala", true },
        .{ ".groovy", "text/x-groovy", true },
        .{ ".gradle", "text/x-gradle", true },
        .{ ".clj", "text/x-clojure", true },

        // .NET
        .{ ".cs", "text/x-csharp", true },
        .{ ".fs", "text/x-fsharp", true },
        .{ ".vb", "text/x-vb", true },

        // Scripting
        .{ ".py", "text/x-python", true },
        .{ ".rb", "text/x-ruby", true },
        .{ ".php", "text/x-php", true },
        .{ ".pl", "text/x-perl", true },
        .{ ".pm", "text/x-perl", true },
        .{ ".lua", "text/x-lua", true },
        .{ ".r", "text/x-r", true },
        .{ ".R", "text/x-r", true },
        .{ ".jl", "text/x-julia", true },
        .{ ".ex", "text/x-elixir", true },
        .{ ".exs", "text/x-elixir", true },
        .{ ".erl", "text/x-erlang", true },
        .{ ".hrl", "text/x-erlang", true },

        // Functional
        .{ ".hs", "text/x-haskell", true },
        .{ ".ml", "text/x-ocaml", true },
        .{ ".mli", "text/x-ocaml", true },
        .{ ".elm", "text/x-elm", true },
        .{ ".rkt", "text/x-racket", true },
        .{ ".lisp", "text/x-lisp", true },
        .{ ".cl", "text/x-lisp", true },

        // Apple
        .{ ".swift", "text/x-swift", true },
        .{ ".m", "text/x-objc", true },
        .{ ".mm", "text/x-objc++", true },

        // Mobile
        .{ ".dart", "text/x-dart", true },

        // Build / CI
        .{ ".cmake", "text/x-cmake", true },
        .{ ".mk", "text/x-makefile", true },

        // Docker
        .{ ".dockerfile", "text/x-dockerfile", true },

        // Database
        .{ ".sql", "text/x-sql", true },

        // Misc text
        .{ ".diff", "text/x-diff", true },
        .{ ".patch", "text/x-diff", true },
        .{ ".log", "text/x-log", true },
        .{ ".lock", "text/plain", true },
        .{ ".gitignore", "text/plain", true },
        .{ ".editorconfig", "text/plain", true },

        // Images (binary — not readable)
        .{ ".png", "image/png", false },
        .{ ".jpg", "image/jpeg", false },
        .{ ".jpeg", "image/jpeg", false },
        .{ ".gif", "image/gif", false },
        .{ ".svg", "image/svg+xml", true }, // SVG is XML-based text
        .{ ".webp", "image/webp", false },
        .{ ".ico", "image/x-icon", false },
        .{ ".bmp", "image/bmp", false },

        // Audio (binary)
        .{ ".mp3", "audio/mpeg", false },
        .{ ".wav", "audio/wav", false },
        .{ ".ogg", "audio/ogg", false },
        .{ ".flac", "audio/flac", false },

        // Video (binary)
        .{ ".mp4", "video/mp4", false },
        .{ ".webm", "video/webm", false },
        .{ ".avi", "video/x-msvideo", false },
        .{ ".mkv", "video/x-matroska", false },

        // Archives (binary)
        .{ ".zip", "application/zip", false },
        .{ ".tar", "application/x-tar", false },
        .{ ".gz", "application/gzip", false },
        .{ ".bz2", "application/x-bzip2", false },
        .{ ".xz", "application/x-xz", false },
        .{ ".7z", "application/x-7z-compressed", false },
        .{ ".rar", "application/x-rar-compressed", false },

        // Documents (binary)
        .{ ".pdf", "application/pdf", false },
        .{ ".doc", "application/msword", false },
        .{ ".docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", false },
        .{ ".xls", "application/vnd.ms-excel", false },
        .{ ".xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", false },
        .{ ".ppt", "application/vnd.ms-powerpoint", false },

        // Fonts (binary)
        .{ ".woff", "font/woff", false },
        .{ ".woff2", "font/woff2", false },
        .{ ".ttf", "font/ttf", false },
        .{ ".otf", "font/otf", false },

        // WebAssembly
        .{ ".wasm", "application/wasm", false },
        .{ ".wat", "text/x-wat", true }, // WAT is the text format of Wasm
    };

    inline for (map) |entry| {
        if (std.mem.eql(u8, ext, entry[0])) return .{ .mime = entry[1], .readable = entry[2] };
    }

    // Unknown extensions are treated as plain text by default.
    return .{ .mime = "text/plain", .readable = true };
}

/// Detects the MIME type from a special filename (files without extensions
/// or with well-known names).
///
/// This handles files like `Makefile`, `Dockerfile`, `.bashrc`, `.gitconfig`,
/// etc. that are identified by their exact name rather than their extension.
///
/// Returns `null` if the filename is not recognized, in which case the
/// caller should fall back to `fromExtension`.
///
/// ## Parameters
///
/// - `name`: The basename of the file (e.g. `"Makefile"`, `".bashrc"`).
pub fn fromFilename(name: []const u8) ?MimeInfo {
    const name_map = .{
        // Build tools
        .{ "Makefile", "text/x-shellscript" },
        .{ "Dockerfile", "text/x-shellscript" },
        .{ "Justfile", "text/x-shellscript" },
        .{ "CMakeLists.txt", "text/x-shellscript" },

        // Ruby ecosystem
        .{ "Vagrantfile", "text/x-ruby" },
        .{ "Rakefile", "text/x-ruby" },
        .{ "Gemfile", "text/x-ruby" },

        // Shell config files (dotfiles)
        .{ ".bashrc", "text/x-shellscript" },
        .{ ".zshrc", "text/x-shellscript" },
        .{ ".profile", "text/x-shellscript" },
        .{ ".bash_profile", "text/x-shellscript" },
        .{ ".env", "text/x-shellscript" },

        // Config files
        .{ ".gitignore", "text/plain" },
        .{ ".gitconfig", "text/toml" },
        .{ ".editorconfig", "text/toml" },
    };

    inline for (name_map) |entry| {
        if (std.mem.eql(u8, name, entry[0])) return .{ .mime = entry[1], .readable = true };
    }

    return null;
}

test "fromExtension returns correct MIME for known extensions" {
    const zig = fromExtension(".zig");
    try std.testing.expectEqualStrings("text/x-zig", zig.mime);
    try std.testing.expect(zig.readable);

    const html = fromExtension(".html");
    try std.testing.expectEqualStrings("text/html", html.mime);
    try std.testing.expect(html.readable);

    const py = fromExtension(".py");
    try std.testing.expectEqualStrings("text/x-python", py.mime);
    try std.testing.expect(py.readable);
}

test "fromExtension returns non-readable for binary files" {
    const png = fromExtension(".png");
    try std.testing.expectEqualStrings("image/png", png.mime);
    try std.testing.expect(!png.readable);

    const wasm = fromExtension(".wasm");
    try std.testing.expectEqualStrings("application/wasm", wasm.mime);
    try std.testing.expect(!wasm.readable);
}

test "fromExtension returns text/plain for unknown extensions" {
    const unknown = fromExtension(".xyz_unknown");
    try std.testing.expectEqualStrings("text/plain", unknown.mime);
    try std.testing.expect(unknown.readable);
}
