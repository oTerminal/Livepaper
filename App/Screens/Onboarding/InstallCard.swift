import DesignSystem
import SwiftUI

/// The card asking where Livepaper runs, before anything has started:
/// onboarding's card, alone, with the picture of Livepaper going into the
/// Applications folder.
struct InstallCard: View {
    @Environment(Installation.self) private var installation

    var body: some View {
        let page = InstallPage(installation)
        OnboardingCard(
            title: page.title,
            message: page.message,
            stepIndex: 0,
            stepCount: 1,
            primaryTitle: page.primary.title,
            onPrimary: page.primary.run,
            secondaryTitle: page.secondary.title,
            onSecondary: page.secondary.run
        ) {
            OnboardingIllustration(picture: .move)
        }
        .padding(Spacing.section)
        .fixedSize()
    }
}

/// What the install card says and offers.
struct InstallPage {
    var title: String
    var message: String
    var primary: OnboardingPage.Action
    var secondary: OnboardingPage.Action

    init(_ installation: Installation) {
        title = "Move Livepaper to Applications"
        switch installation.decision {
        case .askForDrag, .proceed:
            message = "Livepaper was opened from the disk image. Drag it to the Applications folder, then open it from there."
            primary = OnboardingPage.Action(title: "Open Applications Folder") { installation.openApplicationsFolder() }
            secondary = OnboardingPage.Action(title: "Quit") { installation.quit() }
        case .offerMove:
            message = if case .failed(let why) = installation.phase {
                why
            } else {
                "Livepaper works best in the Applications folder. Move it there now?"
            }
            primary = OnboardingPage.Action(title: "Move") { installation.move() }
            secondary = OnboardingPage.Action(title: "Not Now") { installation.notNow() }
        }
    }
}
