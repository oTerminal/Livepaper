import LivepaperCore
import Testing

/// Which cards a launch shows, from what earlier launches recorded; what is
/// recorded when they end; and what the "Open at login" card says for each
/// answer macOS gives.
struct OnboardingTests {
    struct Launch: Sendable, CustomStringConvertible {
        var record = OnboardingRecord()
        /// A library or an app state is on disk: a Livepaper ran here before.
        var ranBefore = false

        var description: String {
            "\(record.onboardedVersion ?? "none"), left \(record.hasLeft), ran before \(ranBefore)"
        }
    }

    static let everyStep: [OnboardingStep] = [.importWallpaper, .openAtLogin, .selectLivepaper]
    static let thisVersion = "1.2.0 (40)"
    static let earlierVersion = "1.1.0 (31)"

    static func onboarded(by version: String, left: Bool = false) -> OnboardingRecord {
        OnboardingRecord(onboardedVersion: version, hasLeft: left)
    }

    static let plans: [Row<Launch, OnboardingPlan>] = [
        Row("fresh: nothing recorded and nothing on disk, so the three steps", Launch(), .steps(everyStep)),
        Row("onboarded by this version: nothing", Launch(record: onboarded(by: thisVersion), ranBefore: true), .nothing),
        Row(
            "after an update, onboarded by an earlier version: nothing",
            Launch(record: onboarded(by: earlierVersion), ranBefore: true), .nothing
        ),
        Row(
            "onboarded, and the library since removed: still nothing, since it is recorded",
            Launch(record: onboarded(by: earlierVersion)), .nothing
        ),
        Row(
            "an update from a Livepaper before onboarding: a library and no record, so nothing",
            Launch(ranBefore: true), .nothing
        ),
        Row(
            "after leaving: making Livepaper the wallpaper again, alone",
            Launch(record: onboarded(by: earlierVersion, left: true), ranBefore: true), .steps([.selectLivepaper])
        ),
        Row(
            "after leaving a Livepaper from before onboarding: that card alone too",
            Launch(record: OnboardingRecord(onboardedVersion: nil, hasLeft: true), ranBefore: true), .steps([.selectLivepaper])
        ),
    ]

    @Test(arguments: plans)
    func `decides what a launch shows`(row: Row<Launch, OnboardingPlan>) {
        let launch = row.input

        #expect(onboardingPlan(record: launch.record, ranBefore: launch.ranBefore) == row.expected)
    }

    // MARK: What is recorded

    static let records: [Row<(OnboardingPlan, OnboardingRecord), OnboardingRecord?>] = [
        Row(
            "the three steps ended: kept with the version that ran them",
            (.steps(everyStep), OnboardingRecord()), onboarded(by: thisVersion)
        ),
        Row(
            "the card after leaving ended: leaving is forgotten, and the version that first ran onboarding stays",
            (.steps([.selectLivepaper]), onboarded(by: earlierVersion, left: true)), onboarded(by: earlierVersion)
        ),
        Row(
            "the card after leaving a Livepaper from before onboarding ended: this version is kept",
            (.steps([.selectLivepaper]), OnboardingRecord(onboardedVersion: nil, hasLeft: true)), onboarded(by: thisVersion)
        ),
        Row("nothing shown: nothing is written", (.nothing, onboarded(by: earlierVersion)), nil),
    ]

    @Test(arguments: records)
    func `records the cards once they end`(row: Row<(OnboardingPlan, OnboardingRecord), OnboardingRecord?>) {
        let (plan, record) = row.input

        #expect(plan.record(afterEnding: record, version: Self.thisVersion) == row.expected)
    }

    @Test func `leaving is recorded, and the next launch offers that card alone`() {
        let left = Self.onboarded(by: Self.earlierVersion).leaving()

        #expect(left == Self.onboarded(by: Self.earlierVersion, left: true))
        #expect(onboardingPlan(record: left, ranBefore: true) == .steps([.selectLivepaper]))
    }

    @Test func `fresh onboarding, ended, is not shown again`() {
        let plan = onboardingPlan(record: OnboardingRecord(), ranBefore: false)
        let ended = plan.record(afterEnding: OnboardingRecord(), version: Self.thisVersion)

        #expect(ended.map { onboardingPlan(record: $0, ranBefore: true) } == .nothing)
    }

    // MARK: The "Open at login" card

    struct Answer: Sendable, CustomStringConvertible {
        let asked: Bool
        let status: LoginItemStatus

        var description: String { "\(asked ? "asked" : "not asked"), \(status)" }
    }

    static let loginPhases: [Row<Answer, OnboardingLoginPhase>] = [
        Row("not asked, off: asks", Answer(asked: false, status: .off), .asking),
        Row("not asked, on already: says so", Answer(asked: false, status: .on), .alreadyOn),
        Row("not asked, waiting for approval: offers Login Items", Answer(asked: false, status: .needsApproval), .needsApproval),
        Row("not asked, not found: says why, since asking cannot work", Answer(asked: false, status: .notFound), .notFound),
        Row("asked, and macOS has it off still: it did not register", Answer(asked: true, status: .off), .notRegistered),
        Row("asked, and on: the card moves on", Answer(asked: true, status: .on), .turnedOn),
        Row("asked, and waiting for approval: offers Login Items", Answer(asked: true, status: .needsApproval), .needsApproval),
        Row("asked, and not found: says why", Answer(asked: true, status: .notFound), .notFound),
    ]

    @Test(arguments: loginPhases)
    func `the login card follows macOS's answer`(row: Row<Answer, OnboardingLoginPhase>) {
        #expect(onboardingLoginPhase(asked: row.input.asked, status: row.input.status) == row.expected)
    }

    @Test func `the login card's table covers every status, asked or not`() {
        let covered = Set(Self.loginPhases.map(\.input.description))

        #expect(covered.count == LoginItemStatus.allCases.count * 2)
    }

    @Test func `only turning it on here moves the card on by itself`() {
        let movesOn = Self.loginPhases.filter(\.expected.movesOn).map(\.expected)

        #expect(movesOn == [.turnedOn])
    }
}
