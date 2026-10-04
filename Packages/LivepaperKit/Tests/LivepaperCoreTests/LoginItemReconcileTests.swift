import LivepaperCore
import Testing

/// What a launch does about the login item, for every status macOS can report,
/// every intent, and the same copy of Livepaper or another.
struct LoginItemReconcileTests {
    static let requirement = #"identifier "app.livepaper.Livepaper" and certificate leaf = H"67414494ac0200d42031aa6a382507f4197d3de7""#
    static let applications = BundleIdentity(path: "/Applications/Livepaper.app", designatedRequirement: requirement)
    /// The same build, moved to another folder.
    static let moved = BundleIdentity(path: "/Users/someone/Desktop/Livepaper.app", designatedRequirement: requirement)

    struct Launch: Sendable, CustomStringConvertible {
        let status: LoginItemStatus
        let intent: LoginItemIntent?
        let bundle: BundleIdentity

        var description: String { "\(status), \(intent.map { $0.openAtLogin ? "on" : "off" } ?? "none")" }
    }

    /// An intent kept with the copy in Applications, unless another copy asked.
    static func asked(_ openAtLogin: Bool, by bundle: BundleIdentity = applications) -> LoginItemIntent {
        LoginItemIntent(openAtLogin: openAtLogin, bundle: bundle)
    }

    static func row(
        _ name: String, _ status: LoginItemStatus, _ intent: LoginItemIntent?, _ bundle: BundleIdentity, _ expected: LoginItemReconciliation
    ) -> Row<Launch, LoginItemReconciliation> {
        Row(name, Launch(status: status, intent: intent, bundle: bundle), expected)
    }

    // Every intent here was kept with the copy in Applications.
    static let table: [Row<Launch, LoginItemReconciliation>] = [
        // Asked on.
        row("on, asked on, the same copy: they agree", .on, asked(true), applications, .nothing),
        row("on, asked on, another copy: the item followed it, which is kept", .on, asked(true), moved, .record(asked(true, by: moved))),
        row("waiting for approval, asked on, the same copy: the user's to allow", .needsApproval, asked(true), applications, .nothing),
        row(
            "waiting for approval, asked on, another copy: the new copy is kept",
            .needsApproval, asked(true), moved, .record(asked(true, by: moved))
        ),
        row("off, asked on, the same copy: turned off in System Settings, kept", .off, asked(true), applications, .record(asked(false))),
        row("off, asked on, another copy: registers again", .off, asked(true), moved, .register(asked(true, by: moved))),
        row("not found, asked on, the same copy: removed, respected", .notFound, asked(true), applications, .record(asked(false))),
        row("not found, asked on, another copy: registers again", .notFound, asked(true), moved, .register(asked(true, by: moved))),
        // Asked off.
        row("on, asked off, the same copy: macOS has it on, which is kept", .on, asked(false), applications, .record(asked(true))),
        row("on, asked off, another copy: macOS has it on, which is kept", .on, asked(false), moved, .record(asked(true, by: moved))),
        row(
            "waiting for approval, asked off, the same copy: registered, which is kept",
            .needsApproval, asked(false), applications, .record(asked(true))
        ),
        row(
            "waiting for approval, asked off, another copy: registered, which is kept",
            .needsApproval, asked(false), moved, .record(asked(true, by: moved))
        ),
        row("off, asked off, the same copy: they agree", .off, asked(false), applications, .nothing),
        row("off, asked off, another copy: they agree, whichever copy asked", .off, asked(false), moved, .nothing),
        row("not found, asked off, the same copy: they agree", .notFound, asked(false), applications, .nothing),
        row("not found, asked off, another copy: they agree, whichever copy asked", .notFound, asked(false), moved, .nothing),
        // Never asked: no intent, so no copy to compare with.
        row("on, never asked", .on, nil, applications, .nothing),
        row("on, never asked, another copy", .on, nil, moved, .nothing),
        row("waiting for approval, never asked", .needsApproval, nil, applications, .nothing),
        row("waiting for approval, never asked, another copy", .needsApproval, nil, moved, .nothing),
        row("off, never asked", .off, nil, applications, .nothing),
        row("off, never asked, another copy", .off, nil, moved, .nothing),
        row("not found, never asked", .notFound, nil, applications, .nothing),
        row("not found, never asked, another copy", .notFound, nil, moved, .nothing),
    ]

    @Test(arguments: table)
    func `reconciles the login item at launch`(row: Row<Launch, LoginItemReconciliation>) {
        let launch = row.input

        #expect(reconcileLoginItem(intent: launch.intent, status: launch.status, bundle: launch.bundle) == row.expected)
    }

    @Test func `the table covers every status, intent and copy`() {
        let covered = Set(Self.table.map { "\($0.input) \($0.input.bundle.path)" })

        #expect(covered.count == LoginItemStatus.allCases.count * 3 * 2)
        #expect(Self.table.count == covered.count)
    }

    // MARK: Identity

    static let otherCopies: [Row<BundleIdentity, Void>] = [
        Row("moved to another folder", moved, ()),
        Row("built again and signed ad hoc", BundleIdentity(path: applications.path, designatedRequirement: #"cdhash H"3684488e""#), ()),
        Row("not signed, in the same place", BundleIdentity(path: applications.path, designatedRequirement: nil), ()),
    ]

    @Test(arguments: otherCopies)
    func `another path or requirement is another copy, which registers again`(row: Row<BundleIdentity, Void>) {
        #expect(reconcileLoginItem(intent: Self.asked(true), status: .off, bundle: row.input) == .register(Self.asked(true, by: row.input)))
    }

    @Test func `an update signed with the same certificate, replaced in place, is the same copy`() {
        let update = BundleIdentity(path: Self.applications.path, designatedRequirement: Self.requirement)

        #expect(reconcileLoginItem(intent: Self.asked(true), status: .off, bundle: update) == .record(Self.asked(false)))
    }

    // MARK: Translocation

    static let translocated = BundleIdentity(
        path: "/private/var/folders/xy/abc123/T/AppTranslocation/0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0/d/Livepaper.app",
        designatedRequirement: requirement
    )

    @Test(arguments: LoginItemStatus.allCases)
    func `a translocated copy changes nothing, whatever it was asked`(status: LoginItemStatus) {
        for intent in [Self.asked(true), Self.asked(false), nil] {
            #expect(reconcileLoginItem(intent: intent, status: status, bundle: Self.translocated) == .nothing)
        }
    }

    static let paths: [Row<String, Bool>] = [
        Row("run from where Gatekeeper put it", translocated.path, true),
        Row("in Applications", "/Applications/Livepaper.app", false),
        Row("in Downloads, not yet opened by Gatekeeper", "/Users/someone/Downloads/Livepaper.app", false),
        Row("in a folder merely named like it", "/Users/someone/AppTranslocation.app/Livepaper.app", false),
    ]

    @Test(arguments: paths)
    func `tells a translocated copy by its path`(row: Row<String, Bool>) {
        #expect(BundleIdentity(path: row.input, designatedRequirement: nil).isTranslocated == row.expected)
    }

    // MARK: Status

    @Test func `on and waiting for approval are registered, off and not found are not`() {
        #expect(LoginItemStatus.allCases.filter(\.isRegistered) == [.on, .needsApproval])
    }
}
