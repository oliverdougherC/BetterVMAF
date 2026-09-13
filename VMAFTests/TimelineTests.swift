import Testing
@testable import VMAF

struct TimelineTests {
    @Test func envelopePreservesSpikesAndBoundsWork() {
        let points = (0..<216_000).map { TimelinePoint(id: $0, time: Double($0) / 60, value: $0 == 12345 ? -17 : ($0 == 12346 ? 111 : 95)) }
        let output = TimelineData.envelope(points, range: 0...3600, buckets: 500)
        #expect(output.count <= 1002)
        #expect(output.contains { $0.id == 12345 && $0.value == -17 })
        #expect(output.contains { $0.id == 12346 && $0.value == 111 })
        #expect(output.first == points.first)
        #expect(output.last == points.last)
        #expect(zip(output, output.dropFirst()).allSatisfy { $0.time <= $1.time })
        #expect(points.count == 216_000)
    }

    @Test func exactAndNearestVFRLookup() {
        let points = [0.0, 0.04, 0.10, 0.12].enumerated().map { TimelinePoint(id: $0.offset, time: $0.element, value: 95) }
        #expect(TimelineData.nearest(points, time: 0.10)?.id == 2)
        #expect(TimelineData.nearest(points, time: 0.075)?.id == 2)
        #expect(TimelineData.nearest(points, time: -1)?.id == 0)
        #expect(TimelineData.nearest(points, time: 9)?.id == 3)
        #expect(TimelineData.nearest([], time: 1) == nil)
        #expect(TimelineData.nearest(points, time: .nan) == nil)
    }

    @Test func emptyConstantAndSignedDomains() {
        #expect(TimelineData.domain([]) == 0...1)
        let one = [TimelinePoint(id: 0, time: 0, value: 111)]
        #expect(TimelineData.domain(one).contains(111))
        #expect(TimelineData.envelope(one, range: 0...1, buckets: 100) == one)
        #expect(TimelineData.domain([TimelinePoint(id: 0, time: 0, value: -42)]).contains(-42))
        #expect(TimelineData.envelope(one, range: 2...3, buckets: 100).isEmpty)
    }
}
