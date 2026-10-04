import SwiftUI

/// Moves and enlarges a picture behind a frame the shape of the display. Pan is
/// a fraction of the frame and zoom a factor from 1, never points, and both are
/// clamped so the picture always covers the frame.
///
/// The picture follows the pointer with no animation, resisting past its edge.
/// Release settles with `Motion.Spring.momentum`, at the speed it was let go,
/// only if the drag was still moving, and picking it up again mid-flight
/// continues from where it is. Under Reduce Motion nothing is thrown and nothing
/// stretches. Keys pan and zoom without animating.
public struct PanZoomEditor: View {
    @Accessibility private var accessibility
    @Binding private var zoom: CGFloat
    @Binding private var pan: CGSize
    @State private var frameSize = CGSize.zero
    @State private var dragStart: CGSize?
    @State private var zoomStart: CGFloat?
    /// How far past its edge the picture has been pulled, in points, after resistance.
    @State private var overscroll = CGSize.zero
    /// How far past its limits the zoom has been pinched, after resistance.
    @State private var zoomOverscroll: CGFloat = 0
    /// Where the picture is on screen right now, which mid-animation is not where the values say.
    @State private var presented = Presented()

    private let image: Image
    private let imageSize: CGSize
    private let frameAspectRatio: CGFloat
    private let focalPoint: UnitPoint

    public init(
        image: Image,
        imageSize: CGSize,
        frameAspectRatio: CGFloat,
        zoom: Binding<CGFloat>,
        pan: Binding<CGSize>,
        focalPoint: UnitPoint = .center
    ) {
        self.image = image
        self.imageSize = imageSize
        self.frameAspectRatio = frameAspectRatio
        self.focalPoint = focalPoint
        _zoom = zoom
        _pan = pan
    }

    public var body: some View {
        VStack(spacing: Spacing.medium) {
            GeometryReader { geometry in
                frame(of: geometry.size)
            }
            .aspectRatio(frameAspectRatio, contentMode: .fit)
            .onGeometryChange(for: CGSize.self, of: \.size) { frameSize = $0 }
            zoomControl
        }
    }

    private func frame(of size: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
        // Laid out once at zoom 1, then moved and enlarged by transforms only.
        let resting = PanZoomMath.pictureRect(source: imageSize, frame: size, zoom: 1, pan: .zero, focalPoint: focalPoint)

        return image
            .resizable()
            .frame(width: resting.width, height: resting.height)
            .modifier(
                PictureTransform(
                    pan: pan,
                    overscroll: overscroll,
                    zoom: PanZoomMath.clampedZoom(zoom) + zoomOverscroll,
                    source: imageSize,
                    frame: size,
                    focalPoint: focalPoint,
                    presented: presented
                )
            )
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipShape(shape)
            .imageOutline(shape)
            .contentShape([.interaction, .focusEffect], shape)
            .gesture(drag(in: size))
            .gesture(magnify(in: size))
            .focusable()
            .onMoveCommand { move($0, in: size) }
            .onKeyPress(characters: CharacterSet(charactersIn: "+=-")) { press in
                withoutAnimation { setZoom(zoom + (press.characters == "-" ? -Metrics.zoomStep : Metrics.zoomStep), in: size) }
                return .handled
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Position and zoom", bundle: .module))
            .accessibilityValue(accessibilityValue)
            .accessibilityAdjustableAction { direction in
                withoutAnimation { setZoom(zoom + (direction == .increment ? Metrics.zoomStep : -Metrics.zoomStep), in: size) }
            }
            .accessibilityAction(named: Text("Move left", bundle: .module)) { move(.left, in: size) }
            .accessibilityAction(named: Text("Move right", bundle: .module)) { move(.right, in: size) }
            .accessibilityAction(named: Text("Move up", bundle: .module)) { move(.up, in: size) }
            .accessibilityAction(named: Text("Move down", bundle: .module)) { move(.down, in: size) }
    }

    private var zoomControl: some View {
        HStack(spacing: Spacing.small) {
            Image(systemName: "minus.magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            // Zooming out can leave less room to pan, so the slider pulls pan back as it goes.
            Slider(value: Binding(get: { zoom }, set: { setZoom($0, in: frameSize) }), in: PanZoomMath.zoomRange) {
                Text("Zoom", bundle: .module)
            }
            .labelsHidden()
            .accessibilityValue(zoomText)
            Image(systemName: "plus.magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            zoomText
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: Metrics.readoutWidth, alignment: .trailing)
                // The slider already speaks this value.
                .accessibilityHidden(true)
            // The same compact button as StatusLine's Restart: a 40 pt target in a
            // row of 40 pt controls. A click animates; Space or Return on the focused
            // button does not, and under Reduce Motion the picture jumps rather than slides.
            CompactTextButton(title: Text("Reset", bundle: .module)) {
                if accessibility.reduceMotion {
                    withoutAnimation(reset)
                } else {
                    withoutAnimationIfKeyPress {
                        withAnimation(accessibility.animation(Motion.Spring.move), reset)
                    }
                }
            }
            .disabled(zoom == 1 && pan == .zero)
        }
        .font(.callout)
    }

    private func reset() {
        zoom = 1
        pan = .zero
    }

    private var zoomText: Text {
        Text("\(Double(PanZoomMath.clampedZoom(zoom)), format: Metrics.onePlace)×", bundle: .module)
    }

    private var accessibilityValue: Text {
        let factor = Double(PanZoomMath.clampedZoom(zoom))
        let across = Int((pan.width * 100).rounded())
        let down = Int((pan.height * 100).rounded())
        return Text(
            "Zoom \(factor, format: Metrics.onePlace), moved \(across) percent across and \(down) percent down",
            bundle: .module
        )
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = dragStart ?? grabPoint(in: size)
                let wanted = PanZoomMath.pan(start, movedBy: value.translation, frame: size)
                let allowed = clamped(wanted, in: size)
                withoutAnimation {
                    dragStart = start
                    pan = allowed
                    overscroll = resisted(
                        CGSize(width: (wanted.width - allowed.width) * size.width, height: (wanted.height - allowed.height) * size.height)
                    )
                }
            }
            .onEnded { value in
                let start = dragStart ?? pan
                dragStart = nil
                let speed = hypot(value.velocity.width, value.velocity.height)
                let carriedVelocity = speed > Metrics.flickVelocity && !accessibility.reduceMotion
                guard carriedVelocity || overscroll != .zero else { return }

                var landing = pan
                if carriedVelocity {
                    // A flick carries the picture a little way on, not the whole of the projected throw.
                    let thrown = CGSize(
                        width: value.translation.width
                            + (value.predictedEndTranslation.width - value.translation.width) * Metrics.throwFraction,
                        height: value.translation.height
                            + (value.predictedEndTranslation.height - value.translation.height) * Metrics.throwFraction
                    )
                    landing = clamped(PanZoomMath.pan(start, movedBy: thrown, frame: size), in: size)
                }
                // Bounce only when the gesture was still moving, and then from the
                // pointer's speed; otherwise just come to rest.
                let distance = hypot((landing.width - pan.width) * size.width, (landing.height - pan.height) * size.height)
                    + hypot(overscroll.width, overscroll.height)
                let spring = carriedVelocity
                    ? Motion.Spring.momentum(initialVelocity: distance > 0 ? speed / distance : 0)
                    : Motion.Spring.ui
                withAnimation(accessibility.animation(spring)) {
                    overscroll = .zero
                    pan = landing
                }
            }
    }

    /// Where a new drag starts from: where the picture is on screen. Grabbed
    /// mid-throw or mid-return that is not where `pan` says, and starting from
    /// `pan` would make the picture jump to its target.
    private func grabPoint(in size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return pan }
        let pulled = CGSize(
            width: unrubberband(offset: presented.overscroll.width, limit: Metrics.overscrollLimit),
            height: unrubberband(offset: presented.overscroll.height, limit: Metrics.overscrollLimit)
        )
        return CGSize(
            width: presented.pan.width + pulled.width / size.width,
            height: presented.pan.height + pulled.height / size.height
        )
    }

    /// Resistance past the edge; under Reduce Motion a plain stop, with nothing to spring back.
    private func resisted(_ overshoot: CGSize) -> CGSize {
        guard !accessibility.reduceMotion else { return .zero }
        return CGSize(
            width: rubberband(offset: overshoot.width, limit: Metrics.overscrollLimit),
            height: rubberband(offset: overshoot.height, limit: Metrics.overscrollLimit)
        )
    }

    private func magnify(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomStart ?? zoom
                let wanted = start * value.magnification
                withoutAnimation {
                    zoomStart = start
                    setZoom(wanted, in: size)
                    // The limits give a little, like the edges do.
                    zoomOverscroll = accessibility.reduceMotion
                        ? 0
                        : rubberband(offset: wanted - PanZoomMath.clampedZoom(wanted), limit: Metrics.zoomOverscrollLimit)
                }
            }
            .onEnded { _ in
                zoomStart = nil
                guard zoomOverscroll != 0 else { return }
                withAnimation(accessibility.animation(Motion.Spring.ui)) { zoomOverscroll = 0 }
            }
    }

    private func move(_ direction: MoveCommandDirection, in size: CGSize) {
        let step: CGSize = switch direction {
        case .left: CGSize(width: -Metrics.panStep, height: 0)
        case .right: CGSize(width: Metrics.panStep, height: 0)
        case .up: CGSize(width: 0, height: -Metrics.panStep)
        case .down: CGSize(width: 0, height: Metrics.panStep)
        @unknown default: .zero
        }
        withoutAnimation {
            pan = clamped(CGSize(width: pan.width + step.width, height: pan.height + step.height), in: size)
        }
    }

    private func setZoom(_ newZoom: CGFloat, in size: CGSize) {
        zoom = PanZoomMath.clampedZoom(newZoom)
        pan = clamped(pan, in: size)
    }

    private func clamped(_ pan: CGSize, in size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return pan }
        return PanZoomMath.clampedPan(pan, source: imageSize, frame: size, zoom: zoom, focalPoint: focalPoint)
    }

    private nonisolated enum Metrics {
        /// Points per second below which a release counts as placed, not thrown.
        static let flickVelocity: CGFloat = 300
        static let throwFraction: CGFloat = 0.25
        /// The furthest the picture can be pulled past its edge.
        static let overscrollLimit: CGFloat = 60
        /// The furthest a pinch can push the zoom past its limits.
        static let zoomOverscrollLimit: CGFloat = 0.25
        static let panStep: CGFloat = 0.02
        static let zoomStep: CGFloat = 0.1
        static let readoutWidth: CGFloat = 40
        static let onePlace = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
    }
}

/// The in-flight pan and overscroll, written as SwiftUI interpolates them.
private final class Presented {
    var pan = CGSize.zero
    var overscroll = CGSize.zero
}

/// Places the picture with transforms only. It is `Animatable` so that the
/// values SwiftUI is showing mid-animation can be read back by the next drag.
private struct PictureTransform: ViewModifier, Animatable {
    var pan: CGSize
    var overscroll: CGSize
    var zoom: CGFloat
    let source: CGSize
    let frame: CGSize
    let focalPoint: UnitPoint
    let presented: Presented

    typealias Pair = AnimatablePair<CGFloat, CGFloat>

    nonisolated var animatableData: AnimatablePair<AnimatablePair<Pair, Pair>, CGFloat> {
        get {
            AnimatablePair(
                AnimatablePair(Pair(pan.width, pan.height), Pair(overscroll.width, overscroll.height)),
                zoom
            )
        }
        set {
            pan = CGSize(width: newValue.first.first.first, height: newValue.first.first.second)
            overscroll = CGSize(width: newValue.first.second.first, height: newValue.first.second.second)
            zoom = newValue.second
        }
    }

    func body(content: Content) -> some View {
        let placed = PanZoomMath.pictureRect(source: source, frame: frame, zoom: zoom, pan: pan, focalPoint: focalPoint)
        // `placed` is sized at the clamped zoom. A pinch past the limits scales a
        // little further, about the middle of that rectangle.
        let clampedZoom = PanZoomMath.clampedZoom(zoom)
        let stretch = zoom / clampedZoom
        let inset = CGSize(width: placed.width * (1 - stretch) / 2, height: placed.height * (1 - stretch) / 2)
        presented.pan = pan
        presented.overscroll = overscroll
        return content
            .scaleEffect(max(zoom, 0.01), anchor: .topLeading)
            .offset(x: placed.minX + inset.width + overscroll.width, y: placed.minY + inset.height + overscroll.height)
    }
}
