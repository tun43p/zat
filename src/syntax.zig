const std = @import("std");

pub const LinePrefix = struct {
    prefix: []const u8,
    color: []const u8,
};

pub const SyntaxDef = struct {
    keywords: []const []const u8,
    types: []const []const u8,
    builtins: []const []const u8 = &.{},
    line_comment: []const u8,
    string_delims: []const u8,
    line_prefixes: []const LinePrefix = &.{},
};

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

// ── Language definitions ──

const zig_def = SyntaxDef{
    .keywords = &.{ "const", "var", "fn", "pub", "return", "if", "else", "while", "for", "switch", "break", "continue", "defer", "errdefer", "try", "catch", "orelse", "unreachable", "struct", "enum", "union", "error", "test", "comptime", "inline", "export", "extern", "align", "and", "or", "undefined", "null", "true", "false" },
    .types = &.{ "u8", "u16", "u32", "u64", "u128", "i8", "i16", "i32", "i64", "i128", "f16", "f32", "f64", "bool", "void", "noreturn", "type", "anyerror", "anytype", "usize", "isize", "comptime_int", "comptime_float" },
    .builtins = &.{ "@import", "@as", "@intCast", "@floatCast", "@ptrCast", "@alignCast", "@enumFromInt", "@intFromEnum", "@intFromPtr", "@ptrFromInt", "@bitCast", "@truncate", "@min", "@max", "@tagName", "@typeName", "@typeInfo", "@sizeOf", "@alignOf", "@bitSizeOf", "@errorName", "@panic", "@compileError", "@compileLog", "@field", "@hasField", "@hasDecl", "@call", "@src", "@This", "@Frame", "@frameAddress", "@returnAddress", "@cImport", "@cInclude", "@embedFile", "@splat", "@reduce", "@shuffle", "@select", "@memcpy", "@memset", "@wasmMemorySize", "@wasmMemoryGrow", "@setCold", "@setRuntimeSafety", "@setAlignStack", "@setFloatMode" },
    .line_comment = "//",
    .string_delims = "\"",
};

const rust_def = SyntaxDef{
    .keywords = &.{ "fn", "let", "mut", "const", "pub", "return", "if", "else", "while", "for", "loop", "match", "break", "continue", "struct", "enum", "impl", "trait", "use", "mod", "crate", "self", "super", "as", "in", "ref", "move", "async", "await", "dyn", "where", "type", "unsafe", "extern", "true", "false" },
    .types = &.{ "u8", "u16", "u32", "u64", "u128", "i8", "i16", "i32", "i64", "i128", "f32", "f64", "bool", "char", "str", "String", "Vec", "Option", "Result", "Box", "usize", "isize" },
    .line_comment = "//",
    .string_delims = "\"",
};

const c_def = SyntaxDef{
    .keywords = &.{ "auto", "break", "case", "const", "continue", "default", "do", "else", "enum", "extern", "for", "goto", "if", "inline", "register", "return", "sizeof", "static", "struct", "switch", "typedef", "union", "volatile", "while", "NULL", "true", "false" },
    .types = &.{ "int", "char", "float", "double", "void", "long", "short", "unsigned", "signed", "size_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t", "int8_t", "int16_t", "int32_t", "int64_t", "bool" },
    .line_comment = "//",
    .string_delims = "\"'",
};

const cpp_def = SyntaxDef{
    .keywords = &.{ "auto", "break", "case", "class", "const", "constexpr", "continue", "default", "delete", "do", "else", "enum", "explicit", "extern", "for", "friend", "goto", "if", "inline", "namespace", "new", "noexcept", "nullptr", "operator", "override", "private", "protected", "public", "return", "sizeof", "static", "struct", "switch", "template", "this", "throw", "try", "catch", "typedef", "typename", "union", "using", "virtual", "volatile", "while", "true", "false" },
    .types = &.{ "int", "char", "float", "double", "void", "long", "short", "unsigned", "signed", "bool", "string", "vector", "map", "set", "size_t", "auto" },
    .line_comment = "//",
    .string_delims = "\"'",
};

const go_def = SyntaxDef{
    .keywords = &.{ "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct", "switch", "type", "var", "true", "false", "nil" },
    .types = &.{ "bool", "byte", "complex64", "complex128", "error", "float32", "float64", "int", "int8", "int16", "int32", "int64", "rune", "string", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr" },
    .line_comment = "//",
    .string_delims = "\"'`",
};

const python_def = SyntaxDef{
    .keywords = &.{ "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while", "with", "yield", "True", "False", "None" },
    .types = &.{ "int", "float", "str", "bool", "list", "dict", "tuple", "set", "bytes", "type", "object", "None" },
    .builtins = &.{ "print", "len", "range", "enumerate", "zip", "map", "filter", "sorted", "reversed", "min", "max", "sum", "abs", "round", "input", "open", "isinstance", "issubclass", "hasattr", "getattr", "setattr", "delattr", "super", "property", "classmethod", "staticmethod", "iter", "next", "repr", "format", "id", "hash", "dir", "vars", "globals", "locals", "callable", "eval", "exec" },
    .line_comment = "#",
    .string_delims = "\"'",
};

const java_def = SyntaxDef{
    .keywords = &.{ "abstract", "assert", "break", "case", "catch", "class", "continue", "default", "do", "else", "enum", "extends", "final", "finally", "for", "if", "implements", "import", "instanceof", "interface", "native", "new", "package", "private", "protected", "public", "return", "static", "strictfp", "super", "switch", "synchronized", "this", "throw", "throws", "transient", "try", "volatile", "while", "true", "false", "null" },
    .types = &.{ "boolean", "byte", "char", "double", "float", "int", "long", "short", "void", "String", "Object", "Integer", "Boolean", "List", "Map", "Set", "var" },
    .line_comment = "//",
    .string_delims = "\"'",
};

const kotlin_def = SyntaxDef{
    .keywords = &.{ "as", "break", "class", "continue", "do", "else", "false", "for", "fun", "if", "in", "interface", "is", "null", "object", "package", "return", "super", "this", "throw", "true", "try", "typealias", "val", "var", "when", "while", "by", "catch", "constructor", "delegate", "dynamic", "field", "file", "finally", "get", "import", "init", "param", "property", "receiver", "set", "setparam", "where", "actual", "abstract", "annotation", "companion", "const", "crossinline", "data", "enum", "expect", "external", "final", "infix", "inline", "inner", "internal", "lateinit", "noinline", "open", "operator", "out", "override", "private", "protected", "public", "reified", "sealed", "suspend", "tailrec", "vararg" },
    .types = &.{ "Boolean", "Byte", "Char", "Double", "Float", "Int", "Long", "Short", "String", "Unit", "Any", "Nothing", "Array", "List", "Map", "Set", "Pair" },
    .line_comment = "//",
    .string_delims = "\"'",
};

const csharp_def = SyntaxDef{
    .keywords = &.{ "abstract", "as", "base", "break", "case", "catch", "checked", "class", "const", "continue", "default", "delegate", "do", "else", "enum", "event", "explicit", "extern", "false", "finally", "fixed", "for", "foreach", "goto", "if", "implicit", "in", "interface", "internal", "is", "lock", "namespace", "new", "null", "operator", "out", "override", "params", "private", "protected", "public", "readonly", "ref", "return", "sealed", "sizeof", "stackalloc", "static", "struct", "switch", "this", "throw", "true", "try", "typeof", "unchecked", "unsafe", "using", "var", "virtual", "volatile", "while", "async", "await", "yield" },
    .types = &.{ "bool", "byte", "char", "decimal", "double", "float", "int", "long", "object", "sbyte", "short", "string", "uint", "ulong", "ushort", "void", "dynamic", "String", "List", "Dictionary" },
    .line_comment = "//",
    .string_delims = "\"'",
};

const swift_def = SyntaxDef{
    .keywords = &.{ "break", "case", "class", "continue", "default", "defer", "do", "else", "enum", "extension", "fallthrough", "for", "func", "guard", "if", "import", "in", "init", "let", "protocol", "repeat", "return", "self", "static", "struct", "switch", "throw", "try", "catch", "var", "where", "while", "as", "false", "is", "nil", "super", "true", "async", "await", "actor" },
    .types = &.{ "Any", "AnyObject", "Bool", "Character", "Double", "Float", "Int", "Int8", "Int16", "Int32", "Int64", "Optional", "String", "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Void", "Array", "Dictionary", "Set" },
    .line_comment = "//",
    .string_delims = "\"",
};

const dart_def = SyntaxDef{
    .keywords = &.{ "abstract", "as", "assert", "async", "await", "break", "case", "catch", "class", "const", "continue", "default", "deferred", "do", "dynamic", "else", "enum", "export", "extends", "extension", "external", "factory", "false", "final", "finally", "for", "get", "if", "implements", "import", "in", "is", "late", "library", "mixin", "new", "null", "on", "operator", "part", "required", "rethrow", "return", "set", "static", "super", "switch", "this", "throw", "true", "try", "typedef", "var", "void", "while", "with", "yield" },
    .types = &.{ "bool", "double", "dynamic", "int", "num", "String", "void", "List", "Map", "Set", "Future", "Stream", "Object", "Null", "Function", "Type" },
    .line_comment = "//",
    .string_delims = "\"'",
};

const js_def = SyntaxDef{
    .keywords = &.{ "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "export", "extends", "false", "finally", "for", "from", "function", "if", "import", "in", "instanceof", "let", "new", "null", "of", "return", "static", "super", "switch", "this", "throw", "true", "try", "typeof", "undefined", "var", "void", "while", "with", "yield" },
    .types = &.{ "Array", "Boolean", "Date", "Error", "Function", "Map", "Number", "Object", "Promise", "RegExp", "Set", "String", "Symbol", "WeakMap", "WeakSet" },
    .line_comment = "//",
    .string_delims = "\"'`",
};

const ts_def = SyntaxDef{
    .keywords = &.{ "abstract", "any", "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "declare", "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for", "from", "function", "get", "if", "implements", "import", "in", "infer", "instanceof", "interface", "is", "keyof", "let", "module", "namespace", "never", "new", "null", "of", "override", "package", "private", "protected", "public", "readonly", "return", "set", "static", "super", "switch", "this", "throw", "true", "try", "type", "typeof", "undefined", "unique", "unknown", "var", "void", "while", "with", "yield" },
    .types = &.{ "Array", "Boolean", "Date", "Error", "Function", "Map", "Number", "Object", "Promise", "RegExp", "Set", "String", "Symbol", "bigint", "boolean", "never", "number", "object", "string", "symbol", "undefined", "unknown", "void" },
    .line_comment = "//",
    .string_delims = "\"'`",
};

const ruby_def = SyntaxDef{
    .keywords = &.{ "alias", "and", "begin", "break", "case", "class", "def", "defined?", "do", "else", "elsif", "end", "ensure", "false", "for", "if", "in", "module", "next", "nil", "not", "or", "redo", "rescue", "retry", "return", "self", "super", "then", "true", "undef", "unless", "until", "when", "while", "yield", "require", "include", "extend", "attr_reader", "attr_writer", "attr_accessor", "puts", "print" },
    .types = &.{ "Array", "Hash", "String", "Integer", "Float", "Symbol", "NilClass", "TrueClass", "FalseClass", "Proc", "Lambda", "IO", "File", "Range", "Regexp" },
    .line_comment = "#",
    .string_delims = "\"'",
};

const php_def = SyntaxDef{
    .keywords = &.{ "abstract", "and", "as", "break", "case", "catch", "class", "clone", "const", "continue", "declare", "default", "do", "else", "elseif", "enddeclare", "endfor", "endforeach", "endif", "endswitch", "endwhile", "extends", "false", "final", "finally", "fn", "for", "foreach", "function", "global", "goto", "if", "implements", "include", "instanceof", "interface", "match", "namespace", "new", "null", "or", "private", "protected", "public", "readonly", "require", "return", "static", "switch", "this", "throw", "trait", "true", "try", "use", "var", "while", "yield" },
    .types = &.{ "array", "bool", "callable", "float", "int", "iterable", "mixed", "never", "null", "object", "self", "static", "string", "void" },
    .line_comment = "//",
    .string_delims = "\"'",
};

const lua_def = SyntaxDef{
    .keywords = &.{ "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while" },
    .types = &.{ "nil", "boolean", "number", "string", "table", "function", "userdata", "thread" },
    .line_comment = "--",
    .string_delims = "\"'",
};

const shell_def = SyntaxDef{
    .keywords = &.{ "if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac", "in", "function", "return", "local", "export", "source", "alias", "unalias", "set", "unset", "shift", "exit", "break", "continue", "readonly", "declare", "typeset", "true", "false" },
    .types = &.{},
    .line_comment = "#",
    .string_delims = "\"'",
};

const elixir_def = SyntaxDef{
    .keywords = &.{ "after", "and", "case", "catch", "cond", "def", "defmodule", "defp", "defstruct", "defprotocol", "defimpl", "do", "else", "end", "false", "fn", "for", "if", "import", "in", "nil", "not", "or", "raise", "receive", "require", "rescue", "return", "true", "try", "unless", "use", "when", "with" },
    .types = &.{ "Atom", "BitString", "Float", "Function", "Integer", "List", "Map", "PID", "Port", "Reference", "Tuple", "String", "Keyword" },
    .line_comment = "#",
    .string_delims = "\"'",
};

const haskell_def = SyntaxDef{
    .keywords = &.{ "as", "case", "class", "data", "default", "deriving", "do", "else", "forall", "foreign", "hiding", "if", "import", "in", "infix", "infixl", "infixr", "instance", "let", "module", "newtype", "of", "qualified", "then", "type", "where", "True", "False" },
    .types = &.{ "Bool", "Char", "Double", "Float", "Int", "Integer", "IO", "Maybe", "Either", "String", "Show", "Eq", "Ord", "Num", "Functor", "Monad" },
    .line_comment = "--",
    .string_delims = "\"'",
};

const ocaml_def = SyntaxDef{
    .keywords = &.{ "and", "as", "assert", "begin", "class", "constraint", "do", "done", "downto", "else", "end", "exception", "external", "false", "for", "fun", "function", "functor", "if", "in", "include", "inherit", "initializer", "lazy", "let", "match", "method", "module", "mutable", "new", "object", "of", "open", "or", "private", "rec", "sig", "struct", "then", "to", "true", "try", "type", "val", "virtual", "when", "while", "with" },
    .types = &.{ "int", "float", "bool", "char", "string", "unit", "list", "array", "option", "ref" },
    .line_comment = "(*",
    .string_delims = "\"'",
};

const sql_def = SyntaxDef{
    .keywords = &.{ "SELECT", "FROM", "WHERE", "INSERT", "INTO", "UPDATE", "DELETE", "CREATE", "DROP", "ALTER", "TABLE", "INDEX", "VIEW", "JOIN", "INNER", "LEFT", "RIGHT", "OUTER", "ON", "AND", "OR", "NOT", "IN", "IS", "NULL", "AS", "ORDER", "BY", "GROUP", "HAVING", "LIMIT", "OFFSET", "UNION", "ALL", "DISTINCT", "SET", "VALUES", "DEFAULT", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "CASCADE", "EXISTS", "BETWEEN", "LIKE", "TRUE", "FALSE", "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION", "select", "from", "where", "insert", "into", "update", "delete", "create", "drop", "alter", "table", "index", "view", "join", "inner", "left", "right", "outer", "on", "and", "or", "not", "in", "is", "null", "as", "order", "by", "group", "having", "limit", "offset", "union", "all", "distinct", "set", "values", "default", "primary", "key", "foreign", "references", "cascade", "exists", "between", "like", "true", "false", "begin", "commit", "rollback", "transaction" },
    .types = &.{ "INT", "INTEGER", "BIGINT", "SMALLINT", "FLOAT", "DOUBLE", "DECIMAL", "NUMERIC", "VARCHAR", "CHAR", "TEXT", "BOOLEAN", "DATE", "TIMESTAMP", "BLOB", "SERIAL", "UUID" },
    .line_comment = "--",
    .string_delims = "\"'",
};

const yaml_def = SyntaxDef{
    .keywords = &.{ "true", "false", "null", "yes", "no", "on", "off", "True", "False", "Null", "Yes", "No", "On", "Off" },
    .types = &.{},
    .line_comment = "#",
    .string_delims = "\"'",
};

const toml_def = SyntaxDef{
    .keywords = &.{ "true", "false" },
    .types = &.{},
    .line_comment = "#",
    .string_delims = "\"'",
};

const css_def = SyntaxDef{
    .keywords = &.{ "important", "inherit", "initial", "unset", "none", "auto", "block", "inline", "flex", "grid", "absolute", "relative", "fixed", "sticky", "solid", "dashed", "dotted", "hidden", "visible", "transparent" },
    .types = &.{},
    .line_comment = "//",
    .string_delims = "\"'",
};

const html_def = SyntaxDef{
    .keywords = &.{},
    .types = &.{},
    .line_comment = "<!--",
    .string_delims = "\"'",
};

const markdown_def = SyntaxDef{
    .keywords = &.{},
    .types = &.{},
    .line_comment = "",
    .string_delims = "`",
    .line_prefixes = &.{
        .{ .prefix = "######", .color = "\x1b[1m\x1b[36m" }, // h6: bold cyan
        .{ .prefix = "#####", .color = "\x1b[1m\x1b[36m" },  // h5: bold cyan
        .{ .prefix = "####", .color = "\x1b[1m\x1b[36m" },   // h4: bold cyan
        .{ .prefix = "###", .color = "\x1b[1m\x1b[35m" },    // h3: bold magenta
        .{ .prefix = "##", .color = "\x1b[1m\x1b[33m" },     // h2: bold yellow
        .{ .prefix = "#", .color = "\x1b[1m\x1b[31m" },      // h1: bold red
        .{ .prefix = ">", .color = "\x1b[90m" },              // blockquote: gray
        .{ .prefix = "- ", .color = "\x1b[36m" },             // list: cyan
        .{ .prefix = "* ", .color = "\x1b[36m" },             // list: cyan
        .{ .prefix = "---", .color = "\x1b[90m" },            // hr: gray
        .{ .prefix = "```", .color = "\x1b[32m" },            // code block: green
    },
};
