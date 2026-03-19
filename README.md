# Zat

What `cat` would be if it went to the gym, thanks to Zig.

A modern file reader that automatically detects MIME types.

![Zat](./docs/zat.png)

## Table of Contents

- [Zat](#zat)
  - [Table of Contents](#table-of-contents)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
    - [Using Homebrew](#using-homebrew)
    - [From Source](#from-source)
      - [Download](#download)
      - [Build the project](#build-the-project)
      - [Build in optimized mode](#build-in-optimized-mode)
  - [Usage](#usage)
    - [Basic Usage](#basic-usage)
    - [Run directly with zig build](#run-directly-with-zig-build)
    - [Run the compiled executable](#run-the-compiled-executable)
    - [Install globally (optional)](#install-globally-optional)
  - [Keyboard Shortcuts](#keyboard-shortcuts)
    - [Navigation](#navigation)
    - [Command Mode](#command-mode)
    - [Search Mode](#search-mode)
  - [Build Commands](#build-commands)
  - [Dependencies](#dependencies)
  - [Testing](#testing)
  - [Authors](#authors)
  - [License](#license)

## Prerequisites

- **Zig** version 0.15.2 or higher
  - Download Zig from [ziglang.org/download](https://ziglang.org/download/)
  - Check your version: `zig version`

## Installation

### Using Homebrew

```bash
brew install tun43p/tap/zat
```

### From Source

#### Download

Clone the repository:

```bash
git clone https://github.com/tun43p/zat.git
cd zat
```

#### Build the project

```bash
zig build
```

The executable will be generated in `zig-out/bin/zat`.

#### Build in optimized mode

For an optimized (release) version:

```bash
zig build -Doptimize=ReleaseFast
```

Available optimization options:

- `Debug` (default) - No optimization, with debug symbols
- `ReleaseSafe` - Optimized with safety checks
- `ReleaseFast` - Optimized for speed
- `ReleaseSmall` - Optimized for size

## Usage

### Basic Usage

```bash
zat [file]
```

### Run directly with zig build

```bash
zig build run -- [file]
```

Example:

```bash
zig build run -- src/main.zig
```

### Run the compiled executable

```bash
./zig-out/bin/zat [file]
```

Example:

```bash
./zig-out/bin/zat README.md
```

### Install globally (optional)

To install the executable on your system:

```bash
zig build install --prefix ~/.local
```

Then add `~/.local/bin` to your PATH if not already done.

## Keyboard Shortcuts

### Navigation

| Key                | Action      |
| ------------------ | ----------- |
| `j` / `Arrow Down` | Scroll down |
| `k` / `Arrow Up`   | Scroll up   |

### Command Mode

| Key   | Action             |
| ----- | ------------------ |
| `:`   | Enter command mode |
| `Esc` | Exit command mode  |

| Command | Action                  |
| ------- | ----------------------- |
| `:q`    | Quit                    |
| `:help` | Show available commands |

### Search Mode

| Key     | Action                               |
| ------- | ------------------------------------ |
| `/`     | Enter search mode                    |
| `Enter` | Confirm search                       |
| `Esc`   | Cancel search / Clear search results |
| `n`     | Jump to next match                   |
| `N`     | Jump to previous match               |

## Build Commands

- `zig build` - Build the project
- `zig build run -- [file]` - Build and run the project with arguments
- `zig build test` - Run tests
- `zig build -Doptimize=ReleaseFast` - Build in optimized release mode

## Dependencies

The project uses the following dependencies:

- **mime** - MIME type detection
  - Repository: [andrewrk/mime](https://github.com/andrewrk/mime)
  - Version: 4.0.0

Dependencies are automatically managed by the Zig build system and will be downloaded on first build.

## Testing

To run tests:

```bash
zig build test
```

## Authors

- **tun43p** - _Initial work_ - [tun43p](https://github.com/tun43p)

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
