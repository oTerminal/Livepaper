import DesignSystem
import SwiftUI

struct OnboardingCardPage: View {
    @State private var replay = 0
    @State private var step = 0

    private let steps: [(title: String, message: String)] = [
        ("Welcome to Livepaper", "Put a video on your desktop. It pauses by itself when you would not see it."),
        ("Choose a video", "Drop any video into the library, or pick one from your Mac."),
        ("Save your battery", "Wallpapers pause on battery, in Low Power Mode and when a window covers the desktop."),
        ("You are set", "Livepaper lives in the menu bar. Open it there at any time."),
    ]

    var body: some View {
        StateSection(
            title: "Step 1 of 4",
            note: """
            Illustration, text and buttons enter 0.10 s apart, once. With Reduce Motion: opacity only, together. \
            Try 0.1x, then Replay.
            """
        ) {
            VStack(alignment: .leading, spacing: Spacing.large) {
                OnboardingCard(
                    title: steps[0].title,
                    message: steps[0].message,
                    stepIndex: 0,
                    stepCount: steps.count,
                    primaryTitle: "Continue",
                    onPrimary: {},
                    secondaryTitle: "Skip",
                    onSecondary: {},
                    illustration: { SamplePicture(seed: 3) }
                )
                .id(replay)
                Button("Replay entrance") { replay += 1 }
            }
        }

        StateSection(
            title: "Stepping through",
            note: """
            Given every step, the card is the tallest step's height at each: the words stay at the top and the dots and \
            buttons at the bottom, so a step change happens in a still frame. The card keeps its identity, so moving \
            between steps re-enters nothing; a click crossfades the picture, and the rest of the step as one page. Try \
            0.1x on “Choose a video”, which has an accessory. Return presses Continue with no animation. Each step opens \
            with the focus on its primary button (keyboard navigation on).
            """
        ) {
            OnboardingCard(
                steps: steps.indices.map { index in
                    OnboardingCardStep(
                        title: steps[index].title,
                        message: steps[index].message,
                        primaryTitle: index == steps.count - 1 ? "Done" : "Continue",
                        secondaryTitle: index == 0 ? nil : "Back",
                        showsAccessory: index == 1
                    )
                },
                stepIndex: step,
                onPrimary: { step = (step + 1) % steps.count },
                onSecondary: { step = max(step - 1, 0) },
                illustration: { SamplePicture(seed: 10 + step) },
                accessory: {
                    HStack(spacing: Spacing.small) {
                        ForEach(1..<4) { seed in
                            WallpaperTile(
                                id: seed, poster: SamplePicture.image(seed: 40 + seed), title: "Sample \(seed)"
                            ) {} livePreview: {
                                EmptyView()
                            }
                        }
                    }
                }
            )
        }

        StateSection(title: "Last step", note: "“Done”, and no secondary button.") {
            OnboardingCard(
                title: steps[3].title,
                message: steps[3].message,
                stepIndex: 3,
                stepCount: steps.count,
                primaryTitle: "Done",
                onPrimary: {},
                illustration: { SamplePicture(seed: 5) }
            )
        }

        StateSection(
            title: "With an accessory",
            note: """
            Controls of the step's own under the words, entering with them: here, wallpapers to start with. Unlike the \
            illustration they are read by VoiceOver and can be pressed. They come and go with their step's page.
            """
        ) {
            OnboardingCard(
                title: "Add a wallpaper",
                message: "Drop a file on this card, or start with one of these.",
                stepIndex: 0,
                stepCount: 3,
                primaryTitle: "Choose File…",
                onPrimary: {},
                illustration: { SamplePicture(seed: 21) },
                accessory: {
                    HStack(spacing: Spacing.small) {
                        ForEach(1..<4) { seed in
                            WallpaperTile(id: seed, poster: SamplePicture.image(seed: 30 + seed), title: "Sample \(seed)") {} livePreview: {
                                EmptyView()
                            }
                        }
                    }
                }
            )
        }

        StateSection(title: "A card alone", note: "One card shows no page dots: one dot would only say “Step 1 of 1”.") {
            OnboardingCard(
                title: "Move Livepaper to Applications",
                message: "Quit Livepaper, drag it into the Applications folder, and open it from there.",
                stepIndex: 0,
                stepCount: 1,
                primaryTitle: "Quit",
                onPrimary: {},
                illustration: { SamplePicture(seed: 6) }
            )
        }

        StateSection(title: "Long text") {
            OnboardingCard(
                title: "Let Livepaper open when you log in, so your wallpaper is there before you are",
                message: """
                Livepaper can open by itself when you log in. macOS will ask you to allow this in System Settings the first \
                time. You can change your mind later in Settings, under General, and nothing else about the app changes.
                """,
                stepIndex: 1,
                stepCount: steps.count,
                primaryTitle: "Open at Login",
                onPrimary: {},
                secondaryTitle: "Not Now",
                onSecondary: {},
                illustration: { SamplePicture(seed: 8) }
            )
        }
    }
}
