const clap = @import("clap");
const std = @import("std");
const writer = std.io.getStdOut().writer();

const HTTPStatusError = error{
    StatusNotOK,
};

const ParseError = error{
    NotFound,
};

const Args = struct {
    url: []const u8,
    output: []const u8,
};

// GPX represents the root GPX element
const GPX = struct {
    version: []const u8,
    creator: []const u8,
    name: ?[]const u8 = null,
    tracks: []Track,
};

// Track represents a GPX track
const Track = struct {
    name: ?[]const u8 = null,
    segments: []Segment,
};

// Segment represents a track segment
const Segment = struct {
    points: []Point,
};

// Point represents a track point with attributes
const Point = struct {
    lat: f64,
    lon: f64,
    elevation: ?f64 = null, // Optional field
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
    const res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        // Report useful error and exit.
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };

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

fn parseJsonFromHtml(html: []u8, allocator: std.mem.Allocator) !std.json.Value {
    const start_marker = "kmtBoot.setProps(\"";
    const end_marker = "\");";

    var start_idx = std.mem.indexOf(u8, html, start_marker) orelse return ParseError.NotFound;
    start_idx += start_marker.len;

    const end_idx = std.mem.lastIndexOf(u8, html[start_idx..], end_marker) orelse return ParseError.NotFound;

    var json = html[start_idx .. start_idx + end_idx];
    json = try std.mem.replaceOwned(u8, allocator, json, "\\\\", "\\");
    json = try std.mem.replaceOwned(u8, allocator, json, "\\\"", "\"");

    return (try std.json.parseFromSlice(std.json.Value, allocator, json, .{})).value;
}

fn writeGPX(track: Track, allocator: std.mem.Allocator, file_path: []const u8) !void {
    var tracks = try allocator.alloc(Track, 1);
    tracks[0] = track;
    const gpx = GPX{
        .version = "1.1",
        .creator = "zigpx",
        .name = track.name,
        .tracks = tracks, // Solution applied
    };

    var file = try std.fs.cwd().createFile(file_path, .{ .truncate = true });
    defer file.close();

    var xml_writer = file.writer();

    try xml_writer.print(
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<gpx version="{s}" creator="{s}" xmlns="http://www.topografix.com/GPX/1/1">
        \\  <metadata>
        \\    <name>{s}</name>
        \\  </metadata>
        \\
    , .{ gpx.version, gpx.creator, gpx.name.? });

    for (gpx.tracks) |track_entry| {
        try xml_writer.writeAll("  <trk>\n");
        if (track_entry.name) |track_name| {
            try xml_writer.print("    <name>{s}</name>\n", .{track_name});
        }

        for (track_entry.segments) |segment| {
            try xml_writer.writeAll("    <trkseg>\n");

            for (segment.points) |point| {
                try xml_writer.print("      <trkpt lat=\"{d:.6}\" lon=\"{d:.6}\">\n", .{ point.lat, point.lon });

                if (point.elevation) |elevation| {
                    try xml_writer.print("        <ele>{d:.1}</ele>\n", .{elevation});
                }

                try xml_writer.writeAll("      </trkpt>\n");
            }

            try xml_writer.writeAll("    </trkseg>\n");
        }

        try xml_writer.writeAll("  </trk>\n");
    }

    try xml_writer.writeAll("</gpx>\n");

    std.debug.print("GPX file written to: {s}\n", .{file_path});
}

fn json_to_track(json: std.json.Value, allocator: std.mem.Allocator) !Track {
    const name_value = json.object.get("page").?.object.get("_embedded").?.object.get("tour").?.object.get("name");
    const name = if (name_value) |n| n.string else "Unknown";

    const items = json.object.get("page").?.object.get("_embedded").?.object.get("tour").?.object.get("_embedded").?.object.get("coordinates").?.object.get("items");

    var points: []Point = undefined;

    if (items) |val| {
        points = try allocator.alloc(Point, val.array.items.len);
        for (val.array.items, 0..) |item, i| {
            const alt_value = item.object.get("alt");
            const elevation = if (alt_value) |alt|
                switch (alt) {
                    .float => alt.float,
                    .integer => @as(f64, @floatFromInt(alt.integer)),
                    else => null,
                }
            else
                null;

            points[i] = Point{
                .lat = item.object.get("lat").?.float,
                .lon = item.object.get("lng").?.float,
                .elevation = elevation,
            };
        }
    }

    var segments = try allocator.alloc(Segment, 1);
    segments[0] = .{ .points = points };

    return Track{ .name = name, .segments = segments };
}

fn run(allocator: std.mem.Allocator) !void {
    const args = parse(allocator) catch |err| {
        try writer.print("Failed to parse arguments: {s}\n", .{@errorName(err)});
        return err;
    };

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "X-Custom-Header", .value = "application" },
        .{ .name = "User-Agent", .value = "Mozilla/5.0" },
    };

    try writer.print("Fetching data from: {s}\n", .{args.url});
    const response = try get(args.url, headers, &client, allocator);

    try writer.print("Parsing HTML response...\n", .{});
    const json = try parseJsonFromHtml(response.items, allocator);

    try writer.print("Converting to GPX track...\n", .{});
    const track = try json_to_track(json, allocator);

    try writer.print("Writing GPX file to: {s}\n", .{args.output});
    try writeGPX(track, allocator, args.output);

    try writer.print("Successfully created GPX file. Track name: {?s}\n", .{track.name});
}

pub fn main() !void {
    const alloc = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    run(arena.allocator()) catch |err| {
        // Print to stderr instead of stdout
        std.debug.print("Failed to run: {s}\n", .{@errorName(err)});
        if (std.debug.runtime_safety) {
            // In debug builds, print the stack trace if available
            if (@errorReturnTrace()) |trace| {
                std.debug.dumpStackTrace(trace.*);
            }
        }
        std.process.exit(1);
    };
}
