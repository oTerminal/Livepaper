import SwiftUI

/// One poster in a `RecentsStrip`.
public nonisolated struct RecentItem<ID: Hashable>: Identifiable {
    public let id: ID
    public let poster: Image
    public let title: String

    public init(id: ID, poster: Image, title: String) {
        self.id = id
        self.poster = poster
        self.title = title
    }
}

/// How a `RecentsStrip` arrives.
public nonisolated enum RecentsStripEntrance: Sendable {
    /// The first items stagger in. For a strip revealed by a click, now and then.
    case staggered
    /// Already there. For a strip revealed by a key press or a hotkey, or one
    /// that is shown often, such as in the menu-bar popover.
    case none
}

/// A row of recently used posters that scrolls sideways. The first items it is
/// given stagger in, even if they arrive after the strip does; an item inserted
/// later enters on its own with no delay, so the strip never replays its
/// entrance while in use.
public struct RecentsStrip<ID: Hashable>: View {
    @Accessibility private var accessibility
    private let items: [RecentItem<ID>]
    private let entrance: RecentsStripEntrance
    private let onSelect: (ID) -> Void

    /// The items that take part in the staggered entrance: the first non-empty
    /// set the strip sees, so recents that load late still stagger.
    @State private var entranceIDs: Set<ID>?

    public init(items: [RecentItem<ID>], entrance: RecentsStripEntrance = .staggered, onSelect: @escaping (ID) -> Void) {
        self.items = items
        self.entrance = entrance
        self.onSelect = onSelect
        _entranceIDs = State(initialValue: items.isEmpty ? nil : Set(items.map(\.id)))
    }

    public var body: some View {
        let entranceIDs = entranceIDs ?? Set(items.map(\.id))
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.small) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    RecentThumbnail(
                        item: item,
                        entrance: entrance,
                        staggerIndex: entranceIDs.contains(item.id) ? index : nil
                    ) {
                        onSelect(item.id)
                    }
                    // Entering is the thumbnail's own affair; a removed one leaves quicker than it came.
                    .transition(.asymmetric(
                        insertion: .identity,
                        removal: .opacity.animation(accessibility.fade(Motion.exit(Motion.Duration.panel)))
                    ))
                }
            }
            // Neighbours make room for an insertion by moving, not by jumping.
            .animation(accessibility.animation(Motion.Spring.move), value: items.map(\.id))
        }
        .scrollIndicators(.hidden)
        // Room inside the clip for the focus ring and the entrance's rise. The scroll
        // view keeps clipping, so a strip with more items than fit ends at its edge;
        // the margins are taken back outside, so the layout is unchanged.
        .contentMargins(.vertical, Spacing.small, for: .scrollContent)
        .contentMargins(.horizontal, Spacing.tight, for: .scrollContent)
        .padding(.vertical, -Spacing.small)
        .padding(.horizontal, -Spacing.tight)
        .onChange(of: items.isEmpty) { _, isEmpty in
            if !isEmpty, self.entranceIDs == nil {
                self.entranceIDs = Set(items.map(\.id))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Recent Wallpapers", bundle: .module))
        .accessibilityHidden(items.isEmpty)
    }
}

private struct RecentThumbnail<ID: Hashable>: View {
    @Accessibility private var accessibility
    @State private var hasEntered: Bool
    @State private var isHovered = false

    let item: RecentItem<ID>
    /// The item's place in the staggered entrance; `nil` for one inserted later.
    let staggerIndex: Int?
    let action: () -> Void

    init(item: RecentItem<ID>, entrance: RecentsStripEntrance, staggerIndex: Int?, action: @escaping () -> Void) {
        self.item = item
        self.staggerIndex = staggerIndex
        self.action = action
        _hasEntered = State(initialValue: entrance == .none)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        let movesIn = !accessibility.reduceMotion
        Button {
            withoutAnimationIfKeyPress(action)
        } label: {
            Color.clear
                .frame(width: Metrics.size.width, height: Metrics.size.height)
                .overlay {
                    item.poster
                        .resizable()
                        .scaledToFill()
                }
                .overlay {
                    Color.white
                        .opacity(isHovered ? Metrics.hoverWash : 0)
                        .animation(
                            accessibility.fade(isHovered ? Motion.enter(Motion.Duration.hover) : Motion.exit(Motion.Duration.hover)),
                            value: isHovered
                        )
                }
                .clipShape(shape)
                .imageOutline(shape)
                .contentShape(shape)
                .contentShape(.focusEffect, shape)
        }
        .buttonStyle(.press)
        .onHover { isHovered = $0 }
        .opacity(hasEntered ? 1 : 0)
        .offset(y: hasEntered || !movesIn ? 0 : Metrics.entranceRise)
        .scaleEffect(hasEntered || !movesIn ? 1 : Metrics.entranceScale)
        .animation(
            accessibility.animation(Motion.enter(Motion.Duration.panel))
                .delay(accessibility.staggerDelay(forIndex: staggerIndex ?? 0)),
            value: hasEntered
        )
        .onAppear { hasEntered = true }
        .accessibilityLabel(item.title)
        .help(item.title)
    }
}

private nonisolated enum Metrics {
    /// 16:10, and no shorter than the minimum hit area.
    static let size = CGSize(width: 72, height: 45)
    /// Matches the 0.96 the rest of the system enters and presses at.
    static let entranceScale = Motion.enterScale
    /// A small fixed rise, not the item's height.
    static let entranceRise = Spacing.small
    static let hoverWash = 0.12
}
