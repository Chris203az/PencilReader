import PencilKit
import ReaderCore
import UIKit

/// Reshaping the clean shapes on the page, as in GoodNotes. A finger tap on a shape's line shows its
/// grips: a line's ends, a rectangle's corners and sides, a circle's or an ellipse's axes, a polygon's
/// corners, an arc's ends and middle, a curve's points. Dragging a grip changes the shape and dragging
/// its line moves it; the line keeps its width, since the stroke is drawn again from the shape.
/// Each change is one step of Annulla; a tap elsewhere, writing or Annulla lets the shape go.
@MainActor
final class ShapeEditor: NSObject {
    private unowned let canvas: NotebookCanvasView
    private unowned let host: UIView

    private let gripLayer = CAShapeLayer()
    /// The shape as it is being dragged, drawn in its ink while its stroke is off the page.
    private let previewLayer = CAShapeLayer()

    private let tap = UITapGestureRecognizer()
    private let pan = UIPanGestureRecognizer()

    /// The stroke being reshaped, where it is in the drawing, and its shape on the page.
    private struct Editing {
        var index: Int
        var stroke: PKStroke
        var shape: InkShape
    }

    private enum Drag {
        case grip(Int)
        case move(start: CGPoint)
    }

    private var editing: Editing?
    private var drag: Drag?
    private var pending: Drag?
    private var dragged: InkShape?
    /// The drawing before the stroke was taken off it to be dragged.
    private var lifted: PKDrawing?
    private var isChangingDrawing = false

    /// On screen, whatever the zoom.
    private static let gripRadius: CGFloat = 7
    private static let gripReach: CGFloat = 26
    private static let lineReach: CGFloat = 14

    /// Off while the lasso is in hand: then a tap belongs to the lasso.
    var isEnabled = true {
        didSet {
            tap.isEnabled = isEnabled
            pan.isEnabled = isEnabled
            if !isEnabled { deselect() }
        }
    }

    /// True when a finger went down on the shape's grips or line, so the page must not scroll with it.
    var holdsTouch: Bool { pending != nil || drag != nil }

    init(canvas: NotebookCanvasView, host: UIView) {
        self.canvas = canvas
        self.host = host
        super.init()
        previewLayer.fillColor = nil
        previewLayer.lineCap = .round
        previewLayer.lineJoin = .round
        host.layer.addSublayer(previewLayer)
        gripLayer.fillColor = UIColor.white.cgColor
        gripLayer.strokeColor = UIColor.tintColor.cgColor
        gripLayer.lineWidth = 2
        host.layer.addSublayer(gripLayer)

        let fingers = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        tap.addTarget(self, action: #selector(tapped(_:)))
        tap.allowedTouchTypes = fingers
        tap.require(toFail: canvas.doubleTap)
        pan.addTarget(self, action: #selector(panned(_:)))
        pan.allowedTouchTypes = fingers
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        canvas.addGestureRecognizer(tap)
        canvas.addGestureRecognizer(pan)
    }

    // MARK: Drawing on screen

    func redraw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let editing else {
            gripLayer.path = nil
            previewLayer.path = nil
            return
        }
        let shape = dragged ?? editing.shape
        let grips = UIBezierPath()
        for grip in shape.grips {
            let center = screenPoint(grip)
            grips.move(to: CGPoint(x: center.x + Self.gripRadius, y: center.y))
            grips.addArc(withCenter: center, radius: Self.gripRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        }
        gripLayer.path = grips.cgPath
        guard lifted != nil else {
            previewLayer.path = nil
            return
        }
        let line = UIBezierPath()
        for (i, point) in shape.outline(spacing: 3).enumerated() {
            if i == 0 { line.move(to: screenPoint(point)) } else { line.addLine(to: screenPoint(point)) }
        }
        previewLayer.path = line.cgPath
    }

    private func screenPoint(_ point: CGPoint) -> CGPoint {
        let zoom = canvas.zoomScale
        return canvas.convert(CGPoint(x: point.x * zoom, y: point.y * zoom), to: host)
    }

    // MARK: Gestures

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let point = canvas.drawingPoint(gesture.location(in: canvas))
        let reach = Self.lineReach / canvas.zoomScale
        let strokes = canvas.drawing.strokes
        let shapes = canvas.notebook?.shapes ?? [:]
        // The top one, when shapes cross.
        for index in strokes.indices.reversed() {
            let stroke = strokes[index]
            guard let stored = shapes[stroke.randomSeed] else { continue }
            let shape = stored.applying(stroke.transform)
            if shape.outlineDistance(to: point) <= reach {
                editing = Editing(index: index, stroke: stroke, shape: shape)
                redraw()
                return
            }
        }
        deselect()
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        let point = canvas.drawingPoint(gesture.location(in: canvas))
        switch gesture.state {
        case .began:
            drag = pending
            pending = nil
            lift()
            update(to: point)
        case .changed:
            update(to: point)
        case .ended:
            update(to: point)
            finishDrag()
        default:
            cancelDrag()
        }
    }

    private func update(to point: CGPoint) {
        guard let editing, let drag else { return }
        switch drag {
        case .grip(let index): dragged = editing.shape.reshaped(grip: index, to: point)
        case .move(let start): dragged = editing.shape.moved(by: CGPoint(x: point.x - start.x, y: point.y - start.y))
        }
        redraw()
    }

    /// What a finger going down at `point` would take: a grip, the shape's line, or nothing.
    private func grab(at point: CGPoint) -> Drag? {
        guard let shape = editing?.shape else { return nil }
        let zoom = canvas.zoomScale
        let distances = shape.grips.map { hypot($0.x - point.x, $0.y - point.y) }
        if let nearest = distances.indices.min(by: { distances[$0] < distances[$1] }),
           distances[nearest] <= Self.gripReach / zoom {
            return .grip(nearest)
        }
        return shape.outlineDistance(to: point) <= Self.gripReach / zoom ? .move(start: point) : nil
    }

    // MARK: Changing the drawing

    /// Takes the stroke off the page while it is dragged; the preview draws the shape instead.
    private func lift() {
        guard let editing, canvas.drawing.strokes.indices.contains(editing.index) else { return }
        let before = canvas.drawing
        lifted = before
        let ink = editing.stroke.ink
        previewLayer.strokeColor = PKInkingTool.convertColor(ink.color, from: .light,
                                                             to: canvas.traitCollection.userInterfaceStyle).cgColor
        let sample = editing.stroke.path.isEmpty ? nil : editing.stroke.path[editing.stroke.path.count / 2]
        let t = editing.stroke.transform
        previewLayer.lineWidth = (sample?.size.width ?? 2) * abs(t.a * t.d - t.b * t.c).squareRoot() * canvas.zoomScale
        var without = before
        without.strokes.remove(at: editing.index)
        isChangingDrawing = true
        canvas.drawing = without
        isChangingDrawing = false
    }

    private func finishDrag() {
        defer {
            drag = nil
            dragged = nil
            redraw()
        }
        guard var editing, let before = lifted, let shape = dragged,
              let stroke = canvas.shapeStroke(shape, like: editing.stroke) else {
            cancelDrag()
            return
        }
        var drawing = before
        drawing.strokes[editing.index] = stroke
        lifted = nil
        editing.stroke = stroke
        editing.shape = shape
        self.editing = editing
        isChangingDrawing = true
        canvas.setDrawingUndoably(drawing, undoingTo: before)
        isChangingDrawing = false
    }

    private func cancelDrag() {
        if let before = lifted {
            lifted = nil
            isChangingDrawing = true
            canvas.drawing = before
            isChangingDrawing = false
        }
        drag = nil
        pending = nil
        dragged = nil
        redraw()
    }

    func deselect() {
        guard editing != nil else { return }
        if lifted != nil { cancelDrag() }
        editing = nil
        redraw()
    }

    /// Writing, Annulla or another page: the shape being edited may not be where it was.
    func drawingChanged() {
        if !isChangingDrawing { deselect() }
    }
}

extension ShapeEditor: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === pan else { return true }
        if pan.state == .possible, drag == nil { pending = nil }
        pending = grab(at: canvas.drawingPoint(touch.location(in: canvas)))
        return pending != nil
    }
}
