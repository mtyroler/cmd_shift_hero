import GameCore
import Testing

@Suite struct EnergyEnvelopeTests {
    @Test func interpolatesAndNormalizes() {
        let envelope = EnergyEnvelope()
        #expect(envelope.level(at: 1) == 0, "empty envelope is silent")

        envelope.append(time: 0, value: 0)
        envelope.append(time: 1, value: 10)
        envelope.append(time: 2, value: 5)

        #expect(envelope.level(at: -1) == 0, "before first sample is silent")
        #expect(envelope.level(at: 1) == 1, "peak normalizes to 1")
        #expect(abs(envelope.level(at: 0.5) - 0.5) < 0.001)
        #expect(abs(envelope.level(at: 1.5) - 0.75) < 0.001)
        #expect(envelope.level(at: 5) == 0.5, "holds last value past the end")
    }

    @Test func dropsOutOfOrderSamples() {
        let envelope = EnergyEnvelope()
        envelope.append(time: 1, value: 4)
        envelope.append(time: 0.5, value: 100) // must be ignored
        #expect(envelope.level(at: 1) == 1)
        #expect(envelope.level(at: 0.75) == 0)
    }
}
