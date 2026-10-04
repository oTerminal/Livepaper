import Foundation

/// What the app senses on the extension's behalf, for every display at once.
/// The sandbox keeps the extension from sensing these itself (it cannot list windows).
public struct SensedConditions: Codable, Equatable, Sendable {
    public var sensedAt: Date
    /// Displays whose desktop is fully covered.
    public var coveredDisplays: Set<DisplayIdentity>
    public var asleepDisplays: Set<DisplayIdentity>
    public var locked: Bool
    public var lowPowerMode: Bool
    public var onBattery: Bool

    public init(
        sensedAt: Date,
        coveredDisplays: Set<DisplayIdentity> = [],
        asleepDisplays: Set<DisplayIdentity> = [],
        locked: Bool = false,
        lowPowerMode: Bool = false,
        onBattery: Bool = false
    ) {
        self.sensedAt = sensedAt
        self.coveredDisplays = coveredDisplays
        self.asleepDisplays = asleepDisplays
        self.locked = locked
        self.lowPowerMode = lowPowerMode
        self.onBattery = onBattery
    }

    // Sets are written in a fixed order, so that the same state gives the same bytes.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sensedAt, forKey: .sensedAt)
        try container.encode(coveredDisplays.sorted { $0.description < $1.description }, forKey: .coveredDisplays)
        try container.encode(asleepDisplays.sorted { $0.description < $1.description }, forKey: .asleepDisplays)
        try container.encode(locked, forKey: .locked)
        try container.encode(lowPowerMode, forKey: .lowPowerMode)
        try container.encode(onBattery, forKey: .onBattery)
    }
}

/// Everything the extension needs in order to show the right thing, written by
/// the app as `render-state.json`. It is the full state every
/// time, so applying it twice is harmless.
public struct RenderState: Codable, Equatable, Sendable {
    /// 1.1 added a display's `scene`.
    public static let schemaVersion = SchemaVersion(major: 1, minor: 1)

    /// What one display shows. Paths are relative to the library root.
    public struct Display: Codable, Equatable, Sendable {
        public var identity: DisplayIdentity
        public var wallpaper: WallpaperID
        /// For a scene, its package, as in the library (`Wallpaper.optimisedCopy`).
        public var optimisedCopy: LibraryPath
        public var poster: LibraryPath
        public var presentation: Presentation
        public var volume: Double
        public var userPaused: Bool
        /// Set when the wallpaper is a scene, which the extension draws rather than plays.
        public var scene: WallpaperScene?

        public init(
            identity: DisplayIdentity,
            wallpaper: WallpaperID,
            optimisedCopy: LibraryPath,
            poster: LibraryPath,
            presentation: Presentation,
            volume: Double,
            userPaused: Bool,
            scene: WallpaperScene? = nil
        ) {
            self.identity = identity
            self.wallpaper = wallpaper
            self.optimisedCopy = optimisedCopy
            self.poster = poster
            self.presentation = presentation
            self.volume = volume
            self.userPaused = userPaused
            self.scene = scene
        }
    }

    /// Counts every state the app writes. It only increases: `next` is the only way to change it.
    public private(set) var generation: UInt64
    /// The stopped form, which Quit leaves: the extension holds
    /// each display's poster as a still and releases its decoders.
    public var isStopped: Bool
    public var displays: [Display]
    public var pauseRules: PauseRules
    /// `nil` when the app has sensed nothing yet.
    public var conditions: SensedConditions?

    public init(
        generation: UInt64 = 1,
        isStopped: Bool = false,
        displays: [Display],
        pauseRules: PauseRules,
        conditions: SensedConditions?
    ) {
        self.generation = generation
        self.isStopped = isStopped
        self.displays = displays
        self.pauseRules = pauseRules
        self.conditions = conditions
    }

    /// The state that follows this one: the change applied, and the generation one higher.
    public func next(_ change: (inout RenderState) -> Void) -> RenderState {
        var next = self
        change(&next)
        next.generation = generation + 1
        return next
    }

    /// One display's conditions, as the playback policy takes them. With
    /// nothing sensed, only the user's pause reaches the policy.
    public func playbackConditions(for display: DisplayIdentity, now: Date) -> PlaybackConditions {
        PlaybackConditions(
            userPaused: displays.first { $0.identity == display }?.userPaused ?? false,
            desktopCovered: conditions?.coveredDisplays.contains(display) ?? false,
            displayAsleep: conditions?.asleepDisplays.contains(display) ?? false,
            displayLocked: conditions?.locked ?? false,
            lowPowerMode: conditions?.lowPowerMode ?? false,
            onBattery: conditions?.onBattery ?? false,
            sensedAt: conditions?.sensedAt ?? .distantPast,
            now: now
        )
    }
}

// MARK: - Codec

extension RenderState.Display {
    private enum CodingKeys: String, CodingKey {
        case wallpaper, optimisedCopy, poster, presentation, volume, userPaused, scene
        case identity = "display"
    }
}

extension RenderState {
    private enum CodingKeys: String, CodingKey {
        case version, generation, displays, pauseRules, conditions
        case isStopped = "stopped"
    }

    public func encode() throws -> Data {
        try PersistedJSON.encoder().encode(self)
    }

    /// Throws for anything it cannot fully trust, an unknown major version
    /// included. The extension then keeps what it shows.
    public static func decode(_ data: Data) throws -> RenderState {
        try PersistedJSON.decoder().decode(RenderState.self, from: data)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(SchemaVersion.self, forKey: .version)
        // When major version 2 arrives, version 1 is decoded here by a frozen
        // copy of this shape and migrated, and `render-state-v1.0.json` proves it.
        try version.requireReadable(by: Self.schemaVersion)

        generation = try container.decode(UInt64.self, forKey: .generation)
        isStopped = try container.decode(Bool.self, forKey: .isStopped)
        displays = try container.decode([Display].self, forKey: .displays)
        pauseRules = try container.decode(PauseRules.self, forKey: .pauseRules)
        conditions = try container.decodeIfPresent(SensedConditions.self, forKey: .conditions)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaVersion, forKey: .version)
        try container.encode(generation, forKey: .generation)
        try container.encode(isStopped, forKey: .isStopped)
        try container.encode(displays, forKey: .displays)
        try container.encode(pauseRules, forKey: .pauseRules)
        try container.encodeIfPresent(conditions, forKey: .conditions)
    }
}
