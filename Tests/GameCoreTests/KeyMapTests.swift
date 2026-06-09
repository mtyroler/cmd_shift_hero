import GameCore
import Testing

@Suite struct KeyMapTests {
    @Test func allTwentySixLettersMapped() {
        #expect(KeyMap.positionForKeyCode.count == 26)
        let letters = Set(KeyMap.positionForKeyCode.values.map(\.letter))
        #expect(letters == Set("QWERTYUIOPASDFGHJKLZXCVBNM"))
    }

    @Test func knownKeyCodes() {
        #expect(KeyMap.positionForKeyCode[0x00] == KeyPosition(row: .home, column: 0)) // A
        #expect(KeyMap.positionForKeyCode[0x0C] == KeyPosition(row: .top, column: 0))  // Q
        #expect(KeyMap.positionForKeyCode[0x06] == KeyPosition(row: .bottom, column: 0)) // Z
        #expect(KeyMap.positionForKeyCode[0x23] == KeyPosition(row: .top, column: 9))  // P
        #expect(KeyMap.positionForKeyCode[0x2E] == KeyPosition(row: .bottom, column: 6)) // M
    }

    @Test func rowGeometry() {
        #expect(KeyRow.top.keyCount == 10)
        #expect(KeyRow.home.keyCount == 9)
        #expect(KeyRow.bottom.keyCount == 7)
        #expect(KeyMap.allPositions.count == 26)
    }
}
