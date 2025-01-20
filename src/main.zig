const std = @import("std");
const clap = @import("clap");

const Args = struct {
    url: []const u8,
    output: []const u8,
};
fn parse() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
const Args = struct {
    url: []const u8,
    output: []const u8,
};

fn parse(
    allocator: std.mem.Allocator,
) !Args {
) !void {
fn parse(
    allocator: std.mem.Allocator,
) !void {
) !Args {
    const params = comptime clap.parseParamsComptime(
        \\-u, --url <str>...     URL of komoot track
        \\-o, --output <str>...  GPX Outputfile
        \\<str>...
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        // Report useful error and exit.
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    const output = if (res.args.output.len > 0) res.args.output[0] else return error.MissingCommand;
    const url = if (res.args.url.len > 0) res.args.url[0] else return error.MissingCommand;

    return Args{
        .url = url,
        .output = output,
    };
}
        .url = url,
        .output = output,
    };
}
}

pub fn main() !void {
    const alloc = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    const allocator = arena.allocator();
    const allocator = arena.allocator();
    const args = try parse(allocator);

    std.debug.print("URL: {s}\n", .{args.url});
    std.debug.print("output: {s}\n", .{args.output});
    const args = try parse(allocator);

    std.debug.print("URL: {s}\n", .{args.url});
    std.debug.print("output: {s}\n", .{args.output});

    std.debug.print("URL: {s}\n", .{args.url});
    std.debug.print("output: {s}\n", .{args.output});
    const args = try parse(allocator);

    std.debug.print("URL: {s}\n", .{args.url});
    std.debug.print("output: {s}\n", .{args.output});
    const args = try parse(allocator);

    std.debug.print("URL: {s}\n", .{args.url});
    std.debug.print("output: {s}\n", .{args.output});
    const args = try parse(allocator);

    std.debug.print("URL: {s}\n", .{args.url});
    std.debug.print("output: {s}\n", .{args.output});

    std.debug.print("URL: {s}\n", .{args.url});
    std.debug.print("output: {s}\n", .{args.output});

    defer arena.deinit();

    const args = try parse(allocator);

    std.debug.print("URL: {s}\n", .{args.url});
    std.debug.print("output: {s}\n", .{args.output});
}
