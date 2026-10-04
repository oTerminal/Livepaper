import Foundation
import Testing
import LivepaperCore

struct PlaybackPolicyTests {
    struct Situation: Sendable {
        var conditions = PlaybackConditions(sensedAt: Moment.launch, now: Moment.after(1))
        var rules = PauseRules()
        var host = HostCapabilities(showsLockScreen: true)

        static func when(
            rules: PauseRules = PauseRules(),
            host: HostCapabilities = HostCapabilities(showsLockScreen: true),
            _ change: (inout PlaybackConditions) -> Void = { _ in }
        ) -> Situation {
            var situation = Situation(rules: rules, host: host)
            change(&situation.conditions)
            return situation
        }
    }

    static let allRulesOff = PauseRules(
        whenDesktopCovered: false, whenDisplayAsleepOrLocked: false, inLowPowerMode: false, onBattery: false
    )
    static let allRulesOn = PauseRules(
        whenDesktopCovered: true, whenDisplayAsleepOrLocked: true, inLowPowerMode: true, onBattery: true
    )
    static let windowHost = HostCapabilities(showsLockScreen: false)

    static let rows: [Row<Situation, PlaybackDecision>] = [
        Row("nothing sensed plays", .when(), .play),

        // Every pause rule, on and off.
        Row("covered desktop pauses and keeps the decoder", .when { $0.desktopCovered = true }, .pause(.desktopCovered)),
        Row("covered desktop plays with its rule off", .when(rules: allRulesOff) { $0.desktopCovered = true }, .play),
        Row("sleeping display suspends", .when { $0.displayAsleep = true }, .suspend(.displayAsleep)),
        Row("sleeping display plays with its rule off", .when(rules: allRulesOff) { $0.displayAsleep = true }, .play),
        Row("Low Power Mode suspends", .when { $0.lowPowerMode = true }, .suspend(.lowPowerMode)),
        Row("Low Power Mode plays with its rule off", .when(rules: allRulesOff) { $0.lowPowerMode = true }, .play),
        Row("battery plays by default, the rule ships off", .when { $0.onBattery = true }, .play),
        Row("battery suspends with its rule on", .when(rules: allRulesOn) { $0.onBattery = true }, .suspend(.onBattery)),

        // The lock screen.
        Row("locked display plays when the host shows the lock screen", .when { $0.displayLocked = true }, .play),
        Row(
            "locked display suspends when the host cannot show the lock screen",
            .when(host: windowHost) { $0.displayLocked = true },
            .suspend(.displayLocked)
        ),
        Row(
            "locked display plays on a host without a lock screen when the rule is off",
            .when(rules: allRulesOff, host: windowHost) { $0.displayLocked = true },
            .play
        ),
        Row(
            "a covered desktop does not pause the lock screen",
            .when { $0.displayLocked = true; $0.desktopCovered = true },
            .play
        ),
        Row(
            "Low Power Mode still suspends the lock screen",
            .when { $0.displayLocked = true; $0.lowPowerMode = true },
            .suspend(.lowPowerMode)
        ),

        // User pause beats everything.
        Row("user pause pauses", .when { $0.userPaused = true }, .pause(.user)),
        Row("user pause holds with every rule off", .when(rules: allRulesOff) { $0.userPaused = true }, .pause(.user)),
        Row(
            "user pause beats a suspending condition",
            .when(rules: allRulesOn) { $0.userPaused = true; $0.displayAsleep = true; $0.lowPowerMode = true; $0.onBattery = true },
            .pause(.user)
        ),

        // Suspend (release the decoder) wins over pause (keep it).
        Row(
            "suspend wins over pause when both apply",
            .when { $0.desktopCovered = true; $0.lowPowerMode = true },
            .suspend(.lowPowerMode)
        ),

        // Conditions expire after 30 s: an app that died must not freeze the wallpaper.
        Row(
            "conditions 30 s old still count",
            .when { $0.desktopCovered = true; $0.now = Moment.after(30) },
            .pause(.desktopCovered)
        ),
        Row("conditions older than 30 s are ignored", .when { $0.desktopCovered = true; $0.now = Moment.after(30.5) }, .play),
        Row(
            "stale suspending conditions are ignored too",
            .when(rules: allRulesOn) { $0.displayAsleep = true; $0.onBattery = true; $0.now = Moment.after(300) },
            .play
        ),
        Row("user pause outlives stale conditions", .when { $0.userPaused = true; $0.now = Moment.after(300) }, .pause(.user)),
    ]

    @Test(arguments: rows)
    func `decides playback`(row: Row<Situation, PlaybackDecision>) {
        let decision = decidePlayback(row.input.conditions, rules: row.input.rules, host: row.input.host)

        #expect(decision == row.expected)
    }

    @Test func `pause rules ship with their defaults`() {
        let rules = PauseRules()

        #expect(rules.whenDesktopCovered)
        #expect(rules.whenDisplayAsleepOrLocked)
        #expect(rules.inLowPowerMode)
        #expect(!rules.onBattery)
    }
}
