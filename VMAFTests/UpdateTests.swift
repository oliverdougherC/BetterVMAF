import AppKit
import Testing
@testable import VMAF

struct UpdateTests {
    @MainActor @Test func updateRelaunchWaitsForBothSingleAndBatchWork() throws {
        let activity = ComparisonActivity()
        let updates = AppUpdates(activity: activity)
        let single = try #require(activity.begin())
        let batch = try #require(activity.begin())

        #expect(!updates.allowUpdateRelaunch(onBusy: {}))
        activity.end(single)
        #expect(!updates.allowUpdateRelaunch(onBusy: {}))
        activity.end(batch)
        #expect(updates.allowUpdateRelaunch(onBusy: { Issue.record("An idle app can relaunch") }))

        activity.isRestarting = true
        #expect(activity.begin() == nil)
        activity.isRestarting = false
        #expect(activity.begin() != nil)
    }

    @MainActor @Test func decliningQuitPreservesActiveWork() throws {
        let activity = ComparisonActivity()
        let updates = AppUpdates(activity: activity)
        let run = try #require(activity.begin())

        let reply = updates.requestTermination(confirm: { false }, reply: { _ in
            Issue.record("A declined quit must never be completed")
        })
        #expect(reply == .terminateCancel)
        #expect(!run.isCancelled)
        #expect(activity.canStart)
        activity.end(run)
        #expect(updates.requestTermination(confirm: {
            Issue.record("An idle quit needs no comparison warning")
            return false
        }, reply: { _ in }) == .terminateNow)
    }

    @MainActor @Test func confirmedQuitStopsOwnedChildAndPreventsFurtherLaunches() async throws {
        let activity = ComparisonActivity()
        let updates = AppUpdates(activity: activity)
        let running = try #require(activity.begin())
        let validating = try #require(activity.begin())
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try running.start(child)
        DispatchQueue.global().async {
            child.waitUntilExit()
            running.finish(child)
        }

        let allowed: Bool = await withCheckedContinuation { continuation in
            let response = updates.requestTermination(confirm: { true }, reply: { allowed in
                continuation.resume(returning: allowed)
            })
            #expect(response == .terminateLater)
            if response != .terminateLater { continuation.resume(returning: false) }
        }
        #expect(allowed)
        #expect(!child.isRunning)
        #expect(child.terminationReason == .uncaughtSignal)
        #expect(running.isCancelled && validating.isCancelled)
        #expect(activity.begin() == nil)
        #expect(throws: CancellationError.self) { try validating.start(Process()) }
    }
}
