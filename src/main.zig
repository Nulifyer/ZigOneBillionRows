const std = @import("std");
const chan = @import("./channel.zig");

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
    const filename = "measurements-1_000.txt";
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

    // threads
    var channel = chan.Channel([]const u8).init(arena_allocator);
    defer channel.deinit();

    const thread = struct {
        fn func(c: *T) !void {
            const val = try c.recv();
            std.debug.print("{d} Thread Received {d}\n", .{ std.time.milliTimestamp(), val });
        }
    };

    const t = try std.Thread.spawn(.{}, thread.func, .{&chan});
    defer t.join();
    std.time.sleep(1_000_000_000);
    const val: u8 = 10;
    try chan.send(val);

    // loop lines
    while (reader.readUntilDelimiterOrEof(buffer, '\n')) |line| {
        if (line == null) break;
        line_count += 1;
        //std.debug.print("{d}: {?s}\n", .{ line_count, line });

        const foundSplit = std.mem.indexOf(u8, line.?, ";");
        if (foundSplit) |idx| {
            const name = line.?[0..idx];
            const valueStr = std.mem.trimRight(u8, line.?[idx + 1 ..], "\r\n");
            const valueNum = try std.fmt.parseFloat(f32, valueStr);

            const key = try arena_allocator.dupe(u8, name);
            const entry = station_map.getOrPut(key) catch |err| {
                std.debug.print("Failed GetOrPut: {}\n", .{err});
                return;
            };
            if (entry.found_existing) {
                entry.value_ptr.update(valueNum);
            } else {
                entry.value_ptr.* = Station.create(key, valueNum);
            }
        } else {
            std.debug.print("Failed split: {?s}\n", .{line});
        }
    } else |err| {
        std.debug.print("Line Error: {}\n", .{err});
    }

    std.debug.print("Line Count: {d}\n", .{line_count});

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

pub fn prettyPrintNsDuration(diff: u64) void {
    const float_diff = @as(f64, @floatFromInt(diff));
    const hours = float_diff / @as(f64, std.time.ns_per_hour);
    const minutes = @mod(float_diff, std.time.ns_per_hour) / @as(f64, std.time.ns_per_min);
    const seconds = @mod(float_diff, std.time.ns_per_min) / @as(f64, std.time.ns_per_s);
    const milliseconds = @mod(float_diff, std.time.ns_per_s) / @as(f64, std.time.ns_per_ms);
    std.debug.print("{d:.0}h:{d:.0}m:{d:.0}s:{d:.3}ms\n", .{ hours, minutes, seconds, milliseconds });
}

const Station = struct {
    name: []const u8,
    count: i32,
    avg: f32,
    sum: f32,
    min: f32,
    max: f32,

    pub fn create(name: []const u8, value: f32) Station {
        return .{
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
