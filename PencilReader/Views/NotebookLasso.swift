import PencilKit
import ReaderCore
import UIKit

/// The notebook's lasso, as in GoodNotes. PencilKit's own lasso only moves what it takes,
/// so this one is drawn by hand on top of the canvas.
///
/// With the lasso in hand the Pencil draws a dashed loop; the strokes mostly inside it are
/// selected and get a box. Dragging inside the box moves them, a corner resizes them keeping
/// their proportions, a side stretches them one way, the grip above the box turns them.
/// The box works with the Pencil and with a finger; a finger elsewhere still scrolls.
/// While dragging, a picture of the strokes follows; the strokes themselves change on release.
/// A tap in the box shows Copia, Taglia, Duplica, Elimina and Cambia colore, a tap outside lets go,
/// and holding on empty paper offers Incolla. Every change is one step of Annulla.
@MainActor
final class LassoEditor: NSObject {
    private unowned let canvas: NotebookCanvasView
    /// Where the loop and the box are drawn: the sheet that holds the canvas.
    private unowned let host: UIView

    private let loopLayer = CAShapeLayer()
    private let boxLayer = CAShapeLayer()
    private let gripLayer = CAShapeLayer()
    private let pictureLayer = CALayer()
    private lazy var menu = UIEditMenuInteraction(delegate: self)

    private let pan = UIPanGestureRecognizer()
    private let tap = UITapGestureRecognizer()
    private let press = UILongPressGestureRecognizer()

    /// The selected strokes as they were when taken, where they are in the drawing, and the box.
    private struct Selection {
        var indices: [Int]
        var originals: [PKStroke]
        var frame: SelectionFrame
    }

    private enum Drag {
        case loop([CGPoint])
        case move(start: CGPoint, frame: SelectionFrame)
        case resize(SelectionHandle, start: CGPoint, frame: SelectionFrame)
        case rotate(start: CGPoint, frame: SelectionFrame)
    }

    private var selection: Selection?
    private var drag: Drag?
    /// What the touch that went down will do once it moves, decided where it went down.
    private var pending: Drag?
    /// The drawing before the selected strokes were taken off it to be dragged.
    private var lifted: PKDrawing?
    private var pastePoint: CGPoint?
    /// True while this editor changes the drawing: any other change lets the selection go.
    private(set) var isChangingDrawing = false

    /// Strokes copied or cut, ready to be pasted on any page of any book.
    private static var clipboard: [PKStroke] = []

    /// On screen, whatever the zoom.
    private static let gripRadius: CGFloat = 6
    private static let gripReach: CGFloat = 26
    private static let rotationGap: CGFloat = 30
    private static let duplicateOffset: CGFloat = 24

    private static let selectionMenu = "selection" as NSString
    private static let pasteMenu = "paste" as NSString

    /// Whether the lasso is the tool in hand.
    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            if !isActive { deselect() }
            pending = nil
            pan.isEnabled = isActive
            tap.isEnabled = isActive
        }
    }

    /// True when the touch going down belongs to the lasso, so the canvas must not scroll with it.
    var holdsTouch: Bool { pending != nil || drag != nil }

    init(canvas: NotebookCanvasView, host: UIView) {
        self.canvas = canvas
        self.host = host
        super.init()
        for layer in [loopLayer, boxLayer] {
            layer.fillColor = nil
            layer.strokeColor = UIColor.tintColor.cgColor
            layer.lineWidth = 1.5
            layer.lineDashPattern = [6, 4]
            layer.lineJoin = .round
            host.layer.addSublayer(layer)
        }
        loopLayer.fillColor = UIColor.tintColor.withAlphaComponent(0.06).cgColor
        gripLayer.fillColor = UIColor.white.cgColor
        gripLayer.strokeColor = UIColor.tintColor.cgColor
        gripLayer.lineWidth = 1.5
        pictureLayer.anchorPoint = .zero
        pictureLayer.isHidden = true
        host.layer.insertSublayer(pictureLayer, below: loopLayer)
        host.layer.addSublayer(gripLayer)
        host.addInteraction(menu)

        pan.addTarget(self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        pan.isEnabled = false
        tap.addTarget(self, action: #selector(tapped(_:)))
        tap.delegate = self
        tap.isEnabled = false
        press.addTarget(self, action: #selector(pressed(_:)))
        press.minimumPressDuration = 0.5
        press.delegate = self
        for gesture in [pan, tap, press] { canvas.addGestureRecognizer(gesture) }
    }

    // MARK: Drawing on screen

    /// Puts the loop, the box and the dragged picture where the page is now, after a scroll or a zoom.
    func redraw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if case .loop(let points) = drag {
            loopLayer.path = path(through: points, closed: true)
        } else {
            loopLayer.path = nil
        }
        guard let frame = currentFrame else {
            boxLayer.path = nil
            gripLayer.path = nil
            pictureLayer.isHidden = true
            return
        }
        boxLayer.path = path(through: frame.corners, closed: true)
        let gap = Self.rotationGap / canvas.zoomScale
        let grips = UIBezierPath()
        let top = screenPoint(frame.position(of: .top, rotationGap: gap))
        let knob = screenPoint(frame.position(of: .rotate, rotationGap: gap))
        grips.move(to: top)
        grips.addLine(to: knob)
        for handle in SelectionHandle.allCases {
            let center = screenPoint(frame.position(of: handle, rotationGap: gap))
            let radius = handle == .rotate ? Self.gripRadius + 2 : Self.gripRadius
            grips.move(to: CGPoint(x: center.x + radius, y: center.y))
            grips.addArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        }
        gripLayer.path = grips.cgPath
        if lifted != nil, let selection {
            // The picture was drawn from the strokes where they were taken; it moves as the box does.
            let zoom = canvas.zoomScale
            let offset = canvas.convert(CGPoint.zero, to: host)
            pictureLayer.setAffineTransform(
                CGAffineTransform(translationX: selection.frame.original.minX, y: selection.frame.original.minY)
                    .concatenating(frame.transform)
                    .concatenating(CGAffineTransform(scaleX: zoom, y: zoom))
                    .concatenating(CGAffineTransform(translationX: offset.x, y: offset.y)))
            pictureLayer.isHidden = false
        } else {
            pictureLayer.isHidden = true
        }
    }

    /// The box as the drag in progress has it, or as it was left.
    private var currentFrame: SelectionFrame? {
        guard let selection else { return nil }
        switch drag {
        case .move(let start, let frame): return frame.moved(from: start, to: lastPoint ?? start)
        case .resize(let handle, let start, let frame): return frame.resized(handle, from: start, to: lastPoint ?? start)
        case .rotate(let start, let frame): return frame.rotated(from: start, to: lastPoint ?? start)
        case .loop, nil: return selection.frame
        }
    }

    private var lastPoint: CGPoint?

    private func screenPoint(_ point: CGPoint) -> CGPoint {
        let zoom = canvas.zoomScale
        return canvas.convert(CGPoint(x: point.x * zoom, y: point.y * zoom), to: host)
    }

    private func path(through points: [CGPoint], closed: Bool) -> CGPath? {
        guard let first = points.first else { return nil }
        let path = UIBezierPath()
        path.move(to: screenPoint(first))
        for point in points.dropFirst() { path.addLine(to: screenPoint(point)) }
        if closed { path.close() }
        return path.cgPath
    }

    /// The dashes run round the loop and the box, as in GoodNotes.
    private func march(_ layer: CAShapeLayer) {
        guard layer.animation(forKey: "march") == nil else { return }
        let animation = CABasicAnimation(keyPath: "lineDashPhase")
        animation.fromValue = 0
        animation.toValue = -20
        animation.duration = 0.6
        animation.repeatCount = .infinity
        layer.add(animation, forKey: "march")
    }

    // MARK: Gestures

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        let point = canvas.drawingPoint(gesture.location(in: canvas))
        switch gesture.state {
        case .began:
            menu.dismissMenu()
            drag = pending
            pending = nil
            lastPoint = point
            switch drag {
            case .loop(let start):
                deselect()
                drag = .loop(start + [point])
                march(loopLayer)
            case .move, .resize, .rotate:
                lift()
            case nil:
                break
            }
            redraw()
        case .changed:
            lastPoint = point
            if case .loop(let points) = drag { drag = .loop(points + [point]) }
            redraw()
        case .ended:
            lastPoint = point
            finishDrag()
        default:
            cancelDrag()
        }
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let point = canvas.drawingPoint(gesture.location(in: canvas))
        guard let selection else { return }
        if selection.frame.contains(point, slack: Self.gripReach / canvas.zoomScale) {
            showSelectionMenu()
        } else {
            deselect()
        }
    }

    @objc private func pressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, !Self.clipboard.isEmpty else { return }
        let location = gesture.location(in: canvas)
        pastePoint = canvas.drawingPoint(location)
        menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: Self.pasteMenu,
                                                           sourcePoint: canvas.convert(location, to: host)))
    }

    /// What a touch going down at `point` would grab: a grip, the inside of the box, or nothing.
    private func grab(at point: CGPoint) -> Drag? {
        guard let frame = selection?.frame else { return nil }
        let zoom = canvas.zoomScale
        if let handle = frame.handle(at: point, radius: Self.gripReach / zoom, rotationGap: Self.rotationGap / zoom) {
            return handle == .rotate ? .rotate(start: point, frame: frame) : .resize(handle, start: point, frame: frame)
        }
        if frame.contains(point, slack: 4 / zoom) { return .move(start: point, frame: frame) }
        return nil
    }

    private func finishDrag() {
        defer {
            drag = nil
            lastPoint = nil
            loopLayer.removeAnimation(forKey: "march")
            redraw()
        }
        switch drag {
        case .loop(let points):
            select(inside: points)
        case .move, .resize, .rotate:
            guard let frame = currentFrame, let before = lifted, var selection else { return }
            selection.frame = frame
            self.selection = selection
            var drawing = before
            for (index, stroke) in zip(selection.indices, placed(selection)) {
                drawing.strokes[index] = stroke
            }
            lifted = nil
            change(to: drawing, undoingTo: before)
            showSelectionMenu()
        case nil:
            break
        }
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
        lastPoint = nil
        loopLayer.removeAnimation(forKey: "march")
        redraw()
    }

    // MARK: Selection

    private func select(inside loop: [CGPoint]) {
        let strokes = canvas.drawing.strokes
        let points = strokes.map { stroke in
            stroke.path.interpolatedPoints(by: .distance(4)).map { $0.location.applying(stroke.transform) }
        }
        let indices = StrokeLasso.selected(strokes: points, lasso: loop)
        guard !indices.isEmpty else { return }
        select(indices, of: strokes)
        showSelectionMenu()
    }

    private func select(_ indices: [Int], of strokes: [PKStroke]) {
        let originals = indices.map { strokes[$0] }
        let bounds = originals.map(\.renderBounds).reduce(CGRect.null) { $0.union($1) }
        selection = Selection(indices: indices, originals: originals, frame: SelectionFrame(around: bounds.insetBy(dx: -4, dy: -4)))
        march(boxLayer)
        redraw()
    }

    func deselect() {
        guard selection != nil || drag != nil else { return }
        if lifted != nil { cancelDrag() }
        selection = nil
        drag = nil
        menu.dismissMenu()
        boxLayer.removeAnimation(forKey: "march")
        redraw()
    }

    /// The canvas' drawing changed: unless this editor did it (an Annulla, another page), the selection goes.
    func drawingChanged() {
        if !isChangingDrawing { deselect() }
    }

    /// The selected strokes where the box has taken them.
    private func placed(_ selection: Selection) -> [PKStroke] {
        let transform = selection.frame.transform
        return selection.originals.map { stroke in
            var moved = stroke
            moved.transform = stroke.transform.concatenating(transform)
            return moved
        }
    }

    /// Takes the selected strokes off the page while they are dragged; a picture of them follows the box.
    private func lift() {
        guard let selection else { return }
        let before = canvas.drawing
        lifted = before
        var image = UIImage()
        // In the canvas' light or dark look, as the strokes show on it.
        canvas.traitCollection.performAsCurrent {
            image = PKDrawing(strokes: selection.originals).image(from: selection.frame.original,
                                                                  scale: canvas.traitCollection.displayScale * canvas.zoomScale)
        }
        pictureLayer.contents = image.cgImage
        pictureLayer.bounds = CGRect(origin: .zero, size: selection.frame.original.size)
        pictureLayer.position = .zero
        var without = before
        for index in selection.indices.sorted(by: >) { without.strokes.remove(at: index) }
        isChangingDrawing = true
        canvas.drawing = without
        isChangingDrawing = false
    }

    /// One step of Annulla.
    private func change(to drawing: PKDrawing, undoingTo previous: PKDrawing? = nil) {
        isChangingDrawing = true
        canvas.setDrawingUndoably(drawing, undoingTo: previous)
        isChangingDrawing = false
    }

    // MARK: Menu actions

    private func showSelectionMenu() {
        guard let frame = selection?.frame else { return }
        let bottom = frame.corners.map(screenPoint).max { $0.y < $1.y } ?? .zero
        let configuration = UIEditMenuConfiguration(identifier: Self.selectionMenu, sourcePoint: bottom)
        // Below the selection, as asked; UIKit puts it above only when there is no room below.
        configuration.preferredArrowDirection = .up
        menu.presentEditMenu(with: configuration)
    }

    private func copySelection() {
        guard let selection else { return }
        Self.clipboard = placed(selection)
    }

    private func deleteSelection() {
        guard let selection else { return }
        var drawing = canvas.drawing
        for index in selection.indices.sorted(by: >) { drawing.strokes.remove(at: index) }
        change(to: drawing)
        deselect()
    }

    private func duplicate() {
        guard let selection else { return }
        let shift = CGAffineTransform(translationX: Self.duplicateOffset, y: Self.duplicateOffset)
        add(placed(selection).map { stroke in
            var copy = stroke
            copy.transform = stroke.transform.concatenating(shift)
            return copy
        })
    }

    private func paste(at point: CGPoint) {
        let strokes = Self.clipboard
        let bounds = strokes.map(\.renderBounds).reduce(CGRect.null) { $0.union($1) }
        guard !strokes.isEmpty, !bounds.isNull else { return }
        let shift = CGAffineTransform(translationX: point.x - bounds.midX, y: point.y - bounds.midY)
        deselect()
        add(strokes.map { stroke in
            var copy = stroke
            copy.transform = stroke.transform.concatenating(shift)
            return copy
        })
    }

    /// Puts strokes on top of the page and, with the lasso in hand, selects them.
    private func add(_ strokes: [PKStroke]) {
        var drawing = canvas.drawing
        let first = drawing.strokes.count
        drawing.strokes += strokes
        change(to: drawing)
        guard isActive else { return }
        select(Array(first..<drawing.strokes.count), of: drawing.strokes)
        showSelectionMenu()
    }

    private func recolor(_ color: UIColor) {
        guard var selection else { return }
        var drawing = canvas.drawing
        for index in selection.indices {
            let stroke = drawing.strokes[index]
            // Changing only the ink keeps everything else, the seed that marks a shape included.
            var recolored = stroke
            recolored.ink = PKInk(stroke.ink.inkType, color: color)
            drawing.strokes[index] = recolored
        }
        selection.originals = zip(selection.originals, selection.indices).map { original, index in
            var recolored = original
            recolored.ink = drawing.strokes[index].ink
            return recolored
        }
        self.selection = selection
        change(to: drawing)
    }

    /// The colors of the tool bar, for Cambia colore.
    private var palette: [UIColor] {
        canvas.notebook?.tools.state.palette.map(\.uiColor) ?? [.black, .systemBlue, .systemRed]
    }
}

extension LassoEditor: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let point = canvas.drawingPoint(touch.location(in: canvas))
        if gestureRecognizer === pan {
            guard isActive else { return false }
            if pan.state == .possible, drag == nil { pending = nil }
            if let grabbed = grab(at: point) {
                pending = grabbed
            } else if touch.type == .pencil {
                pending = .loop([point])
            }
            return pending != nil
        }
        if gestureRecognizer === tap { return isActive }
        if gestureRecognizer === press {
            // A finger anywhere; the Pencil only with the lasso, since otherwise it writes.
            guard !Self.clipboard.isEmpty, touch.type == .direct || isActive else { return false }
            return grab(at: point) == nil
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // The long press waits alongside the scrolling; the lasso's drag keeps its touch to itself.
        gestureRecognizer === press
    }
}

extension LassoEditor: UIEditMenuInteractionDelegate {
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
                             suggestedActions: [UIMenuElement]) -> UIMenu? {
        if configuration.identifier as? NSString == Self.pasteMenu {
            let point = pastePoint
            return UIMenu(children: [UIAction(title: String(localized: "Incolla"), image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in
                if let point { self?.paste(at: point) }
            }])
        }
        guard selection != nil else { return nil }
        let colors = palette.enumerated().map { index, color in
            UIAction(title: String(localized: "Colore \(index + 1)"),
                     image: UIImage(systemName: "circle.fill")?.withTintColor(color, renderingMode: .alwaysOriginal)) { [weak self] _ in
                self?.recolor(color)
            }
        }
        return UIMenu(children: [
            UIAction(title: String(localized: "Copia"), image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in self?.copySelection() },
            UIAction(title: String(localized: "Taglia"), image: UIImage(systemName: "scissors")) { [weak self] _ in
                self?.copySelection()
                self?.deleteSelection()
            },
            UIAction(title: String(localized: "Duplica"), image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in self?.duplicate() },
            UIAction(title: String(localized: "Elimina"), image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.deleteSelection()
            },
            UIMenu(title: String(localized: "Cambia colore"), image: UIImage(systemName: "paintpalette"), children: colors)
        ])
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        guard configuration.identifier as? NSString == Self.selectionMenu, let frame = selection?.frame else { return .null }
        let corners = frame.corners.map(screenPoint)
        return CGRect(boundingPoints: corners)
    }
}
