import AppKit
import LivepaperCore
import LivepaperImport
import LivepaperSystem
import Observation
import os

/// First-run onboarding: which cards this launch shows, decided once when
/// the app starts from what the preferences recorded, and where the card that
/// shows has got to. The onboarding window reads it and its buttons call it; the
/// import, the login item and the displays are the model's.
///
/// Three cards at most, each done by one press, where Wallper had seven slides
/// and 46 s to a live wallpaper: a wallpaper,
/// imported and set on every display; the login item; and Livepaper made the
/// system wallpaper, done when the heartbeat says a desktop surface is acquired.
@Observable
final class Onboarding {
    /// The first card's import.
    enum FirstWallpaper: Equatable {
        case choosing
        /// What is being imported, and its stage in words once it runs.
        case importing(name: String, words: String?)
        /// Why nothing came of it, in a sentence.
        case failed(String)
        /// Imported, or already in the library, and set on every display.
        case set(Wallpaper)
    }

    let plan: OnboardingPlan
    let samples: [SampleWallpaper]
    private(set) var stepIndex = 0
    private(set) var firstWallpaper = FirstWallpaper.choosing
    /// Whether the "Open at login" card asked for the login item.
    private(set) var hasAskedLogin = false
    /// What came of making Livepaper the system wallpaper, as `Selection` reports it.
    private(set) var selectionOutcome = SelectionOutcome.idle
    /// By the last card's button or the window closed: the record is kept, and the window goes.
    private(set) var hasEnded = false
    /// Each sample's poster, read from its file.
    private(set) var samplePosters: [SampleWallpaper.ID: CGImage] = [:]

    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private let services: OnboardingServices
    @ObservationIgnored private var loginWatch: Task<Void, Never>?
    @ObservationIgnored private var selectionWatch: Task<Void, Never>?

    /// Decides the plan now, before this launch writes anything: whether a
    /// library is on disk tells an update from a Livepaper before onboarding
    /// from a fresh install.
    init(model: AppModel) {
        self.model = model
        services = model.services.onboarding
        samples = services.samples
        plan = onboardingPlan(record: services.record.record, ranBefore: services.ranBefore)
        OnboardingLog.logger.notice("\(OnboardingLog.planned(self.plan), privacy: .public)")
    }

    // MARK: Where it has got to

    var steps: [OnboardingStep] {
        if case .steps(let steps) = plan { steps } else { [] }
    }

    /// Nil when nothing is shown.
    var step: OnboardingStep? {
        steps.indices.contains(stepIndex) ? steps[stepIndex] : nil
    }

    /// Whether this launch shows anything.
    var shows: Bool { plan != .nothing && !hasEnded }

    var loginPhase: OnboardingLoginPhase {
        onboardingLoginPhase(asked: hasAskedLogin, status: model.loginItem)
    }

    /// What the cards after the first show: the wallpaper just set, else what the first display shows.
    var wallpaper: Wallpaper? {
        if case .set(let wallpaper) = firstWallpaper { return wallpaper }
        return model.nowPlaying.lazy.compactMap(\.wallpaper).first
    }

    /// A drop is taken on the first card while nothing is importing.
    var takesDrops: Bool {
        guard step == .importWallpaper else { return false }
        if case .importing = firstWallpaper { return false }
        return true
    }

    // MARK: The first card

    /// Files dropped on the card or chosen in the Open panel: imported through
    /// the import list as any import is, and the first wallpaper that comes of
    /// them set on every display. Then the next card.
    func importWallpaper(from urls: [URL]) {
        guard takesDrops, let first = urls.first else { return }
        firstWallpaper = .importing(name: first.deletingPathExtension().lastPathComponent, words: nil)
        Task {
            let outcome = await model.importFirstWallpaper(from: urls) { batch in
                if case .importing(let name, let words) = batch { self.firstWallpaper = .importing(name: name, words: words) }
            }
            switch outcome {
            case .set(let wallpaper):
                firstWallpaper = .set(wallpaper)
                OnboardingLog.logger.notice("\(OnboardingLog.firstWallpaper(wallpaper), privacy: .public)")
                next()
            case .failed(let words):
                firstWallpaper = .failed(words)
            }
        }
    }

    func pickSample(_ sample: SampleWallpaper) {
        importWallpaper(from: [sample.url])
    }

    /// The Open panel, as a sheet on the onboarding window.
    func chooseFile() {
        model.chooseFiles { [weak self] urls in self?.importWallpaper(from: urls) }
    }

    /// Reads each sample's poster from its file, once.
    func loadSamplePosters() {
        for sample in samples where samplePosters[sample.id] == nil {
            Task {
                if let poster = await SampleWallpaper.poster(of: sample.url) { samplePosters[sample.id] = poster }
            }
        }
    }

    // MARK: The login card

    /// Asks macOS for the login item. The card moves on when macOS has it on,
    /// now or once the user allows it in Login Items; otherwise it says why.
    func turnOnOpenAtLogin() {
        hasAskedLogin = true
        model.setOpenAtLogin(true)
        if loginPhase.movesOn {
            next()
        } else {
            watchLoginItem()
        }
    }

    func openLoginItems() {
        model.openLoginItemsSettings()
    }

    /// Once allowed in System Settings, the status is read again when Livepaper
    /// becomes active, and the card moves on.
    private func watchLoginItem() {
        guard loginWatch == nil else { return }
        loginWatch = Task { [weak self] in
            guard let self else { return }
            for await phase in Observations({ self.loginPhase }) where phase.movesOn {
                if step == .openAtLogin { next() }
                return
            }
        }
    }

    // MARK: The last card

    /// Makes Livepaper the system wallpaper. The card is done when the heartbeat
    /// says so; when the store cannot be used, or no heartbeat says so in 30 s,
    /// System Settings opens at Wallpaper, and the user's click there finishes it.
    func selectLivepaper() {
        let selecting = model.services.system.selection
        watchSelection(selecting)
        Task { await selecting.select() }
    }

    /// System Settings at Wallpaper again, should the user have closed it.
    func openWallpaperPane() {
        model.openWallpaperPane()
    }

    private func watchSelection(_ selecting: Selection) {
        guard selectionWatch == nil else { return }
        selectionWatch = Task { [weak self] in
            for await outcome in selecting.outcomes {
                self?.selectionOutcome = outcome
            }
        }
    }

    // MARK: Moving on

    /// The next card, or Not Now's: a step skipped is left as it is.
    func next() {
        guard stepIndex < steps.count - 1 else { return }
        stepIndex += 1
    }

    /// The last card's Done: the cards end and the record is kept.
    func end() {
        guard !hasEnded else { return }
        hasEnded = true
        loginWatch?.cancel()
        selectionWatch?.cancel()
        if let record = plan.record(afterEnding: services.record.record, version: services.version) {
            services.record.record = record
        }
        OnboardingLog.logger.notice("\(OnboardingLog.ended(at: self.step), privacy: .public)")
    }

    /// The window closed by its close button: the cards end as by their last
    /// button. Not while quitting, when the next launch shows them again.
    func windowClosed() {
        guard !model.isQuitting else { return }
        end()
    }
}

// MARK: - What onboarding runs on

/// What onboarding reads beyond the model: the record, whether a Livepaper ran
/// here before, and the samples. Wired, the record is the app's preferences; in
/// the fakes run it is kept in memory, so that a fakes run never touches what
/// the real app reads.
struct OnboardingServices {
    var record: any OnboardingRecordKeeping
    /// A library or an app state is on disk from an earlier run, looked for
    /// before this launch writes anything.
    var ranBefore: Bool
    /// This build, as kept with the record: "0.1.0 (1)".
    var version: String
    var samples: [SampleWallpaper]

    static func wired(location: LibraryLocation) -> OnboardingServices {
        let files = FileManager.default
        return OnboardingServices(
            record: DefaultsOnboardingRecord(),
            ranBefore: files.fileExists(atPath: location.manifest.path) || files.fileExists(atPath: location.appState.path),
            version: BundleVersion.main.words,
            samples: SampleWallpaper.bundled()
        )
    }
}

/// Where the onboarding record is kept.
protocol OnboardingRecordKeeping: AnyObject {
    var record: OnboardingRecord { get set }
}

/// The app's preferences: `OnboardedVersion`, the build that ran onboarding, and
/// `LeftLivepaper`, set when the user left Livepaper as their wallpaper.
final class DefaultsOnboardingRecord: OnboardingRecordKeeping {
    static let versionKey = "OnboardedVersion"
    static let leftKey = "LeftLivepaper"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var record: OnboardingRecord {
        get {
            OnboardingRecord(onboardedVersion: defaults.string(forKey: Self.versionKey), hasLeft: defaults.bool(forKey: Self.leftKey))
        }
        set {
            defaults.set(newValue.onboardedVersion, forKey: Self.versionKey)
            if newValue.hasLeft {
                defaults.set(true, forKey: Self.leftKey)
            } else {
                defaults.removeObject(forKey: Self.leftKey)
            }
        }
    }
}

final class InMemoryOnboardingRecord: OnboardingRecordKeeping {
    var record: OnboardingRecord

    init(_ record: OnboardingRecord = OnboardingRecord()) {
        self.record = record
    }
}

/// Onboarding's log lines, in the app's category.
enum OnboardingLog {
    static let logger = AppLog.logger

    static func planned(_ plan: OnboardingPlan) -> String {
        switch plan {
        case .nothing: "onboarding: none this launch"
        case .steps(let steps): "onboarding: showing \(steps.map(name).joined(separator: ", "))"
        }
    }

    static let choosingFile = "onboarding: choosing a file to import, in a sheet on the onboarding window"

    static func firstWallpaper(_ wallpaper: Wallpaper) -> String {
        "onboarding: wallpaper \(wallpaper.id) set on every display"
    }

    static func ended(at step: OnboardingStep?) -> String {
        "onboarding: ended" + (step.map { " at \(name($0))" } ?? "")
    }

    private static func name(_ step: OnboardingStep) -> String {
        switch step {
        case .importWallpaper: "import a wallpaper"
        case .openAtLogin: "open at login"
        case .selectLivepaper: "make Livepaper the wallpaper"
        }
    }
}
