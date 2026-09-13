import Foundation
import Testing
@testable import VMAF

struct AnalysisAdmissionTests {
    @Test func concurrentWholeJobsNeverExceedOneActivePermit() async throws {
        let admission = AnalysisAdmission()
        let counter = AdmissionTestCounter()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await admission.withPermit {
                        await counter.enter()
                        try await Task.sleep(for: .milliseconds(2))
                        await counter.leave()
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(await counter.maximum == 1)
        #expect(await counter.completed == 20)
        #expect(await admission.activeCount == 0)
        #expect(await admission.waitingCount == 0)
    }

    @Test func cancelledWaitingJobNeverExecutesOrConsumesTheNextPermit() async throws {
        let admission = AnalysisAdmission()
        let latch = AdmissionTestLatch()
        let counter = AdmissionTestCounter()
        let holder = Task { try await admission.withPermit { await latch.wait() } }
        defer { Task { await latch.open() } }
        try await Self.waitFor(admission, active: 1, waiting: 0)
        let queued = Task { try await admission.withPermit { await counter.enter() } }
        try await Self.waitFor(admission, active: 1, waiting: 1)
        let start = Date()
        queued.cancel()
        await #expect(throws: CancellationError.self) { try await queued.value }
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(await counter.maximum == 0)
        #expect(await admission.activeCount == 1)
        #expect(await admission.waitingCount == 0)
        await latch.open()
        try await holder.value
        #expect(try await admission.withPermit { 42 } == 42)
        #expect(await admission.activeCount == 0)
    }

    @Test func failedAndCancelledActiveJobsReleaseTheirPermits() async throws {
        let admission = AnalysisAdmission()
        await #expect(throws: AdmissionTestError.self) {
            try await admission.withPermit { throw AdmissionTestError.expected }
        }
        #expect(try await admission.withPermit { true })
        let active = Task { try await admission.withPermit { try await Task.sleep(for: .seconds(30)) } }
        try await Self.waitFor(admission, active: 1, waiting: 0)
        active.cancel()
        await #expect(throws: CancellationError.self) { try await active.value }
        #expect(try await admission.withPermit { true })
        #expect(await admission.activeCount == 0)
    }

    @Test func actualServiceQueuedTaskCancellationReturnsBeforeActiveJobFinishes() async throws {
        try await Self.checkServiceQueuedCancellation(explicit: false)
    }

    @Test func actualServiceExplicitCancelAlsoCancelsAdmissionWait() async throws {
        try await Self.checkServiceQueuedCancellation(explicit: true)
    }

    private static func checkServiceQueuedCancellation(explicit: Bool) async throws {
        let admission = AnalysisAdmission()
        let latch = AdmissionTestLatch()
        let holder = Task { try await admission.withPermit { await latch.wait() } }
        defer { Task { await latch.open() } }
        try await waitFor(admission, active: 1, waiting: 0)
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = AnalysisService(engine: AnalysisEngine(directory: missing), admission: admission)
        let queued = Task { try await service.analyze(referenceURL: missing, comparisonURL: missing, configuration: .init()) }
        try await waitFor(admission, active: 1, waiting: 1)
        let start = Date()
        if explicit { service.cancel() } else { queued.cancel() }
        // Starting any actual work would throw a file/engine error, not this cancellation.
        await #expect(throws: CancellationError.self) { try await queued.value }
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(await admission.activeCount == 1)
        #expect(await admission.waitingCount == 0)
        await latch.open()
        try await holder.value
        let next = AnalysisService(engine: AnalysisEngine(directory: missing), admission: admission)
        do {
            _ = try await next.analyze(referenceURL: missing, comparisonURL: missing, configuration: .init())
            Issue.record("Expected the admitted job's deliberate missing-input failure.")
        } catch {
            #expect(!(error is CancellationError))
        }
        #expect(await admission.activeCount == 0)
        #expect(try await admission.withPermit { "next job succeeds" } == "next job succeeds")
    }

    private static func waitFor(_ admission: AnalysisAdmission, active: Int, waiting: Int) async throws {
        for _ in 0..<2_000 {
            if await admission.activeCount == active, await admission.waitingCount == waiting { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw AdmissionTestError.timeout
    }
}

private enum AdmissionTestError: Error { case expected, timeout }
private actor AdmissionTestCounter {
    private var current = 0
    var maximum = 0
    var completed = 0
    func enter() { current += 1; maximum = max(maximum, current) }
    func leave() { current -= 1; completed += 1 }
}
private actor AdmissionTestLatch {
    private var opened = false
    private var continuations: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuations.append($0) }
    }
    func open() {
        opened = true
        let pending = continuations
        continuations.removeAll()
        for continuation in pending { continuation.resume() }
    }
}
