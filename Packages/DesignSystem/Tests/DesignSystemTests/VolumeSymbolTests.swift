import Testing
import DesignSystem

struct VolumeSymbolTests {
    @Test(arguments: [
        (volume: 0.0, symbol: "speaker.fill"),
        (volume: -0.2, symbol: "speaker.fill"),
        (volume: 0.01, symbol: "speaker.wave.1.fill"),
        (volume: 0.33, symbol: "speaker.wave.1.fill"),
        (volume: 1.0 / 3, symbol: "speaker.wave.2.fill"),
        (volume: 0.6, symbol: "speaker.wave.2.fill"),
        (volume: 2.0 / 3, symbol: "speaker.wave.3.fill"),
        (volume: 1.0, symbol: "speaker.wave.3.fill"),
        (volume: 1.5, symbol: "speaker.wave.3.fill"),
    ])
    func `the speaker shows the level in thirds`(volume: Double, symbol: String) {
        #expect(VolumeSymbol.name(volume: volume, isMuted: false) == symbol)
    }

    @Test(arguments: [0.0, 0.6, 1.0])
    func `muted is the slashed speaker at any level`(volume: Double) {
        #expect(VolumeSymbol.name(volume: volume, isMuted: true) == "speaker.slash.fill")
    }
}
