const std = @import("std");
const Task = @import("task.zig").Task;
const Queue = @import("queue.zig").Queue;
const WorkerPool = @import("worker.zig").WorkerPool;

fn simpleTask() !void {
    std.debug.print("Hello, World!\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var queue = Queue.init(allocator);
    defer queue.deinit();

    var should_stop = std.atomic.Value(bool).init(false);
    var worker_pool = try WorkerPool.init(allocator, 4, &queue, &should_stop);
    defer worker_pool.deinit();

    const num_tasks = 10;
    for (0..num_tasks) |i| {
        try queue.enqueue(Task.init(i, simpleTask, null, null, null));
    }

    std.time.sleep(500 * std.time.ns_per_ms);

    should_stop.store(true, .release);

    for (worker_pool.workers) |worker| {
        worker.thread.join();
    }

    std.debug.print("All tasks processed.\n", .{});
}
