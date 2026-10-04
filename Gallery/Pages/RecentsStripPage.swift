import DesignSystem
import SwiftUI

struct RecentsStripPage: View {
    @State private var replay = 0
    @State private var selected = "Nothing selected yet"
    @State private var inserted = 0
    @State private var hasLoaded = false
    private let posters = (0..<14).map { SamplePicture.image(seed: $0 + 20) }

    private func items(_ count: Int) -> [RecentItem<Int>] {
        (0..<count).map { RecentItem(id: $0, poster: posters[$0 % posters.count], title: "Wallpaper \($0 + 1)") }
    }

    private var newItems: [RecentItem<Int>] {
        (0..<inserted).reversed().map {
            RecentItem(id: 100 + $0, poster: posters[($0 + 5) % posters.count], title: "New \($0 + 1)")
        }
    }

    var body: some View {
        StateSection(
            title: "Five items",
            note: "Staggers in on first appearance: 0.04 s apart. With Reduce Motion, a plain crossfade with no stagger. \(selected)."
        ) {
            RecentsStrip(items: items(5)) { selected = "Selected wallpaper \($0 + 1)" }
                .id(replay)
            Button("Replay entrance") { replay += 1 }
        }

        StateSection(
            title: "Fourteen items",
            note: "Scrolls. The stagger stops growing at the eighth item, so the tail arrives together."
        ) {
            RecentsStrip(items: items(14)) { selected = "Selected wallpaper \($0 + 1)" }
                .frame(maxWidth: 520)
                .id(replay)
        }

        StateSection(title: "Inserting later", note: "A new item enters on its own; the strip does not replay its entrance.") {
            RecentsStrip(items: newItems + items(3)) { _ in }
            Button("Insert at the front") { inserted += 1 }
        }

        StateSection(
            title: "Arriving after the strip",
            note: "Recents that load late still stagger: the entrance belongs to the first items the strip is given."
        ) {
            RecentsStrip(items: hasLoaded ? items(6) : []) { _ in }
                .id(replay)
            Button(hasLoaded ? "Unload" : "Load") { hasLoaded.toggle() }
        }

        StateSection(
            title: "No entrance",
            note: "For a strip revealed by a key press, or shown often, such as in the menu-bar popover: already there."
        ) {
            RecentsStrip(items: items(5), entrance: .none) { _ in }
                .id(replay)
        }

        StateSection(title: "Empty", note: "Renders nothing, and takes no space.") {
            RecentsStrip(items: [RecentItem<Int>]()) { _ in }
                .border(.red)
        }
    }
}
