import Testing
import LivepaperCore
import LivepaperPlayback

struct WatchdogSchedulingTests {
    // MARK: Which events start a check

    enum Event: Sendable {
        case request(WatchdogTrigger)
        case finish
    }

    /// What each event gave back: whether a check starts, or which check runs next.
    enum Outcome: Equatable, Sendable {
        case starts(Bool)
        case next(WatchdogTrigger?)
    }

    static func told(_ events: [Event]) -> [Outcome] {
        var schedule = WatchdogSchedule()
        return events.map { event in
            switch event {
            case .request(let trigger): .starts(schedule.request(trigger))
            case .finish: .next(schedule.finish())
            }
        }
    }

    static let triggers: [Row<[Event], [Outcome]>] = [
        Row("a wake starts a check", [.request(.wake)], [.starts(true)]),
        Row("an unlock starts a check", [.request(.unlock)], [.starts(true)]),
        Row("a recovery starts a check", [.request(.recovery)], [.starts(true)]),
        Row("the agent's update starts a check", [.request(.update)], [.starts(true)]),
        Row("the app's check notification starts a check", [.request(.check)], [.starts(true)]),
        Row("a check that ends with nothing waiting stops", [.request(.wake), .finish], [.starts(true), .next(nil)]),
        Row(
            "a trigger during a check runs one more check after it",
            [.request(.wake), .request(.unlock), .finish, .finish],
            [.starts(true), .starts(false), .next(.unlock), .next(nil)]
        ),
        Row(
            "triggers during a check coalesce into one, for the latest reason",
            [.request(.update), .request(.unlock), .request(.recovery), .finish, .finish],
            [.starts(true), .starts(false), .starts(false), .next(.recovery), .next(nil)]
        ),
        Row(
            "after a check ends, the next trigger starts one again",
            [.request(.check), .finish, .request(.update)],
            [.starts(true), .next(nil), .starts(true)]
        ),
    ]

    @Test(arguments: triggers)
    func `schedules checks`(row: Row<[Event], [Outcome]>) {
        #expect(Self.told(row.input) == row.expected)
    }

    // MARK: Which surfaces it may judge

    static func candidate(_ change: (inout WatchdogCandidate) -> Void = { _ in }) -> WatchdogCandidate {
        var candidate = WatchdogCandidate(
            isLive: true, isPreview: false, mode: .desktop, state: .playing, displayCovered: false, displayAsleep: false
        )
        change(&candidate)
        return candidate
    }

    static let judgeable: [Row<WatchdogCandidate, Bool>] = [
        Row("a desktop surface that plays on screen is judged", candidate(), true),
        Row("the Settings preview is not: it is throttled when Settings is behind", candidate { $0.isPreview = true }, false),
        Row("a covered display is not: covered means not composited", candidate { $0.displayCovered = true }, false),
        Row("a covered display on the lock screen is: the lock screen is above every window", candidate {
            $0.displayCovered = true
            $0.mode = .locked
        }, true),
        Row("a sleeping display is not", candidate { $0.displayAsleep = true }, false),
        Row("a paused surface is not", candidate { $0.state = .paused }, false),
        Row("a suspended surface is not", candidate { $0.state = .suspended }, false),
        Row("a still is not", candidate { $0.state = .still }, false),
        Row("the neutral colour is not", candidate { $0.state = .nothing }, false),
        Row("a surface the agent let go of is not", candidate { $0.isLive = false }, false),
    ]

    @Test(arguments: judgeable)
    func `judges only surfaces that play on screen`(row: Row<WatchdogCandidate, Bool>) {
        #expect(WatchdogSchedule.mayJudge(row.input) == row.expected)
    }

    // MARK: What a count means

    static let judgements: [Row<PictureCount, WatchdogStep>] = [
        Row("every picture shown is healthy", PictureCount(displayed: 60, expected: 60, fed: 60), .healthy),
        Row("half the pictures shown is healthy, whatever was fed", PictureCount(displayed: 30, expected: 60, fed: 0), .healthy),
        Row(
            "a covered surface fed as usual is not composited, not stalled",
            PictureCount(displayed: 0, expected: 60, fed: 60),
            .notComposited
        ),
        Row(
            "a wedged decoder that stops taking frames is a stall",
            PictureCount(displayed: 0, expected: 60, fed: 0),
            .recover(.flush)
        ),
        Row(
            "a stopped clock is a stall: the renderer's queue fills and feeding stops",
            PictureCount(displayed: 0, expected: 60, fed: 12),
            .recover(.flush)
        ),
        Row(
            "too few shown while half the frames were fed is not composited",
            PictureCount(displayed: 29, expected: 60, fed: 30),
            .notComposited
        ),
        Row(
            "too few shown and too few fed is a stall",
            PictureCount(displayed: 29, expected: 60, fed: 29),
            .recover(.flush)
        ),
        Row(
            "a scene drawn as usual is healthy, however few of its pictures the window server presented (a covered desktop)",
            PictureCount(displayed: 60, expected: 60, fed: 60, asked: 60, presented: 3),
            .healthy
        ),
        Row(
            "a scene whose display link is not called while the engine stands ready is withheld, not stalled",
            PictureCount(displayed: 0, expected: 60, fed: 0, asked: 0, withheld: true),
            .notComposited
        ),
        Row(
            "a scene whose engine does not answer is a stall",
            PictureCount(displayed: 0, expected: 60, fed: 0, asked: 0, withheld: false),
            .recover(.flush)
        ),
    ]

    @Test(arguments: judgements)
    func `tells a surface that is not composited from one that stalled`(row: Row<PictureCount, WatchdogStep>) {
        var schedule = WatchdogSchedule()

        #expect(schedule.judge(.numbered(1), row.input) == row.expected)
    }

    // MARK: The ladder

    static let healthy = PictureCount(displayed: 60, expected: 60, fed: 60)
    static let stalled = PictureCount(displayed: 0, expected: 60, fed: 0)
    static let notComposited = PictureCount(displayed: 0, expected: 60, fed: 60)
    /// A scene on a desktop the window server does not show: its display link is not called.
    static let withheld = PictureCount(displayed: 0, expected: 60, fed: 0, asked: 0, withheld: true)
    static let toTheTop: [WatchdogStep] = [.recover(.flush), .recover(.rebuildSurface), .recover(.rebuildPipeline), .requestRestart]

    enum Step: Sendable {
        case count(Int, PictureCount)
        case forget(Int)
        case recover(RecoveryLevel)
    }

    struct Climb: Equatable, Sendable {
        var steps: [WatchdogStep]
        var restartAgentRequested: Bool
    }

    static func climbed(_ steps: [Step]) -> Climb {
        var schedule = WatchdogSchedule()
        var results: [WatchdogStep] = []
        for step in steps {
            switch step {
            case .count(let surface, let count): results.append(schedule.judge(.numbered(surface), count))
            case .forget(let surface): schedule.forget(.numbered(surface))
            case .recover(let level): _ = schedule.recoveryRequested(level)
            }
        }
        return Climb(steps: results, restartAgentRequested: schedule.restartAgentRequested)
    }

    static let ladders: [Row<[Step], Climb>] = [
        Row("progress is healthy", [.count(1, healthy)], Climb(steps: [.healthy], restartAgentRequested: false)),
        Row(
            "a stall climbs flush, rebuild surface, rebuild pipeline, then asks for the agent",
            [.count(1, stalled), .count(1, stalled), .count(1, stalled), .count(1, stalled)],
            Climb(steps: toTheTop, restartAgentRequested: true)
        ),
        Row(
            "the agent is asked for again while the stall lasts",
            [.count(1, stalled), .count(1, stalled), .count(1, stalled), .count(1, stalled), .count(1, stalled)],
            Climb(
                steps: [.recover(.flush), .recover(.rebuildSurface), .recover(.rebuildPipeline), .requestRestart, .requestRestart],
                restartAgentRequested: true
            )
        ),
        Row(
            "a recovery that works starts the next stall at the bottom",
            [.count(1, stalled), .count(1, healthy), .count(1, stalled)],
            Climb(steps: [.recover(.flush), .healthy, .recover(.flush)], restartAgentRequested: false)
        ),
        Row(
            "each surface climbs its own ladder",
            [.count(1, stalled), .count(2, stalled), .count(1, stalled)],
            Climb(steps: [.recover(.flush), .recover(.flush), .recover(.rebuildSurface)], restartAgentRequested: false)
        ),
        Row(
            "a later healthy check clears the request",
            [.count(1, stalled), .count(1, stalled), .count(1, stalled), .count(1, stalled), .count(1, healthy)],
            Climb(
                steps: [.recover(.flush), .recover(.rebuildSurface), .recover(.rebuildPipeline), .requestRestart, .healthy],
                restartAgentRequested: false
            )
        ),
        Row(
            "the request stays while another surface still needs it",
            [.count(1, stalled), .count(1, stalled), .count(1, stalled), .count(1, stalled), .count(2, healthy)],
            Climb(
                steps: [.recover(.flush), .recover(.rebuildSurface), .recover(.rebuildPipeline), .requestRestart, .healthy],
                restartAgentRequested: true
            )
        ),
        Row(
            "a surface that goes takes its request with it",
            [.count(1, stalled), .count(1, stalled), .count(1, stalled), .count(1, stalled), .forget(1)],
            Climb(steps: toTheTop, restartAgentRequested: false)
        ),
        Row(
            "the app's recovery moves the ladder above the level it tried",
            [.count(1, stalled), .recover(.rebuildPipeline), .count(1, stalled)],
            Climb(steps: [.recover(.flush), .requestRestart], restartAgentRequested: true)
        ),
        Row(
            "the app's recovery never moves the ladder down",
            [.count(1, stalled), .count(1, stalled), .count(1, stalled), .recover(.flush), .count(1, stalled)],
            Climb(
                steps: [.recover(.flush), .recover(.rebuildSurface), .recover(.rebuildPipeline), .requestRestart],
                restartAgentRequested: true
            )
        ),
        Row(
            "the app's recovery leaves healthy surfaces at the bottom",
            [.count(1, healthy), .recover(.rebuildPipeline), .count(1, stalled)],
            Climb(steps: [.healthy, .recover(.flush)], restartAgentRequested: false)
        ),
        Row(
            "a surface not composited starts no ladder",
            [.count(1, notComposited), .count(1, notComposited), .recover(.rebuildPipeline), .count(1, stalled)],
            Climb(steps: [.notComposited, .notComposited, .recover(.flush)], restartAgentRequested: false)
        ),
        Row(
            "a surface not composited keeps its place on the ladder",
            [.count(1, stalled), .count(1, notComposited), .count(1, stalled)],
            Climb(steps: [.recover(.flush), .notComposited, .recover(.rebuildSurface)], restartAgentRequested: false)
        ),
        Row(
            "a surface not composited keeps its restart request",
            [.count(1, stalled), .count(1, stalled), .count(1, stalled), .count(1, stalled), .count(1, notComposited)],
            Climb(steps: toTheTop + [.notComposited], restartAgentRequested: true)
        ),
        Row(
            "a covered scene checked again and again never climbs, and never asks for an agent restart",
            [.count(1, withheld), .count(1, withheld), .count(1, withheld), .count(1, withheld), .count(1, withheld), .count(1, withheld)],
            Climb(steps: Array(repeating: .notComposited, count: 6), restartAgentRequested: false)
        ),
    ]

    @Test(arguments: ladders)
    func `climbs the ladder per surface`(row: Row<[Step], Climb>) {
        #expect(Self.climbed(row.input) == row.expected)
    }

    @Test func `the app's recovery runs on the stalled surfaces only`() {
        var schedule = WatchdogSchedule()
        _ = schedule.judge(.numbered(1), Self.stalled)
        _ = schedule.judge(.numbered(2), Self.healthy)
        _ = schedule.judge(.numbered(3), Self.stalled)

        let recovered = schedule.recoveryRequested(.flush)

        #expect(recovered == [.numbered(1), .numbered(3)])
    }

    @Test func `the app never sends a restart to run inside the process`() {
        var schedule = WatchdogSchedule()
        _ = schedule.judge(.numbered(1), Self.stalled)

        let recovered = schedule.recoveryRequested(.restartAgent)

        #expect(recovered.isEmpty)
    }
}
