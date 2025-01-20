const std = @import("std");
const clap = @import("clap");

fn parse() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

fn parse(
    allocator: std.mem.Allocator,
) !void {
fn parse(
    allocator: std.mem.Allocator,
) !void {
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

    for (res.args.output) |s|
        std.debug.print("--url = {s}\n", .{s});
    for (res.args.url) |s|
        std.debug.print("--output = {s}\n", .{s});
}

pub fn main() !void {
    const alloc = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    const allocator = arena.allocator();

    defer arena.deinit();

    try parse(allocator);
}
