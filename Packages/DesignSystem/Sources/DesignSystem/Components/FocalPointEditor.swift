import SwiftUI

/// Picks the part of a picture that stays in view when it is cropped. The value
/// is normalised, (0, 0) top left to (1, 1) bottom right, never points.
///
/// The handle follows the pointer with no animation. Release settles with
/// `Motion.Spring.momentum`, at the speed it was let go, only if the drag was
/// still moving; under Reduce Motion it stays where it was let go. Arrow keys
/// nudge without animating.
public struct FocalPointEditor: View {
    @Accessibility private var accessibility
    @Binding private var focalPoint: UnitPoint
    @State private var isDragging = false
    /// The release spring, so the guides can move with the handle while they fade.
    @State private var throwAnimation: Animation?

    private let image: Image
    private let imageSize: CGSize

    public init(image: Image, imageSize: CGSize, focalPoint: Binding<UnitPoint>) {
        self.image = image
        self.imageSize = imageSize
        _focalPoint = focalPoint
    }

    public var body: some View {
        GeometryReader { geometry in
            let picture = FocalPointMath.pictureRect(source: imageSize, in: geometry.size)
            let position = FocalPointMath.position(of: focalPoint, in: picture)
            let shape = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)

            ZStack(alignment: .topLeading) {
                image
                    .resizable()
                    .frame(width: picture.width, height: picture.height)
                    .overlay { guides(at: position, in: picture) }
                    .clipShape(shape)
                    .imageOutline(shape)
                    .offset(x: picture.minX, y: picture.minY)
                Handle(isPressed: isDragging)
                    .offset(x: position.x - Spacing.minimumHitArea / 2, y: position.y - Spacing.minimumHitArea / 2)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .contentShape(.rect)
            .contentShape(.focusEffect, shape.offset(x: picture.minX, y: picture.minY).size(picture.size))
            .gesture(drag(in: picture))
        }
        .focusable()
        .onMoveCommand(perform: nudge)
        .accessibilityElement()
        .accessibilityLabel(Text("Focal point", bundle: .module))
        .accessibilityValue(
            Text(
                "\(Int((focalPoint.x * 100).rounded())) percent from the left, \(Int((focalPoint.y * 100).rounded())) percent from the top",
                bundle: .module
            )
        )
        .accessibilityAdjustableAction { direction in
            withoutAnimation { focalPoint = FocalPointMath.nudged(focalPoint, dx: direction == .increment ? 5 : -5, dy: 0) }
        }
        .accessibilityAction(named: Text("Move up", bundle: .module)) {
            withoutAnimation { focalPoint = FocalPointMath.nudged(focalPoint, dx: 0, dy: -5) }
        }
        .accessibilityAction(named: Text("Move down", bundle: .module)) {
            withoutAnimation { focalPoint = FocalPointMath.nudged(focalPoint, dx: 0, dy: 5) }
        }
    }

    /// Cross-hairs through the focal point, shown while it is being moved.
    private func guides(at position: CGPoint, in picture: CGRect) -> some View {
        // Two positioned strokes, not a Canvas: a position animates, so on a flick the
        // guides follow the handle's spring as they fade instead of jumping to its landing.
        ZStack {
            GuideStroke(axis: .vertical)
                .frame(width: Metrics.guideWidth, height: picture.height)
                .position(x: position.x - picture.minX, y: picture.height / 2)
            GuideStroke(axis: .horizontal)
                .frame(width: picture.width, height: Metrics.guideWidth)
                .position(x: picture.width / 2, y: position.y - picture.minY)
        }
        .animation(throwAnimation, value: position)
        .frame(width: picture.width, height: picture.height)
        .opacity(isDragging ? 1 : 0)
        // There at once on pointer down; fades once the handle is let go.
        .animation(isDragging ? nil : accessibility.fade(Motion.exit(Motion.Duration.hover)), value: isDragging)
        .allowsHitTesting(false)
    }

    private func drag(in picture: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                withoutAnimation {
                    isDragging = true
                    throwAnimation = nil
                    focalPoint = FocalPointMath.focalPoint(at: value.location, in: picture)
                }
            }
            .onEnded { value in
                isDragging = false
                let speed = hypot(value.velocity.width, value.velocity.height)
                // Reduce Motion drops the movement itself: the handle stays where it was let go.
                guard speed > Metrics.flickVelocity, !accessibility.reduceMotion else { return }
                // A flick carries the handle a little way on, not the whole of the projected throw.
                let landing = CGPoint(
                    x: value.location.x + (value.predictedEndLocation.x - value.location.x) * Metrics.throwFraction,
                    y: value.location.y + (value.predictedEndLocation.y - value.location.y) * Metrics.throwFraction
                )
                // The spring starts at the pointer's speed, so the handle carries on
                // rather than stopping dead and setting off again.
                let distance = hypot(landing.x - value.location.x, landing.y - value.location.y)
                let spring = Motion.Spring.momentum(initialVelocity: distance > 0 ? speed / distance : 0)
                throwAnimation = accessibility.animation(spring)
                withAnimation(accessibility.animation(spring)) {
                    focalPoint = FocalPointMath.focalPoint(at: landing, in: picture)
                }
            }
    }

    private func nudge(_ direction: MoveCommandDirection) {
        let step: (dx: Int, dy: Int) = switch direction {
        case .left: (-1, 0)
        case .right: (1, 0)
        case .up: (0, -1)
        case .down: (0, 1)
        @unknown default: (0, 0)
        }
        withoutAnimation { focalPoint = FocalPointMath.nudged(focalPoint, dx: step.dx, dy: step.dy) }
    }

    /// Dark beneath light, as the handle has its shadow, so the line holds over any picture.
private struct GuideStroke: View {
    let axis: Axis

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.25))
            Rectangle().fill(.white.opacity(0.7))
                .padding(axis == .vertical ? .horizontal : .vertical, 1)
        }
    }
}

private nonisolated enum Metrics {
    static let guideWidth: CGFloat = 3
        /// Points per second below which a release counts as placed, not thrown.
        static let flickVelocity: CGFloat = 300
        static let throwFraction: CGFloat = 0.25
    }
}

/// The ring marking the focal point. Drawn small, with a full-size hit area.
private struct Handle: View {
    @Accessibility private var accessibility
    let isPressed: Bool

    var body: some View {
        Circle()
            .strokeBorder(.white, lineWidth: 2)
            .background(Circle().fill(.white.opacity(0.25)))
            .frame(width: Metrics.diameter, height: Metrics.diameter)
            .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
            .scaleEffect(Press.scale(isPressed: isPressed, isStatic: accessibility.reduceMotion))
            .opacity(Press.opacity(isPressed: isPressed, isStatic: accessibility.reduceMotion))
            .animation(isPressed ? nil : accessibility.fade(Motion.enter(Motion.Duration.press)), value: isPressed)
            .frame(width: Spacing.minimumHitArea, height: Spacing.minimumHitArea)
            .accessibilityHidden(true)
    }

    private nonisolated enum Metrics {
        static let diameter: CGFloat = 24
    }
}
