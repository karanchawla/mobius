const std = @import("std");

pub const Task = struct {
    id: u64,
    execute_fn: *const fn () anyerror!void,
    priority: ?u8,
    execute_at: ?i64,
    recur_interval: ?u64,

    pub fn init(id: u64, execute_fn: *const fn () anyerror!void, priority: ?u8, execute_at: ?i64, recur_interval: ?u64) Task {
        return .{
            .id = id,
            .priority = priority,
            .execute_fn = execute_fn,
            .execute_at = execute_at,
            .recur_interval = recur_interval,
        };
    }

    pub fn isRecurring(self: Task) bool {
        return self.recur_interval != null;
    }

    pub fn isScheduled(self: Task) bool {
        return self.execute_at != null;
    }

    pub fn isPrioritized(self: Task) bool {
        return self.priority != null;
    }
};

// Unit tests

test "Task initialization" {
    const dummyFn = struct {
        fn dummy() anyerror!void {}
    }.dummy;

    const task = Task.init(1, dummyFn, 5, 1000, 60);
    try std.testing.expectEqual(@as(u64, 1), task.id);
    try std.testing.expectEqual(dummyFn, task.execute_fn);
    try std.testing.expectEqual(@as(?u8, 5), task.priority);
    try std.testing.expectEqual(@as(?i64, 1000), task.execute_at);
    try std.testing.expectEqual(@as(?u64, 60), task.recur_interval);
}

test "Task.isRecurring" {
    const dummyFn = struct {
        fn dummy() anyerror!void {}
    }.dummy;

    const recurring_task = Task.init(1, dummyFn, null, null, 60);
    const non_recurring_task = Task.init(2, dummyFn, null, null, null);

    try std.testing.expect(recurring_task.isRecurring());
    try std.testing.expect(!non_recurring_task.isRecurring());
}

test "Task.isScheduled" {
    const dummyFn = struct {
        fn dummy() anyerror!void {}
    }.dummy;

    const scheduled_task = Task.init(1, dummyFn, null, 1000, null);
    const non_scheduled_task = Task.init(2, dummyFn, null, null, null);

    try std.testing.expect(scheduled_task.isScheduled());
    try std.testing.expect(!non_scheduled_task.isScheduled());
}

test "Task.isPrioritized" {
    const dummyFn = struct {
        fn dummy() anyerror!void {}
    }.dummy;

    const prioritized_task = Task.init(1, dummyFn, 5, null, null);
    const non_prioritized_task = Task.init(2, dummyFn, null, null, null);

    try std.testing.expect(prioritized_task.isPrioritized());
    try std.testing.expect(!non_prioritized_task.isPrioritized());
}

test "Task with all fields set" {
    const dummyFn = struct {
        fn dummy() anyerror!void {}
    }.dummy;

    const task = Task.init(1, dummyFn, 5, 1000, 60);
    try std.testing.expect(task.isPrioritized());
    try std.testing.expect(task.isScheduled());
    try std.testing.expect(task.isRecurring());
}

test "Task with only required fields" {
    const dummyFn = struct {
        fn dummy() anyerror!void {}
    }.dummy;

    const task = Task.init(1, dummyFn, null, null, null);
    try std.testing.expect(!task.isPrioritized());
    try std.testing.expect(!task.isScheduled());
    try std.testing.expect(!task.isRecurring());
}
