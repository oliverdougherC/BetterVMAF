import Foundation
import Security
import Testing
@testable import VMAF

struct SandboxComparisonTests {
    private final class FixtureBundle {}

    @Test func sandboxedTestHostScoresWithBundledFFmpeg() async throws {
        let task = try #require(SecTaskCreateFromSelf(nil))
        let entitlement = SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil)
        #expect(entitlement as? Bool == true)

        let fixtures = Bundle(for: FixtureBundle.self)
        let reference = try #require(fixtures.url(forResource: "vmaf-reference", withExtension: "mp4"))
        let encoded = try #require(fixtures.url(forResource: "vmaf-comparison", withExtension: "mp4"))
        let calculator = VMAFCalculator()
        let run = ComparisonRun()
        let result = try await calculator.calculateVMAF(referenceVideo: reference, comparisonVideo: encoded, run: run)

        #expect(result.frameCount == 24)
        #expect(abs(result.score - 33.08) < 0.5)
        #expect(result.libvmafVersion == "3.2.0")
    }
}
