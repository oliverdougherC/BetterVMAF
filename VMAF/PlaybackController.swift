import AVFoundation
import SwiftUI

/// Shared transport uses the analyzed pair map, including unequal source/encode start PTS.
@MainActor
final class PlaybackController: ObservableObject {
    let referencePlayer = AVPlayer()
    let comparisonPlayer = AVPlayer()
    @Published private(set) var ready = false
    @Published private(set) var playing = false
    @Published private(set) var seeking = false
    @Published private(set) var selectedIndex = 0
    @Published private(set) var error: String?
    @Published var loop = false
    private(set) var frames: [AnalysisFramePair] = []
    private var interval: ClosedRange<Int>?
    private var observer: Any?
    private var statusObservations: [NSKeyValueObservation] = []
    private var generation = UUID()
    private var seekGeneration = UUID()
    var timestamp: Double { frames.indices.contains(selectedIndex) ? frames[selectedIndex].timestamp : 0 }
    var duration: Double { frames.last.map { $0.timestamp + $0.duration } ?? 0 }

    func load(_ result: VMAFCalculator.VMAFResult) async {
        close()
        let loadID = UUID()
        generation = loadID
        guard let analysis = result.analysis, !analysis.samples.isEmpty else {
            error = "Playback requires a result with verified source identities and frame mapping. Analyze this pair again."
            return
        }
        frames = analysis.framePairs
        do {
            // Prevent a changed on-disk file being shown as evidence for an older result.
            let identityWorker = Task.detached(priority: .userInitiated) {
                (try AnalysisFileIdentity.capture(analysis.reference.url), try AnalysisFileIdentity.capture(analysis.comparison.url))
            }
            let identities = try await withTaskCancellationHandler { try await identityWorker.value } onCancel: { identityWorker.cancel() }
            guard identities.0.sha256 == analysis.reference.sha256,
                  identities.1.sha256 == analysis.comparison.sha256 else {
                throw AnalysisError.invalid("A video changed after analysis. Analyze it again before inspecting this result.")
            }
            try Task.checkCancellation()
            let reference = AVURLAsset(url: analysis.reference.url)
            let comparison = AVURLAsset(url: analysis.comparison.url)
            async let firstPlayable = reference.load(.isPlayable)
            async let secondPlayable = comparison.load(.isPlayable)
            let playable = try await (firstPlayable, secondPlayable)
            guard playable.0 && playable.1 else {
                throw AnalysisError.invalid("macOS cannot play one of these containers or codecs. Analysis is retained. For visual review, create a supported lossless intermediate and analyze that exact pair; this viewer does not silently substitute media.")
            }
            guard generation == loadID, !Task.isCancelled else { return }
            referencePlayer.replaceCurrentItem(with: AVPlayerItem(asset: reference))
            comparisonPlayer.replaceCurrentItem(with: AVPlayerItem(asset: comparison))
            referencePlayer.isMuted = true
            comparisonPlayer.isMuted = true
            for player in [referencePlayer, comparisonPlayer] {
                player.automaticallyWaitsToMinimizeStalling = false
                if let item = player.currentItem {
                    statusObservations.append(item.observe(\.status, options: [.new]) { [weak self] item, _ in
                        let failed = item.status == .failed
                        let message = item.error?.localizedDescription
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == loadID else { return }
                            if failed { self.pause(); self.ready = false; self.seeking = false; self.error = message ?? "Native playback failed for this codec. Use a supported lossless intermediate and reanalyze it." }
                        }
                    })
                }
            }
            // Playability describes the asset; both player items must finish asynchronous preparation.
            for attempt in 0..<500 {
                try Task.checkCancellation()
                guard generation == loadID else { return }
                let items = [referencePlayer.currentItem, comparisonPlayer.currentItem]
                if items.allSatisfy({ $0?.status == .readyToPlay }) { break }
                if let failed = items.compactMap({ $0 }).first(where: { $0.status == .failed }) {
                    throw failed.error ?? AnalysisError.invalid("Native decoder preparation failed.")
                }
                if attempt == 499 { throw AnalysisError.invalid("Native playback did not become ready. Try reopening the pair or a supported lossless intermediate.") }
                try await Task.sleep(for: .milliseconds(20))
            }
            ready = true
            observer = referencePlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.04, preferredTimescale: 600), queue: .main) { [weak self] time in
                Task { @MainActor [weak self] in self?.tick(time.seconds) }
            }
            seek(index: 0)
        } catch {
            guard generation == loadID, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    func select(start: Double, end: Double) {
        guard !frames.isEmpty else { return }
        let lower = Self.index(at: start, frames: frames)
        let upper = Self.index(at: max(start, end.nextDown), frames: frames)
        interval = lower...max(lower, upper)
        loop = true
        seek(index: lower)
    }
    func seek(time: Double) { interval = nil; seek(index: Self.index(at: time, frames: frames)) }
    func step(_ delta: Int) { seek(index: selectedIndex + delta) }
    func toggle() { playing ? pause() : play() }
    func pause() { referencePlayer.pause(); comparisonPlayer.pause(); playing = false }
    func play() {
        guard ready, !seeking, frames.indices.contains(selectedIndex) else { return }
        let pair = frames[selectedIndex]
        guard let referenceTime = Self.mediaTime(pts: pair.referencePTS, timeBase: pair.referenceTimeBase),
              let comparisonTime = Self.mediaTime(pts: pair.comparisonPTS, timeBase: pair.comparisonTimeBase) else {
            error = "The recorded time base cannot be represented by native playback."; return
        }
        let host = CMClockGetTime(CMClockGetHostTimeClock()) + CMTime(seconds: 0.15, preferredTimescale: 1_000_000_000)
        referencePlayer.setRate(1, time: referenceTime, atHostTime: host)
        comparisonPlayer.setRate(1, time: comparisonTime, atHostTime: host)
        playing = true
    }
    func seek(index: Int, resume: Bool = false) {
        guard ready, !frames.isEmpty else { return }
        pause()
        let index = min(max(index, 0), frames.count - 1)
        selectedIndex = index
        let pair = frames[index]
        guard let referenceTime = Self.mediaTime(pts: pair.referencePTS, timeBase: pair.referenceTimeBase),
              let comparisonTime = Self.mediaTime(pts: pair.comparisonPTS, timeBase: pair.comparisonTimeBase) else {
            error = "The recorded time base cannot be represented by native playback."; return
        }
        let request = UUID()
        seekGeneration = request
        seeking = true
        Task { [weak self] in
            guard let self, self.seekGeneration == request, self.ready else { return }
            async let first = self.exactSeek(self.referencePlayer, to: referenceTime, request: request)
            async let second = self.exactSeek(self.comparisonPlayer, to: comparisonTime, request: request)
            let completed = await (first, second)
            guard self.seekGeneration == request, self.ready else { return }
            self.seeking = false
            if !completed.0 || !completed.1 { self.error = "Native player could not complete this exact frame seek. Retry or use a supported lossless intermediate." }
            else { self.error = nil; if resume { self.play() } }
        }
    }
    private func exactSeek(_ player: AVPlayer, to time: CMTime, request: UUID) async -> Bool {
        guard ready, seekGeneration == request, !Task.isCancelled else { return false }
        // Register synchronously on the main actor so a stale async-let cannot issue a later seek.
        return await withCheckedContinuation { continuation in
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                continuation.resume(returning: finished)
            }
        }
    }
    private func tick(_ referenceTime: Double) {
        guard playing, !seeking, referenceTime.isFinite, let first = frames.first else { return }
        let normalized = referenceTime - first.referenceTimestamp
        selectedIndex = Self.index(at: normalized + 1e-9, frames: frames)
        let range = interval ?? 0...(frames.count - 1)
        let end = frames[range.upperBound]
        if normalized >= end.timestamp + end.duration - 0.01 {
            if loop { seek(index: range.lowerBound, resume: true) }
            else { pause() }
            return
        }
        let comparisonTime = comparisonPlayer.currentTime().seconds - first.comparisonTimestamp
        let tolerance = max(0.02, frames[selectedIndex].duration * 0.55)
        // A stalled decoder cannot continue silently beside a running source.
        if !comparisonTime.isFinite || abs(comparisonTime - normalized) > tolerance {
            seek(index: selectedIndex, resume: true)
        }
    }
    /// Preserve the rational boundary exactly: rounding Double seconds down can display the previous frame.
    nonisolated static func mediaTime(pts: Int64, timeBase: String) -> CMTime? {
        let parts = timeBase.split(separator: "/")
        guard parts.count == 2, let numerator = Int32(parts[0]), let denominator = Int32(parts[1]),
              numerator > 0, denominator > 0 else { return nil }
        let time = CMTimeMultiply(CMTime(value: pts, timescale: denominator), multiplier: numerator)
        return time.isValid && time.isNumeric ? time : nil
    }
    nonisolated static func index(at time: Double, frames: [AnalysisFramePair]) -> Int {
        guard !frames.isEmpty else { return 0 }
        var low = 0, high = frames.count
        while low < high { let mid = (low + high) / 2; if frames[mid].timestamp <= time { low = mid + 1 } else { high = mid } }
        return max(0, low - 1)
    }
    func close() {
        generation = UUID()
        seekGeneration = UUID()
        pause()
        if let observer { referencePlayer.removeTimeObserver(observer) }
        observer = nil
        statusObservations.removeAll()
        referencePlayer.replaceCurrentItem(with: nil)
        comparisonPlayer.replaceCurrentItem(with: nil)
        ready = false
        seeking = false
        frames = []
        interval = nil
        error = nil
    }
}
