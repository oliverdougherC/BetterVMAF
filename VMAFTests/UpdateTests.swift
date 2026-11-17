import AppKit
import Testing
@testable import VMAF

struct UpdateTests {
    @MainActor @Test func deferredUpdateRequiresExplicitRetryAfterAllWorkEnds() throws {
        let activity = ComparisonActivity()
        let updates = AppUpdates(activity: activity)
        let single = try #require(activity.begin())
        let batch = try #require(activity.begin())

        var installCount = 0
        #expect(updates.postponeInstallationIfNeeded { installCount += 1 })
        updates.installDownloadedUpdate()
        activity.end(single)
        updates.installDownloadedUpdate()
        #expect(installCount == 0)
        activity.end(batch)
        #expect(installCount == 0)
        updates.installDownloadedUpdate()
        updates.installDownloadedUpdate()
        #expect(installCount == 1)
        #expect(!updates.postponeInstallationIfNeeded {
            Issue.record("An idle app lets Sparkle continue directly")
        })

        activity.isRestarting = true
        #expect(activity.begin() == nil)
        activity.isRestarting = false
        #expect(activity.begin() != nil)
    }

    @MainActor @Test func quitConfirmationCanOverlapUpdatePreparation() throws {
        let activity = ComparisonActivity()
        let updates = AppUpdates(activity: activity)
        let run = try #require(activity.begin())

        let response = updates.requestTermination(confirm: {
            activity.end(run)
            #expect(updates.postponeInstallationIfNeeded {})
            return false
        }, reply: { _ in })
        #expect(response == .terminateCancel)
        #expect(updates.deferredInstallation != nil)

        #expect(updates.requestTermination(confirm: { false }, reply: { _ in }) == .terminateNow)
        #expect(activity.begin() == nil)
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
        #expect(updates.postponeInstallationIfNeeded {
            Issue.record("Intentional quit must leave Sparkle to install without relaunching")
        })
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
        updates.installDownloadedUpdate()
        #expect(activity.begin() == nil)
        #expect(throws: CancellationError.self) { try validating.start(Process()) }
    }
}
