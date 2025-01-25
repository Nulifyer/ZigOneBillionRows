const std = @import("std");
const chanz = @import("./channel.zig");
const LineQueueChannel = chanz.BufferedChan([]u8, 100);

pub fn main() !void {
    const start = try std.time.Instant.now();

    // create GPA allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // file path
    const folder =
        \\C:\Users\Kyle\Documents\source\OdinOneBillionRows\data
    ;
    //const filename = "measurements-1_000.txt";
    const filename = "measurements-1_000_000.txt";
    const fullpath = folder ++ "\\" ++ filename;

    // open file
    const file = try std.fs.openFileAbsolute(fullpath, .{ .mode = .read_only });
    defer file.close();
    const reader = file.reader();

    // create buffer reader
    var line_count: u32 = 0;
    const buffer = try allocator.alloc(u8, 500);
    defer allocator.free(buffer);

    // create map
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var arena_allocator = arena.allocator();
    var station_map = std.StringHashMap(Station).init(allocator);
    defer station_map.deinit();
    var station_map_mutex = std.Thread.Mutex{};

    // create channel
    var channel = LineQueueChannel.init(allocator);
    defer channel.deinit();

    // create threads
    var wg: std.Thread.WaitGroup = undefined;
    wg.reset();
    const num_threads = 12;
    var threads: [num_threads]std.Thread = undefined;
    for (&threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, worker, .{ &channel, &wg, &arena_allocator, &station_map, &station_map_mutex });
    }

    // loop lines
    while (reader.readUntilDelimiterOrEof(buffer, '\n')) |line| {
        if (line == null) break;
        line_count += 1;
        const dupe_line = try arena_allocator.dupe(u8, line.?);
        wg.start();
        try channel.send(dupe_line);
    } else |err| {
        std.debug.print("Line Error: {}\n", .{err});
    }

    // close channel when empty
    var len: u8 = 0;
    while (true) {
        len = channel.len();
        std.debug.print("Chan Count: {d}\n", .{len});
        if (len == 0) break;
    }
    channel.close();

    std.debug.print("Line Count: {d}\n", .{line_count});
    std.debug.print("Station Count: {d}\n", .{station_map.count()});

    var iter = station_map.iterator();
    while (iter.next()) |entry| {
        var station = entry.value_ptr;
        station.avg = station.sum / @as(f32, @floatFromInt(station.count));
        station.print();
    }

    const end = try std.time.Instant.now();
    const diff = end.since(start);
    prettyPrintNsDuration(diff);
}

fn worker(
    channel: *LineQueueChannel,
    wg: *std.Thread.WaitGroup,
    allocator: *std.mem.Allocator,
    station_map: *std.StringHashMap(Station),
    station_map_mutex: *std.Thread.Mutex,
) !void {
    std.debug.print("thread started\n", .{});
    while (!channel.closed) {
        defer wg.finish();
        const val = try channel.recv();
        try processLine(allocator, val, station_map, station_map_mutex);
    }
    std.debug.print("thread closed\n", .{});
}

pub fn processLine(
    allocator: *std.mem.Allocator,
    line: []u8,
    station_map: *std.StringHashMap(Station),
    station_map_mutex: *std.Thread.Mutex,
) !void {
    //std.debug.print("{s}\n", .{line});
    const foundSplit = std.mem.indexOf(u8, line, ";");
    if (foundSplit) |idx| {
        const name = line[0..idx];
        const valueStr = std.mem.trimRight(u8, line[idx + 1 ..], "\r\n");
        const valueNum = try std.fmt.parseFloat(f32, valueStr);

        // const key = allocator.dupe(u8, name) catch |err| {
        //     std.debug.print("Failed to dupe key: {}\n", .{err});
        //     return;
        // };
        station_map_mutex.lock();
        const entry = try station_map.getOrPut(name);
        if (entry.found_existing) {
            var existing_station = entry.value_ptr.*;

            existing_station.mutex.lock();
            defer existing_station.mutex.unlock();
            station_map_mutex.unlock();

            entry.value_ptr.update(valueNum);

            allocator.free(line);
        } else {
            defer station_map_mutex.unlock();
            entry.value_ptr.* = Station.create(name, valueNum);
        }
    } else {
        std.debug.print("Failed split: {?s}\n", .{line});
    }
}

pub fn prettyPrintNsDuration(diff: u64) void {
    const float_diff = @as(f64, @floatFromInt(diff));
    const hours = float_diff / @as(f64, std.time.ns_per_hour);
    const minutes = @mod(float_diff, std.time.ns_per_hour) / @as(f64, std.time.ns_per_min);
    const seconds = @mod(float_diff, std.time.ns_per_min) / @as(f64, std.time.ns_per_s);
    const milliseconds = @mod(float_diff, std.time.ns_per_s) / @as(f64, std.time.ns_per_ms);
    std.debug.print("{d:.0}h:{d:.0}m:{d:.0}s:{d:.3}ms\n", .{ hours, minutes, seconds, milliseconds });
}

const Station = struct {
    mutex: std.Thread.Mutex,
    name: []const u8,
    count: i32,
    avg: f32,
    sum: f32,
    min: f32,
    max: f32,

    pub fn create(name: []const u8, value: f32) Station {
        return .{
            .mutex = std.Thread.Mutex{},
            .name = name,
            .count = 1,
            .avg = 0,
            .sum = value,
            .min = value,
            .max = value,
        };
    }
    pub fn update(self: *Station, value: f32) void {
        self.count += 1;
        self.sum += value;
        if (value < self.min) self.min = value;
        if (value > self.max) self.max = value;
    }
    pub fn print(self: *Station) void {
        std.debug.print("{s};{d};{d:.1};{d:.1};{d:.1}\n", .{ self.name, self.count, self.avg, self.min, self.max });
    }
};
