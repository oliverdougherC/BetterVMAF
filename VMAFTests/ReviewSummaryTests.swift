import Testing
@testable import VMAF

struct ReviewSummaryTests {
    @Test func isolatedAndSustainedDamageStaySeparate() {
        let points = (0..<600).map { i in
            ReviewObservation(frame: i, time: Double(i) / 60, duration: 1.0 / 60,
                              value: i == 12 ? 10 : ((300..<324).contains(i) ? 50 : 95))
        }
        let (_, concerns) = ReviewSummary.summarize(points, id: "vmaf", name: "VMAF", unit: "points", lowerIsBetter: false)
        #expect(concerns.contains { $0.firstFrame == 12 && $0.lastFrame == 12 && $0.kind == "Isolated frame" })
        #expect(concerns.contains { $0.firstFrame == 300 && $0.lastFrame == 323 && $0.kind == "Sustained interval" })
        #expect(!concerns.contains { $0.firstFrame == 0 })
    }

    @Test func durationWeightedVFRAndMissingCoverage() {
        let values = [ReviewObservation(frame: 0, time: 0, duration: 0.9, value: 10),
                      ReviewObservation(frame: 1, time: 0.9, duration: 0.1, value: 100),
                      ReviewObservation(frame: 2, time: 1, duration: 0.1, value: nil)]
        let (d, _) = ReviewSummary.summarize(values, id: "test", name: "Test", unit: "points", lowerIsBetter: false)
        #expect(d.median == .finite(10))
        #expect(d.durationWeightedMean == .finite(19))
        #expect(d.coverageSeconds == 1)
        #expect(d.missingCount == 1)
    }

    @Test func infinityNegativeAndLowerIsBetter() {
        let values = (0..<100).map { ReviewObservation(frame: $0, time: Double($0), duration: 1, value: $0 == 40 ? 20 : 0) }
        let (d, concerns) = ReviewSummary.summarize(values, id: "cambi", name: "CAMBI", unit: "points", lowerIsBetter: true)
        #expect(d.extreme == .finite(20))
        #expect(d.tailLabel == "P95")
        #expect(concerns.first?.firstFrame == 40)
        let infinity = [ReviewObservation(frame: 0, time: 0, duration: 1, value: .infinity)]
        let identity = ReviewSummary.summarize(infinity, id: "xpsnr", name: "XPSNR", unit: "dB", lowerIsBetter: false)
        #expect(identity.0.median == .positiveInfinity)
        #expect(identity.1.isEmpty)
        let signed = [ReviewObservation(frame: 0, time: 0, duration: 1, value: -42)]
        #expect(ReviewSummary.summarize(signed, id: "signed", name: "Signed", unit: "points", lowerIsBetter: false).0.extreme == .finite(-42))
    }

    @Test func mergeKeepsReasonsAndExactFrameRange() {
        let a = ReviewConcern(id: "a", start: 0.1, end: 0.2, firstFrame: 1, lastFrame: 2, reasons: ["VMAF lower tail"], kind: "Isolated frame")
        let b = ReviewConcern(id: "b", start: 0.21, end: 0.4, firstFrame: 3, lastFrame: 4, reasons: ["XPSNR lower tail"], kind: "Isolated frame")
        let merged = ReviewSummary.merge([b, a])
        #expect(merged.count == 1)
        #expect(merged[0].reasons.count == 2)
        #expect(merged[0].firstFrame == 1 && merged[0].lastFrame == 4)
        #expect(merged[0].start == 0.1 && merged[0].end == 0.4)
    }
}
