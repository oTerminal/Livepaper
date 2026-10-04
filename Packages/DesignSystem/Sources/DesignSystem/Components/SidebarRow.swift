import SwiftUI

/// A row of the sidebar. It sits on the sidebar's glass, so it is never glass
/// itself: selection and hover are plain fills. The selection fill does not
/// animate, because arrow keys move it; only the hover fill does.
public struct SidebarRow: View {
    @Accessibility private var accessibility
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    private let title: String
    private let systemImage: String
    private let badge: String?
    private let isSelected: Bool
    private let action: () -> Void

    public init(
        title: String,
        systemImage: String,
        badge: String? = nil,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.badge = badge
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.small) {
                // Outline by default, fill marks the active row.
                Image(systemName: systemImage)
                    .symbolVariant(isSelected ? .fill : .none)
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .frame(width: Metrics.iconSlot)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Spacing.small)
                if let badge {
                    Text(badge)
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .layoutPriority(1)
                }
            }
            // No part of the row animates with the selection: arrow keys move it,
            // and a caller's `withAnimation` must not leak in.
            .animation(nil, value: isSelected)
            .opacity(isEnabled ? 1 : Metrics.disabledOpacity)
            .padding(.horizontal, Spacing.small)
            .frame(maxWidth: .infinity, minHeight: Spacing.minimumHitArea - 2 * Spacing.hairline, alignment: .leading)
            .background { fills }
            // The fill is inset so neighbouring fills never touch, but the hit
            // area is the full 40 pt and neighbouring rows' areas meet exactly.
            .padding(.vertical, Spacing.hairline)
            .contentShape(.rect)
            .contentShape(.focusEffect, RoundedRectangle(cornerRadius: Radius.control, style: .continuous).inset(by: Spacing.hairline))
        }
        // A sidebar row that shrinks under the pointer distracts: it dims instead.
        .buttonStyle(PressButtonStyle(isStatic: true))
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        // "Playlists, 3", not "3, Playlists": VoiceOver speaks a value before the label.
        .accessibilityLabel(Text(verbatim: badge.map { "\(title), \($0)" } ?? title))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        // The element made above is not the button's, so it has no press of its own.
        .accessibilityAction {
            if isEnabled { action() }
        }
    }

    private var fills: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        let showsHover = isHovered && !isSelected && isEnabled
        return ZStack {
            shape
                .fill(.quinary)
                .opacity(showsHover ? 1 : 0)
                .animation(
                    accessibility.fade(isHovered ? Motion.enter(Motion.Duration.hover) : Motion.exit(Motion.Duration.hover)),
                    value: isHovered
                )
            shape
                .fill(Color.accentColor.opacity(accessibility.increaseContrast ? 0.32 : 0.18))
                .opacity(isSelected ? 1 : 0)
                // Even if the caller changes the selection inside `withAnimation`.
                .animation(nil, value: isSelected)
        }
    }
}

/// One entry of a `SidebarRowGroup`.
public nonisolated struct SidebarRowItem<ID: Hashable>: Identifiable {
    public let id: ID
    public let title: String
    public let systemImage: String
    public let badge: String?

    public init(id: ID, title: String, systemImage: String, badge: String? = nil) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.badge = badge
    }
}

extension SidebarRowItem: Sendable where ID: Sendable {}

/// A column of sidebar rows with one selection. It is a single tab stop, like a
/// native list: the up and down arrows move the selection, without animation.
/// Each row can have a context menu of its own, for the row under the pointer.
public struct SidebarRowGroup<ID: Hashable, RowMenu: View>: View {
    @Binding private var selection: ID
    private let label: String
    private let items: [SidebarRowItem<ID>]
    private let rowMenu: (ID) -> RowMenu

    /// `label` names the group for VoiceOver, such as "Library". `contextMenu`
    /// is a row's menu, given the row's identifier.
    public init(
        _ label: String,
        selection: Binding<ID>,
        items: [SidebarRowItem<ID>],
        @ViewBuilder contextMenu: @escaping (ID) -> RowMenu
    ) {
        self.label = label
        self.items = items
        rowMenu = contextMenu
        _selection = selection
    }

    public var body: some View {
        // No spacing: the rows' hit areas meet exactly.
        VStack(spacing: 0) {
            ForEach(items) { item in
                SidebarRow(
                    title: item.title,
                    systemImage: item.systemImage,
                    badge: item.badge,
                    isSelected: item.id == selection
                ) {
                    selection = item.id
                }
                .focusable(false)
                .contextMenu { rowMenu(item.id) }
            }
        }
        .background {
            // The tab stop. A focusable view's ring is the union of the focus shapes
            // of everything inside it, which for a stack of rows is a ring around
            // every row. Beside the rows instead of around them, it has one shape.
            Color.clear
                .focusable()
                .contentShape(.focusEffect, RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .onMoveCommand(perform: move)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func move(_ direction: MoveCommandDirection) {
        guard let index = items.firstIndex(where: { $0.id == selection }) else { return }
        let next: Int
        switch direction {
        case .up: next = index - 1
        case .down: next = index + 1
        default: return
        }
        guard items.indices.contains(next) else { return }
        withoutAnimation { selection = items[next].id }
    }
}

extension SidebarRowGroup where RowMenu == EmptyView {
    /// A group whose rows have no context menu.
    public init(_ label: String, selection: Binding<ID>, items: [SidebarRowItem<ID>]) {
        self.init(label, selection: selection, items: items) { _ in EmptyView() }
    }
}

private nonisolated enum Metrics {
    /// Symbols differ in width; a fixed slot keeps every title on one edge.
    static let iconSlot: CGFloat = 20
    static let disabledOpacity = 0.4
}
