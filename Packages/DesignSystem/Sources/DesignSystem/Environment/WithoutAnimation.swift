import AppKit
import SwiftUI

/// Runs a change that came from a key press or a global hotkey. Such changes
/// never animate, including through a component's own `.animation(_:value:)`.
public func withoutAnimation<Result>(_ body: () throws -> Result) rethrows -> Result {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    return try withTransaction(transaction, body)
}

/// Runs an action that both a click and a key press can trigger, such as a
/// default button that Return also presses. The click may animate; the key
/// press may not.
public func withoutAnimationIfKeyPress(_ body: () -> Void) {
    if NSApp.currentEvent?.type == .keyDown {
        withoutAnimation(body)
    } else {
        body()
    }
}
