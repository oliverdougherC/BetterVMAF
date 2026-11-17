import AppKit
import Testing
@testable import VMAF

struct UpdateTests {
    @MainActor @Test func terminationWaitsForEveryOwnedComparison() {
        let updates = AppUpdates()
        let activity = ComparisonActivity.shared

        #expect(updates.applicationShouldTerminate(.shared) == .terminateNow)
        let single = activity.begin()
        let batch = activity.begin()
        defer {
            activity.end(single)
            activity.end(batch)
        }

        #expect(updates.applicationShouldTerminate(.shared) == .terminateCancel)
        activity.end(single)
        #expect(updates.applicationShouldTerminate(.shared) == .terminateCancel)
        activity.end(batch)
        #expect(updates.applicationShouldTerminate(.shared) == .terminateNow)
    }
}
