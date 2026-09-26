import Foundation

/// Waits for a task only until a deadline (IMP-13): Finish starts the title and cover while
/// clips complete, then takes whatever is ready by the deadline and saves.
public enum TaskDeadline {
    /// The task's value if it finishes by `deadline`; otherwise the task is cancelled and this
    /// returns nil. Returns once the task has stopped, so the task must honour cancellation
    /// (network calls do) for the deadline to hold.
    public static func value<T: Sendable>(of task: Task<T, Never>, until deadline: ContinuousClock.Instant) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await task.value }
            group.addTask {
                try? await Task.sleep(until: deadline, clock: .continuous)
                return nil
            }
            let first = await group.next() ?? nil
            if first == nil { task.cancel() }
            group.cancelAll()
            return first
        }
    }
}
