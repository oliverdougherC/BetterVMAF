import Foundation
import SwiftUI

/// One window owns one task. Input changes and stale completions cannot reuse a result.
@MainActor
final class ComparisonSession: ObservableObject {
    typealias Runner = @Sendable (URL, URL, AnalysisConfiguration, @escaping @Sendable (AnalysisProgress) -> Void) async throws -> VMAFCalculator.VMAFResult
    enum State: String { case idle, running, cancelling }
    @Published private(set) var source: URL?
    @Published private(set) var encode: URL?
    @Published private(set) var result: VMAFCalculator.VMAFResult?
    @Published private(set) var error: String?
    @Published private(set) var state: State = .idle
    @Published private(set) var progress: AnalysisProgress?
    @Published private(set) var configuration = AnalysisConfiguration()
    private var lastProgress = Date.distantPast
    private var task: Task<Void, Never>?
    private var runID: UUID?
    private let runner: Runner
    var isBusy: Bool { state != .idle }

    init(runner: @escaping Runner = { try await ComparisonSession.analyze($0, $1, $2, $3) }) { self.runner = runner }

    nonisolated static func analyze(_ source: URL, _ encode: URL, _ configuration: AnalysisConfiguration, _ progress: @escaping @Sendable (AnalysisProgress) -> Void) async throws -> VMAFCalculator.VMAFResult {
        let calculator = VMAFCalculator()
        calculator.onProgress = progress
        return try await calculator.calculateVMAF(referenceVideo: source, comparisonVideo: encode, configuration: configuration)
    }

    func selectProfile(_ profile: AnalysisConfiguration.ViewingProfile) {
        guard !isBusy else { return }
        configuration.viewingProfile = profile
        result = nil
    }
    func select(_ url: URL, source isSource: Bool) {
        guard !isBusy else { return }
        if isSource { source = url } else { encode = url }
        result = nil
        error = nil
    }

    func start() {
        guard !isBusy, let source, let encode else { return }
        let id = UUID()
        runID = id
        state = .running // Lock inputs before the first suspension, including preflight.
        result = nil
        error = nil
        let runner = runner
        let configuration = configuration
        progress = nil
        lastProgress = .distantPast
        task = Task { [weak self] in
            do {
                let result = try await runner(source, encode, configuration) { [weak self] update in
                    Task { @MainActor [weak self] in
                        guard let self, self.runID == id, self.state == .running else { return }
                        let now = Date()
                        if update.isFinished || now.timeIntervalSince(self.lastProgress) >= 0.1 {
                            self.progress = update; self.lastProgress = now
                        }
                    }
                }
                guard let self, self.runID == id else { return }
                if !Task.isCancelled && self.state == .running { self.result = result }
            } catch {
                guard let self, self.runID == id else { return }
                if !Task.isCancelled && self.state != .cancelling { self.error = error.localizedDescription }
            }
            guard let self, self.runID == id else { return }
            self.state = .idle
            self.task = nil
            self.runID = nil
        }
    }

    func cancel() {
        guard isBusy else { return }
        state = .cancelling
        task?.cancel()
    }
}

struct BatchComparison: Identifiable {
    enum State: String { case pending, running, completed, failed, cancelled }
    let id: UUID
    let url: URL
    var state: State = .pending
    var result: VMAFCalculator.VMAFResult?
    var error: String?
    var progress: AnalysisProgress?
    var compatibilityKey: String?
    init(url: URL) { id = UUID(); self.url = url }
}

/// Bounded sequential queue. Row identity never depends on mutable array indices.
@MainActor
final class BatchComparisonSession: ObservableObject {
    static let maximumCandidates = 8
    static let maximumRetainedFrames = 1_000_000
    @Published private(set) var queueMessage: String?
    @Published private(set) var source: URL?
    @Published private(set) var items: [BatchComparison] = []
    @Published private(set) var state: ComparisonSession.State = .idle
    private var task: Task<Void, Never>?
    private var currentTask: Task<VMAFCalculator.VMAFResult, Error>?
    private var currentID: UUID?
    private var runID: UUID?
    @Published private(set) var configuration = AnalysisConfiguration()
    private var lastProgress = Date.distantPast
    private var cancelledIDs = Set<UUID>()
    private var pinnedSourceSHA256: String?
    private let runner: ComparisonSession.Runner
    var isBusy: Bool { state != .idle }
    init(runner: @escaping ComparisonSession.Runner = { try await ComparisonSession.analyze($0, $1, $2, $3) }) { self.runner = runner }

    func selectProfile(_ profile: AnalysisConfiguration.ViewingProfile) {
        guard !isBusy else { return }
        configuration.viewingProfile = profile
        items = items.map { BatchComparison(url: $0.url) }
        pinnedSourceSHA256 = nil
        queueMessage = nil
    }
    func selectSource(_ url: URL) {
        guard !isBusy else { return }
        source = url
        // Every retained candidate becomes a new comparison against this source.
        items = items.map { BatchComparison(url: $0.url) }
        pinnedSourceSHA256 = nil
        queueMessage = nil
    }
    func add(_ urls: [URL]) {
        guard !isBusy else { return }
        for url in urls where !items.contains(where: { $0.url == url }) {
            guard items.count < Self.maximumCandidates else {
                queueMessage = "A queue is limited to \(Self.maximumCandidates) encodes. Export and remove completed candidates before adding more."
                break
            }
            items.append(BatchComparison(url: url))
        }
    }
    func remove(_ id: UUID) { guard !isBusy else { return }; items.removeAll { $0.id == id }; queueMessage = nil }
    func clear() { guard !isBusy else { return }; items.removeAll(); queueMessage = nil }
    func retry(_ id: UUID) {
        guard !isBusy, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = .pending
        items[index].result = nil
        items[index].error = nil
    }
    func cancelItem(_ id: UUID) {
        guard isBusy, let index = items.firstIndex(where: { $0.id == id }),
              items[index].state == .running || items[index].state == .pending else { return }
        cancelledIDs.insert(id)
        if currentID == id { currentTask?.cancel() }
        else { items[index].state = .cancelled }
    }
    func cancel() {
        guard isBusy else { return }
        state = .cancelling
        currentTask?.cancel()
        task?.cancel()
    }
    func start() {
        guard !isBusy, let source else { return }
        let queue = items.filter { $0.state == .pending }.map { ($0.id, $0.url) }
        guard !queue.isEmpty else { return }
        let run = UUID()
        runID = run
        state = .running
        cancelledIDs = []
        queueMessage = nil
        let runner = runner
        let configuration = configuration
        task = Task { [weak self] in
            for (id, url) in queue {
                guard let self, self.runID == run, !Task.isCancelled else { break }
                if self.cancelledIDs.contains(id) { continue }
                let retained = self.items.compactMap(\.result).reduce(0) { $0 + $1.frameCount }
                if let expected = self.items.compactMap(\.result).first?.frameCount,
                   retained + expected > Self.maximumRetainedFrames {
                    self.queueMessage = "Queue paused at the 1,000,000 retained-frame limit. Export and remove completed candidates, then start pending jobs."
                    break
                }
                self.update(id) { $0.state = .running; $0.error = nil; $0.result = nil }
                self.lastProgress = .distantPast
                let child = Task { [weak self] in
                    try await runner(source, url, configuration) { [weak self] update in
                        Task { @MainActor [weak self] in
                            guard let self, self.runID == run, self.currentID == id, self.state == .running else { return }
                            let now = Date()
                            if update.isFinished || now.timeIntervalSince(self.lastProgress) >= 0.1 {
                                self.update(id) { $0.progress = update }; self.lastProgress = now
                            }
                        }
                    }
                }
                self.currentTask = child
                self.currentID = id
                let outcome = await child.result // Teardown completes before edits or another job.
                let compatibility: String?
                if case .success(let result) = outcome, let analysis = result.analysis {
                    let worker = Task.detached(priority: .utility) { try ComparisonTradeoffs.compatibilityKey(analysis) }
                    compatibility = try? await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                } else { compatibility = nil }
                guard self.runID == run else { break }
                let cancelled = Task.isCancelled || self.cancelledIDs.contains(id)
                let retainedAtCompletion = self.items.compactMap(\.result).reduce(0) { $0 + $1.frameCount }
                var rejection: String?
                if case .success(let result) = outcome, !cancelled {
                    if let expected = self.pinnedSourceSHA256, result.analysis?.reference.sha256 != expected {
                        rejection = "The source file changed during this queue. Choose the source again to reset every candidate before continuing."
                    } else if retainedAtCompletion + result.frameCount > Self.maximumRetainedFrames {
                        rejection = "This result would exceed the 1,000,000 retained-frame budget. Export and remove completed candidates, then retry."
                    } else if self.pinnedSourceSHA256 == nil { self.pinnedSourceSHA256 = result.analysis?.reference.sha256 }
                }
                self.update(id) { row in
                    if cancelled { row.state = .cancelled; return }
                    switch outcome {
                    case .success(let result):
                        if let rejection { row.state = .failed; row.error = rejection }
                        else { row.result = result; row.compatibilityKey = compatibility; row.state = .completed }
                    case .failure(let error): row.error = error.localizedDescription; row.state = .failed
                    }
                }
                self.currentTask = nil
                self.currentID = nil
                if let rejection { self.queueMessage = rejection; break }
            }
            guard let self, self.runID == run else { return }
            self.state = .idle
            self.task = nil
            self.currentTask = nil
            self.currentID = nil
            self.runID = nil
        }
    }
    private func update(_ id: UUID, _ mutate: (inout BatchComparison) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
    }
}
