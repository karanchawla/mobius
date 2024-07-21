const std = @import("std");
const testing = std.testing;
const Task = @import("task.zig").Task;

pub const Queue = struct {
    tasks: std.PriorityQueue(Task, void, compareTasks),
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Queue {
        return .{
            .tasks = std.PriorityQueue(Task, void, compareTasks).init(allocator, {}),
            .mutex = std.Thread.Mutex{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Queue) void {
        self.tasks.deinit();
    }

    pub fn enqueue(self: *Queue, task: Task) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.tasks.add(task);
    }

    pub fn dequeue(self: *Queue) ?Task {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.tasks.removeOrNull();
    }

    fn compareTasks(context: void, a: Task, b: Task) std.math.Order {
        _ = context;
        if (a.priority) |a_priority| {
            if (b.priority) |b_priority| {
                return std.math.order(a_priority, b_priority);
            } else {
                return .lt;
            }
        } else if (b.priority != null) {
            return .gt;
        } else {
            return .eq;
        }
    }
};

// Unit tests

fn dummyFunction() !void {}

fn createTask(id: u64, priority: ?u8) Task {
    return Task.init(id, dummyFunction, priority, null, null);
}

test "Queue - initialization" {
    var queue = Queue.init(testing.allocator);
    defer queue.deinit();

    try testing.expect(queue.tasks.count() == 0);
}

test "Queue - enqueue and dequeue" {
    var queue = Queue.init(testing.allocator);
    defer queue.deinit();

    const task1 = createTask(1, 5);
    const task2 = createTask(2, 3);
    const task3 = createTask(3, 7);

    try queue.enqueue(task1);
    try queue.enqueue(task2);
    try queue.enqueue(task3);

    try testing.expectEqual(@as(usize, 3), queue.tasks.count());

    const dequeued1 = queue.dequeue().?;
    try testing.expectEqual(@as(u64, 2), dequeued1.id);

    const dequeued2 = queue.dequeue().?;
    try testing.expectEqual(@as(u64, 1), dequeued2.id);

    const dequeued3 = queue.dequeue().?;
    try testing.expectEqual(@as(u64, 3), dequeued3.id);

    try testing.expect(queue.dequeue() == null);
}

test "Queue - priority ordering" {
    var queue = Queue.init(testing.allocator);
    defer queue.deinit();

    const tasks = [_]Task{
        createTask(1, 5),
        createTask(2, 3),
        createTask(3, 7),
        createTask(4, 1),
        createTask(5, 9),
    };

    for (tasks) |task| {
        try queue.enqueue(task);
    }

    const expected_order = [_]u64{ 4, 2, 1, 3, 5 };

    for (expected_order) |expected_id| {
        const dequeued = queue.dequeue().?;
        try testing.expectEqual(expected_id, dequeued.id);
    }

    try testing.expect(queue.dequeue() == null);
}

test "Queue - enqueue and dequeue with null priorities" {
    var queue = Queue.init(testing.allocator);
    defer queue.deinit();

    const task1 = createTask(1, null);
    const task2 = createTask(2, 5);
    const task3 = createTask(3, null);

    try queue.enqueue(task1);
    try queue.enqueue(task2);
    try queue.enqueue(task3);

    const dequeued1 = queue.dequeue().?;
    try testing.expectEqual(@as(u64, 2), dequeued1.id);

    const dequeued2 = queue.dequeue().?;
    try testing.expectEqual(@as(u64, 1), dequeued2.id);

    const dequeued3 = queue.dequeue().?;
    try testing.expectEqual(@as(u64, 3), dequeued3.id);

    try testing.expect(queue.dequeue() == null);
}

test "Queue - basic thread safety" {
    var queue = Queue.init(testing.allocator);
    defer queue.deinit();

    const ThreadContext = struct {
        queue: *Queue,
        id: u64,
    };

    const thread_count = 4;
    var threads: [thread_count]std.Thread = undefined;

    for (0..thread_count) |i| {
        const context = ThreadContext{
            .queue = &queue,
            .id = i,
        };

        threads[i] = try std.Thread.spawn(.{}, struct {
            fn threadFn(ctx: ThreadContext) void {
                const task = createTask(ctx.id, @intCast(ctx.id % 10));
                ctx.queue.enqueue(task) catch unreachable;
                _ = ctx.queue.dequeue();
            }
        }.threadFn, .{context});
    }

    for (threads) |thread| {
        thread.join();
    }

    try testing.expect(queue.tasks.count() == 0);
}

test "Queue - advanced thread safety" {
    var queue = Queue.init(testing.allocator);
    defer queue.deinit();

    const ThreadContext = struct {
        queue: *Queue,
        start_id: u64,
        tasks_to_enqueue: usize,
    };

    const num_threads = 4;
    const tasks_per_thread = 1000;

    var threads: [num_threads]std.Thread = undefined;

    for (0..num_threads) |i| {
        const context = ThreadContext{
            .queue = &queue,
            .start_id = i * tasks_per_thread,
            .tasks_to_enqueue = tasks_per_thread,
        };

        threads[i] = try std.Thread.spawn(.{}, struct {
            fn threadFn(ctx: ThreadContext) void {
                // Enqueue tasks
                for (0..ctx.tasks_to_enqueue) |j| {
                    const task_id = ctx.start_id + j;
                    const priority = @as(u8, @intCast(task_id % 10));
                    const task = createTask(task_id, priority);
                    ctx.queue.enqueue(task) catch unreachable;
                }

                // Dequeue half of the tasks
                for (0..ctx.tasks_to_enqueue / 2) |_| {
                    _ = ctx.queue.dequeue();
                }
            }
        }.threadFn, .{context});
    }

    // Wait for all threads to complete
    for (threads) |thread| {
        thread.join();
    }

    // Check the final state of the queue
    const remaining_tasks = num_threads * tasks_per_thread / 2;
    try testing.expectEqual(remaining_tasks, queue.tasks.count());

    // Verify that the remaining tasks are in the correct order (by priority)
    var prev_priority: ?u8 = null;
    while (queue.dequeue()) |task| {
        if (prev_priority) |prev| {
            try testing.expect(task.priority.? >= prev);
        }
        prev_priority = task.priority;
    }
}
