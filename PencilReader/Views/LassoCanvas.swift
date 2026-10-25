import SwiftUI
import UIKit

/// Transparent layer that turns Apple Pencil strokes into lasso selections.
/// Finger touches never draw (unless enabled for the simulator): a tap
/// closes the panel, a horizontal swipe turns the page, a swipe down exits,
/// a pinch or a double tap zooms. While zoomed, dragging moves the page
/// instead of swiping.
struct LassoCanvas: UIViewRepresentable {
    var allowsFinger: Bool
    var isZoomed: Bool
    var onStroke: ([CGPoint]) -> Void
    var onTap: () -> Void
    var onSwipe: (UISwipeGestureRecognizer.Direction) -> Void
    /// Incremental scale factor around a point.
    var onZoom: (CGFloat, CGPoint) -> Void
    var onZoomEnded: () -> Void
    /// Incremental translation.
    var onPan: (CGSize) -> Void
    var onDoubleTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> LassoCanvasView { LassoCanvasView() }

    func updateUIView(_ view: LassoCanvasView, context: Context) {
        view.allowsFinger = allowsFinger
        view.isZoomed = isZoomed
        view.onStroke = onStroke
        view.onTap = onTap
        view.onSwipe = onSwipe
        view.onZoom = onZoom
        view.onZoomEnded = onZoomEnded
        view.onPan = onPan
        view.onDoubleTap = onDoubleTap
    }
}

final class LassoCanvasView: UIView, UIGestureRecognizerDelegate {
    var allowsFinger = false {
        didSet { updateGestures() }
    }
    var isZoomed = false {
        didSet { updateGestures() }
    }
    var onStroke: (([CGPoint]) -> Void)?
    var onTap: (() -> Void)?
    var onSwipe: ((UISwipeGestureRecognizer.Direction) -> Void)?
    var onZoom: ((CGFloat, CGPoint) -> Void)?
    var onZoomEnded: (() -> Void)?
    var onPan: ((CGSize) -> Void)?
    var onDoubleTap: ((CGPoint) -> Void)?

    private var points: [CGPoint] = []
    private var activeTouch: UITouch?
    private let strokeLayer = CAShapeLayer()
    private var swipes: [UISwipeGestureRecognizer] = []
    private let pan = UIPanGestureRecognizer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = false

        strokeLayer.strokeColor = UIColor.systemOrange.cgColor
        strokeLayer.fillColor = UIColor.systemOrange.withAlphaComponent(0.08).cgColor
        strokeLayer.lineWidth = 3
        strokeLayer.lineCap = .round
        strokeLayer.lineJoin = .round
        layer.addSublayer(strokeLayer)

        let fingers = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        for direction in [UISwipeGestureRecognizer.Direction.left, .right, .down] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            swipe.direction = direction
            swipe.allowedTouchTypes = fingers
            addGestureRecognizer(swipe)
            swipes.append(swipe)
        }
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.allowedTouchTypes = fingers
        addGestureRecognizer(doubleTap)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.allowedTouchTypes = fingers
        tap.require(toFail: doubleTap)
        addGestureRecognizer(tap)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.allowedTouchTypes = fingers
        pinch.delegate = self
        addGestureRecognizer(pinch)
        pan.addTarget(self, action: #selector(handlePan(_:)))
        pan.allowedTouchTypes = fingers
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        addGestureRecognizer(pan)
        updateGestures()
    }

    private func updateGestures() {
        swipes.forEach { $0.isEnabled = !allowsFinger && !isZoomed }
        pan.isEnabled = isZoomed
        // With finger drawing on, one finger draws and two move the page.
        pan.minimumNumberOfTouches = allowsFinger ? 2 : 1
    }

    /// Pinch and drag together, so the page follows the fingers while zooming.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        (gestureRecognizer is UIPinchGestureRecognizer && other == pan)
            || (gestureRecognizer == pan && other is UIPinchGestureRecognizer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func draws(_ touch: UITouch) -> Bool {
        touch.type == .pencil || (allowsFinger && touch.type == .direct)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first(where: draws) else {
            return super.touchesBegan(touches, with: event)
        }
        activeTouch = touch
        points = [touch.location(in: self)]
        strokeLayer.removeAllAnimations()
        strokeLayer.opacity = 1
        updatePath()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else {
            return super.touchesMoved(touches, with: event)
        }
        for sample in event?.coalescedTouches(for: touch) ?? [touch] {
            points.append(sample.location(in: self))
        }
        updatePath()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else {
            return super.touchesEnded(touches, with: event)
        }
        activeTouch = nil
        let stroke = points
        points = []
        fadeOut()
        onStroke?(stroke)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else {
            return super.touchesCancelled(touches, with: event)
        }
        activeTouch = nil
        points = []
        strokeLayer.path = nil
    }

    private func updatePath() {
        let path = UIBezierPath()
        guard let first = points.first else { return }
        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        strokeLayer.path = path.cgPath
    }

    private func fadeOut() {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.beginTime = CACurrentMediaTime() + 0.4
        fade.duration = 0.4
        fade.fillMode = .backwards
        strokeLayer.opacity = 0
        strokeLayer.add(fade, forKey: "fade")
    }

    @objc private func handleSwipe(_ swipe: UISwipeGestureRecognizer) { onSwipe?(swipe.direction) }
    @objc private func handleTap() { onTap?() }
    @objc private func handleDoubleTap(_ tap: UITapGestureRecognizer) { onDoubleTap?(tap.location(in: self)) }

    @objc private func handlePinch(_ pinch: UIPinchGestureRecognizer) {
        switch pinch.state {
        case .changed:
            onZoom?(pinch.scale, pinch.location(in: self))
            pinch.scale = 1
        case .ended, .cancelled:
            onZoomEnded?()
        default:
            break
        }
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .changed else { return }
        let t = pan.translation(in: self)
        onPan?(CGSize(width: t.x, height: t.y))
        pan.setTranslation(.zero, in: self)
    }
}
