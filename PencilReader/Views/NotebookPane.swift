import PencilKit
import ReaderCore
import SwiftUI
import UIKit.UIGestureRecognizerSubclass

/// The notebook next to the book page: a header, then a page the Pencil writes on.
struct NotebookPane: View {
    @Bindable var notebook: NotebookModel
    @State private var showsToolbarSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if notebook.tools.layout.position == .top {
                toolbar
                Divider()
            }
            if notebook.isWriting {
                NotebookCanvas(notebook: notebook)
            } else {
                ContentUnavailableView {
                    Label("Nessuna nota su questa pagina", systemImage: "square.and.pencil")
                } actions: {
                    Button("Nuova nota") { notebook.startNote() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxHeight: .infinity)
            }
            if notebook.tools.layout.position == .bottom {
                Divider()
                toolbar
            }
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showsToolbarSettings) {
            ToolbarSettingsView(tools: notebook.tools)
        }
    }

    private var toolbar: some View {
        NotebookToolbar(notebook: notebook)
            .disabled(!notebook.isWriting)
    }

    private var header: some View {
        HStack(spacing: 18) {
            Text("Note · pag. \(notebook.pageIndex + 1)")
                .font(.headline)
                .monospacedDigit()
            Spacer()
            Menu("Opzioni", systemImage: "slider.horizontal.3") {
                Button("Barra strumenti…", systemImage: "rectangle.topthird.inset.filled") { showsToolbarSettings = true }
                Picker("Sfondo", selection: $notebook.paper) {
                    ForEach(PaperStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                Toggle("Raddrizza le forme", isOn: $notebook.straightensShapes)
            }
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// Draggable line between the book page and the notebook. The line follows the finger;
/// the two sides are resized once, when it is let go, so they do not shake while moving.
struct NotebookDivider: View {
    @Binding var split: Double
    /// Width the two sides share, without the divider itself.
    let available: CGFloat
    @GestureState private var dragOffset: CGFloat = 0

    static let width: CGFloat = 24

    var body: some View {
        Capsule()
            .fill(dragOffset == 0 ? Color.secondary.opacity(0.5) : Color.accentColor)
            .frame(width: dragOffset == 0 ? 4 : 6, height: dragOffset == 0 ? 44 : 120)
            .frame(width: Self.width)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .offset(x: dragOffset)
            .gesture(
                // Measured on the screen: the handle moves while dragged, so its own coordinates
                // would shift under the finger and make it shake.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .updating($dragOffset) { value, state, _ in state = offset(for: value.translation.width) }
                    .onEnded { value in
                        split = SplitRatio.clamped(split + Double(value.translation.width / available))
                        NotebookSettings.saveSplit(split)
                    }
            )
            .accessibilityLabel("Divisore tra pagina e quaderno")
    }

    /// The drag, stopped where the split reaches its limits.
    private func offset(for translation: CGFloat) -> CGFloat {
        CGFloat(SplitRatio.clamped(split + Double(translation / available)) - split) * available
    }
}

/// Hosts the notebook page: the paper, then the PencilKit canvas on top of it.
struct NotebookCanvas: UIViewRepresentable {
    let notebook: NotebookModel

    func makeUIView(context: Context) -> NotebookSheetView {
        let view = NotebookSheetView()
        view.canvas.notebook = notebook
        notebook.attach(view.canvas)
        return view
    }

    func updateUIView(_ view: NotebookSheetView, context: Context) {
        view.paper = notebook.paper
        let tools = notebook.tools
        if view.canvas.appliedTools?.state != tools.state || view.canvas.appliedTools?.ruler != tools.isRulerActive {
            view.canvas.tool = tools.pkTool
            view.canvas.isRulerActive = tools.isRulerActive
            view.canvas.appliedTools = (tools.state, tools.isRulerActive)
        }
    }

    static func dismantleUIView(_ view: NotebookSheetView, coordinator: Void) {
        if let notebook = view.canvas.notebook { notebook.detach(view.canvas) }
    }
}

/// Paper and canvas are siblings. The canvas is never given extra subviews, and its
/// view hierarchy is never changed from inside PencilKit's drawing callbacks.
/// The shape snapped while the Pencil is held is drawn above both, in its own layer.
final class NotebookSheetView: UIView {
    let canvas = NotebookCanvasView()
    private let paperView = PaperView()
    private let preview = CAShapeLayer()
    private var previewShape: InkShape?
    /// The pen's width on the page; on screen it grows with the zoom.
    private var previewWidth: CGFloat = 1
    /// "Annulla" or "Ripristina", shown for a moment after a swipe.
    private let toast = UILabel()

    var paper: PaperStyle = .grid {
        didSet { paperView.style = paper }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        paperView.style = paper
        addSubview(paperView)
        addSubview(canvas)
        preview.fillColor = nil
        preview.lineCap = .round
        preview.lineJoin = .round
        layer.addSublayer(preview)
        toast.font = .preferredFont(forTextStyle: .headline)
        toast.textColor = .white
        toast.textAlignment = .center
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        toast.layer.cornerRadius = 14
        toast.clipsToBounds = true
        toast.alpha = 0
        addSubview(toast)
        canvas.onScroll = { [weak self] offset, zoom in
            self?.paperView.show(offset: offset, zoom: zoom)
            self?.drawPreview()
        }
        canvas.onSwipeAction = { [weak self] name in self?.showToast(name) }
        canvas.onShapePreview = { [weak self] shape, color, width in
            self?.showPreview(shape, color: color, width: width)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("NotebookSheetView si crea solo da codice")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        paperView.frame = bounds
        canvas.frame = bounds
        preview.frame = bounds
        canvas.fitContent()
    }

    private func showPreview(_ shape: InkShape?, color: UIColor, width: CGFloat) {
        previewShape = shape
        preview.strokeColor = color.cgColor
        previewWidth = width
        drawPreview()
    }

    private func drawPreview() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let previewShape else {
            preview.path = nil
            return
        }
        let path = UIBezierPath()
        let zoom = canvas.zoomScale
        preview.lineWidth = previewWidth * zoom
        for (i, point) in previewShape.outline(spacing: 4).enumerated() {
            // Drawing coordinates are the content's before zooming.
            let onScreen = canvas.convert(CGPoint(x: point.x * zoom, y: point.y * zoom), to: self)
            if i == 0 { path.move(to: onScreen) } else { path.addLine(to: onScreen) }
        }
        preview.path = path.cgPath
    }

    private func showToast(_ text: String) {
        toast.text = text
        let size = toast.intrinsicContentSize
        toast.frame = CGRect(x: bounds.midX - (size.width + 36) / 2, y: 20, width: size.width + 36, height: size.height + 16)
        toast.layer.removeAllAnimations()
        toast.alpha = 1
        UIView.animate(withDuration: 0.25, delay: 0.35, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.toast.alpha = 0
        }
    }
}

/// A scrolling PencilKit canvas: the Pencil writes, a finger scrolls. The page
/// grows downward as the writing goes further down.
///
/// Shapes work as in GoodNotes: draw, then hold the Pencil still without lifting it. The clean
/// shape appears at once and follows the tip until the Pencil lifts, then replaces the stroke.
/// Without the pause nothing happens, so handwriting is never touched.
final class NotebookCanvasView: PKCanvasView {
    weak var notebook: NotebookModel?
    /// Called on every scroll and zoom, so the paper behind can move and grow with the writing.
    var onScroll: ((CGPoint, CGFloat) -> Void)?
    /// Called with "Annulla" or "Ripristina" after a finger swipe did that.
    var onSwipeAction: ((String) -> Void)?
    /// Shows the shape snapped while the Pencil is held, in the ink's color and width; nil hides it.
    var onShapePreview: ((InkShape?, UIColor, CGFloat) -> Void)?

    /// What the tool bar last set, so the tool is only replaced when the choice changes.
    var appliedTools: (state: NotebookToolState, ruler: Bool)?
    /// Never the canvas itself: a canvas that is its own delegate also answers
    /// PencilKit's private delegate calls, and calls itself forever when a stroke begins.
    private let events = CanvasEvents()
    private let hold = PencilHoldRecognizer(target: nil, action: nil)
    private var swipes: [UISwipeGestureRecognizer] = []
    private let simultaneous = SimultaneousGestures()
    private let pencilTaps = PencilTaps()

    /// The shape found when the Pencil was held, the point that stays put and where the tip was.
    private var snapped: (shape: InkShape, anchor: CGPoint, tip: CGPoint)?
    /// The snapped shape as the tip has moved it since.
    private var shape: InkShape?
    /// Strokes on the page when the current one began: one more means PencilKit has added it.
    private var strokesAtStart = 0
    private var liftedWithShape = false
    private var isReplacing = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        drawingPolicy = .pencilOnly
        alwaysBounceVertical = true
        backgroundColor = .clear
        events.canvas = self
        pencilTaps.canvas = self
        delegate = events
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = pencilTaps
        addInteraction(pencilInteraction)
        hold.onBegin = { [weak self] in self?.strokeBegan() }
        hold.onHold = { [weak self] points in
            guard let self else { return false }
            return self.snap(points.map(self.drawingPoint))
        }
        hold.onMove = { [weak self] point in
            guard let self else { return }
            self.drag(to: self.drawingPoint(point))
        }
        hold.onEnd = { [weak self] lifted in self?.strokeEnded(lifted: lifted) }
        addGestureRecognizer(hold)

        minimumZoomScale = 1
        maximumZoomScale = 4
        bouncesZoom = true
        // A finger swiped sideways undoes (right) or redoes (left); scrolling up and down still works.
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
            swipe.direction = direction
            swipe.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            swipe.delegate = simultaneous
            addGestureRecognizer(swipe)
            swipes.append(swipe)
        }
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("NotebookCanvasView si crea solo da codice")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        // First responder, so Annulla and Ripristina reach the canvas' undo manager.
        becomeFirstResponder()
    }

    /// There is always a screen of paper below the last stroke. The page is as wide as the
    /// notebook at 1x; the content size is that page at the current zoom.
    func fitContent() {
        let inkBottom = drawing.strokes.isEmpty ? 0 : drawing.bounds.maxY
        let height = max(bounds.height, inkBottom + bounds.height / 2)
        let size = CGSize(width: bounds.width * zoomScale, height: height * zoomScale)
        if contentSize != size { contentSize = size }
    }

    /// Shows a page at 1x: the zoom is not kept from one page to the next.
    func resetZoom() {
        setZoomScale(1, animated: false)
    }

    /// From the canvas' content coordinates, which grow with the zoom, to the drawing's.
    private func drawingPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / zoomScale, y: point.y / zoomScale)
    }

    fileprivate func scrolled() {
        onScroll?(contentOffset, zoomScale)
    }

    fileprivate func zoomed() {
        // Zoomed in, a finger moves the page sideways instead of undoing.
        swipes.forEach { $0.isEnabled = zoomScale <= 1.01 }
        onScroll?(contentOffset, zoomScale)
    }

    @objc private func swiped(_ swipe: UISwipeGestureRecognizer) {
        guard let undoManager else { return }
        if swipe.direction == .right, undoManager.canUndo {
            undoManager.undo()
            onSwipeAction?("Annulla")
        } else if swipe.direction == .left, undoManager.canRedo {
            undoManager.redo()
            onSwipeAction?("Ripristina")
        }
    }

    @objc private func doubleTapped() {
        setZoomScale(1, animated: true)
    }

    fileprivate func drawingDidChange() {
        // Grows after the current callback, not while PencilKit is still handling the stroke.
        DispatchQueue.main.async { [weak self] in self?.fitContent() }
        notebook?.drawingDidChange()
        if !isReplacing, liftedWithShape { replaceStrokeIfAdded() }
    }

    // MARK: Shapes

    /// Color and width of the pen in use; nil for the eraser and the lasso, which never make shapes.
    private var ink: (color: UIColor, width: CGFloat)? {
        guard let tool = tool as? PKInkingTool else { return nil }
        return (PKInkingTool.convertColor(tool.color, from: .light, to: traitCollection.userInterfaceStyle), tool.width)
    }

    private func strokeBegan() {
        snapped = nil
        shape = nil
        liftedWithShape = false
        strokesAtStart = drawing.strokes.count
        onShapePreview?(nil, .clear, 0)
    }

    /// The Pencil has been still for a moment: shows the shape the stroke so far looks like, if any.
    private func snap(_ points: [CGPoint]) -> Bool {
        guard notebook?.straightensShapes == true, let ink, let tip = points.last,
              let found = ShapeRecognizer.recognize(points) else { return false }
        snapped = (found, found.anchor(oppositeTo: tip), tip)
        shape = found
        onShapePreview?(found, ink.color, ink.width)
        return true
    }

    private func drag(to point: CGPoint) {
        guard let snapped, let ink else { return }
        let moved = snapped.shape.dragged(anchor: snapped.anchor, from: snapped.tip, to: point)
        shape = moved
        onShapePreview?(moved, ink.color, ink.width)
    }

    private func strokeEnded(lifted: Bool) {
        guard lifted, shape != nil else {
            snapped = nil
            shape = nil
            onShapePreview?(nil, .clear, 0)
            return
        }
        liftedWithShape = true
        replaceStrokeIfAdded()
    }

    /// PencilKit adds the stroke when the Pencil lifts, just before or just after this view hears
    /// of the lift: whichever comes second swaps the stroke for the shape.
    private func replaceStrokeIfAdded() {
        guard drawing.strokes.count > strokesAtStart, let shape else { return }
        liftedWithShape = false
        snapped = nil
        self.shape = nil
        // Outside PencilKit's callback, which must not see the drawing change under it.
        DispatchQueue.main.async { [weak self] in
            self?.replaceLastStroke(with: shape)
            self?.onShapePreview?(nil, .clear, 0)
        }
    }

    /// Same ink and width as the hand-drawn stroke, through the shape's outline.
    private func replaceLastStroke(with shape: InkShape) {
        guard let stroke = drawing.strokes.last, !stroke.path.isEmpty else { return }
        let sample = stroke.path[stroke.path.count / 2]
        let controls = shape.outline().enumerated().map { i, location in
            PKStrokePoint(location: location, timeOffset: TimeInterval(i) * 0.005, size: sample.size,
                          opacity: sample.opacity, force: sample.force, azimuth: sample.azimuth, altitude: sample.altitude)
        }
        let shapeStroke = PKStroke(ink: stroke.ink,
                                   path: PKStrokePath(controlPoints: controls, creationDate: stroke.path.creationDate))
        // As in GoodNotes, one Annulla takes the whole shape away: PencilKit's own step for the
        // hand-drawn stroke is undone first, and the shape is added as a single step instead.
        if let undoManager, undoManager.canUndo {
            isReplacing = true
            undoManager.undo()
            isReplacing = false
            if drawing.strokes.count == strokesAtStart {
                var updated = drawing
                updated.strokes.append(shapeStroke)
                setDrawingUndoably(updated)
                return
            }
            // That step was something else: put it back and swap the stroke in place.
            isReplacing = true
            undoManager.redo()
            isReplacing = false
        }
        var updated = drawing
        updated.strokes[updated.strokes.count - 1] = shapeStroke
        setDrawingUndoably(updated)
    }

    /// One assignment, recorded so that Annulla brings back the hand-drawn stroke and Ripeti the shape.
    private func setDrawingUndoably(_ newDrawing: PKDrawing) {
        let previous = drawing
        undoManager?.registerUndo(withTarget: self) { canvas in canvas.setDrawingUndoably(previous) }
        isReplacing = true
        drawing = newDrawing
        isReplacing = false
    }
}

/// Receives the canvas' drawing and scroll events.
private final class CanvasEvents: NSObject, PKCanvasViewDelegate {
    weak var canvas: NotebookCanvasView?

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        canvas?.drawingDidChange()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        canvas?.scrolled()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        canvas?.zoomed()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        canvas?.fitContent()
    }
}

/// The double tap on Apple Pencil 2.
private final class PencilTaps: NSObject, UIPencilInteractionDelegate {
    weak var canvas: NotebookCanvasView?

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        canvas?.notebook?.tools.pencilDoubleTap()
    }
}

/// Lets the undo swipes work alongside the canvas' own scrolling.
private final class SimultaneousGestures: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// Follows the Pencil while PencilKit draws, without ever taking its touches: notices when the
/// tip stays still long enough to ask for a shape, then reports where it goes until it lifts.
private final class PencilHoldRecognizer: UIGestureRecognizer {
    static let holdDuration: TimeInterval = 0.5
    /// Smaller movements still count as holding still.
    static let stillness: CGFloat = 4

    var onBegin: (() -> Void)?
    /// Returns whether a shape was found; if not, holding still again later tries again.
    var onHold: (([CGPoint]) -> Bool)?
    var onMove: ((CGPoint) -> Void)?
    /// True when the Pencil lifted, false when the touch was cancelled.
    var onEnd: ((Bool) -> Void)?

    private weak var trackedTouch: UITouch?
    private var points: [CGPoint] = []
    private var stillAt: CGPoint = .zero
    private var timer: Timer?
    private var isHeld = false

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil, let touch = touches.first else { return }
        trackedTouch = touch
        points = [touch.location(in: view)]
        stillAt = points[0]
        isHeld = false
        onBegin?()
        restartTimer()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        for sample in event.coalescedTouches(for: touch) ?? [touch] {
            let point = sample.location(in: view)
            if isHeld {
                onMove?(point)
            } else {
                points.append(point)
                if hypot(point.x - stillAt.x, point.y - stillAt.y) > Self.stillness {
                    stillAt = point
                    restartTimer()
                }
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        onEnd?(true)
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        onEnd?(false)
        state = .failed
    }

    override func reset() {
        super.reset()
        timer?.invalidate()
        timer = nil
        trackedTouch = nil
        points = []
        isHeld = false
    }

    private func restartTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.holdDuration, repeats: false) { [weak self] _ in
            guard let self, !self.isHeld, self.trackedTouch != nil else { return }
            self.isHeld = self.onHold?(self.points) ?? false
        }
        // In the common modes, so it also fires while touches are being tracked.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

/// Ruled or squared paper. It stays still while the canvas scrolls over it and
/// is drawn in the page's own coordinates, so the lines line up with the ink.
private final class PaperView: UIView {
    var style: PaperStyle = .grid {
        didSet { setNeedsDisplay() }
    }

    private var scrollOffset: CGPoint = .zero
    private var zoom: CGFloat = 1

    private let step: CGFloat = 28

    /// Where the canvas is scrolled to and how far it is zoomed, so the lines stay under the ink.
    func show(offset: CGPoint, zoom: CGFloat) {
        guard offset != scrollOffset || zoom != self.zoom else { return }
        scrollOffset = offset
        self.zoom = zoom
        setNeedsDisplay()
    }

    init() {
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        isOpaque = true
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("PaperView si crea solo da codice")
    }

    override func draw(_ rect: CGRect) {
        guard style != .blank, let context = UIGraphicsGetCurrentContext() else { return }
        // The visible part of the page, in the drawing's own coordinates.
        let page = CGRect(x: (rect.minX + scrollOffset.x) / zoom, y: (rect.minY + scrollOffset.y) / zoom,
                          width: rect.width / zoom, height: rect.height / zoom)
        context.translateBy(x: -scrollOffset.x, y: -scrollOffset.y)
        context.scaleBy(x: zoom, y: zoom)
        context.setStrokeColor(UIColor.systemGray4.cgColor)
        context.setLineWidth(0.5 / zoom)
        var y = floor(page.minY / step) * step
        while y <= page.maxY {
            context.move(to: CGPoint(x: page.minX, y: y))
            context.addLine(to: CGPoint(x: page.maxX, y: y))
            y += step
        }
        if style == .grid {
            var x = floor(page.minX / step) * step
            while x <= page.maxX {
                context.move(to: CGPoint(x: x, y: page.minY))
                context.addLine(to: CGPoint(x: x, y: page.maxY))
                x += step
            }
        }
        context.strokePath()
    }
}
