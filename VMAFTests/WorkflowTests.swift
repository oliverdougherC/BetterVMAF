import Foundation
import Testing
@testable import VMAF

/// Deliberately ignores cancellation until released, like process teardown still in flight.
private actor ControlledAnalysis {
    var calls = 0
    var continuations: [CheckedContinuation<VMAFCalculator.VMAFResult, Error>] = []
    var profiles: [AnalysisConfiguration.ViewingProfile] = []
    func run(_ configuration: AnalysisConfiguration) async throws -> VMAFCalculator.VMAFResult {
        calls += 1; profiles.append(configuration.viewingProfile)
        return try await withCheckedThrowingContinuation { continuations.append($0) }
    }
    func complete(_ result: VMAFCalculator.VMAFResult) { continuations.removeFirst().resume(returning: result) }
    func fail() { continuations.removeFirst().resume(throwing: AnalysisError.invalid("Deliberate fixture failure")) }
    func count() -> Int { calls }
}

@MainActor
struct WorkflowTests {
    let source = URL(fileURLWithPath: "/fixtures/source.mp4")
    let encode = URL(fileURLWithPath: "/fixtures/encode.mp4")
    let other = URL(fileURLWithPath: "/fixtures/other.mp4")
    func waitUntil(_ condition: @escaping @MainActor () async -> Bool) async throws {
        for _ in 0..<200 { if await condition() { return }; try await Task.sleep(for: .milliseconds(5)) }
        Issue.record("Timed out waiting for controlled workflow state")
    }
    @Test func cancellationLocksInputsAndSuppressesLateCompletion() async throws {
        let control = ControlledAnalysis()
        let owner = ComparisonSession { _, _, configuration, _ in try await control.run(configuration) }
        owner.select(source, source: true); owner.select(encode, source: false)
        owner.start(); owner.start()
        try await waitUntil { await control.count() == 1 }
        owner.cancel(); owner.select(other, source: false); owner.start()
        #expect(owner.state == .cancelling)
        #expect(owner.encode == encode)
        await control.complete(ExportFixture.result())
        try await waitUntil { !owner.isBusy }
        #expect(owner.result == nil)
        #expect(await control.count() == 1)
        owner.select(other, source: false); owner.start()
        try await waitUntil { await control.count() == 2 }
        await control.complete(ExportFixture.result())
        try await waitUntil { !owner.isBusy }
        #expect(owner.result != nil)
        owner.selectProfile(.phone)
        #expect(owner.result == nil)
        owner.start()
        try await waitUntil { await control.count() == 3 }
        #expect(await control.profiles.last == .phone)
        await control.fail()
        try await waitUntil { !owner.isBusy }
        #expect(owner.result == nil)
        #expect(owner.error == "Deliberate fixture failure")
    }
    @Test func batchCancelClearRemoveRestartUsesStableRows() async throws {
        let control = ControlledAnalysis()
        let queue = BatchComparisonSession { _, _, configuration, _ in try await control.run(configuration) }
        queue.selectSource(source); queue.add([encode, other])
        let first = queue.items[0].id
        queue.start(); queue.start()
        try await waitUntil { await control.count() == 1 }
        queue.cancel(); queue.clear(); queue.remove(first); queue.selectSource(other); queue.start()
        #expect(queue.items.count == 2)
        #expect(queue.source == source)
        await control.complete(ExportFixture.result())
        try await waitUntil { !queue.isBusy }
        #expect(queue.items[0].state == .cancelled)
        #expect(queue.items[0].result == nil)
        #expect(await control.count() == 1)
        queue.remove(first); queue.start()
        try await waitUntil { await control.count() == 2 }
        await control.complete(ExportFixture.result())
        try await waitUntil { !queue.isBusy }
        #expect(queue.items.count == 1)
        #expect(queue.items[0].state == .completed)
        queue.selectSource(other)
        #expect(queue.items[0].result == nil)
        #expect(queue.items[0].state == .pending)
    }
    @Test func cancelOneJobContinuesQueueAndProfileInvalidatesAll() async throws {
        let control = ControlledAnalysis()
        let queue = BatchComparisonSession { _, _, configuration, _ in try await control.run(configuration) }
        queue.selectSource(source); queue.add([encode, other]); queue.start()
        try await waitUntil { await control.count() == 1 }
        queue.cancelItem(queue.items[0].id)
        await control.complete(ExportFixture.result())
        try await waitUntil { await control.count() == 2 }
        #expect(queue.items[0].state == .cancelled)
        await control.complete(ExportFixture.result())
        try await waitUntil { !queue.isBusy }
        let oldIDs = queue.items.map(\.id)
        queue.selectProfile(.television4K)
        #expect(queue.items.allSatisfy { $0.result == nil && $0.state == .pending })
        #expect(queue.items.map(\.id) != oldIDs)
    }
    @Test func batchCapacityStopsBeforeLaunchingExcessJob() async throws {
        let control = ControlledAnalysis()
        let queue = BatchComparisonSession { _, _, configuration, _ in try await control.run(configuration) }
        queue.selectSource(source)
        queue.add((0..<10).map { URL(fileURLWithPath: "/fixtures/\($0).mp4") })
        #expect(queue.items.count == 8)
        #expect(queue.queueMessage != nil)
        queue.start()
        try await waitUntil { await control.count() == 1 }
        let large = VMAFCalculator.VMAFResult(score: 90, minScore: 90, maxScore: 90, harmonicMean: 90, frameMetrics: [], duration: 20_000, frameCount: 600_000)
        await control.complete(large)
        try await waitUntil { !queue.isBusy }
        #expect(await control.count() == 1)
        #expect(queue.items[1].state == .pending)
        #expect(queue.queueMessage?.contains("1,000,000") == true)
    }
    @Test func changedSourceBetweenJobsRejectsResultAndStopsQueue() async throws {
        let control = ControlledAnalysis()
        let queue = BatchComparisonSession { _, _, configuration, _ in try await control.run(configuration) }
        queue.selectSource(source); queue.add([encode, other, URL(fileURLWithPath: "/fixtures/third.mp4")]); queue.start()
        try await waitUntil { await control.count() == 1 }
        await control.complete(ExportFixture.result())
        try await waitUntil { await control.count() == 2 }
        await control.complete(try VMAFCalculator.VMAFResult(analysis: ExportFixture.analysis(sourceHash: "changed")))
        try await waitUntil { !queue.isBusy }
        #expect(queue.items[0].state == .completed)
        #expect(queue.items[1].state == .failed)
        #expect(queue.items[1].result == nil)
        #expect(queue.items[1].error?.contains("source file changed") == true)
        #expect(queue.items[2].state == .pending)
        #expect(await control.count() == 2)
    }
    @Test func actualCompletedFrameCountCannotExceedRetainedBudget() async throws {
        let control = ControlledAnalysis()
        let queue = BatchComparisonSession { _, _, configuration, _ in try await control.run(configuration) }
        queue.selectSource(source); queue.add([encode, other]); queue.start()
        try await waitUntil { await control.count() == 1 }
        let first = VMAFCalculator.VMAFResult(score: 90, minScore: 90, maxScore: 90, harmonicMean: 90, frameMetrics: [], duration: 10, frameCount: 400_000)
        await control.complete(first)
        try await waitUntil { await control.count() == 2 }
        let unexpectedlyLarge = VMAFCalculator.VMAFResult(score: 90, minScore: 90, maxScore: 90, harmonicMean: 90, frameMetrics: [], duration: 20, frameCount: 700_000)
        await control.complete(unexpectedlyLarge)
        try await waitUntil { !queue.isBusy }
        #expect(queue.items[0].state == .completed)
        #expect(queue.items[1].state == .failed)
        #expect(queue.items[1].result == nil)
        #expect(queue.items[1].error?.contains("retained-frame budget") == true)
    }
    @Test func variableFrameNavigationUsesPresentationTimes() {
        let pairs = ExportFixture.analysis().framePairs
        #expect(PlaybackController.index(at: -0.1, frames: pairs) == 0)
        #expect(PlaybackController.index(at: 0.04, frames: pairs) == 1)
        #expect(PlaybackController.index(at: 0.065, frames: pairs) == 1)
        #expect(PlaybackController.index(at: 0.1, frames: pairs) == 2)
        #expect(PlaybackController.index(at: 100, frames: pairs) == 2)
    }
}
