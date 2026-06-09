/// Bumped whenever the onset-detection or chart-generation algorithm changes,
/// so stale cached charts are regenerated.
/// v2: onset times moved to the full capture timeline (v1 caches were
/// shifted early by the Music.app startup lead-in).
public enum AnalysisVersion {
    public static let current = 2
}
