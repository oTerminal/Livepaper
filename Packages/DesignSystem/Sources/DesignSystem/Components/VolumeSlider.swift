import SwiftUI

/// What the speaker before a `VolumeSlider` is.
public nonisolated enum VolumeSliderSpeaker: Sendable {
    /// The mute button, as in the inspector: a click mutes and unmutes.
    case muteButton
    /// The level alone, where the one mute is elsewhere, such as a display's card
    /// in the popover, whose footer holds Mute. The slash still shows while muted.
    case indicator
}

/// A speaker, a slider and a percent readout. Muting dims the slider but
/// leaves it usable, and moving it unmutes: the user who drags a muted slider
/// wants sound. The symbol and the readout sit in fixed slots so nothing shifts
/// as the level changes.
public struct VolumeSlider: View {
    @Environment(\.isEnabled) private var isEnabled
    @Accessibility private var accessibility

    @Binding private var volume: Double
    @Binding private var isMuted: Bool
    private let speaker: VolumeSliderSpeaker

    /// - Parameter speaker: The mute button, or, where mute lives elsewhere, the level alone.
    public init(volume: Binding<Double>, isMuted: Binding<Bool>, speaker: VolumeSliderSpeaker = .muteButton) {
        _volume = volume
        _isMuted = isMuted
        self.speaker = speaker
    }

    public var body: some View {
        HStack(spacing: Spacing.tight) {
            switch speaker {
            case .muteButton: muteButton
            case .indicator: indicator
            }
            Slider(value: level, in: 0...1) {
                Text("Volume", bundle: .module)
            }
            .labelsHidden()
            .opacity(isMuted ? Metrics.mutedOpacity : 1)
            // The mute button's withAnimation is for the symbol; the dimming snaps.
            .animation(nil, value: isMuted)
            // The dimming is visual only, so say it.
            .accessibilityValue(isMuted ? Text("Muted, \(percent)", bundle: .module) : Text(percent))
            readout
        }
        // At least the mute button's 40 pt in both, so the row is one height
        // beside a button or a bare symbol.
        .frame(minHeight: Spacing.minimumHitArea)
    }

    private var muteButton: some View {
        Button {
            // Only the click animates the symbol. Waves changing under a dragged
            // slider, and a mute from the keyboard, swap at once.
            withoutAnimationIfKeyPress {
                withAnimation(accessibility.animation(Motion.Spring.ui)) { isMuted.toggle() }
            }
        } label: {
            symbol
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                .frame(minWidth: Spacing.minimumHitArea, minHeight: Spacing.minimumHitArea)
                .contentShape(.rect)
        }
        .buttonStyle(.press)
        .accessibilityLabel(isMuted ? Text("Unmute", bundle: .module) : Text("Mute", bundle: .module))
    }

    /// Not a control: `secondary`, as the readout is, so it does not ask to be
    /// clicked. Mute comes from elsewhere without animation, so the symbol swaps
    /// at once; the slider's value already says "Muted, 60%" to VoiceOver.
    private var indicator: some View {
        symbol
            .foregroundStyle(isEnabled ? .secondary : .tertiary)
            .accessibilityHidden(true)
    }

    private var symbol: some View {
        Image(systemName: VolumeSymbol.name(volume: volume, isMuted: isMuted))
            .contentTransition(accessibility.symbolReplace)
            // Leading, so the speaker stays put while the waves come and go.
            .frame(width: Metrics.symbolSlot, alignment: .leading)
    }

    /// As wide as its widest value, so the slider never changes length.
    private var readout: some View {
        Text(1.0, format: Self.percentFormat)
            .hidden()
            .overlay(alignment: .trailing) {
                Text(percent)
            }
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(isEnabled && !isMuted ? .secondary : .tertiary)
            .animation(nil, value: isMuted)
            // The slider already carries the value.
            .accessibilityHidden(true)
    }

    private var level: Binding<Double> {
        Binding {
            min(max(volume, 0), 1)
        } set: { newValue in
            volume = newValue
            if isMuted {
                isMuted = false
            }
        }
    }

    private var percent: String {
        min(max(volume, 0), 1).formatted(Self.percentFormat)
    }

    private static var percentFormat: FloatingPointFormatStyle<Double>.Percent {
        .percent.precision(.fractionLength(0))
    }
}

private nonisolated enum Metrics {
    /// Fits `speaker.wave.3.fill`, the widest of the five symbols, at body size.
    static let symbolSlot: CGFloat = 24
    static let mutedOpacity = 0.45
}
