const std = @import("std");
const chanz = @import("./channel.zig");

fn worker(c: *chanz.Chan(usize), i: usize) !void {
    while (!c.closed) {
        const val = try c.recv();
        std.time.sleep(2 * std.time.ms_per_s);
        std.debug.print("{d} Thread Received {d} {d}\n", .{ std.time.nanoTimestamp(), val, i });
    }
}

pub fn main() !void {
    // create GPA allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var channel = chanz.Chan(usize).init(allocator);
    defer channel.deinit();

    var threads: [6]std.Thread = undefined;
    for (0..threads.len) |i| {
        threads[i] = try std.Thread.spawn(.{}, worker, .{ &channel, i + 1 });
    }
    defer for (threads) |t| {
        t.join();
    };

    var val: usize = 0;
    for (0..100) |i| {
        try channel.send(val);
        if (i > 99) {
            const dur = 3 * std.time.ns_per_s;
            std.time.sleep(dur);
        }
        val += i;
    }

    channel.close();
}
