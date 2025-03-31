const std = @import("std");
const Prompter = @import("prompter");

const CommitType = struct {
    name: []const u8,
    description: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) @panic("The allocator has leaked!");
    }
    const allocator = gpa.allocator();
    const out = std.io.getStdOut().writer();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var path_arg: ?[]const u8 = null;
    if (args.len > 1) {
        path_arg = args[1];
    }

    // Setup the prompt theme
    const theme = Prompter.Themes.SimpleTheme{};
    var p = Prompter.Prompt.init(allocator, theme.theme());

    // Define commit types with descriptions
    const commit_types = [_]CommitType{
        .{ .name = "feat", .description = "A new feature" },
        .{ .name = "fix", .description = "A bug fix" },
        .{ .name = "refactor", .description = "Code change that neither fixes a bug nor adds a feature" },
        .{ .name = "revert", .description = "Revert to a previous commit" },
        .{ .name = "build", .description = "Changes affecting build system or external dependencies" },
        .{ .name = "chore", .description = "Other changes that don't modify src or test files" },
        .{ .name = "ci", .description = "Changes to CI configuration files and scripts" },
        .{ .name = "docs", .description = "Documentation only changes" },
        .{ .name = "perf", .description = "A code change that improves performance" },
        .{ .name = "style", .description = "Changes that do not affect the meaning of the code" },
        .{ .name = "test", .description = "Adding missing tests or correcting existing tests" },
        .{ .name = "debug", .description = "Adding or modifying debug output" },
        .{ .name = "custom", .description = "Custom commit type" },
    };

    // Prepare options for display
    var options = try allocator.alloc([]const u8, commit_types.len);
    defer allocator.free(options);

    // We need to free each option string before exiting
    for (commit_types, 0..) |ct, i| {
        const option_text = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ ct.name, ct.description });
        options[i] = option_text;
    }
    // Add a defer block to free all the option strings
    defer {
        for (options) |option| {
            allocator.free(option);
        }
    }

    // Prompt for commit type selection
    try out.writeAll("Select commit type:\n");
    const sel_opt = try p.option("Commit type", options, 0);

    // Handle selection abort
    if (sel_opt == null) {
        try out.writeAll("Commit aborted.\n");
        return;
    }

    // Handle selected commit type
    var commit_type: []const u8 = undefined;
    var custom_type: []const u8 = undefined;
    var needs_to_free_custom_type = false;

    if (sel_opt.? == commit_types.len - 1) {
        custom_type = try p.string("Enter custom commit type", null);
        needs_to_free_custom_type = true;
        commit_type = custom_type;
    } else {
        commit_type = commit_types[sel_opt.?].name;
    }

    // Prompt for commit message
    const commit_message = try p.string("Enter commit message", null);
    defer allocator.free(commit_message);

    // Build the full commit message
    const full_commit_message = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ commit_type, commit_message });
    defer allocator.free(full_commit_message);

    // Free custom type if it was allocated
    defer if (needs_to_free_custom_type) allocator.free(custom_type);

    // Execute git commands using process.Child
    // First check if there are any staged files
    var has_staged_files = false;
    {
        var diff_cmd_args = [_][]const u8{ "git", "diff", "--cached", "--quiet" };
        var diff_cmd = std.process.Child.init(&diff_cmd_args, allocator);
        diff_cmd.stderr_behavior = .Ignore;
        diff_cmd.stdout_behavior = .Ignore;
        
        const diff_term = try diff_cmd.spawnAndWait();
        // Exit code 1 means there are staged changes, 0 means no staged changes
        has_staged_files = diff_term.Exited == 1;
    }

    // Only add files if there are no staged files
    if (!has_staged_files) {
        var add_cmd_args = if (path_arg) |path|
            [_][]const u8{ "git", "add", path }
        else
            [_][]const u8{ "git", "add", "." };

        var add_cmd = std.process.Child.init(&add_cmd_args, allocator);
        add_cmd.stderr_behavior = .Inherit;
        add_cmd.stdout_behavior = .Inherit;

        const add_term = try add_cmd.spawnAndWait();

        if (add_term.Exited != 0) {
            try out.writeAll("Error adding files to git\n");
            return;
        }
    }

    // Create commit
    var commit_cmd_args = [_][]const u8{ "git", "commit", "-m", full_commit_message };
    var commit_cmd = std.process.Child.init(&commit_cmd_args, allocator);
    commit_cmd.stderr_behavior = .Inherit;
    commit_cmd.stdout_behavior = .Inherit;

    const commit_term = try commit_cmd.spawnAndWait();

    if (commit_term.Exited != 0) {
        try out.writeAll("Error creating commit\n");
        return;
    }

    try out.print("Successfully committed: {s}\n", .{full_commit_message});
}
