import DesignSystem
import SwiftUI

struct FavouriteTogglePage: View {
    @State private var isFavourite = false
    @State private var name = "Harbour at Dusk"

    var body: some View {
        StateSection(
            title: "Beside a name, as in the inspector",
            note: """
            Click the heart, or Tab to it and press Space: it fills and takes the accent, with no motion either way. \
            VoiceOver reads a toggle, “Favourite”, on or off.
            """
        ) {
            HStack(spacing: Spacing.tight) {
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 0)
                FavouriteToggle(isOn: $isFavourite)
            }
            .frame(width: 320)
        }

        StateSection(title: "Off and on", note: "An outline in secondary; filled in the accent, as a sidebar row marks its selection.") {
            HStack(spacing: Spacing.large) {
                FavouriteToggle(isOn: .constant(false))
                FavouriteToggle(isOn: .constant(true))
            }
        }

        StateSection(title: "Disabled") {
            HStack(spacing: Spacing.large) {
                FavouriteToggle(isOn: .constant(false))
                FavouriteToggle(isOn: .constant(true))
            }
            .disabled(true)
        }
    }
}
