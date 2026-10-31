import PencilKit
import ReaderCore
import SwiftUI

/// What the reader opens from "Fissa la lettura" or from the list of recaps.
enum RecapSheet: Identifiable {
    /// Pick the pages, then write; the range is the one suggested.
    case new(ClosedRange<Int>)
    case open(ReadingRecap)

    var id: String {
        switch self {
        case .new: "new"
        case .open(let recap): recap.id.uuidString
        }
    }
}

/// "Fissa la lettura": the reader picks the pages just read and re-elaborates them by hand without
/// looking at the book; meanwhile the AI writes its own short version, shown only once theirs is
/// done, next to their page, which stays editable.
struct FixReadingView: View {
    private enum Step {
        case range
        case writing
        case compare
    }

    /// Needed only for a new recap: the book open, to read the text of the pages.
    private let model: ReaderModel?
    @State private var recapID: UUID?
    @State private var step: Step
    @State private var first: Int
    @State private var last: Int
    /// The AI's column beside the handwriting, once the reader has finished; they can close and reopen it.
    @State private var showsAI = true
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    private let store = RecapStore.shared

    init(model: ReaderModel, suggested: ClosedRange<Int>) {
        self.model = model
        _step = State(initialValue: .range)
        _first = State(initialValue: suggested.lowerBound)
        _last = State(initialValue: suggested.upperBound)
    }

    init(recap: ReadingRecap) {
        model = nil
        _recapID = State(initialValue: recap.id)
        _step = State(initialValue: recap.finished == nil ? .writing : .compare)
        _first = State(initialValue: recap.firstPage)
        _last = State(initialValue: recap.lastPage)
    }

    private var recap: ReadingRecap? { recapID.flatMap { store.recap(withID: $0) } }

    var body: some View {
        NavigationStack {
            Group {
                if step == .range, let model {
                    rangeForm(model)
                } else if let recap {
                    writingPage(recap)
                } else {
                    ContentUnavailableView("Rielaborazione eliminata", systemImage: "trash")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .range ? "Annulla" : "Chiudi") { dismiss() }
                }
                if step == .writing, let recapID {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Ho finito") {
                            store.markFinished(recapID)
                            withAnimation(.snappy) { step = .compare }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                if step == .compare {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            withAnimation(.snappy) { showsAI.toggle() }
                        } label: {
                            Label(showsAI ? "Nascondi la versione dell'IA" : "Mostra la versione dell'IA",
                                  systemImage: "sidebar.trailing")
                        }
                    }
                }
            }
        }
    }

    private var title: String {
        switch step {
        case .range: String(localized: "Fissa la lettura")
        case .writing, .compare: "\(recap?.bookTitle ?? "") · \(recap?.pagesLabel ?? "")"
        }
    }

    // MARK: Pages

    private func rangeForm(_ model: ReaderModel) -> some View {
        Form {
            Section {
                Label {
                    Text("Scegli le pagine che hai appena letto: le rielabori con parole tue, a mano e senza guardare il libro. Intanto l'IA prepara la sua versione, che vedrai solo dopo aver finito la tua.")
                } icon: {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(.tint)
                }
            }
            Section {
                Stepper("Dalla pagina \(first + 1)", value: $first, in: 0...last)
                Stepper("Alla pagina \(last + 1)", value: $last, in: first...(model.pageCount - 1))
                Button("Fino alla pagina aperta (\(model.pageIndex + 1))") {
                    last = max(model.pageIndex, first)
                }
                .disabled(last == model.pageIndex)
            } header: {
                Text("Pagine lette")
            } footer: {
                Text(last == first ? "Una pagina." : "\(last - first + 1) pagine.")
            }
            Section {
                Button("Inizia la rielaborazione", systemImage: "pencil.and.scribble") { begin(model) }
                    .frame(maxWidth: .infinity)
                    .bold()
            }
        }
        .monospacedDigit()
    }

    private func begin(_ model: ReaderModel) {
        let pages = first...last
        let recap = store.create(book: model.document, title: model.title, pages: pages)
        recapID = recap.id
        store.writeAIVersion(of: recap.id, library: library) { await model.recognizeText(of: pages) }
        withAnimation(.snappy) { step = .writing }
    }

    // MARK: Writing and comparing

    /// One canvas for both steps, so the handwriting stays put when the AI's version slides in.
    private func writingPage(_ recap: ReadingRecap) -> some View {
        VStack(spacing: 0) {
            if step == .writing {
                RecapGuide(recap: recap)
            } else {
                Label("Confronta con la versione dell'IA: correggi e completa la tua dove serve.",
                      systemImage: "arrow.left.arrow.right")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            Divider()
            GeometryReader { geo in
                HStack(spacing: 0) {
                    RecapCanvas(recapID: recap.id, sheetWidth: geo.size.width)
                    if step == .compare && showsAI {
                        Divider()
                        AIRecapColumn(recap: recap)
                            .frame(width: geo.size.width * 0.4)
                            .transition(.move(edge: .trailing))
                    }
                }
            }
            if step == .writing {
                AIProgressLine(recap: recap)
            }
        }
    }
}

/// What to write, as retrieval practice: from memory, then the links between ideas.
private struct RecapGuide: View {
    let recap: ReadingRecap

    private static let prompts = [
        String(localized: "L'idea principale, in una frase"),
        String(localized: "I concetti chiave e come si collegano"),
        String(localized: "Un esempio, una formula o un'applicazione"),
        String(localized: "Cosa non ti è ancora chiaro")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chiudi il libro e scrivi con parole tue, senza guardare:")
                .font(.subheadline.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                GridRow {
                    prompt(0)
                    prompt(1)
                }
                GridRow {
                    prompt(2)
                    prompt(3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func prompt(_ index: Int) -> some View {
        Label(Self.prompts[index], systemImage: "\(index + 1).circle")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

/// While the reader writes: only whether the AI is ready, never its text.
private struct AIProgressLine: View {
    let recap: ReadingRecap
    private let store = RecapStore.shared

    var body: some View {
        HStack(spacing: 8) {
            if recap.ai != nil {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("La versione dell'IA è pronta: la vedi quando tocchi «Ho finito».")
            } else if case .failed = store.aiState[recap.id] {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text("L'IA non ha risposto: potrai riprovare dopo.")
            } else {
                ProgressView().controlSize(.small)
                Text("L'IA sta preparando la sua versione…")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// The AI's re-elaboration, or why it isn't there with a way to ask again.
struct AIRecapColumn: View {
    let recap: ReadingRecap
    @Environment(Library.self) private var library
    private let store = RecapStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("Versione dell'IA", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let ai = recap.ai {
                    if !ai.title.isEmpty {
                        Text(ai.title).font(.title3.bold())
                    }
                    if !ai.idea.isEmpty {
                        Text(ai.idea)
                            .font(.body.weight(.medium))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(ai.points.enumerated()), id: \.offset) { index, point in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(index + 1).")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Text(point)
                            }
                        }
                    }
                    .font(.callout)
                } else {
                    missing
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder private var missing: some View {
        switch store.aiState[recap.id] {
        case .working:
            HStack(spacing: 8) {
                ProgressView()
                Text("L'IA sta scrivendo la sua versione…")
            }
            .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).foregroundStyle(.secondary)
            retry
        case nil:
            Text("La versione dell'IA non c'è ancora.").foregroundStyle(.secondary)
            retry
        }
    }

    private var retry: some View {
        Button("Chiedi all'IA", systemImage: "arrow.clockwise") {
            store.writeAIVersion(of: recap.id, library: library)
        }
        .buttonStyle(.bordered)
    }
}

// MARK: Handwriting

/// The reader's handwritten re-elaboration on lined paper, with the system's Pencil tools.
/// Saved at every stroke.
struct RecapCanvas: UIViewRepresentable {
    let recapID: UUID
    /// The width of the whole sheet: when the AI's column takes part of it, the page shrinks to fit.
    let sheetWidth: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(recapID: recapID) }

    func makeUIView(context: Context) -> RecapSheetView {
        let view = RecapSheetView()
        view.sheetWidth = sheetWidth
        view.canvas.drawing = RecapStore.shared.drawing(of: recapID)
        view.canvas.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: RecapSheetView, context: Context) {
        view.sheetWidth = sheetWidth
    }

    static func dismantleUIView(_ view: RecapSheetView, coordinator: Coordinator) {
        view.hideTools()
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let recapID: UUID

        init(recapID: UUID) {
            self.recapID = recapID
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            RecapStore.shared.saveDrawing(canvasView.drawing, of: recapID)
            (canvasView.superview as? RecapSheetView)?.fitContent()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            (scrollView.superview as? RecapSheetView)?.followScroll()
        }
    }
}

final class RecapSheetView: UIView {
    let canvas = PKCanvasView()
    private let paper = PaperView()
    private let toolPicker = PKToolPicker()
    var sheetWidth: CGFloat = 0 {
        didSet {
            if sheetWidth != oldValue { setNeedsLayout() }
        }
    }

    /// The whole page always fits the width: narrower than the sheet, it is drawn smaller.
    private var fitZoom: CGFloat {
        guard sheetWidth > 0, bounds.width > 0 else { return 1 }
        return min(1, bounds.width / sheetWidth)
    }

    init() {
        super.init(frame: .zero)
        paper.style = .lines
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .default
        canvas.alwaysBounceVertical = true
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 1
        canvas.tool = PKInkingTool(.pen, color: .label, width: 3)
        addSubview(paper)
        addSubview(canvas)
        toolPicker.addObserver(canvas)
    }

    required init?(coder: NSCoder) {
        fatalError("RecapSheetView si crea solo da codice")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        paper.frame = bounds
        canvas.frame = bounds
        let zoom = fitZoom
        if abs(canvas.zoomScale - zoom) > 0.001 {
            // Keep the same line of the page at the top.
            let top = canvas.contentOffset.y / canvas.zoomScale
            canvas.minimumZoomScale = zoom
            canvas.maximumZoomScale = zoom
            canvas.zoomScale = zoom
            fitContent()
            let maxY = max(0, canvas.contentSize.height - bounds.height)
            canvas.contentOffset = CGPoint(x: 0, y: min(max(0, top * zoom), maxY))
        }
        fitContent()
        followScroll()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        toolPicker.setVisible(true, forFirstResponder: canvas)
        canvas.becomeFirstResponder()
    }

    func hideTools() {
        toolPicker.setVisible(false, forFirstResponder: canvas)
        canvas.resignFirstResponder()
    }

    /// Always room to keep writing below the last line.
    func fitContent() {
        guard bounds.height > 0 else { return }
        let zoom = canvas.zoomScale
        // In page points, as the drawing is.
        let visible = bounds.height / zoom
        let bottom = canvas.drawing.strokes.isEmpty ? 0 : canvas.drawing.bounds.maxY
        let height = max(visible * 1.5, bottom + visible / 2) * zoom
        if abs(canvas.contentSize.width - bounds.width) > 1 || abs(canvas.contentSize.height - height) > 1 {
            canvas.contentSize = CGSize(width: bounds.width, height: height)
        }
    }

    func followScroll() {
        paper.show(offset: canvas.contentOffset, zoom: canvas.zoomScale)
    }
}

// MARK: List

/// Every recap, of every book, grouped by book; the current book first when there is one.
struct RecapListView: View {
    var currentBookID: UUID?
    @State private var opening: ReadingRecap?
    @State private var deleting: ReadingRecap?
    @Environment(\.dismiss) private var dismiss
    private let store = RecapStore.shared

    private struct Book: Identifiable {
        let id: UUID
        let title: String
        /// Newest first.
        let recaps: [ReadingRecap]
    }

    private var books: [Book] {
        let grouped = Dictionary(grouping: store.recaps, by: \.bookID)
        return grouped.map { id, recaps in Book(id: id, title: recaps[0].bookTitle, recaps: recaps) }
            .sorted { lhs, rhs in
                if (lhs.id == currentBookID) != (rhs.id == currentBookID) { return lhs.id == currentBookID }
                return lhs.recaps[0].created > rhs.recaps[0].created
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.recaps.isEmpty {
                    ContentUnavailableView {
                        Label("Nessuna rielaborazione", systemImage: "brain.head.profile")
                    } description: {
                        Text("Quando finisci di leggere, apri il timer e tocca «Fissa la lettura»: rielabori le pagine lette e le trovi qui.")
                    }
                } else {
                    List {
                        ForEach(books) { book in
                            Section(book.title) {
                                ForEach(book.recaps) { recap in
                                    Button { opening = recap } label: { RecapRow(recap: recap) }
                                        .swipeActions {
                                            Button("Elimina", systemImage: "trash", role: .destructive) { deleting = recap }
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Rielaborazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
            .fullScreenCover(item: $opening) { recap in
                FixReadingView(recap: recap)
            }
            .confirmationDialog("Eliminare questa rielaborazione?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Elimina", role: .destructive) {
                    if let deleting { store.delete(deleting.id) }
                }
            } message: {
                Text("Si perdono la tua pagina scritta a mano e la versione dell'IA.")
            }
        }
    }
}

private struct RecapRow: View {
    let recap: ReadingRecap

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(recap.ai?.title.isEmpty == false ? recap.ai!.title : String(localized: "Rielaborazione"))
                    .foregroundStyle(.primary)
                Text("\(recap.pagesLabel) · \(recap.created.formatted(.relative(presentation: .named)))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if recap.finished == nil {
                Text("Da finire")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.2), in: Capsule())
                    .foregroundStyle(.orange)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
