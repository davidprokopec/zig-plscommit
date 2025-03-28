# plscommit

A simple CLI tool for creating well-formatted Git commit messages, written in Zig.

## Features

- Helps format commits with standardized prefixes (feat, fix, refactor, etc.)
- Intelligently identifies changed files from git diff
- Interactive prompts for selecting files and commit message details
- Simple and intuitive CLI interface

## Installation

### Prerequisites

- [Zig](https://ziglang.org/) compiler (0.11.0 or later)

### Building from source

```bash
git clone https://github.com/yourusername/zig-plscommit.git
cd zig-plscommit
zig build -Doptimize=ReleaseSafe
```

This will build the executable in `zig-out/bin/plscommit`. You can add this to your PATH or create a symlink to use it system-wide.

## Usage

### Basic usage

Run the tool in a git repository:

```bash
plscommit
```

This will scan for modified files and prompt you to commit them.

### Specifying files

You can also specify files to commit:

```bash
plscommit path/to/file.zig
```

## Commit Types

The tool supports the following commit types:

- `feat`: A new feature
- `fix`: A bug fix
- `refactor`: Code refactoring
- `revert`: Reverting changes
- `build`: Changes to build system
- `chore`: Maintenance tasks
- `ci`: CI/CD changes
- `docs`: Documentation updates
- `perf`: Performance improvements
- `style`: Code style changes
- `test`: Adding/updating tests

## License

GPL-3.0-or-later 