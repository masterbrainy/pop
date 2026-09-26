import Foundation
import Testing
@testable import PopKit

/// Covers `TaskDeadline.value(of:until:)`, which Finish uses to cap how long it waits for the
/// title and cover (IMP-13): a task that finishes in time gives its value, one that doesn't is
/// cancelled and gives nil at the deadline instead of holding the book open.
struct TaskDeadlineTests {
    @Test func aTaskThatFinishesInTimeGivesItsValue() async {
        let task = Task { "Rex Learns to Share" }
        let value = await TaskDeadline.value(of: task, until: .now.advanced(by: .seconds(5)))
        #expect(value == "Rex Learns to Share")
    }

    @Test func aTaskStillRunningAtTheDeadlineIsCancelledAndGivesNil() async {
        let task = Task { () -> String? in
            do {
                try await Task.sleep(for: .seconds(30))
                return "too late"
            } catch {
                return nil
            }
        }
        let started = ContinuousClock.now
        let value = await TaskDeadline.value(of: task, until: .now.advanced(by: .milliseconds(100)))
        #expect(value == nil)
        #expect(task.isCancelled)
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test func aDeadlineAlreadyPastStillReturnsPromptly() async {
        let task = Task { () -> Int in
            try? await Task.sleep(for: .seconds(30))
            return 1
        }
        let started = ContinuousClock.now
        _ = await TaskDeadline.value(of: task, until: .now.advanced(by: .seconds(-1)))
        #expect(ContinuousClock.now - started < .seconds(5))
    }
}
