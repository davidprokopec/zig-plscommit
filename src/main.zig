//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const std = @import("std");
const os = std.os;
const fs = std.fs;
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const process = std.process;

const io = std.io;
const stdout = io.getStdOut().writer();
const stdin = io.getStdIn().reader();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1) {
        try goThroughFiles(allocator, args[1..]);
    } else {
        try goThroughFiles(allocator, &[_][]const u8{});
    }
}

const CommitType = struct {
    value: []const u8,
    title: []const u8,
};

fn commitFile(allocator: Allocator, file: []const u8) !bool {
    // Get the repository root
    const repo_root = try getRepoRoot(allocator);
    defer allocator.free(repo_root);

    const filestr = if (mem.eql(u8, file, ".")) "" else try std.fmt.allocPrint(allocator, "({s})", .{file});
    defer if (!mem.eql(u8, file, ".")) allocator.free(filestr);

    const prompt = try std.fmt.allocPrint(allocator, "Commit type {s}", .{filestr});
    defer allocator.free(prompt);

    // Prepare commit types
    var commit_types = StringHashMap([]const u8).init(allocator);
    defer commit_types.deinit();

    try commit_types.put("", "custom");
    try commit_types.put("feat", "feat");
    try commit_types.put("fix", "fix");
    try commit_types.put("refactor", "refactor");
    try commit_types.put("revert", "revert");
    try commit_types.put("build", "build");
    try commit_types.put("chore", "chore");
    try commit_types.put("ci", "ci");
    try commit_types.put("docs", "docs");
    try commit_types.put("perf", "perf");
    try commit_types.put("style", "style");
    try commit_types.put("test", "test");

    // Select commit type
    const type_result = try selector(allocator, prompt, commit_types);
    const commit_type = if (mem.eql(u8, type_result, ""))
        try ask(allocator, "Custom commit type")
    else
        type_result;
    defer allocator.free(commit_type);

    // Get commit message
    const commit_msg = try ask(allocator, "What did you modify?");
    defer allocator.free(commit_msg);

    if (commit_type.len > 0 and commit_msg.len > 0) {
        const full = try std.fmt.allocPrint(allocator, "{s}{s}: {s}", .{ commit_type, filestr, commit_msg });
        defer allocator.free(full);

        try runCommand(allocator, repo_root, &[_][]const u8{ "git", "add", file });
        try runCommand(allocator, repo_root, &[_][]const u8{ "git", "commit", "-m", full });

        return true;
    }

    return false;
}

fn askAboutFile(allocator: Allocator, file: []const u8) !void {
    var options = StringHashMap([]const u8).init(allocator);
    defer options.deinit();

    try options.put("0", "do not commit");
    try options.put("1", "commit");
    try options.put("2", "commit parent directory");

    const prompt = try std.fmt.allocPrint(allocator, "Commit {s}?", .{file});
    defer allocator.free(prompt);

    const ans = try selector(allocator, prompt, options);
    defer allocator.free(ans);

    if (mem.eql(u8, ans, "0")) {
        return;
    } else if (mem.eql(u8, ans, "1")) {
        _ = try commitFile(allocator, file);
    } else if (mem.eql(u8, ans, "2")) {
        const parent_path = fs.path.dirname(file);
        if (parent_path) |path| {
            try askAboutFile(allocator, path);
        } else {
            try askAboutFile(allocator, ".");
        }
    }
}

fn goThroughFiles(allocator: Allocator, files: []const []const u8) !void {
    if (files.len == 0) {
        // Get list of modified files from git
        var git_files = try getGitDiffFiles(allocator);
        defer {
            for (git_files.items) |item| {
                allocator.free(item);
            }
            git_files.deinit();
        }

        const final = if (git_files.items.len > 0)
            git_files.items
        else
            &[_][]const u8{"."};

        if (final.len > 1) {
            for (final) |file| {
                try askAboutFile(allocator, file);
            }
        } else {
            try goThroughFiles(allocator, final);
        }
    } else {
        for (files) |file| {
            if (file.len > 0) {
                _ = commitFile(allocator, file) catch |err| {
                    std.debug.print("Error: {}\n", .{err});
                };
            }
        }
    }
}

fn getGitDiffFiles(allocator: Allocator) !ArrayList([]const u8) {
    const result = try runCommandOutput(allocator, null, &[_][]const u8{ "git", "diff", "--name-only" });
    defer allocator.free(result);

    var files = ArrayList([]const u8).init(allocator);
    errdefer {
        for (files.items) |item| {
            allocator.free(item);
        }
        files.deinit();
    }

    var lines = mem.splitAny(u8, result, "\n");
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        // Process file path according to original rules
        var file = line;

        if (mem.endsWith(u8, file, "/"))
            file = file[0 .. file.len - 1];

        if (mem.endsWith(u8, file, "/mod.rs"))
            file = file[0 .. file.len - 7];

        if (mem.endsWith(u8, file, "/index.ts") or mem.endsWith(u8, file, "/index.js"))
            file = file[0 .. file.len - 9];

        if (mem.eql(u8, file, "src") or mem.endsWith(u8, file, "/src"))
            continue;

        // Truncate path to max 3 components
        const components = mem.count(u8, file, "/") + 1;
        if (components > 3) {
            var count: usize = 0;
            var last_index: usize = file.len;

            var i: usize = file.len;
            while (i > 0) {
                i -= 1;
                if (file[i] == '/') {
                    count += 1;
                    if (count == 3) {
                        file = file[i..last_index];
                        break;
                    }
                    last_index = i;
                }
            }
        }

        if (file.len > 0) {
            const duped = try allocator.dupe(u8, file);
            try files.append(duped);
        }
    }

    return files;
}

fn getRepoRoot(allocator: Allocator) ![]const u8 {
    const result = try runCommandOutput(allocator, null, &[_][]const u8{ "git", "rev-parse", "--show-toplevel" });
    // Trim trailing newline
    const trimmed = mem.trimRight(u8, result, "\n");
    return allocator.dupe(u8, trimmed);
}

fn runCommand(allocator: Allocator, cwd: ?[]const u8, argv: []const []const u8) !void {
    const result = try process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .cwd = cwd,
    });
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    if (result.stdout.len > 0) {
        try stdout.writeAll(result.stdout);
    }

    if (result.stderr.len > 0) {
        try stdout.writeAll(result.stderr);
    }

    if (result.term.Exited != 0) {
        return error.CommandFailed;
    }
}

fn runCommandOutput(allocator: Allocator, cwd: ?[]const u8, argv: []const []const u8) ![]const u8 {
    const result = try process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .cwd = cwd,
    });

    allocator.free(result.stderr);
    return result.stdout;
}

fn ask(allocator: Allocator, question: []const u8) ![]const u8 {
    try stdout.print("{s}: ", .{question});

    var buffer = ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try stdin.readUntilDelimiterArrayList(&buffer, '\n', 1024);

    return allocator.dupe(u8, mem.trim(u8, buffer.items, "\r\n"));
}

fn selector(allocator: Allocator, question: []const u8, options: StringHashMap([]const u8)) ![]const u8 {
    try stdout.print("{s}:\n", .{question});

    var iterator = options.iterator();
    var option_keys = ArrayList([]const u8).init(allocator);
    defer option_keys.deinit();

    // Print options
    var i: usize = 0;
    while (iterator.next()) |entry| {
        try stdout.print("[{}] {s}\n", .{ i, entry.value_ptr.* });
        try option_keys.append(entry.key_ptr.*);
        i += 1;
    }

    // Get selection
    try stdout.print("Select option: ", .{});

    var buffer = ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try stdin.readUntilDelimiterArrayList(&buffer, '\n', 64);
    const selection = mem.trim(u8, buffer.items, "\r\n");

    // Convert to integer and get corresponding key
    const selected_index = std.fmt.parseInt(usize, selection, 10) catch {
        // If entry fails, just return empty string
        return allocator.dupe(u8, "");
    };

    if (selected_index >= option_keys.items.len) {
        return allocator.dupe(u8, "");
    }

    return allocator.dupe(u8, option_keys.items[selected_index]);
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "use other module" {
    try std.testing.expectEqual(@as(i32, 150), lib.add(100, 50));
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("zig_plscommit_lib");
