const std = @import("std");
const Thread = std.Thread;
const Allocator = std.mem.Allocator;

pub fn Channel(comptime T: type) type {
    return struct {
        mutex: Thread.Mutex,
        data: std.ArrayList(T),
        cond: Thread.Condition,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .mutex = Thread.Mutex{},
                .data = std.ArrayList(T).init(allocator),
                .cond = Thread.Condition{},
            };
        }
        pub fn deinit(self: *Channel(T)) void {
            self.data.deinit();
        }
        pub fn Send(self: *Channel(T), value: T) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.data.addOne(value);
        }
        pub fn Revieve(self: *Channel(T)) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();
            const value = self.data.popOrNull();
            return value;
        }
    };
}
