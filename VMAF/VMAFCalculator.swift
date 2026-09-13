import Foundation

/// Compatibility surface for existing charts; AnalysisResult is the authoritative export/result model.
final class VMAFCalculator: @unchecked Sendable {
    struct VMAFResult: Sendable {
        let score: Double
        let minScore: Double
        let maxScore: Double
        let harmonicMean: Double
        let frameMetrics: [FrameMetric]
        let duration: TimeInterval
        let frameCount: Int
        let analysis: AnalysisResult?
        var sourceURL: URL? { analysis?.reference.url }
        var comparisonURL: URL? { analysis?.comparison.url }
        init(score: Double, minScore: Double, maxScore: Double, harmonicMean: Double, frameMetrics: [FrameMetric],
             duration: TimeInterval, frameCount: Int, analysis: AnalysisResult? = nil) {
            self.score = score; self.minScore = minScore; self.maxScore = maxScore; self.harmonicMean = harmonicMean
            self.frameMetrics = frameMetrics; self.duration = duration; self.frameCount = frameCount; self.analysis = analysis
        }
        init(analysis: AnalysisResult) throws {
            guard let mean = analysis.pooledMetrics["vmaf"]?["mean"]?.finiteValue,
                  let min = analysis.pooledMetrics["vmaf"]?["min"]?.finiteValue,
                  let max = analysis.pooledMetrics["vmaf"]?["max"]?.finiteValue else { throw AnalysisError.missingMetric("VMAF summary") }
            self.init(score: mean, minScore: min, maxScore: max,
                harmonicMean: analysis.pooledMetrics["vmaf"]?["harmonic_mean"]?.finiteValue ?? .nan,
                frameMetrics: try analysis.samples.enumerated().map { index, sample in
                    guard sample.pair.index == index, sample.pair.timestamp.isFinite, sample.pair.timestamp >= 0, sample.pair.duration.isFinite, sample.pair.duration > 0, let primary = sample.values["vmaf"]?.finiteValue else { throw AnalysisError.invalid("Invalid primary output or frame mapping in analysis result.") }
                    return FrameMetric(frameNumber: sample.pair.index, vmafScore: primary,
                        integerMotion: sample.values["integer_motion"]?.finiteValue,
                        integerMotion2: sample.values["integer_motion2"]?.finiteValue,
                        integerAdm2: sample.values["integer_adm2"]?.finiteValue,
                        integerAdmScales: (0..<4).map { sample.values["integer_adm_scale\($0)"]?.finiteValue },
                        integerVifScales: (0..<4).map { sample.values["integer_vif_scale\($0)"]?.finiteValue },
                        timestamp: sample.pair.timestamp)
                }, duration: analysis.comparedDuration, frameCount: analysis.samples.count, analysis: analysis)
        }
    }

    struct FrameMetric: Codable, Identifiable, Sendable {
        let frameNumber: Int
        let vmafScore: Double
        let integerMotion: Double?
        let integerMotion2: Double?
        let integerAdm2: Double?
        let integerAdmScales: [Double?]
        let integerVifScales: [Double?]
        let timestamp: TimeInterval
        var id: Int { frameNumber }
        init(frameNumber: Int, vmafScore: Double, integerMotion: Double? = nil, integerMotion2: Double? = nil,
             integerAdm2: Double? = nil, integerAdmScales: [Double?] = [], integerVifScales: [Double?] = [],
             timestamp: TimeInterval = .nan) {
            self.frameNumber = frameNumber; self.vmafScore = vmafScore; self.integerMotion = integerMotion
            self.integerMotion2 = integerMotion2; self.integerAdm2 = integerAdm2
            self.integerAdmScales = integerAdmScales; self.integerVifScales = integerVifScales; self.timestamp = timestamp
        }
    }

    protocol VMAFCalculatorDelegate {
        func vmafCalculatorDidUpdateProgress(frameCount: Int, fps: Double, progress: Double, totalFrames: Int)
    }
    var delegate: VMAFCalculatorDelegate?
    var onProgress: (@Sendable (AnalysisProgress) -> Void)?
    private let lock = NSLock()
    private var activeService: AnalysisService?
    private var activeRun: UUID?
    private var lastCommand = ""
    private var lastErrorOutput = ""
    private var lastTerminationStatus: Int32?
    private var estimatedTotalFrames = 0
    private let injectedEngine: AnalysisEngine?
    init(engine: AnalysisEngine? = nil) { injectedEngine = engine }

    func cancel() {
        lock.lock(); let service = activeService; lock.unlock()
        service?.cancel()
    }
    func getEstimatedTotalFrames() -> Int? {
        lock.lock(); defer { lock.unlock() }; return estimatedTotalFrames > 0 ? estimatedTotalFrames : nil
    }
    func getLastCommand() -> String { lock.lock(); defer { lock.unlock() }; return lastCommand }
    func getLastErrorOutput() -> String { lock.lock(); defer { lock.unlock() }; return lastErrorOutput }
    func getLastTerminationStatus() -> Int32? { lock.lock(); defer { lock.unlock() }; return lastTerminationStatus }

    private func begin() throws -> UUID {
        lock.lock(); defer { lock.unlock() }
        guard activeRun == nil else { throw AnalysisError.busy }
        lastCommand = ""; lastErrorOutput = ""; lastTerminationStatus = nil; estimatedTotalFrames = 0
        let id = UUID(); activeRun = id; return id
    }
    private func finish(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        if activeRun == id { activeService = nil; activeRun = nil }
    }
    private func install(_ service: AnalysisService) { lock.lock(); activeService = service; lock.unlock() }
    private func diagnostic(_ command: String, _ stderr: String, _ status: Int32?) {
        lock.lock(); defer { lock.unlock() }; lastCommand = command; lastErrorOutput = stderr; lastTerminationStatus = status
    }
    private func progress(_ update: AnalysisProgress, runID: UUID) {
        lock.lock()
        guard activeRun == runID else { lock.unlock(); return }
        estimatedTotalFrames = update.totalFrames ?? 0
        lock.unlock()
        onProgress?(update)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock(); let current = self.activeRun == runID; self.lock.unlock()
            guard current else { return }
            self.delegate?.vmafCalculatorDidUpdateProgress(frameCount: update.frameCount, fps: update.processingFPS,
                progress: (update.fraction ?? 0) * 100, totalFrames: update.totalFrames ?? 0)
        }
    }

    func calculateVMAF(referenceVideo: URL, comparisonVideo: URL,
                       configuration: AnalysisConfiguration = AnalysisConfiguration()) async throws -> VMAFResult {
        let reference = referenceVideo, comparison = comparisonVideo, config = configuration
        let id = try begin()
        defer { finish(id) }
        do {
            let service = try AnalysisService(engine: injectedEngine ?? AnalysisEngine.bundled())
            install(service)
            let result = try await service.analyze(referenceURL: reference, comparisonURL: comparison, configuration: config,
                progress: { [weak self] in self?.progress($0, runID: id) },
                diagnostic: { [weak self] in self?.diagnostic($0, $1, $2) })
            try Task.checkCancellation()
            return try VMAFResult(analysis: result)
        } catch {
            if !(error is CancellationError) { diagnostic(getLastCommand(), getLastErrorOutput().isEmpty ? error.localizedDescription : getLastErrorOutput(), getLastTerminationStatus()) }
            throw error
        }
    }
}
