/// Bumped whenever the onset-detection or chart-generation algorithm changes,
/// so stale cached charts are regenerated.
/// v2: onset times moved to the full capture timeline (v1 caches were
/// shifted early by the Music.app startup lead-in).
/// v3: starvation relax — sustained/ambient passages now yield onsets, so
/// v2 caches (with dead stretches) regenerate.
public enum AnalysisVersion {
    public static let current = 3
}
