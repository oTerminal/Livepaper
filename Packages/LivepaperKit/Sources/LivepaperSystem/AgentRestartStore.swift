import Foundation

/// Where the time of the last WallpaperAgent restart is kept from one launch to
/// the next, so that relaunching the app does not open the ten-minute gap early.
public protocol AgentRestartStore: AnyObject {
    var lastRestart: Date? { get set }
}

/// Keeps the last restart in the app's defaults.
public final class DefaultsAgentRestartStore: AgentRestartStore {
    public static let key = "app.livepaper.host.lastAgentRestart"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var lastRestart: Date? {
        get { defaults.object(forKey: Self.key) as? Date }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
