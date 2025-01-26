const clap = @import("clap");
const std = @import("std");
const writer = std.io.getStdOut().writer();

/// AppError represents the possible errors that can occur
const AppError = error{
    HTTPStatusNotOK,
    ParseErrorNotFound,
    MissingCommand,
    FileWriteError,
    MissingOutput,
    MissingURL,
};

/// Args represents the command line arguments
const Args = struct {
    url: []const u8,
    output: []const u8,
};

/// GPX represents the root GPX element
const GPX = struct {
    version: []const u8,
    creator: []const u8,
    name: ?[]const u8 = null,
    tracks: []Track,
};

/// Track represents a GPX track
const Track = struct {
    name: ?[]const u8 = null,
    segments: []Segment,
};

/// Segment represents a track segment
const Segment = struct {
    points: []Point,
};

/// Point represents a track point with attributes
const Point = struct {
    latitude: f64,
    longitude: f64,
    elevation: ?f64 = null,
};

fn parseArgs(
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

    const output = if (res.args.output.len > 0) res.args.output[0] else {
        std.debug.print("Error: Missing required argument --output\n", .{});
        return AppError.MissingOutput;
    };
    const url = if (res.args.url.len > 0) res.args.url[0] else {
        std.debug.print("Error: Missing required argument --url\n", .{});
        return AppError.MissingURL;
    };

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
        return AppError.HTTPStatusNotOK;
    }

    return response_body;
}

fn parseJsonFromHtml(html: []u8, allocator: std.mem.Allocator) !std.json.Value {
    const start_marker = "kmtBoot.setProps(\"";
    const end_marker = "\");";

    var start_idx = std.mem.indexOf(u8, html, start_marker) orelse return AppError.ParseErrorNotFound;
    start_idx += start_marker.len;

    const end_idx = std.mem.lastIndexOf(u8, html[start_idx..], end_marker) orelse return AppError.ParseErrorNotFound;

    var json = html[start_idx .. start_idx + end_idx];
    json = try std.mem.replaceOwned(u8, allocator, json, "\\\\", "\\");
    json = try std.mem.replaceOwned(u8, allocator, json, "\\\"", "\"");

    return (try std.json.parseFromSlice(std.json.Value, allocator, json, .{})).value;
}

fn writeGPX(track: Track, file_path: []const u8) !void {
    var tracks: [1]Track = .{track};
    const gpx = GPX{
        .version = "1.1",
        .creator = "zigzag",
        .name = track.name,
        .tracks = &tracks,
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
                try xml_writer.print("      <trkpt lat=\"{d:.6}\" lon=\"{d:.6}\">\n", .{ point.latitude, point.longitude });

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

fn convertJsonToTrack(json: std.json.Value, allocator: std.mem.Allocator) !Track {
    const track_name_entry = json.object.get("page").?
        .object.get("_embedded").?
        .object.get("tour").?
        .object.get("name");
    const track_name = if (track_name_entry) |n| n.string else "Unknown";

    const coordinate_items = json.object.get("page").?
        .object.get("_embedded").?
        .object.get("tour").?
        .object.get("_embedded").?
        .object.get("coordinates").?
        .object.get("items");

    var points: []Point = undefined;

    if (coordinate_items) |coordinates_json| {
        points = try allocator.alloc(Point, coordinates_json.array.items.len);
        for (coordinates_json.array.items, 0..) |geo_point, i| {
            const altitude_entry = geo_point.object.get("alt");
            const elevation = if (altitude_entry) |alt|
                switch (alt) {
                    .float => alt.float,
                    .integer => @as(f64, @floatFromInt(alt.integer)),
                    else => null,
                }
            else
                null;

            points[i] = Point{
                .latitude = geo_point.object.get("lat").?.float,
                .longitude = geo_point.object.get("lng").?.float,
                .elevation = elevation,
            };
        }
    }

    var segments = [1]Segment{.{ .points = points }};

    return Track{ .name = track_name, .segments = &segments };
}

fn fetchTrackHtml(url: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "X-Custom-Header", .value = "application" },
        .{ .name = "User-Agent", .value = "Mozilla/5.0" },
    };

    return (try get(url, headers, &client, allocator)).items;
}

fn run(allocator: std.mem.Allocator) !void {
    const args = try parseArgs(allocator);

    const html = try fetchTrackHtml(args.url, allocator);

    const json = try parseJsonFromHtml(html, allocator);

    const track = try convertJsonToTrack(json, allocator);

    try writeGPX(track, args.output);

    try writer.print("Successfully created GPX file. Track name: {?s}\n", .{track.name});
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
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
