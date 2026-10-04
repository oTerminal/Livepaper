import SwiftUI

/// Motion tokens. Every animation in the app is built from these; raw durations,
/// curves and springs outside this package are a lint error.
///
/// UI motion stays under 300 ms, enters and exits ease out, nothing eases in,
/// and exits are quicker than enters.
public nonisolated enum Motion {
    /// How long an element takes to enter, in seconds.
    public enum Duration {
        public static let hover: TimeInterval = 0.12
        public static let press: TimeInterval = 0.14
        public static let tooltip: TimeInterval = 0.15
        public static let popover: TimeInterval = 0.18
        public static let menu: TimeInterval = 0.20
        public static let panel: TimeInterval = 0.25
        /// Sheets and onboarding cards travel further, so they alone may exceed 300 ms.
        public static let sheet: TimeInterval = 0.35
        /// With Reduce Motion, movement becomes a crossfade of this length.
        public static let reducedCrossfade: TimeInterval = 0.2

        /// Exits run faster than enters: the user has already decided.
        public static func exit(for enter: TimeInterval) -> TimeInterval {
            enter * 0.7
        }
    }

    public enum Curve {
        /// Enters and exits.
        public static let easeOut = UnitCurve.bezier(
            startControlPoint: UnitPoint(x: 0.23, y: 1),
            endControlPoint: UnitPoint(x: 0.32, y: 1)
        )
        /// Movement of something already on screen.
        public static let easeInOut = UnitCurve.bezier(
            startControlPoint: UnitPoint(x: 0.77, y: 0),
            endControlPoint: UnitPoint(x: 0.175, y: 1)
        )
        /// Sheets and drawers.
        public static let drawer = UnitCurve.bezier(
            startControlPoint: UnitPoint(x: 0.32, y: 0.72),
            endControlPoint: UnitPoint(x: 0, y: 1)
        )
    }

    public enum Spring {
        /// State changes in controls.
        public static let ui = Animation.spring(duration: 0.3, bounce: 0)
        /// Elements changing position.
        public static let move = Animation.spring(duration: 0.4, bounce: 0)
        /// Only after a gesture that carried velocity.
        public static let momentum = Animation.spring(duration: 0.4, bounce: 0.2)

        /// `momentum`, starting at the speed the gesture was released at, so a
        /// thrown element carries on rather than stopping dead and setting off
        /// again. `initialVelocity` is in distances-to-the-target per second.
        public static func momentum(initialVelocity: Double) -> Animation {
            .interpolatingSpring(duration: 0.4, bounce: 0.2, initialVelocity: initialVelocity)
        }
    }

    /// The scale an element enters from and leaves to, combined with opacity and
    /// anchored at its trigger. Nothing appears from nothing.
    public static let enterScale: CGFloat = 0.96

    /// An ease-out animation for an entering element.
    public static func enter(_ duration: TimeInterval) -> Animation {
        .timingCurve(Curve.easeOut, duration: duration)
    }

    /// An ease-out animation for a leaving element, quicker than its enter.
    public static func exit(_ enterDuration: TimeInterval) -> Animation {
        .timingCurve(Curve.easeOut, duration: Duration.exit(for: enterDuration))
    }

    /// What movement becomes with Reduce Motion: gentler, not absent.
    public static let reducedCrossfade = Animation.timingCurve(Curve.easeOut, duration: Duration.reducedCrossfade)

    /// `animation`, or the crossfade when Reduce Motion is on. Pair it with a
    /// transition or effect that drops its movement too.
    public static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedCrossfade : animation
    }
}
