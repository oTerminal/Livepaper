import CoreGraphics

/// Where a hotkey recorder's caption goes. The recorder is as wide as its field
/// and the clear button's slot in every phase, so a field at a form row's
/// trailing edge never moves when a conflict appears: a caption that fits starts
/// under the field, and a wider one hangs from the field's trailing edge, out
/// under the row's label.
public nonisolated enum HotkeyRecorderCaption {
    /// The caption's leading edge, from the recorder's.
    public static func offset(width caption: CGFloat, fieldWidth: CGFloat, recorderWidth: CGFloat) -> CGFloat {
        caption <= recorderWidth ? 0 : fieldWidth - caption
    }
}
