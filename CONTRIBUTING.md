# Contributing to Zat

Thanks for your interest in contributing to Zat!

## Prerequisites

- [Zig](https://ziglang.org/download/) 0.15.2+
- Git with GPG signing configured

## Getting Started

```bash
git clone https://github.com/tun43p/zat.git
cd zat
zig build
zig build run -- README.md
```

## Development

### Build

```bash
zig build                              # debug build
zig build -Doptimize=ReleaseFast       # optimized build
```

### Test

```bash
zig build test
```

### Project Structure

```txt
src/
  main.zig       # Entry point, input loop, state management
  terminal.zig   # Raw mode, alternate screen, key reading
  renderer.zig   # Screen rendering (header, lines, footer)
  syntax.zig     # Syntax highlighting definitions
  mime.zig       # MIME type detection by extension
  file.zig       # File loading and metadata
```

## Commit Convention

We use [Conventional Commits](https://www.conventionalcommits.org/). All commits **must** follow this format:

```txt
<type>(<scope?>): <description>
```

### Types

- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation only
- `style` - Formatting, no code change
- `refactor` - Code change that neither fixes a bug nor adds a feature
- `test` - Adding or updating tests
- `chore` - Build process, dependencies, CI

### Examples

```txt
feat(syntax): add Ruby syntax highlighting
fix(renderer): fix footer overlap on small terminals
docs: update installation instructions
chore: update zig to 0.15.2
```

## Signed Commits

All commits **must** be signed. Set up GPG signing:

```bash
git config --global commit.gpgsign true
git config --global user.signingkey <your-gpg-key-id>
```

See [GitHub's guide on signing commits](https://docs.github.com/en/authentication/managing-commit-signature-verification) if you need help setting this up.

## Pull Requests

1. Fork the repository
2. Create a branch from `main` (`feat/my-feature` or `fix/my-bug`)
3. Make your changes
4. Ensure `zig build test` passes
5. Submit a PR against `main`

## Adding a New Language

To add syntax highlighting for a new language:

1. Add the MIME type in `src/mime.zig`
2. Create a `SyntaxDef` in `src/syntax.zig`
3. Add it to the `fromMime` map

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
