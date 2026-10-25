import PencilKit
import ReaderCore
import SwiftUI

/// The notebook next to the book page: a header, then a page the Pencil writes on.
struct NotebookPane: View {
    @Bindable var notebook: NotebookModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            NotebookCanvas(notebook: notebook)
        }
        .background(Color(.systemBackground))
    }

    private var header: some View {
        HStack(spacing: 18) {
            Text("Note · pag. \(notebook.pageIndex + 1)")
                .font(.headline)
                .monospacedDigit()
            Spacer()
            Button("Annulla", systemImage: "arrow.uturn.backward") { notebook.undo() }
            Button("Ripeti", systemImage: "arrow.uturn.forward") { notebook.redo() }
            Menu("Sfondo", systemImage: "square.grid.3x3") {
                Picker("Sfondo", selection: $notebook.paper) {
                    ForEach(PaperStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
            }
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// Draggable line between the book page and the notebook.
struct NotebookDivider: View {
    @Binding var split: Double
    /// Width the two sides share, without the divider itself.
    let available: CGFloat
    @State private var startSplit: Double?

    static let width: CGFloat = 16

    var body: some View {
        Capsule()
            .fill(.secondary.opacity(0.5))
            .frame(width: 4, height: 44)
            .frame(width: Self.width)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let start = startSplit ?? split
                        startSplit = start
                        split = SplitRatio.clamped(start + Double(value.translation.width / available))
                    }
                    .onEnded { _ in
                        startSplit = nil
                        NotebookSettings.saveSplit(split)
                    }
            )
            .accessibilityLabel("Divisore tra pagina e quaderno")
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
    }

    static func dismantleUIView(_ view: NotebookSheetView, coordinator: Void) {
        if let notebook = view.canvas.notebook { notebook.detach(view.canvas) }
    }
}

/// Paper and canvas are siblings. The canvas is never given extra subviews, and its
/// view hierarchy is never changed from inside PencilKit's drawing callbacks.
final class NotebookSheetView: UIView {
    let canvas = NotebookCanvasView()
    private let paperView = PaperView()

    var paper: PaperStyle = .grid {
        didSet { paperView.style = paper }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        paperView.style = paper
        addSubview(paperView)
        addSubview(canvas)
        canvas.onScroll = { [weak self] offset in self?.paperView.scrollOffset = offset }
    }

    required init?(coder: NSCoder) {
        fatalError("NotebookSheetView si crea solo da codice")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        paperView.frame = bounds
        canvas.frame = bounds
        canvas.fitContent()
    }
}

/// A scrolling PencilKit canvas: the Pencil writes, a finger scrolls. The page
/// grows downward as the writing goes further down.
final class NotebookCanvasView: PKCanvasView, PKCanvasViewDelegate {
    weak var notebook: NotebookModel?
    /// Called on every scroll, so the paper behind can move with the writing.
    var onScroll: ((CGPoint) -> Void)?

    private let toolPicker = PKToolPicker()

    override var contentOffset: CGPoint {
        didSet { onScroll?(contentOffset) }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        drawingPolicy = .pencilOnly
        alwaysBounceVertical = true
        backgroundColor = .clear
        delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("NotebookCanvasView si crea solo da codice")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        toolPicker.setVisible(true, forFirstResponder: self)
        toolPicker.addObserver(self)
        becomeFirstResponder()
    }

    /// There is always a screen of paper below the last stroke.
    func fitContent() {
        let inkBottom = drawing.strokes.isEmpty ? 0 : drawing.bounds.maxY
        let height = max(bounds.height, inkBottom + bounds.height / 2)
        let size = CGSize(width: bounds.width, height: height)
        if contentSize != size { contentSize = size }
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        // Grows after the current callback: resizing while PencilKit is still handling
        // the stroke re-entered it and crashed the app.
        DispatchQueue.main.async { [weak self] in self?.fitContent() }
        notebook?.drawingDidChange()
    }
}

/// Ruled or squared paper. It stays still while the canvas scrolls over it and
/// is drawn in the page's own coordinates, so the lines line up with the ink.
private final class PaperView: UIView {
    var style: PaperStyle = .grid {
        didSet { setNeedsDisplay() }
    }

    var scrollOffset: CGPoint = .zero {
        didSet { setNeedsDisplay() }
    }

    private let step: CGFloat = 28

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
        let page = rect.offsetBy(dx: scrollOffset.x, dy: scrollOffset.y)
        context.translateBy(x: -scrollOffset.x, y: -scrollOffset.y)
        context.setStrokeColor(UIColor.systemGray4.cgColor)
        context.setLineWidth(0.5)
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
