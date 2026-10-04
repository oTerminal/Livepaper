import DesignSystem
import SwiftUI

struct WallpaperTilePage: View {
    @State private var selection: Int? = 1
    private let posters = (0..<8).map { SamplePicture.image(seed: $0) }
    private let titles = ["Harbour at Dusk", "Slow Rain", "Paper Lanterns", "Northern Line", "Tide Pool", "Ember", "Glasshouse", "Overpass"]

    var body: some View {
        StateSection(
            title: "Grid",
            note: """
            Rest the pointer on a tile for 200 ms and it goes live. Only one tile is live at a time. \
            With Reduce Motion, posters stay posters.
            """
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: Spacing.large)], spacing: Spacing.large) {
                ForEach(posters.indices, id: \.self) { index in
                    WallpaperTile(
                        id: index,
                        poster: posters[index],
                        title: titles[index],
                        isSelected: selection == index,
                        isFavourite: index == 2
                    ) {
                        selection = index
                    } livePreview: {
                        FakeLivePreview(seed: index)
                    }
                }
            }
            .livePreviewScope()
        }

        StateSection(
            title: "Live",
            note: """
            What a tile shows once the pointer has rested on it: the preview crossfades in over the poster. This one is \
            held live; move the pointer over it and away and it goes back to its poster.
            """
        ) {
            LiveTile(poster: posters[7], title: "Overpass")
        }

        if !Self.photos.isEmpty {
            StateSection(
                title: "Real posters",
                note: "Photographs from this Mac's stock desktop pictures, for judging the outline with and without Increase Contrast."
            ) {
                HStack(alignment: .top, spacing: Spacing.large) {
                    ForEach(Self.photos.indices, id: \.self) { index in
                        WallpaperTile(id: "photo-\(index)", poster: Self.photos[index].image, title: Self.photos[index].title) {
                        } livePreview: {
                            EmptyView()
                        }
                    }
                }
                .frame(maxWidth: 820)
            }
        }

        StateSection(title: "States", note: "Poster, selected, favourite, and a long title.") {
            HStack(alignment: .top, spacing: Spacing.large) {
                WallpaperTile(id: "poster", poster: posters[3], title: "Poster") {} livePreview: { EmptyView() }
                WallpaperTile(id: "selected", poster: posters[4], title: "Selected", isSelected: true) {} livePreview: { EmptyView() }
                WallpaperTile(id: "favourite", poster: posters[5], title: "Favourite", isFavourite: true) {} livePreview: { EmptyView() }
                WallpaperTile(id: "long", poster: posters[6], title: "A title far too long to fit under one small tile") {} livePreview: {
                    EmptyView()
                }
            }
            .frame(maxWidth: 820)
        }
    }
}

extension WallpaperTilePage {
    /// Stock desktop pictures, where this Mac has them: light and dark edges, sky, and near-white.
    fileprivate static let photos: [(title: String, image: Image)] = {
        let names = ["Catalina Light", "Big Sur Night Grasses", "Catalina Clouds", "Hello Metallic Silver"]
        let folder = URL(fileURLWithPath: "/System/Library/Desktop Pictures/.thumbnails")
        return names.compactMap { name in
            NSImage(contentsOf: folder.appending(path: "\(name).heic")).map { (name, Image(nsImage: $0)) }
        }
    }()
}

/// A tile whose own coordinator was told the pointer arrived and never left.
private struct LiveTile: View {
    @Accessibility private var accessibility
    @State private var coordinator = LivePreviewCoordinator()
    let poster: Image
    let title: String

    var body: some View {
        WallpaperTile(id: "live", poster: poster, title: title) {} livePreview: { FakeLivePreview(seed: 7) }
            .frame(width: 200)
            .environment(coordinator)
            // Like livePreviewScope: no hover autoplay under Reduce Motion.
            .onChange(of: accessibility.reduceMotion, initial: true) { _, reduceMotion in
                coordinator.isEnabled = !reduceMotion
                if !reduceMotion {
                    coordinator.pointerEntered("live")
                }
            }
    }
}

/// Stands in for the video layer the app hands to a tile.
private struct FakeLivePreview: View {
    let seed: Int

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            SamplePicture(seed: seed)
                .hueRotation(.degrees(phase * 40))
                .overlay(alignment: .bottomLeading) {
                    Text("LIVE")
                        .font(.caption2.bold())
                        .padding(.horizontal, Spacing.tight)
                        .background(.red, in: .capsule)
                        .foregroundStyle(.white)
                        .padding(Spacing.small)
                }
        }
    }
}
