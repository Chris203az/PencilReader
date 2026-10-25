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

/// Hosts the PencilKit canvas, which keeps a single drawing for the page on screen.
struct NotebookCanvas: UIViewRepresentable {
    let notebook: NotebookModel

    func makeUIView(context: Context) -> NotebookCanvasView {
        let view = NotebookCanvasView()
        view.notebook = notebook
        notebook.attach(view)
        return view
    }

    func updateUIView(_ view: NotebookCanvasView, context: Context) {
        view.paper = notebook.paper
    }

    static func dismantleUIView(_ view: NotebookCanvasView, coordinator: Void) {
        if let notebook = view.notebook { notebook.detach(view) }
    }
}

/// A scrolling PencilKit canvas: the Pencil writes, a finger scrolls. The page
/// grows downward as the writing goes further down.
final class NotebookCanvasView: PKCanvasView, PKCanvasViewDelegate {
    weak var notebook: NotebookModel?
    var paper: PaperStyle = .grid {
        didSet { paperView.style = paper }
    }

    private let paperView = PaperView()
    private let toolPicker = PKToolPicker()

    override init(frame: CGRect) {
        super.init(frame: frame)
        drawingPolicy = .pencilOnly
        alwaysBounceVertical = true
        backgroundColor = .clear
        delegate = self
        insertSubview(paperView, at: 0)
        paperView.style = paper
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

    override func layoutSubviews() {
        super.layoutSubviews()
        fitContent()
    }

    /// There is always a screen of paper below the last stroke.
    func fitContent() {
        let inkBottom = drawing.strokes.isEmpty ? 0 : drawing.bounds.maxY
        let height = max(bounds.height, inkBottom + bounds.height / 2)
        contentSize = CGSize(width: bounds.width, height: height)
        paperView.frame = CGRect(origin: .zero, size: contentSize)
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        fitContent()
        notebook?.drawingDidChange()
    }
}

/// Ruled or squared paper, drawn under the ink and scrolling with it.
private final class PaperView: UIView {
    var style: PaperStyle = .grid {
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
        context.setStrokeColor(UIColor.systemGray4.cgColor)
        context.setLineWidth(0.5)
        var y = floor(rect.minY / step) * step
        while y <= rect.maxY {
            context.move(to: CGPoint(x: rect.minX, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += step
        }
        if style == .grid {
            var x = floor(rect.minX / step) * step
            while x <= rect.maxX {
                context.move(to: CGPoint(x: x, y: rect.minY))
                context.addLine(to: CGPoint(x: x, y: rect.maxY))
                x += step
            }
        }
        context.strokePath()
    }
}
