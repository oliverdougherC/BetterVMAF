#if ANALYSIS_CLI
import Foundation

/// Build with -D ANALYSIS_CLI for reproducible service-level conformance; omitted from the app target.
@main struct AnalysisCommandLine {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count == 5 else {
            FileHandle.standardError.write(Data("Usage: analysis-cli ENGINE_DIRECTORY REFERENCE ENCODE OUTPUT_JSON\n".utf8))
            exit(64)
        }
        do {
            let engine = AnalysisEngine(directory: URL(fileURLWithPath: args[1]))
            let result = try await AnalysisService(engine: engine).analyze(referenceURL: URL(fileURLWithPath: args[2]),
                comparisonURL: URL(fileURLWithPath: args[3]), configuration: .init())
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(result).write(to: URL(fileURLWithPath: args[4]), options: .atomic)
            print("\(result.samples.count) frames; VMAF \(result.pooledMetrics["vmaf"]?["mean"]?.finiteValue ?? .nan); model \(result.modelIdentifier)")
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}
#endif
