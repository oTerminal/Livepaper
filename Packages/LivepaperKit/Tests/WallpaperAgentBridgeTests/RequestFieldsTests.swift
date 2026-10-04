import Foundation
import LivepaperCore
import Testing
@testable import WallpaperAgentBridge

struct RequestFieldsTests {
    static let surface = UUID(uuidString: "2CAB47E4-8A91-4A15-93E3-6D0927A9068A")!

    static let identifierRows: [Row<Payload, UUID?>] = [
        Row("an agent's identifier gives its surface UUID", Payload { FakeIDXPC(surface) }, surface),
        Row("an identifier without a UUID gives none", Payload { FakeNamedIDXPC("desktop") }, nil),
        Row("no identifier gives none", .none, nil),
    ]

    @Test(arguments: identifierRows)
    func `reads the surface UUID from the agent's identifier`(row: Row<Payload, UUID?>) {
        #expect(AgentPayload.surface(in: row.input.make()) == row.expected)
    }

    static let builtIn = FakeDestination(width: 1800, height: 1169, scale: 2, display: 1)
    static let external = FakeDestination(width: 1920, height: 1080, scale: 1, display: 3)
    static let builtInDestination = SurfaceDestination(display: 1, size: Size(width: 1800, height: 1169), scale: 2)

    static func acquire(
        _ destination: SurfaceDestination = builtInDestination,
        isPreview: Bool = false,
        mode: AgentSurfaceMode? = .desktop,
        activity: ActivityState? = .active
    ) -> AcquireRequest {
        AcquireRequest(surface: surface, destination: destination, isPreview: isPreview, mode: mode, activityState: activity)
    }

    static let acquireRows: [Row<Payload, AcquireRequest>] = [
        Row(
            "the desktop surface of the built-in display",
            Payload { FakeCreationRequestXPC(FakeCreationRequest(destination: builtIn, isPreview: false)) },
            acquire()
        ),
        Row(
            "the Settings preview is flagged",
            Payload { FakeCreationRequestXPC(FakeCreationRequest(destination: builtIn, isPreview: true)) },
            acquire(isPreview: true)
        ),
        Row(
            "an acquire on the lock screen carries the locked mode",
            Payload { FakeCreationRequestXPC(FakeCreationRequest(destination: builtIn, isPreview: false, presentationMode: .locked)) },
            acquire(mode: .locked)
        ),
        Row(
            "an external display at 1x",
            Payload { FakeCreationRequestXPC(FakeCreationRequest(destination: external, isPreview: false)) },
            acquire(SurfaceDestination(display: 3, size: Size(width: 1920, height: 1080), scale: 1))
        ),
        Row(
            "a destination that names no display",
            Payload {
                let destination = FakeDestination(width: 1800, height: 1169, scale: 2, display: nil)
                return FakeCreationRequestXPC(FakeCreationRequest(destination: destination, isPreview: false))
            },
            acquire(SurfaceDestination(display: nil, size: Size(width: 1800, height: 1169), scale: 2))
        ),
        Row(
            "a mode the bridge has not seen is kept by name",
            Payload { FakeCreationRequestXPC(FakeCreationRequest(destination: builtIn, isPreview: false, presentationMode: .ambient)) },
            acquire(mode: .other("ambient"))
        ),
        Row(
            "a mode with a payload is kept by its case name",
            Payload {
                FakeCreationRequestXPC(FakeCreationRequest(destination: builtIn, isPreview: false, presentationMode: .dimmed(level: 0.5)))
            },
            acquire(mode: .other("dimmed"))
        ),
        Row(
            "a suspended surface",
            Payload { FakeCreationRequestXPC(FakeCreationRequest(destination: builtIn, isPreview: false, activityState: .suspended)) },
            acquire(activity: .suspended)
        ),
        Row(
            "an activity state the bridge has not seen is kept by name",
            Payload { FakeCreationRequestXPC(FakeCreationRequest(destination: builtIn, isPreview: false, activityState: .dozing)) },
            acquire(activity: .other("dozing"))
        ),
        Row(
            "a destination with a size and a scale and nothing else",
            Payload { FakeSparseRequestXPC(width: 1512, height: 982, scale: 2) },
            acquire(SurfaceDestination(display: nil, size: Size(width: 1512, height: 982), scale: 2), mode: nil, activity: nil)
        ),
        Row(
            "a request with none of the fields leaves them all out, and is not the preview",
            Payload { FakeBareRequestXPC() },
            acquire(SurfaceDestination(display: nil, size: nil, scale: nil), mode: nil, activity: nil)
        ),
        Row("no request at all", .none, acquire(SurfaceDestination(display: nil, size: nil, scale: nil), mode: nil, activity: nil)),
    ]

    @Test(arguments: acquireRows)
    func `reads an acquire request`(row: Row<Payload, AcquireRequest>) {
        #expect(AgentPayload.acquire(row.input.make(), surface: Self.surface) == row.expected)
    }

    static let updateRows: [Row<Payload, UpdateRequest>] = [
        Row(
            "locking puts the surface in the locked mode",
            Payload { FakeUpdateRequestXPC(FakeUpdateRequest(presentationMode: .locked, destination: builtIn)) },
            UpdateRequest(surface: surface, destination: builtInDestination, mode: .locked, activityState: .active)
        ),
        Row(
            "unlocking puts it back in the default mode",
            Payload { FakeUpdateRequestXPC(FakeUpdateRequest(presentationMode: .default, destination: builtIn)) },
            UpdateRequest(surface: surface, destination: builtInDestination, mode: .desktop, activityState: .active)
        ),
        Row(
            "the idle mode",
            Payload { FakeUpdateRequestXPC(FakeUpdateRequest(presentationMode: .idle, destination: builtIn)) },
            UpdateRequest(surface: surface, destination: builtInDestination, mode: .idle, activityState: .active)
        ),
        Row(
            "a suspended surface on a mode the bridge has not seen",
            Payload {
                FakeUpdateRequestXPC(FakeUpdateRequest(presentationMode: .ambient, activityState: .suspended, destination: external))
            },
            UpdateRequest(
                surface: surface,
                destination: SurfaceDestination(display: 3, size: Size(width: 1920, height: 1080), scale: 1),
                mode: .other("ambient"),
                activityState: .suspended
            )
        ),
        Row(
            "an update with none of the fields",
            Payload { FakeBareRequestXPC() },
            UpdateRequest(
                surface: surface,
                destination: SurfaceDestination(display: nil, size: nil, scale: nil),
                mode: nil,
                activityState: nil
            )
        ),
    ]

    @Test(arguments: updateRows)
    func `reads an update request`(row: Row<Payload, UpdateRequest>) {
        #expect(AgentPayload.update(row.input.make(), surface: Self.surface) == row.expected)
    }

    static let modeNames: [Row<String, AgentSurfaceMode>] = [
        Row("default is the desktop", "default", .desktop),
        Row("locked is the lock screen", "locked", .locked),
        Row("idle is the screen saver", "idle", .idle),
        Row("anything else is kept by name", "ambient", .other("ambient")),
    ]

    @Test(arguments: modeNames)
    func `names surface modes as the agent does`(row: Row<String, AgentSurfaceMode>) {
        #expect(AgentSurfaceMode(agentName: row.input) == row.expected)
        #expect(row.expected.description == row.input)
    }

    static let activityNames: [Row<String, ActivityState>] = [
        Row("active", "active", .active),
        Row("suspended", "suspended", .suspended),
        Row("anything else is kept by name", "dozing", .other("dozing")),
    ]

    @Test(arguments: activityNames)
    func `names activity states as the agent does`(row: Row<String, ActivityState>) {
        #expect(ActivityState(agentName: row.input) == row.expected)
        #expect(row.expected.description == row.input)
    }
}
