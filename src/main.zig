const std = @import("std");
const builtin = @import("builtin");

const MAP_CAPACITY = 512 * 2 * 2;
const T = i32;
const F = f32;

const Stat = struct {
    min: F,
    max: F,
    sum: F,
    count: u32,

    pub fn mergeIn(self: *Stat, other: Stat) void {
        self.min = @min(self.min, other.min);
        self.max = @max(self.max, other.max);
        self.sum += other.sum;
        self.count += other.count;
    }
    pub fn addItem(self: *Stat, item: F) void {
        self.min = @min(self.min, item);
        self.max = @max(self.max, item);
        self.sum += item;
        self.count += 1;
    }
};

const WorkerCtx = struct {
    map: std.StringHashMap(Stat),
    countries: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) !WorkerCtx {
        var self: WorkerCtx = undefined;
        self.map = std.StringHashMap(Stat).init(allocator);
        try self.map.ensureTotalCapacity(MAP_CAPACITY);
        self.countries = std.ArrayList([]const u8).init(allocator);
        return self;
    }
    pub fn deinit(self: *WorkerCtx) void {
        self.map.deinit();
        self.countries.deinit();
    }
};

inline fn parseSimpleFloat(chunk: []const u8, pos: *usize) F {
    var inum: i32 = 0;
    var is_neg: bool = false;
    for (0..6) |i| {
        var idx = pos.* + i;
        if (idx > chunk.len - 1)
            idx = chunk.len - 1;
        const item = chunk[idx];
        switch (item) {
            '-' => is_neg = true,
            '0'...'9' => {
                inum *= 10;
                inum += item - '0';
            },
            '\n' => {
                pos.* = idx + 1;
                break;
            },
            else => {},
        }
    }
    inum *= if (is_neg) -1 else 1;
    const num: f32 = @as(f32, @floatFromInt(inum)) / 10;
    return num;
}

fn threadRun(
    chunk: []const u8,
    chunk_idx: usize,
    allocator: std.mem.Allocator,
    main_ctx: *WorkerCtx,
    main_mutex: *std.Thread.Mutex,
    wg: *std.Thread.WaitGroup,
) void {
    defer wg.finish();
    var ctx = WorkerCtx.init(allocator) catch unreachable;
    defer ctx.deinit();
    std.log.debug("Running thread {}!", .{chunk_idx});
    var pos: usize = 0;
    while (pos < chunk.len) {
        const new_pos = std.mem.indexOfScalarPos(u8, chunk, pos, ';') orelse chunk.len;
        const city = chunk[pos..new_pos];
        pos = new_pos + 1;
        const num = parseSimpleFloat(chunk, &pos);
        const entry = ctx.map.getOrPut(city) catch unreachable;
        if (entry.found_existing) {
            entry.value_ptr.addItem(num);
        } else {
            entry.value_ptr.* = Stat{ .min = num, .max = num, .sum = num, .count = 1 };
        }
    }

    var it = ctx.map.iterator();
    while (it.next()) |entry| {
        const country = entry.key_ptr.*;
        const stat = entry.value_ptr.*;
        main_mutex.lock();
        if (main_ctx.map.getPtr(country)) |main_stat| {
            main_stat.mergeIn(stat);
        } else {
            main_ctx.countries.append(country) catch unreachable;
            main_ctx.map.put(country, stat) catch unreachable;
        }
        main_mutex.unlock();
    }
    std.log.debug("Finished thread {}!", .{chunk_idx});
}

fn strLessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == std.math.Order.lt;
}

pub fn main() !void {
    std.log.debug("Starting!", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const folder = "C:\\Users\\Kyle\\Documents\\source\\OdinOneBillionRows\\data";
    const filename = "measurements-1_000.txt";
    const fullpath = folder ++ "\\" ++ filename;

    const file = try std.fs.cwd().openFile(fullpath, .{ .mode = .read_only });
    defer file.close();

    const buffer_size: usize = 1024 * 1024; // 1MB buffer size, adjust as necessary
    var buffer = try allocator.alloc(u8, buffer_size);
    defer allocator.free(buffer);

    var tp: std.Thread.Pool = undefined;
    try tp.init(.{ .allocator = allocator });
    var wg = std.Thread.WaitGroup{};

    var main_ctx = try WorkerCtx.init(allocator);
    defer main_ctx.deinit();
    var main_mutex = std.Thread.Mutex{};

    var chunk_start: usize = 0;
    //const job_count = try std.Thread.getCpuCount() - 1;

    while (true) {
        const bytes_read = try file.read(buffer);
        if (bytes_read == 0) break; // EOF

        const chunk_end: usize = bytes_read;
        const chunk: []const u8 = buffer[0..chunk_end];

        // Process the chunk with threads
        wg.start();
        try tp.spawn(threadRun, .{ chunk, chunk_start, allocator, &main_ctx, &main_mutex, &wg });

        chunk_start += chunk_end;
    }

    std.log.debug("Waiting and working", .{});
    tp.waitAndWork(&wg);
    std.log.debug("Finished waiting and working", .{});

    std.mem.sortUnstable([]const u8, main_ctx.countries.items, {}, strLessThan);
    std.debug.print("{{", .{});
    for (main_ctx.countries.items, 0..) |country, i| {
        const stat = main_ctx.map.get(country).?;
        const avg = stat.sum / @as(F, @floatFromInt(stat.count));
        std.debug.print("{s}={d:.1}/{d:.1}/{d:.1}", .{ country, stat.min, avg, stat.max });
        if (i + 1 != main_ctx.countries.items.len) std.debug.print(", ", .{});
    }
    std.debug.print("}}\n", .{});
}
