const std = @import("std");

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

    // loop lines
    while (reader.readUntilDelimiterOrEof(buffer, '\n')) |line| {
        if (line == null) break;
        line_count += 1;
        std.debug.print("{d}: {?s}\n", .{ line_count, line });
    } else |err| {
        std.debug.print("Line Error: {}\n", .{err});
    }

    std.debug.print("Line Count: {d}\n", .{line_count});

    const end = try std.time.Instant.now();
    const elapsed1: f64 = @floatFromInt(end.since(start));
    std.debug.print("Time elapsed is: {d:.3}ms\n", .{
        elapsed1 / std.time.ns_per_ms,
    });
}
