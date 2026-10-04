import DesignSystem
import SwiftUI

struct PauseRuleTogglePage: View {
    @State private var onBattery = true
    @State private var lowPower = true
    @State private var covered = true
    @State private var asleep = false
    @State private var hot = true

    var body: some View {
        StateSection(
            title: "Rules",
            note: "One off, one unavailable, one with a long detail. Titles line up whatever the width of the symbol. Click the words."
        ) {
            Form {
                PauseRuleToggle(
                    title: "On battery",
                    detail: "Pause when the Mac is not plugged in.",
                    systemImage: "battery.50percent",
                    isOn: $onBattery,
                    note: "Not available on this Mac",
                    isAvailable: false
                )
                PauseRuleToggle(
                    title: "Low Power Mode",
                    detail: "Pause while Low Power Mode is on.",
                    systemImage: "bolt.circle",
                    isOn: $lowPower
                )
                PauseRuleToggle(
                    title: "Desktop covered",
                    detail: """
                    Pause when windows cover the whole desktop on a display, such as a full-screen app or a maximised \
                    window, and carry on as soon as any part of the desktop shows again.
                    """,
                    systemImage: "macwindow.on.rectangle",
                    isOn: $covered
                )
                PauseRuleToggle(
                    title: "Display asleep",
                    detail: "Pause when the display sleeps or the screen is locked.",
                    systemImage: "moon",
                    isOn: $asleep
                )
                PauseRuleToggle(
                    title: "Hot Mac",
                    detail: "Pause when the Mac is under thermal pressure.",
                    systemImage: "thermometer.high",
                    isOn: $hot
                )
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(maxWidth: 520)
        }

        StateSection(title: "Title only") {
            Form {
                PauseRuleToggle(title: "On battery", systemImage: "battery.50percent", isOn: $onBattery)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(maxWidth: 520)
        }
    }
}
