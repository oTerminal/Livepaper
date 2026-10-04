import AppKit
import DesignSystem
import LivepaperCore
import LivepaperSystem
import SwiftUI

/// Onboarding's window: one `OnboardingCard` whose values follow the step,
/// so moving on crossfades the picture and the step's words and buttons and
/// nothing re-enters. The card is given every step, so it is the tallest step's
/// height throughout, and the window never changes size between steps. The whole
/// window takes a drop on the first card. It closes when the cards end, and
/// closing it ends them.
///
/// Before them, when where Livepaper runs is in question, the window shows
/// that card alone (`InstallCard`). Closing it then quits, and ends nothing:
/// onboarding has not been shown. Not Now gives way to onboarding's cards in the
/// same window, or closes it when none are due.
struct OnboardingWindow: View {
    @Environment(Onboarding.self) private var onboarding
    @Environment(Installation.self) private var installation
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isDropTargeted: Bool

    /// A preview can show it under a drop.
    init(isDropTargeted: Bool = false) {
        _isDropTargeted = State(initialValue: isDropTargeted)
    }

    var body: some View {
        // One view throughout, so that the install card giving way to
        // onboarding's is not taken for the window closing.
        ZStack {
            if installation.isAsking {
                InstallCard()
            } else {
                steps
            }
        }
        .onChange(of: installation.isAsking) { _, isAsking in
            if !isAsking && !onboarding.shows { dismissWindow(id: AppWindows.onboardingID) }
        }
        .onDisappear {
            if onboarding.shows && !installation.isAsking { onboarding.windowClosed() }
        }
    }

    @ViewBuilder private var steps: some View {
        let page = OnboardingPage(onboarding)
        // Every card this launch shows, each as it would read now, the one showing among them.
        let pages = onboarding.steps.isEmpty ? [page] : onboarding.steps.map { OnboardingPage(onboarding, step: $0) }
        OnboardingCard(
            steps: pages.map(\.cardStep),
            stepIndex: onboarding.steps.isEmpty ? 0 : onboarding.stepIndex,
            onPrimary: page.primary.run,
            onSecondary: page.secondary?.run
        ) {
            OnboardingIllustration(picture: page.picture)
        } accessory: {
            SampleTiles()
        }
        // While an import runs, or Livepaper is being made the wallpaper, nothing on the card can start another.
        .disabled(page.isBusy)
        .padding(Spacing.section)
        .fixedSize()
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard onboarding.takesDrops, !files.isEmpty else { return false }
            onboarding.importWallpaper(from: files)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .dropZoneOverlay(
            isTargeted: isDropTargeted && onboarding.takesDrops,
            title: "Drop to Import",
            message: "It becomes your wallpaper, on every display."
        )
        .onChange(of: onboarding.hasEnded) { _, hasEnded in
            if hasEnded { dismissWindow(id: AppWindows.onboardingID) }
        }
    }
}

/// What the card says and offers, from where onboarding has got to. The words
/// take sentence case for the title, title case for buttons.
struct OnboardingPage {
    struct Action {
        let title: String
        let run: () -> Void
    }

    var title: String
    var message: String
    var primary: Action
    var secondary: Action?
    var picture: OnboardingPicture
    var offersSamples = false
    var isBusy = false

    /// The card showing.
    init(_ onboarding: Onboarding) {
        self.init(onboarding, step: onboarding.step)
    }

    /// A step's card as it reads now, showing or not: the card is sized by every one.
    init(_ onboarding: Onboarding, step: OnboardingStep?) {
        switch step {
        case .importWallpaper: self.init(importing: onboarding)
        case .openAtLogin: self.init(login: onboarding)
        case .selectLivepaper, nil: self.init(selecting: onboarding)
        }
    }

    /// What the card is told of this step.
    var cardStep: OnboardingCardStep {
        OnboardingCardStep(
            title: title, message: message, primaryTitle: primary.title, secondaryTitle: secondary?.title, showsAccessory: offersSamples
        )
    }

    private init(title: String, message: String, primary: Action, secondary: Action? = nil, picture: OnboardingPicture) {
        self.title = title
        self.message = message
        self.primary = primary
        self.secondary = secondary
        self.picture = picture
    }

    // MARK: 1, a wallpaper

    private init(importing onboarding: Onboarding) {
        let hasSamples = !onboarding.samples.isEmpty
        let choosing = hasSamples
            ? "Drop a file on this card, or start with one of these. It plays on every display."
            : "Drop a file on this card, or choose one. It plays on every display."
        let again = hasSamples ? "Drop another file, choose one, or start with one of these." : "Drop another file, or choose one."
        let message = switch onboarding.firstWallpaper {
        case .choosing, .set: choosing
        // As long as the words it replaces, so that the card keeps its height while the import runs.
        case .importing(let name, let words): "Importing “\(name)”: \(words ?? "Checking")… Once it is in, it plays on every display."
        case .failed(let why): "\(why) \(again)"
        }
        self.init(
            title: "Add a wallpaper",
            message: message,
            primary: Action(title: "Choose File…") { onboarding.chooseFile() },
            picture: .dropWell
        )
        offersSamples = hasSamples
        if case .importing = onboarding.firstWallpaper { isBusy = true }
    }

    // MARK: 2, the login item

    private init(login onboarding: Onboarding) {
        let next = Action(title: "Continue") { onboarding.next() }
        let picture = OnboardingPicture.login(onboarding.wallpaper)
        switch onboarding.loginPhase {
        case .asking:
            self.init(
                title: "Open at login",
                message: "Livepaper can open when you log in, so your wallpaper is there from the start.",
                primary: Action(title: "Open at Login") { onboarding.turnOnOpenAtLogin() },
                secondary: Action(title: "Not Now") { onboarding.next() },
                picture: picture
            )
        case .alreadyOn, .turnedOn:
            self.init(title: "Open at login", message: "Livepaper opens when you log in.", primary: next, picture: picture)
        case .needsApproval:
            self.init(
                title: "Open at login",
                message: "Allow Livepaper in System Settings, under Login Items, to finish turning this on.",
                primary: Action(title: "Open System Settings…") { onboarding.openLoginItems() },
                secondary: next,
                picture: picture
            )
        case .notFound:
            self.init(
                title: "Open at login",
                message: "Login item not found. Move Livepaper to the Applications folder, then turn this on in Settings.",
                primary: next,
                picture: picture
            )
        case .notRegistered:
            self.init(
                title: "Open at login",
                message: "Livepaper could not be added to your login items. You can try again in Settings.",
                primary: next,
                picture: picture
            )
        }
    }

    // MARK: 3, Livepaper as the wallpaper

    private init(selecting onboarding: Onboarding) {
        let picture = OnboardingPicture.desktop(onboarding.wallpaper)
        let done = Action(title: "Done") { onboarding.end() }
        let notNow = Action(title: "Not Now") { onboarding.end() }
        let outcome = onboarding.selectionOutcome
        switch outcome {
        case .idle, .left, .chooseAnotherInPane, .failed(_, leaving: true):
            self.init(
                title: "Make Livepaper your wallpaper",
                message: "Livepaper becomes the wallpaper in System Settings, on every display and Space.",
                primary: Action(title: "Set as Wallpaper") { onboarding.selectLivepaper() },
                secondary: notNow,
                picture: picture
            )
        case .working:
            self.init(
                title: "Make Livepaper your wallpaper",
                message: "Making Livepaper the wallpaper on every display and Space. This takes a moment…",
                primary: Action(title: "Set as Wallpaper") {},
                secondary: notNow,
                picture: picture
            )
            isBusy = true
        case .selected:
            self.init(
                title: "Livepaper is your wallpaper",
                message: "It lives in the menu bar: open it there to change wallpapers, pause them, or import more.",
                primary: done,
                picture: picture
            )
        case .chooseInPane, .failed(_, leaving: false):
            self.init(
                title: "Make Livepaper your wallpaper",
                message: (outcome.words ?? "") + " This card finishes when you have.",
                primary: Action(title: "Open Wallpaper Settings") { onboarding.openWallpaperPane() },
                secondary: notNow,
                picture: picture
            )
        }
    }
}

/// The first card's samples, as tiles like the library's: each plays when the
/// pointer rests on it, and a click imports it and sets it on every display.
struct SampleTiles: View {
    @Environment(Onboarding.self) private var onboarding

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            ForEach(onboarding.samples) { sample in
                WallpaperTile(
                    id: sample.id,
                    poster: onboarding.samplePosters[sample.id].map { Image(decorative: $0, scale: 2) } ?? .posterLoading,
                    title: sample.title,
                    isSelected: isImporting(sample)
                ) {
                    onboarding.pickSample(sample)
                } livePreview: {
                    // Clear: the poster shows until the first frame is up.
                    PreviewPlayerView(url: sample.url, presentation: Presentation(), backgroundColor: .clear)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .livePreviewScope()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Samples")
        .onAppear { onboarding.loadSamplePosters() }
    }

    private func isImporting(_ sample: SampleWallpaper) -> Bool {
        if case .importing(let name, _) = onboarding.firstWallpaper { return name == sample.title }
        return false
    }
}

// MARK: Previews

#Preview("Add a wallpaper") {
    OnboardingPreview(.fresh)
}

#Preview("Add a wallpaper, under a drop") {
    OnboardingPreview(.fresh, isDropTargeted: true)
}

#Preview("Open at login") {
    OnboardingPreview(.fresh) { onboarding, _ in onboarding.next() }
}

#Preview("Open at login, needing approval") {
    OnboardingPreview(.fresh) { onboarding, fakes in
        onboarding.next()
        fakes.systemServices.answerToTurningOn = .needsApproval
        onboarding.turnOnOpenAtLogin()
    }
}

#Preview("Make Livepaper your wallpaper") {
    OnboardingPreview(.fresh) { onboarding, _ in
        onboarding.next()
        onboarding.next()
    }
}

#Preview("Make Livepaper your wallpaper, in System Settings") {
    OnboardingPreview(.fresh) { onboarding, fakes in
        onboarding.next()
        onboarding.next()
        fakes.selectionWorld.store.isReadable = false
        onboarding.selectLivepaper()
    }
}

#Preview("After leaving") {
    OnboardingPreview(.afterLeaving)
}

#Preview("Opened from the disk image") {
    OnboardingPreview(.fresh, install: .drag)
}

#Preview("Outside Applications") {
    OnboardingPreview(.fresh, install: .move)
}

#Preview("Outside Applications, Move failed") {
    OnboardingPreview(.fresh, install: .move, failedMove: true)
}

/// Onboarding's window on the fakes, as a scenario of `-onboarding` and `-install` starts it.
private struct OnboardingPreview: View {
    let onboarding: Onboarding
    let installation: Installation
    let model: AppModel
    var isDropTargeted = false

    init(
        _ scenario: FakeOnboarding,
        install: FakeInstall? = nil,
        failedMove: Bool = false,
        isDropTargeted: Bool = false,
        _ change: (Onboarding, Fakes) -> Void = { _, _ in }
    ) {
        let fakes = Fakes(library: .seeded, onboarding: scenario, install: install)
        model = AppModel(services: fakes.makeServices())
        model.prepareForPreview(displays: fakes.connectedDisplays, hostStatus: .notSelected)
        onboarding = Onboarding(model: model)
        installation = Installation(services: fakes.installServices())
        self.isDropTargeted = isDropTargeted
        if failedMove {
            fakes.movesFail = true
            installation.move()
        }
        change(onboarding, fakes)
    }

    var body: some View {
        OnboardingWindow(isDropTargeted: isDropTargeted)
            .environment(onboarding)
            .environment(installation)
            .environment(model)
    }
}
