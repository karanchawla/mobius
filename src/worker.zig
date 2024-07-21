const std = @import("std");
const testing = std.testing;
const Queue = @import("queue.zig").Queue;
const Task = @import("task.zig").Task;

// Worker to process tasks with error handling
const Worker = struct {
    queue: *Queue,
    thread: std.Thread,
    should_stop: *std.atomic.Value(bool),

    pub fn init(queue: *Queue, should_stop: *std.atomic.Value(bool)) !Worker {
        const thread = try std.Thread.spawn(.{}, workerFunction, .{ queue, should_stop });
        return Worker{ .queue = queue, .thread = thread, .should_stop = should_stop };
    }

    fn workerFunction(queue: *Queue, should_stop: *std.atomic.Value(bool)) void {
        while (!should_stop.load(.acquire)) {
            if (queue.dequeue()) |task| {
                task.execute_fn() catch |err| {
                    std.log.err("Error executing task {d}: {s}", .{ task.id, @errorName(err) });
                };
            }
        }
    }
};

pub const WorkerPool = struct {
    workers: []Worker,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, num_workers: usize, queue: *Queue, should_stop: *std.atomic.Value(bool)) !WorkerPool {
        const workers = try allocator.alloc(Worker, num_workers);
        for (workers) |*worker| {
            worker.* = try Worker.init(queue, should_stop);
        }
        return WorkerPool{ .workers = workers, .allocator = allocator };
    }

    pub fn deinit(self: *WorkerPool) void {
        self.allocator.free(self.workers);
    }
};

// Unit tests
fn dummyFunction() !void {}

fn createTask(id: u64, priority: ?u8) Task {
    return Task.init(id, dummyFunction, priority, null, null);
}

test "Worker - initialization" {
    var queue = Queue.init(testing.allocator);
    defer queue.deinit();
    var should_stop = std.atomic.Value(bool).init(false);

    const worker = try Worker.init(&queue, &should_stop);
    try testing.expect(worker.queue == &queue);
    try testing.expect(worker.should_stop == &should_stop);

    should_stop.store(true, .release);
    worker.thread.join();
}

test "Worker - task execution" {
    var queue = Queue.init(testing.allocator);
    defer queue.deinit();
    var should_stop = std.atomic.Value(bool).init(false);

    const worker = try Worker.init(&queue, &should_stop);

    // Add some tasks to the queue
    try queue.enqueue(createTask(1, 5));
    try queue.enqueue(createTask(2, 3));
    try queue.enqueue(createTask(3, 7));

    // Start the worker
    const thread = try std.Thread.spawn(.{}, Worker.workerFunction, .{ worker.queue, worker.should_stop });

    // Let the worker run for a short time
    std.time.sleep(100 * std.time.ns_per_ms);

    // Stop the worker
    should_stop.store(true, .release);
    thread.join();

    // Check if all tasks were processed
    try testing.expect(queue.tasks.count() == 0);
}

test "WorkerPool - initialization" {
    var queue = Queue.init(testing.allocator);
    defer queue.deinit();
    var should_stop = std.atomic.Value(bool).init(false);

    const num_workers = 4;
    var worker_pool = try WorkerPool.init(testing.allocator, num_workers, &queue, &should_stop);
    defer worker_pool.deinit();

    try testing.expectEqual(num_workers, worker_pool.workers.len);
    for (worker_pool.workers) |worker| {
        try testing.expect(worker.queue == &queue);
        try testing.expect(worker.should_stop == &should_stop);
    }
    should_stop.store(true, .release);
    for (worker_pool.workers) |worker| {
        worker.thread.join();
    }
}

test "WorkerPool - task execution" {
    var queue = Queue.init(testing.allocator);
    defer queue.deinit();
    var should_stop = std.atomic.Value(bool).init(false);

    const num_workers = 4;
    var worker_pool = try WorkerPool.init(testing.allocator, num_workers, &queue, &should_stop);
    defer worker_pool.deinit();

    // Add some tasks to the queue
    const num_tasks = 100;
    for (0..num_tasks) |i| {
        try queue.enqueue(createTask(@intCast(i), @intCast(@mod(i, 10))));
    }

    // Let the workers run for a short time
    std.time.sleep(500 * std.time.ns_per_ms);

    // Stop the workers
    should_stop.store(true, .release);

    // Wait for all workers to finish
    for (worker_pool.workers) |worker| {
        worker.thread.join();
    }

    // Check if all tasks were processed
    try testing.expect(queue.tasks.count() == 0);
}
