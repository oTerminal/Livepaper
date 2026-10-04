import Darwin
import Foundation
import LivepaperCore

/// The Mac a report is made on: macOS's version and build, and the hardware model.
nonisolated public struct MachineFacts: Equatable, Sendable {
    /// `27.0 (26A428)`.
    public var macOS: String
    /// `hw.model`: `Mac17,2`.
    public var model: String

    public init(macOS: String, model: String) {
        self.macOS = macOS
        self.model = model
    }

    public static func current() -> MachineFacts {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let number = [version.majorVersion, version.minorVersion] + (version.patchVersion > 0 ? [version.patchVersion] : [])
        let build = sysctlText("kern.osversion").map { " (\($0))" } ?? ""
        return MachineFacts(macOS: number.map(String.init).joined(separator: ".") + build, model: sysctlText("hw.model") ?? "unknown")
    }

    private static func sysctlText(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8)
    }
}

/// What "Copy diagnostics", "Save…" and `livepaper diagnostics` give: the
/// app's and the extension's versions, the Mac, the wallpaper service, each
/// display and its assignment, the pauses and mute, the login item, the
/// wallpaper store's shape and the extension's last ten minutes of log, as
/// text in sections.
///
/// It is made from plain values the app passes in, and says nothing the user
/// would not hand over: wallpapers, playlists and displays go by ID, and the
/// store by counts. The one text it did not write, what the extension logged,
/// goes through `redaction` as it is made, so no path, user name, Steam
/// account, wallpaper name or file name reaches it. Nothing is sent anywhere.
nonisolated public struct DiagnosticsReport: Equatable, Sendable {
    public struct Section: Equatable, Sendable {
        public var title: String
        public var lines: [String]
    }

    public let madeAt: Date
    public let sections: [Section]

    /// - Parameters:
    ///   - isTranslocated: whether the app runs from a path holding `/AppTranslocation/`.
    ///   - connected: the displays connected now.
    ///   - loginItemIntent: whether the user asked for the login item, nil when they never did.
    ///   - redaction: made from the home folder, the user's and the Steam account's names, the library and the sources imported.
    public init(
        madeAt: Date,
        app: BundleVersion,
        wallpaperExtension: BundleVersion?,
        machine: MachineFacts,
        isTranslocated: Bool,
        host: RenderHostStatus,
        state: AppState,
        connected: [DisplayIdentity],
        isPausedAll: Bool,
        loginItem: LoginItemStatus,
        loginItemIntent: Bool?,
        store: WallpaperStoreShape,
        extensionLog: ExtensionLogLines,
        redaction: Redaction
    ) {
        self.madeAt = madeAt
        let selfCheck = extensionLog.selfCheck.map { "\(redaction.redact($0.message)), at \($0.timestamp)" }
            ?? (extensionLog.problem == nil ? "none logged since the Mac started" : "not read")
        sections = [
            Section(title: "App", lines: [
                "Livepaper \(app.words)",
                "Wallpaper extension \(wallpaperExtension?.words ?? "not found in the app")",
                "Translocated: \(Self.yesNo(isTranslocated))",
            ]),
            Section(title: "Mac", lines: ["macOS \(machine.macOS)", "Hardware \(machine.model)"]),
            Section(title: "Wallpaper service", lines: ["Status: \(host.name)", "Self-check: \(selfCheck)"]),
            Section(title: "Displays", lines: Self.displays(state: state, connected: connected)),
            Section(title: "Pauses and mute", lines: Self.pauses(state: state, isPausedAll: isPausedAll)),
            Section(title: "Login item", lines: [
                "Status: \(Self.words(for: loginItem))",
                "Intent: \(loginItemIntent.map(Self.onOff) ?? "none recorded")",
            ]),
            Section(title: "Wallpaper store", lines: Self.store(store)),
            Section(title: "Extension log, last \(ExtensionLogLines.minutes) minutes", lines: Self.log(extensionLog, redaction: redaction)),
        ]
    }

    /// The report as text: a heading, then each section's title and its lines, indented.
    public var text: String {
        let heading = "Livepaper diagnostics, made \(madeAt.formatted(.iso8601))"
        let body = sections.map { section in
            ([section.title] + section.lines.map { "  " + $0 }).joined(separator: "\n")
        }
        return ([heading] + body).joined(separator: "\n\n") + "\n"
    }

    /// What "Save…" names a report made then: plain text, dated in `timeZone`,
    /// with the seconds, so that two saved a minute apart keep apart.
    public static func fileName(madeAt date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func two(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
        let day = "\(parts.year ?? 0)-\(two(parts.month))-\(two(parts.day))"
        return "Livepaper Diagnostics \(day) at \(two(parts.hour)).\(two(parts.minute)).\(two(parts.second)).txt"
    }

    // MARK: Sections

    /// Every display the app knows of, connected or with anything kept for it, in the order of their UUIDs.
    private static func displays(state: AppState, connected: [DisplayIdentity]) -> [String] {
        let known = Set(connected).union(state.assignments.keys).union(state.pausedDisplays).union(state.rotation.keys)
        let rows = known.sorted { $0.description < $1.description }.map { display in
            let fromAll = state.applyToAll.flatMap(words(for:)).map { "\($0) from All Displays" }
            var words = [words(for: state.assignments[display]) ?? fromAll ?? "nothing"]
            if state.pausedDisplays.contains(display) { words.append("paused") }
            if case .playlist? = state.assignment(for: display) {
                let rotation = state.rotation[display]
                words.append("showing \(rotation?.current?.description ?? "none")")
                words.append("last rotation \(rotation?.lastRotation?.formatted(.iso8601) ?? "never")")
            }
            let name = display.description + (connected.contains(display) ? "" : ", not connected")
            return "\(name): \(words.joined(separator: ", "))"
        }
        return rows + ["All Displays: \(state.applyToAll.flatMap(words(for:)) ?? "nothing")"]
    }

    private static func pauses(state: AppState, isPausedAll: Bool) -> [String] {
        let rules = state.pauseRules
        let paused = state.pausedDisplays.map(\.description).sorted()
        return [
            "Pause rules: desktop covered \(onOff(rules.whenDesktopCovered)), "
                + "display asleep or locked \(onOff(rules.whenDisplayAsleepOrLocked)), "
                + "Low Power Mode \(onOff(rules.inLowPowerMode)), on battery \(onOff(rules.onBattery))",
            "Paused displays: \(paused.isEmpty ? "none" : paused.joined(separator: ", "))",
            "Pause All: \(onOff(isPausedAll))",
            "Mute: \(onOff(state.isMuted))",
        ]
    }

    private static func store(_ shape: WallpaperStoreShape) -> [String] {
        let kept = "Kept copy: \(yesNo(shape.keptCopyExists))"
        switch shape.store {
        case .read(let entries, let naming): return ["Desktop entries: \(entries)", "Naming Livepaper: \(naming)", kept]
        case .unreadable: return ["Desktop entries: not read, the store is missing or unreadable", kept]
        case .unknownShape: return ["Desktop entries: not read, the store is of a shape this build does not know", kept]
        }
    }

    private static func log(_ log: ExtensionLogLines, redaction: Redaction) -> [String] {
        if let problem = log.problem { return ["Not read: \(redaction.redact(problem))"] }
        guard !log.lines.isEmpty else { return ["No lines"] }
        return log.lines.map { redaction.redact($0.text) }
    }

    // MARK: Words

    private static func words(for assignment: Assignment?) -> String? {
        switch assignment {
        case .wallpaper(let id)?: "wallpaper \(id)"
        case .playlist(let id)?: "playlist \(id)"
        case nil: nil
        }
    }

    private static func words(for status: LoginItemStatus) -> String {
        switch status {
        case .off: "off"
        case .on: "on"
        case .needsApproval: "needs approval"
        case .notFound: "not found"
        }
    }

    private static func onOff(_ isOn: Bool) -> String {
        isOn ? "on" : "off"
    }

    private static func yesNo(_ isSo: Bool) -> String {
        isSo ? "yes" : "no"
    }
}
