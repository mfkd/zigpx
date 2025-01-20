const clap = @import("clap");
const std = @import("std");
const writer = std.io.getStdOut().writer();

const HTTPStatusError = error{
    StatusNotOK,
};

const Args = struct {
    url: []const u8,
    output: []const u8,
};

fn parse(
    allocator: std.mem.Allocator,
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

fn get(
    url: []const u8,
    headers: []const std.http.Header,
    client: *std.http.Client,
    allocator: std.mem.Allocator,
) !std.ArrayList(u8) {
    var response_body = std.ArrayList(u8).init(allocator);

    const response = try client.fetch(.{
        .method = .GET,
        .location = .{ .url = url },
        .extra_headers = headers,
        .response_storage = .{ .dynamic = &response_body },
    });

    if (response.status != std.http.Status.ok) {
        try writer.print("Response Status: {d}\n", .{response.status});
        return HTTPStatusError.StatusNotOK;
    }

    return response_body;
}

pub fn main() !void {
    const alloc = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    const allocator = arena.allocator();

    defer arena.deinit();

    const args = try parse(allocator);

    var client = std.http.Client{
        .allocator = allocator,
    };

    const headers = &[_]std.http.Header{
        .{ .name = "X-Custom-Header", .value = "application" },
    };

    const response = try get(args.url, headers, &client, alloc);

    try writer.print("{s}", .{response.items});
}
