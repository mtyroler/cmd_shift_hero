import AudioAnalysis
import Testing

@Suite struct AnalysisPlaceholderTests {
    @Test func versionIsSet() {
        #expect(AnalysisVersion.current >= 1)
    }
}
