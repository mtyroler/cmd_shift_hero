/// The single master clock for gameplay. Implementations derive time from
/// audio sample counters (never wall clocks) so visuals can't drift from sound.
public protocol GameClock: AnyObject, Sendable {
    /// Current position of the *audible* song in seconds. Notes are judged and
    /// rendered against this value. Frozen while paused.
    var audibleSongTime: Double { get }
}
