/// What the extension tells the app, packed into the 64-bit state of a Darwin
/// notification: the extension never writes a file.
///
/// The low 32 bits are the generation of the render state it is showing and
/// the high 32 bits are flags.
public struct Heartbeat: Equatable, Sendable {
    public struct Flags: OptionSet, Hashable, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        /// WallpaperAgent has acquired a desktop surface. This is how the app
        /// learns that the user has selected Livepaper.
        public static let desktopSurfaceAcquired = Flags(rawValue: 1 << 0)
        /// The extension is holding posters as stills: the stopped render state, or none it could read.
        public static let holdingStill = Flags(rawValue: 1 << 1)
        /// The agent is reconnecting in a loop, and the app should restart it.
        public static let spiralDetected = Flags(rawValue: 1 << 2)
        /// The private API the extension needs was not found at launch.
        public static let selfCheckFailed = Flags(rawValue: 1 << 3)
        /// The watchdog climbed its ladder to the top, and the app should restart
        /// WallpaperAgent: the sandbox keeps the extension from doing it.
        public static let restartAgentRequested = Flags(rawValue: 1 << 4)
    }

    /// The low 32 bits of the generation of the render state being shown.
    public var generation: UInt32
    public var flags: Flags

    public init(generation: UInt32, flags: Flags) {
        self.generation = generation
        self.flags = flags
    }

    /// A heartbeat for a render state's full generation, which wraps into 32 bits.
    public init(acknowledging generation: UInt64, flags: Flags) {
        self.init(generation: UInt32(truncatingIfNeeded: generation), flags: flags)
    }

    public init(packed: UInt64) {
        self.init(generation: UInt32(truncatingIfNeeded: packed), flags: Flags(rawValue: UInt32(truncatingIfNeeded: packed >> 32)))
    }

    public var packed: UInt64 {
        UInt64(flags.rawValue) << 32 | UInt64(generation)
    }

    /// Whether the extension is showing the render state with this generation.
    /// Only the low 32 bits are compared, so it holds across the wrap.
    public func acknowledges(_ generation: UInt64) -> Bool {
        self.generation == UInt32(truncatingIfNeeded: generation)
    }
}
