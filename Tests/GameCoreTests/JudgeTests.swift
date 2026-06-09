import GameCore
import Testing

@Suite struct JudgeTests {
    private func makeSession() -> GameSession {
        let key = KeyPosition(row: .home, column: 0)
        let other = KeyPosition(row: .home, column: 1)
        return GameSession(chart: Chart(notes: [
            Note(time: 1.0, key: key),
            Note(time: 2.0, key: other),
            Note(time: 3.0, key: key),
        ]))
    }

    @Test func perfectHit() {
        let session = makeSession()
        let result = session.registerPress(key: KeyPosition(row: .home, column: 0), at: 1.02)
        #expect(result?.0 == .perfect)
        #expect(session.state.score == 100)
        #expect(session.state.combo == 1)
    }

    @Test func goodHit() {
        let session = makeSession()
        let result = session.registerPress(key: KeyPosition(row: .home, column: 0), at: 1.08)
        #expect(result?.0 == .good)
        #expect(session.state.score == 50)
    }

    @Test func pressOutsideWindowIsStray() {
        let session = makeSession()
        let result = session.registerPress(key: KeyPosition(row: .home, column: 0), at: 1.5)
        #expect(result == nil)
        #expect(session.state.score == 0)
    }

    @Test func wrongKeyIsStray() {
        let session = makeSession()
        let result = session.registerPress(key: KeyPosition(row: .top, column: 0), at: 1.0)
        #expect(result == nil)
    }

    @Test func noteCannotBeHitTwice() {
        let session = makeSession()
        let key = KeyPosition(row: .home, column: 0)
        #expect(session.registerPress(key: key, at: 1.0) != nil)
        #expect(session.registerPress(key: key, at: 1.05) == nil)
    }

    @Test func advanceMarksMisses() {
        let session = makeSession()
        let missed = session.advance(to: 2.5)
        #expect(missed == [0, 1])
        #expect(session.state.misses == 2)
        #expect(session.state.combo == 0)
    }

    @Test func comboAndMultiplierProgression() {
        let key = KeyPosition(row: .home, column: 0)
        let alt = KeyPosition(row: .home, column: 1)
        // 12 alternating notes, 0.5s apart, all hit perfectly.
        let notes = (0..<12).map { Note(time: Double($0) * 0.5 + 1, key: $0 % 2 == 0 ? key : alt) }
        let session = GameSession(chart: Chart(notes: notes))
        for (i, note) in notes.enumerated() {
            let result = session.registerPress(key: note.key, at: note.time)
            #expect(result?.0 == .perfect)
            #expect(session.state.combo == i + 1)
        }
        // First 10 hits at ×1, the rest at ×2.
        #expect(session.state.multiplier == 2)
        #expect(session.state.score == 10 * 100 + 2 * 200)
        #expect(session.state.bestCombo == 12)
    }

    @Test func nearestNoteWinsWhenTwoInWindow() {
        let key = KeyPosition(row: .home, column: 0)
        let session = GameSession(chart: Chart(notes: [
            Note(time: 1.00, key: key),
            Note(time: 1.15, key: key),
        ]))
        let result = session.registerPress(key: key, at: 1.13)
        #expect(result?.1 == 1) // the 1.15 note, not the 1.00 note
    }
}
