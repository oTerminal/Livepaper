import CoreGraphics
import DesignSystem
import LivepaperCore
import LivepaperImport
import SwiftUI

// Core and Import cannot import the design system, and no component knows a
// domain type, so each pair is mapped here, case for case, and nowhere else.

extension StatusLineContent {
    var statusLineStatus: StatusLineStatus {
        switch self {
        case .idle(let words): .idle(words)
        case .working(let words): .working(words)
        case .serviceNotResponding: .serviceNotResponding
        }
    }
}

extension LoginItemStatus {
    var loginItemState: LoginItemState {
        switch self {
        case .off: .off
        case .on: .on
        case .needsApproval: .needsApproval
        case .notFound: .notFound
        }
    }
}

extension KeyCombination {
    /// The modifiers have the same bits on both sides.
    init(_ hotkey: Hotkey) {
        self.init(keyCode: hotkey.keyCode, modifiers: Modifiers(rawValue: hotkey.modifiers.rawValue), keyLabel: hotkey.keyLabel)
    }

    var hotkey: Hotkey {
        Hotkey(keyCode: keyCode, modifiers: Hotkey.Modifiers(rawValue: modifiers.rawValue), keyLabel: keyLabel)
    }
}

extension SetOnDisplayFeedback.Phase {
    var setOnDisplayState: SetOnDisplayState {
        switch self {
        case .idle: .idle
        case .working: .working
        case .done: .done
        }
    }
}

extension ImportList.RowState {
    /// A duplicate finished too: nothing was imported, and its toast says what it already is.
    var importProgressState: ImportProgressState {
        switch self {
        case .waiting: .queued
        case .running(_, let words, let fraction): .running(fraction: fraction, detail: words)
        case .finished, .duplicate: .finished
        case .failed(let reason, _, _): .failed(message: reason)
        }
    }
}

extension ImportToast {
    /// A plain toast, its symbol from its kind.
    var toastItem: ToastItem {
        switch kind {
        case .alreadyThere: ToastItem(message: words, systemImage: "square.on.square")
        case .notImported: ToastItem(message: words, systemImage: "exclamationmark.triangle")
        }
    }
}

extension Point {
    /// The focal point editor's value: both are 0 to 1, top left to bottom right.
    init(_ point: UnitPoint) {
        self.init(x: point.x, y: point.y)
    }

    var unitPoint: UnitPoint { UnitPoint(x: x, y: y) }
}

extension Presentation {
    /// The pan and zoom editor's pan: a fraction of the frame on each axis, as stored.
    var panSize: CGSize {
        get { CGSize(width: pan.x, height: pan.y) }
        set { pan = Point(x: newValue.width, y: newValue.height) }
    }
}
