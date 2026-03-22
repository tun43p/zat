//! Syntax highlighting definitions for 28+ programming languages.
//!
//! This module provides language-specific definitions used by the
//! `Renderer` to colorize source code. Each language is described by a
//! `SyntaxDef` struct that contains:
//!
//! - **Keywords**: reserved words that get bold + magenta highlighting
//!   (e.g. `fn`, `if`, `return`, `class`).
//! - **Types**: type names that get bright yellow highlighting
//!   (e.g. `u8`, `bool`, `String`, `Vec`).
//! - **Builtins**: built-in functions/identifiers that get bright blue
//!   highlighting (e.g. Python's `print`, `len`, `range`; Zig's `@import`).
//! - **Line comment prefix**: the string that starts a single-line comment
//!   (e.g. `"//"`, `"#"`, `"--"`). Everything after this prefix on a
//!   line is rendered in gray.
//! - **String delimiters**: characters that delimit string literals
//!   (e.g. `"`, `'`, `` ` ``). Content between matching delimiters is
//!   rendered in green.
//! - **Line prefixes**: for languages like Markdown, patterns at the
//!   start of a line that trigger full-line coloring (e.g. `#` headings,
//!   `>` blockquotes, `- ` list items).
//!
//! ## How it works
//!
//! The renderer calls `fromMime("text/x-zig")` to get the syntax
//! definition for the file's MIME type. If no definition exists (unknown
//! language), `null` is returned and the file is displayed without syntax
//! highlighting.
//!
//! ## Performance
//!
//! All keyword/type/builtin sets use `std.StaticStringMap`, which is a
//! compile-time perfect hash map. Lookups are O(1) with zero heap
//! allocation. The `fromMime` function uses `inline for` to unroll the
//! MIME → definition mapping at compile time.
//!
//! ## Adding a new language
//!
//! 1. Create a `const my_lang_def = SyntaxDef{ ... }` with the language's
//!    keywords, types, comment prefix, and string delimiters.
//! 2. Add an entry `.{ "text/x-mylang", my_lang_def }` to the `map` in
//!    `fromMime`.
//! 3. Add the file extension → MIME mapping in `mime.zig`.

const std = @import("std");

/// Alias for `std.StaticStringMap(void)` — a compile-time perfect hash
/// set of strings. Used for O(1) keyword/type/builtin lookups with no
/// heap allocation. The `void` value type means we only care about
/// membership, not associated values.
const StringSet = std.StaticStringMap(void);

/// A line prefix rule for languages that apply special coloring to entire
/// lines based on their starting characters (used primarily for Markdown).
///
/// For example, a Markdown heading `## Title` matches the prefix `"##"`
/// and the entire line is rendered in bold yellow.
pub const LinePrefix = struct {
    /// The string that the line must start with (after leading spaces).
    prefix: []const u8,
    /// The ANSI color escape sequence to apply to the entire line.
    color: []const u8,
};

/// Defines the syntax highlighting rules for a single programming language.
///
/// The renderer uses this definition to tokenize each line of source code
/// and apply the appropriate ANSI color escape sequences.
///
/// ## Tokenization strategy
///
/// The renderer processes each line character by character:
/// 1. If the current position matches `line_comment`, the rest of the
///    line is colored as a comment (gray).
/// 2. If the current character is in `string_delims`, everything up to
///    the matching closing delimiter is colored as a string (green).
///    Backslash escapes (`\"`) are handled.
/// 3. If the current character starts a word (`[a-zA-Z0-9_@]`), the
///    full word is extracted and checked against `builtins`, then
///    `keywords`, then `types` (in that priority order).
/// 4. Number literals (words starting with a digit) get their own color.
/// 5. Everything else (operators, punctuation) is rendered as-is.
pub const SyntaxDef = struct {
    /// Set of reserved keywords for this language.
    /// These are rendered in bold magenta.
    keywords: StringSet,
    /// Set of type names for this language.
    /// These are rendered in bright yellow.
    types: StringSet,
    /// Set of built-in functions/identifiers for this language.
    /// These are rendered in bright blue. Defaults to an empty set.
    builtins: StringSet = StringSet.initComptime(.{}),
    /// The string that starts a single-line comment (e.g. "//", "#", "--").
    /// An empty string means the language has no single-line comment syntax
    /// (e.g. CSS, HTML — they use block comments which are not yet supported).
    line_comment: []const u8,
    /// Characters that can delimit string literals (e.g. `"'`).
    /// The renderer looks for matching pairs of these characters.
    string_delims: []const u8,
    /// Line prefix rules for full-line coloring (primarily used for Markdown).
    /// Empty by default. Prefixes are checked in order — put longer
    /// prefixes first to avoid partial matches (e.g. `"###"` before `"#"`).
    line_prefixes: []const LinePrefix = &.{},
};

/// Returns the syntax definition for a given MIME type.
///
/// This is the main entry point used by the renderer. It maps MIME type
/// strings (as returned by `mime.zig`) to their corresponding `SyntaxDef`.
///
/// ## Supported MIME types
///
/// | MIME type            | Language     |
/// |----------------------|--------------|
/// | `text/x-zig`         | Zig          |
/// | `text/x-rust`        | Rust         |
/// | `text/x-c`           | C            |
/// | `text/x-c++`         | C++          |
/// | `text/x-go`          | Go           |
/// | `text/x-python`      | Python       |
/// | `text/x-java`        | Java         |
/// | `text/x-kotlin`      | Kotlin       |
/// | `text/x-csharp`      | C#           |
/// | `text/x-swift`       | Swift        |
/// | `text/x-dart`        | Dart         |
/// | `text/javascript`    | JavaScript   |
/// | `text/typescript`    | TypeScript   |
/// | `text/tsx` / `jsx`   | TSX / JSX    |
/// | `text/x-ruby`        | Ruby         |
/// | `text/x-php`         | PHP          |
/// | `text/x-lua`         | Lua          |
/// | `text/x-shellscript` | Shell/Bash   |
/// | `text/x-nushell`     | Nushell      |
/// | `text/x-elixir`      | Elixir       |
/// | `text/x-haskell`     | Haskell      |
/// | `text/x-ocaml`       | OCaml        |
/// | `text/x-sql`         | SQL          |
/// | `text/yaml`          | YAML         |
/// | `text/toml`          | TOML         |
/// | `text/css`           | CSS          |
/// | `text/html`          | HTML         |
/// | `text/markdown`      | Markdown     |
/// | `text/mdx`           | MDX          |
///
/// Returns `null` for unrecognized MIME types (the file will be displayed
/// without syntax highlighting).
pub fn fromMime(mime_type: []const u8) ?SyntaxDef {
    const map = .{
        .{ "text/x-zig", zig_def },
        .{ "text/x-rust", rust_def },
        .{ "text/x-c", c_def },
        .{ "text/x-c++", cpp_def },
        .{ "text/x-go", go_def },
        .{ "text/x-python", python_def },
        .{ "text/x-java", java_def },
        .{ "text/x-kotlin", kotlin_def },
        .{ "text/x-csharp", csharp_def },
        .{ "text/x-swift", swift_def },
        .{ "text/x-dart", dart_def },
        .{ "text/javascript", js_def },
        .{ "text/typescript", ts_def },
        .{ "text/tsx", ts_def },
        .{ "text/jsx", js_def },
        .{ "text/x-ruby", ruby_def },
        .{ "text/x-php", php_def },
        .{ "text/x-lua", lua_def },
        .{ "text/x-shellscript", shell_def },
        .{ "text/x-nushell", shell_def },
        .{ "text/x-elixir", elixir_def },
        .{ "text/x-haskell", haskell_def },
        .{ "text/x-ocaml", ocaml_def },
        .{ "text/x-sql", sql_def },
        .{ "text/yaml", yaml_def },
        .{ "text/toml", toml_def },
        .{ "text/css", css_def },
        .{ "text/html", html_def },
        .{ "text/markdown", markdown_def },
        .{ "text/mdx", markdown_def },
    };

    inline for (map) |entry| {
        if (std.mem.eql(u8, mime_type, entry[0])) return entry[1];
    }

    return null;
}

/// Converts a compile-time array of strings into a `StaticStringMap(void)`.
///
/// This is a convenience function that creates a perfect hash set from a
/// list of words. It runs at **comptime** (compile time), meaning the
/// hash table is built during compilation and has zero runtime cost.
///
/// ## Parameters
///
/// - `words`: A compile-time-known slice of strings to include in the set.
///
/// ## Example (conceptual)
///
/// ```zig
/// const my_keywords = setOf(&.{ "if", "else", "while", "for" });
/// // my_keywords.has("if")    → true
/// // my_keywords.has("print") → false
/// ```
fn setOf(comptime words: []const []const u8) StringSet {
    comptime {
        var kvs: [words.len]struct { []const u8, void } = undefined;
        for (words, 0..) |w, i| {
            kvs[i] = .{ w, {} };
        }

        return StringSet.initComptime(kvs);
    }
}

// Language definitions
//
// Each constant below defines the syntax highlighting rules for one
// programming language. They are referenced by `fromMime` above.
//
// The general pattern is:
//   .keywords     = reserved words (control flow, declarations, etc.)
//   .types        = type names (primitives, common standard library types)
//   .builtins     = built-in functions (only for languages that have them)
//   .line_comment = single-line comment prefix
//   .string_delims = characters that delimit string literals
//   .line_prefixes = (Markdown only) full-line coloring rules

/// Zig language syntax definition.
/// Includes Zig's built-in functions (prefixed with `@`) as builtins.
const zig_def = SyntaxDef{
    .keywords = setOf(&.{ "const", "var", "fn", "pub", "return", "if", "else", "while", "for", "switch", "break", "continue", "defer", "errdefer", "try", "catch", "orelse", "unreachable", "struct", "enum", "union", "error", "test", "comptime", "inline", "export", "extern", "align", "and", "or", "undefined", "null", "true", "false" }),
    .types = setOf(&.{ "u8", "u16", "u32", "u64", "u128", "i8", "i16", "i32", "i64", "i128", "f16", "f32", "f64", "bool", "void", "noreturn", "type", "anyerror", "anytype", "usize", "isize", "comptime_int", "comptime_float" }),
    .builtins = setOf(&.{ "@import", "@as", "@intCast", "@floatCast", "@ptrCast", "@alignCast", "@enumFromInt", "@intFromEnum", "@intFromPtr", "@ptrFromInt", "@bitCast", "@truncate", "@min", "@max", "@tagName", "@typeName", "@typeInfo", "@sizeOf", "@alignOf", "@bitSizeOf", "@errorName", "@panic", "@compileError", "@compileLog", "@field", "@hasField", "@hasDecl", "@call", "@src", "@This", "@Frame", "@frameAddress", "@returnAddress", "@cImport", "@cInclude", "@embedFile", "@splat", "@reduce", "@shuffle", "@select", "@memcpy", "@memset", "@wasmMemorySize", "@wasmMemoryGrow", "@setCold", "@setRuntimeSafety", "@setAlignStack", "@setFloatMode" }),
    .line_comment = "//",
    .string_delims = "\"",
};

/// Rust language syntax definition.
const rust_def = SyntaxDef{
    .keywords = setOf(&.{ "fn", "let", "mut", "const", "pub", "return", "if", "else", "while", "for", "loop", "match", "break", "continue", "struct", "enum", "impl", "trait", "use", "mod", "crate", "self", "super", "as", "in", "ref", "move", "async", "await", "dyn", "where", "type", "unsafe", "extern", "true", "false" }),
    .types = setOf(&.{ "u8", "u16", "u32", "u64", "u128", "i8", "i16", "i32", "i64", "i128", "f32", "f64", "bool", "char", "str", "String", "Vec", "Option", "Result", "Box", "usize", "isize" }),
    .line_comment = "//",
    .string_delims = "\"",
};

/// C language syntax definition.
const c_def = SyntaxDef{
    .keywords = setOf(&.{ "auto", "break", "case", "const", "continue", "default", "do", "else", "enum", "extern", "for", "goto", "if", "inline", "register", "return", "sizeof", "static", "struct", "switch", "typedef", "union", "volatile", "while", "NULL", "true", "false" }),
    .types = setOf(&.{ "int", "char", "float", "double", "void", "long", "short", "unsigned", "signed", "size_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t", "int8_t", "int16_t", "int32_t", "int64_t", "bool" }),
    .line_comment = "//",
    .string_delims = "\"'",
};

/// C++ language syntax definition (extends C with OOP and template keywords).
const cpp_def = SyntaxDef{
    .keywords = setOf(&.{ "auto", "break", "case", "class", "const", "constexpr", "continue", "default", "delete", "do", "else", "enum", "explicit", "extern", "for", "friend", "goto", "if", "inline", "namespace", "new", "noexcept", "nullptr", "operator", "override", "private", "protected", "public", "return", "sizeof", "static", "struct", "switch", "template", "this", "throw", "try", "catch", "typedef", "typename", "union", "using", "virtual", "volatile", "while", "true", "false" }),
    .types = setOf(&.{ "int", "char", "float", "double", "void", "long", "short", "unsigned", "signed", "bool", "string", "vector", "map", "set", "size_t", "auto" }),
    .line_comment = "//",
    .string_delims = "\"'",
};

/// Go language syntax definition.
const go_def = SyntaxDef{
    .keywords = setOf(&.{ "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct", "switch", "type", "var", "true", "false", "nil" }),
    .types = setOf(&.{ "bool", "byte", "complex64", "complex128", "error", "float32", "float64", "int", "int8", "int16", "int32", "int64", "rune", "string", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr" }),
    .line_comment = "//",
    .string_delims = "\"'`",
};

/// Python language syntax definition.
/// Includes common built-in functions as builtins.
const python_def = SyntaxDef{
    .keywords = setOf(&.{ "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while", "with", "yield", "True", "False", "None" }),
    .types = setOf(&.{ "int", "float", "str", "bool", "list", "dict", "tuple", "set", "bytes", "type", "object", "None" }),
    .builtins = setOf(&.{ "print", "len", "range", "enumerate", "zip", "map", "filter", "sorted", "reversed", "min", "max", "sum", "abs", "round", "input", "open", "isinstance", "issubclass", "hasattr", "getattr", "setattr", "delattr", "super", "property", "classmethod", "staticmethod", "iter", "next", "repr", "format", "id", "hash", "dir", "vars", "globals", "locals", "callable", "eval", "exec" }),
    .line_comment = "#",
    .string_delims = "\"'",
};

/// Java language syntax definition.
const java_def = SyntaxDef{
    .keywords = setOf(&.{ "abstract", "assert", "break", "case", "catch", "class", "continue", "default", "do", "else", "enum", "extends", "final", "finally", "for", "if", "implements", "import", "instanceof", "interface", "native", "new", "package", "private", "protected", "public", "return", "static", "strictfp", "super", "switch", "synchronized", "this", "throw", "throws", "transient", "try", "volatile", "while", "true", "false", "null" }),
    .types = setOf(&.{ "boolean", "byte", "char", "double", "float", "int", "long", "short", "void", "String", "Object", "Integer", "Boolean", "List", "Map", "Set", "var" }),
    .line_comment = "//",
    .string_delims = "\"'",
};

/// Kotlin language syntax definition.
const kotlin_def = SyntaxDef{
    .keywords = setOf(&.{ "as", "break", "class", "continue", "do", "else", "false", "for", "fun", "if", "in", "interface", "is", "null", "object", "package", "return", "super", "this", "throw", "true", "try", "typealias", "val", "var", "when", "while", "by", "catch", "constructor", "delegate", "dynamic", "field", "file", "finally", "get", "import", "init", "param", "property", "receiver", "set", "setparam", "where", "actual", "abstract", "annotation", "companion", "const", "crossinline", "data", "enum", "expect", "external", "final", "infix", "inline", "inner", "internal", "lateinit", "noinline", "open", "operator", "out", "override", "private", "protected", "public", "reified", "sealed", "suspend", "tailrec", "vararg" }),
    .types = setOf(&.{ "Boolean", "Byte", "Char", "Double", "Float", "Int", "Long", "Short", "String", "Unit", "Any", "Nothing", "Array", "List", "Map", "Set", "Pair" }),
    .line_comment = "//",
    .string_delims = "\"'",
};

/// C# language syntax definition.
const csharp_def = SyntaxDef{
    .keywords = setOf(&.{ "abstract", "as", "base", "break", "case", "catch", "checked", "class", "const", "continue", "default", "delegate", "do", "else", "enum", "event", "explicit", "extern", "false", "finally", "fixed", "for", "foreach", "goto", "if", "implicit", "in", "interface", "internal", "is", "lock", "namespace", "new", "null", "operator", "out", "override", "params", "private", "protected", "public", "readonly", "ref", "return", "sealed", "sizeof", "stackalloc", "static", "struct", "switch", "this", "throw", "true", "try", "typeof", "unchecked", "unsafe", "using", "var", "virtual", "volatile", "while", "async", "await", "yield" }),
    .types = setOf(&.{ "bool", "byte", "char", "decimal", "double", "float", "int", "long", "object", "sbyte", "short", "string", "uint", "ulong", "ushort", "void", "dynamic", "String", "List", "Dictionary" }),
    .line_comment = "//",
    .string_delims = "\"'",
};

/// Swift language syntax definition.
const swift_def = SyntaxDef{
    .keywords = setOf(&.{ "break", "case", "class", "continue", "default", "defer", "do", "else", "enum", "extension", "fallthrough", "for", "func", "guard", "if", "import", "in", "init", "let", "protocol", "repeat", "return", "self", "static", "struct", "switch", "throw", "try", "catch", "var", "where", "while", "as", "false", "is", "nil", "super", "true", "async", "await", "actor" }),
    .types = setOf(&.{ "Any", "AnyObject", "Bool", "Character", "Double", "Float", "Int", "Int8", "Int16", "Int32", "Int64", "Optional", "String", "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Void", "Array", "Dictionary", "Set" }),
    .line_comment = "//",
    .string_delims = "\"",
};

/// Dart language syntax definition.
const dart_def = SyntaxDef{
    .keywords = setOf(&.{ "abstract", "as", "assert", "async", "await", "break", "case", "catch", "class", "const", "continue", "default", "deferred", "do", "dynamic", "else", "enum", "export", "extends", "extension", "external", "factory", "false", "final", "finally", "for", "get", "if", "implements", "import", "in", "is", "late", "library", "mixin", "new", "null", "on", "operator", "part", "required", "rethrow", "return", "set", "static", "super", "switch", "this", "throw", "true", "try", "typedef", "var", "void", "while", "with", "yield" }),
    .types = setOf(&.{ "bool", "double", "dynamic", "int", "num", "String", "void", "List", "Map", "Set", "Future", "Stream", "Object", "Null", "Function", "Type" }),
    .line_comment = "//",
    .string_delims = "\"'",
};

/// JavaScript language syntax definition.
const js_def = SyntaxDef{
    .keywords = setOf(&.{ "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "export", "extends", "false", "finally", "for", "from", "function", "if", "import", "in", "instanceof", "let", "new", "null", "of", "return", "static", "super", "switch", "this", "throw", "true", "try", "typeof", "undefined", "var", "void", "while", "with", "yield" }),
    .types = setOf(&.{ "Array", "Boolean", "Date", "Error", "Function", "Map", "Number", "Object", "Promise", "RegExp", "Set", "String", "Symbol", "WeakMap", "WeakSet" }),
    .line_comment = "//",
    .string_delims = "\"'`",
};

/// TypeScript language syntax definition (extends JS with type system keywords).
const ts_def = SyntaxDef{
    .keywords = setOf(&.{ "abstract", "any", "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "declare", "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for", "from", "function", "get", "if", "implements", "import", "in", "infer", "instanceof", "interface", "is", "keyof", "let", "module", "namespace", "never", "new", "null", "of", "override", "package", "private", "protected", "public", "readonly", "return", "set", "static", "super", "switch", "this", "throw", "true", "try", "type", "typeof", "undefined", "unique", "unknown", "var", "void", "while", "with", "yield" }),
    .types = setOf(&.{ "Array", "Boolean", "Date", "Error", "Function", "Map", "Number", "Object", "Promise", "RegExp", "Set", "String", "Symbol", "bigint", "boolean", "never", "number", "object", "string", "symbol", "undefined", "unknown", "void" }),
    .line_comment = "//",
    .string_delims = "\"'`",
};

/// Ruby language syntax definition.
const ruby_def = SyntaxDef{
    .keywords = setOf(&.{ "alias", "and", "begin", "break", "case", "class", "def", "defined?", "do", "else", "elsif", "end", "ensure", "false", "for", "if", "in", "module", "next", "nil", "not", "or", "redo", "rescue", "retry", "return", "self", "super", "then", "true", "undef", "unless", "until", "when", "while", "yield", "require", "include", "extend", "attr_reader", "attr_writer", "attr_accessor", "puts", "print" }),
    .types = setOf(&.{ "Array", "Hash", "String", "Integer", "Float", "Symbol", "NilClass", "TrueClass", "FalseClass", "Proc", "Lambda", "IO", "File", "Range", "Regexp" }),
    .line_comment = "#",
    .string_delims = "\"'",
};

/// PHP language syntax definition.
const php_def = SyntaxDef{
    .keywords = setOf(&.{ "abstract", "and", "as", "break", "case", "catch", "class", "clone", "const", "continue", "declare", "default", "do", "else", "elseif", "enddeclare", "endfor", "endforeach", "endif", "endswitch", "endwhile", "extends", "false", "final", "finally", "fn", "for", "foreach", "function", "global", "goto", "if", "implements", "include", "instanceof", "interface", "match", "namespace", "new", "null", "or", "private", "protected", "public", "readonly", "require", "return", "static", "switch", "this", "throw", "trait", "true", "try", "use", "var", "while", "yield" }),
    .types = setOf(&.{ "array", "bool", "callable", "float", "int", "iterable", "mixed", "never", "null", "object", "self", "static", "string", "void" }),
    .line_comment = "//",
    .string_delims = "\"'",
};

/// Lua language syntax definition.
const lua_def = SyntaxDef{
    .keywords = setOf(&.{ "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while" }),
    .types = setOf(&.{ "nil", "boolean", "number", "string", "table", "function", "userdata", "thread" }),
    .line_comment = "--",
    .string_delims = "\"'",
};

/// Shell/Bash language syntax definition.
/// Also used for Nushell files.
const shell_def = SyntaxDef{
    .keywords = setOf(&.{ "if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac", "in", "function", "return", "local", "export", "source", "alias", "unalias", "set", "unset", "shift", "exit", "break", "continue", "readonly", "declare", "typeset", "true", "false" }),
    .types = setOf(&.{}),
    .line_comment = "#",
    .string_delims = "\"'",
};

/// Elixir language syntax definition.
const elixir_def = SyntaxDef{
    .keywords = setOf(&.{ "after", "and", "case", "catch", "cond", "def", "defmodule", "defp", "defstruct", "defprotocol", "defimpl", "do", "else", "end", "false", "fn", "for", "if", "import", "in", "nil", "not", "or", "raise", "receive", "require", "rescue", "return", "true", "try", "unless", "use", "when", "with" }),
    .types = setOf(&.{ "Atom", "BitString", "Float", "Function", "Integer", "List", "Map", "PID", "Port", "Reference", "Tuple", "String", "Keyword" }),
    .line_comment = "#",
    .string_delims = "\"'",
};

/// Haskell language syntax definition.
const haskell_def = SyntaxDef{
    .keywords = setOf(&.{ "as", "case", "class", "data", "default", "deriving", "do", "else", "forall", "foreign", "hiding", "if", "import", "in", "infix", "infixl", "infixr", "instance", "let", "module", "newtype", "of", "qualified", "then", "type", "where", "True", "False" }),
    .types = setOf(&.{ "Bool", "Char", "Double", "Float", "Int", "Integer", "IO", "Maybe", "Either", "String", "Show", "Eq", "Ord", "Num", "Functor", "Monad" }),
    .line_comment = "--",
    .string_delims = "\"'",
};

/// OCaml language syntax definition.
/// Note: OCaml uses block comments `(* ... *)` which are not yet supported.
/// `line_comment` is empty because OCaml has no single-line comment syntax.
const ocaml_def = SyntaxDef{
    .keywords = setOf(&.{ "and", "as", "assert", "begin", "class", "constraint", "do", "done", "downto", "else", "end", "exception", "external", "false", "for", "fun", "function", "functor", "if", "in", "include", "inherit", "initializer", "lazy", "let", "match", "method", "module", "mutable", "new", "object", "of", "open", "or", "private", "rec", "sig", "struct", "then", "to", "true", "try", "type", "val", "virtual", "when", "while", "with" }),
    .types = setOf(&.{ "int", "float", "bool", "char", "string", "unit", "list", "array", "option", "ref" }),
    .line_comment = "",
    .string_delims = "\"'",
};

/// SQL language syntax definition.
/// Includes both uppercase and lowercase variants of keywords since SQL
/// is case-insensitive by convention but developers use both styles.
const sql_def = SyntaxDef{
    .keywords = setOf(&.{ "SELECT", "FROM", "WHERE", "INSERT", "INTO", "UPDATE", "DELETE", "CREATE", "DROP", "ALTER", "TABLE", "INDEX", "VIEW", "JOIN", "INNER", "LEFT", "RIGHT", "OUTER", "ON", "AND", "OR", "NOT", "IN", "IS", "NULL", "AS", "ORDER", "BY", "GROUP", "HAVING", "LIMIT", "OFFSET", "UNION", "ALL", "DISTINCT", "SET", "VALUES", "DEFAULT", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "CASCADE", "EXISTS", "BETWEEN", "LIKE", "TRUE", "FALSE", "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION", "select", "from", "where", "insert", "into", "update", "delete", "create", "drop", "alter", "table", "index", "view", "join", "inner", "left", "right", "outer", "on", "and", "or", "not", "in", "is", "null", "as", "order", "by", "group", "having", "limit", "offset", "union", "all", "distinct", "set", "values", "default", "primary", "key", "foreign", "references", "cascade", "exists", "between", "like", "true", "false", "begin", "commit", "rollback", "transaction" }),
    .types = setOf(&.{ "INT", "INTEGER", "BIGINT", "SMALLINT", "FLOAT", "DOUBLE", "DECIMAL", "NUMERIC", "VARCHAR", "CHAR", "TEXT", "BOOLEAN", "DATE", "TIMESTAMP", "BLOB", "SERIAL", "UUID" }),
    .line_comment = "--",
    .string_delims = "\"'",
};

/// YAML language syntax definition.
/// Keywords include boolean-like values and null variants.
const yaml_def = SyntaxDef{
    .keywords = setOf(&.{ "true", "false", "null", "yes", "no", "on", "off", "True", "False", "Null", "Yes", "No", "On", "Off" }),
    .types = setOf(&.{}),
    .line_comment = "#",
    .string_delims = "\"'",
};

/// TOML language syntax definition.
const toml_def = SyntaxDef{
    .keywords = setOf(&.{ "true", "false" }),
    .types = setOf(&.{}),
    .line_comment = "#",
    .string_delims = "\"'",
};

/// CSS language syntax definition.
/// Note: CSS uses block comments `/* ... */` which are not yet supported.
/// `line_comment` is empty.
const css_def = SyntaxDef{
    .keywords = setOf(&.{ "important", "inherit", "initial", "unset", "none", "auto", "block", "inline", "flex", "grid", "absolute", "relative", "fixed", "sticky", "solid", "dashed", "dotted", "hidden", "visible", "transparent" }),
    .types = setOf(&.{}),
    .line_comment = "",
    .string_delims = "\"'",
};

/// HTML language syntax definition.
/// Minimal definition — HTML is primarily handled via string delimiters
/// for attribute values. No keyword or type highlighting.
const html_def = SyntaxDef{
    .keywords = setOf(&.{}),
    .types = setOf(&.{}),
    .line_comment = "",
    .string_delims = "\"'",
};

/// Markdown language syntax definition.
///
/// Markdown is unique in that it uses `line_prefixes` for full-line
/// coloring instead of keyword-based highlighting. Headings, blockquotes,
/// list items, and horizontal rules each get their own color.
///
/// Code blocks (delimited by ```) are handled separately in the renderer
/// via `code_block_states` — their content is rendered in green.
///
/// The `string_delims` is set to backtick (`` ` ``) to highlight inline
/// code spans.
const markdown_def = SyntaxDef{
    .keywords = setOf(&.{}),
    .types = setOf(&.{}),
    .line_comment = "",
    .string_delims = "`",
    .line_prefixes = &.{
        // Headings: ordered from most specific (######) to least (#) to
        // prevent `#` from matching `###` lines.
        .{ .prefix = "######", .color = "\x1b[1m\x1b[36m" }, // h6: bold cyan
        .{ .prefix = "#####", .color = "\x1b[1m\x1b[36m" }, // h5: bold cyan
        .{ .prefix = "####", .color = "\x1b[1m\x1b[36m" }, // h4: bold cyan
        .{ .prefix = "###", .color = "\x1b[1m\x1b[35m" }, // h3: bold magenta
        .{ .prefix = "##", .color = "\x1b[1m\x1b[33m" }, // h2: bold yellow
        .{ .prefix = "#", .color = "\x1b[1m\x1b[31m" }, // h1: bold red
        // Block elements
        .{ .prefix = ">", .color = "\x1b[90m" }, // blockquote: gray
        .{ .prefix = "- ", .color = "\x1b[36m" }, // unordered list (dash): cyan
        .{ .prefix = "* ", .color = "\x1b[36m" }, // unordered list (asterisk): cyan
        .{ .prefix = "---", .color = "\x1b[90m" }, // horizontal rule: gray
        .{ .prefix = "```", .color = "\x1b[32m" }, // code block fence: green
    },
};

test "fromMime returns SyntaxDef for known MIME types" {
    const zig_syn = fromMime("text/x-zig");
    try std.testing.expect(zig_syn != null);
    try std.testing.expectEqualStrings("//", zig_syn.?.line_comment);

    const py_syn = fromMime("text/x-python");
    try std.testing.expect(py_syn != null);
    try std.testing.expectEqualStrings("#", py_syn.?.line_comment);

    const md_syn = fromMime("text/markdown");
    try std.testing.expect(md_syn != null);
}

test "fromMime returns null for unknown MIME types" {
    try std.testing.expect(fromMime("application/octet-stream") == null);
    try std.testing.expect(fromMime("image/png") == null);
}

test "CSS, HTML, and OCaml have empty line_comment" {
    const css_syn = fromMime("text/css");
    try std.testing.expect(css_syn != null);
    try std.testing.expectEqualStrings("", css_syn.?.line_comment);

    const html_syn = fromMime("text/html");
    try std.testing.expect(html_syn != null);
    try std.testing.expectEqualStrings("", html_syn.?.line_comment);

    const ocaml_syn = fromMime("text/x-ocaml");
    try std.testing.expect(ocaml_syn != null);
    try std.testing.expectEqualStrings("", ocaml_syn.?.line_comment);
}
