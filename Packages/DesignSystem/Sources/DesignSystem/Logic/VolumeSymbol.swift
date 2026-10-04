/// The speaker a volume slider shows: the level in thirds, or the slashed
/// speaker while muted. One rule for the mute button and for the speaker that
/// only shows the level (`VolumeSliderSpeaker`).
public nonisolated enum VolumeSymbol {
    /// The SF Symbol's name for `volume` (0 to 1; outside it counts as the nearer end).
    public static func name(volume: Double, isMuted: Bool) -> String {
        if isMuted { return "speaker.slash.fill" }
        switch volume {
        case ...0: return "speaker.fill"
        case ..<(1.0 / 3): return "speaker.wave.1.fill"
        case ..<(2.0 / 3): return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}
