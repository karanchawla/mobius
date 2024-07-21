const std = @import("std");
const Task = @import("task.zig").Task;

pub const Scheduler = struct {
    scheduled_tasks: std.ArrayList(Task),
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,
    thread: ?std.Thread,
    should_stop: std.atomic.Value(bool),

    pub fn init(allocator: std.mem.Allocator) Scheduler {
        return .{
            .scheduled_tasks = std.ArrayList(Task).init(allocator),
            .mutex = std.Thread.Mutex{},
            .allocator = allocator,
            .thread = null,
            .should_stop = std.atomic.Value(bool).init(false),
        };
    }

    pub fn deinit(self: *Scheduler) void {
        self.scheduled_tasks.deinit();
    }

    pub fn start(self: *Scheduler) !void {
        if (self.thread != null) {
            return error.AlreadyRunning;
        }
        self.thread = try std.Thread.spawn(.{}, Scheduler.run, .{ self, &self.should_stop });
    }

    pub fn stop(self: *Scheduler) void {
        if (self.thread) |thread| {
            self.should_stop.store(true, .release);
            thread.join();
            self.thread = null;
        }
    }

    pub fn scheduleTask(self: *Scheduler, id: u64, execute_fn: *const fn () anyerror!void, execute_at: ?i64, recur_interval: ?u64) !void {
        const now = std.time.timestamp();
        const task = Task.init(id, execute_fn, null, execute_at orelse now, recur_interval);
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.scheduled_tasks.append(task);
    }

    pub fn run(self: *Scheduler, should_stop: *std.atomic.Value(bool)) !void {
        while (!should_stop.load(.acquire)) {
            const now = std.time.timestamp();
            var i: usize = 0;
            while (i < self.scheduled_tasks.items.len) {
                const task = &self.scheduled_tasks.items[i];
                if (task.execute_at.? <= now) {
                    task.execute_fn() catch |err| {
                        std.log.err("Error executing task {d}: {s}", .{ task.id, @errorName(err) });
                    };
                    if (task.isRecurring()) {
                        task.execute_at = now + @as(i64, @intCast(task.recur_interval.?));
                        i += 1;
                    } else {
                        _ = self.scheduled_tasks.swapRemove(i);
                    }
                } else {
                    i += 1;
                }
            }
            std.time.sleep(std.time.ns_per_ms);
        }
    }
};
