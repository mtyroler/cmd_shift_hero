import GameCore
import Testing

@Suite struct StarPowerTests {
    private func sessionWithFullMeter() -> GameSession {
        let key = KeyPosition(row: .home, column: 0)
        let alt = KeyPosition(row: .home, column: 1)
        // 25 alternating perfect hits → meter = 25 × 0.04 = 1.0
        let notes = (0..<30).map { Note(time: Double($0) * 0.5 + 1, key: $0 % 2 == 0 ? key : alt) }
        let session = GameSession(chart: Chart(notes: notes))
        for note in notes.prefix(25) {
            session.registerPress(key: note.key, at: note.time)
        }
        return session
    }

    @Test func meterFillsAndActivates() {
        let session = sessionWithFullMeter()
        #expect(session.starMeter >= 1)
        #expect(session.tryActivateStarPower(at: 13.5))
        #expect(session.starPowerActive)
        #expect(session.starMeter == 0)
    }

    @Test func cannotActivateOnEmptyMeter() {
        let session = GameSession(chart: Chart(notes: []))
        #expect(!session.tryActivateStarPower(at: 0))
    }

    @Test func starPowerDoublesScoreAndExpires() {
        let session = sessionWithFullMeter()
        let before = session.state.score
        session.tryActivateStarPower(at: 13.5)

        // Note 26 (index 25) at t=13.5, hit perfectly during star power:
        // combo 25 → ×3 multiplier, doubled by star power.
        session.registerPress(key: session.note(at: 25).key, at: session.note(at: 25).time)
        #expect(session.state.score == before + 100 * 3 * 2)

        // Expires after 8s.
        _ = session.advance(to: 13.5 + GameSession.starPowerDuration + 0.01)
        #expect(!session.starPowerActive)
    }

    @Test func finisherClearsWindowAsPerfects() {
        let session = sessionWithFullMeter()
        // Pending notes at 13.5, 14.0, 14.5 (indices 25–27) fall inside t+1.5.
        let cleared = session.tryFinisher(at: 13.4)
        #expect(cleared == [25, 26, 27])
        #expect(session.state.perfects == 28)
        #expect(session.starMeter == 0) // finisher hits must not refill the meter
        // Second finisher without meter fails.
        #expect(session.tryFinisher(at: 15.0) == nil)
    }
}
