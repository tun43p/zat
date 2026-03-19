const std = @import("std");

pub const MimeInfo = struct {
    mime: []const u8,
    readable: bool,
};

pub fn fromExtension(ext: []const u8) MimeInfo {
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

        // Misc
        .{ ".diff", "text/x-diff", true },
        .{ ".patch", "text/x-diff", true },
        .{ ".log", "text/x-log", true },
        .{ ".lock", "text/plain", true },
        .{ ".gitignore", "text/plain", true },
        .{ ".editorconfig", "text/plain", true },

        // Images
        .{ ".png", "image/png", false },
        .{ ".jpg", "image/jpeg", false },
        .{ ".jpeg", "image/jpeg", false },
        .{ ".gif", "image/gif", false },
        .{ ".svg", "image/svg+xml", true },
        .{ ".webp", "image/webp", false },
        .{ ".ico", "image/x-icon", false },
        .{ ".bmp", "image/bmp", false },

        // Audio
        .{ ".mp3", "audio/mpeg", false },
        .{ ".wav", "audio/wav", false },
        .{ ".ogg", "audio/ogg", false },
        .{ ".flac", "audio/flac", false },

        // Video
        .{ ".mp4", "video/mp4", false },
        .{ ".webm", "video/webm", false },
        .{ ".avi", "video/x-msvideo", false },
        .{ ".mkv", "video/x-matroska", false },

        // Archives
        .{ ".zip", "application/zip", false },
        .{ ".tar", "application/x-tar", false },
        .{ ".gz", "application/gzip", false },
        .{ ".bz2", "application/x-bzip2", false },
        .{ ".xz", "application/x-xz", false },
        .{ ".7z", "application/x-7z-compressed", false },
        .{ ".rar", "application/x-rar-compressed", false },

        // Documents
        .{ ".pdf", "application/pdf", false },
        .{ ".doc", "application/msword", false },
        .{ ".docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", false },
        .{ ".xls", "application/vnd.ms-excel", false },
        .{ ".xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", false },
        .{ ".ppt", "application/vnd.ms-powerpoint", false },

        // Fonts
        .{ ".woff", "font/woff", false },
        .{ ".woff2", "font/woff2", false },
        .{ ".ttf", "font/ttf", false },
        .{ ".otf", "font/otf", false },

        // Wasm
        .{ ".wasm", "application/wasm", false },
        .{ ".wat", "text/x-wat", true },
    };

    inline for (map) |entry| {
        if (std.mem.eql(u8, ext, entry[0])) return .{ .mime = entry[1], .readable = entry[2] };
    }

    return .{ .mime = "text/plain", .readable = true };
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
