import PDFKit
import PencilKit
import ReaderCore
import SwiftUI

// MARK: Kinds

/// What a study mark says, from its ink: the three highlighter colors, the underlined terms
/// and the margin notes. Its raw value is the kind of the summary's zones.
enum SummaryKind: String, CaseIterable, Identifiable {
    case key, formula, review, term, note

    var id: String { rawValue }

    var label: String {
        switch self {
        case .key: StudyColor.key.label
        case .formula: StudyColor.formula.label
        case .review: StudyColor.review.label
        case .term: "Termini inglesi"
        case .note: "Note a margine"
        }
    }

    var detail: String {
        switch self {
        case .key: "Definizioni e idee principali"
        case .formula: "Equazioni, valori, ipotesi e unità"
        case .review: "Non chiaro: da rivedere o chiedere"
        case .term: "Parole tecniche sottolineate"
        case .note: "Domande e note scritte a penna"
        }
    }

    var color: Color {
        switch self {
        case .key: StudyColor.key.color
        case .formula: StudyColor.formula.color
        case .review: StudyColor.review.color
        case .term: Color(uiColor: StudyTool.underlineColor)
        case .note: Color(uiColor: StudyTool.penColor)
        }
    }

    var systemImage: String {
        switch self {
        case .key, .formula, .review: "highlighter"
        case .term: "underline"
        case .note: "pencil.line"
        }
    }

    /// Words sit above an underline: its zone reaches up by about a line of text.
    var textReach: CGFloat { self == .term ? 0.025 : 0 }

    /// The nearest of the study colors, so marks saved with an older shade still find their kind.
    init(stroke: PKStroke) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        stroke.ink.color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func distance(_ color: UIColor) -> CGFloat {
            var cr: CGFloat = 0, cg: CGFloat = 0, cb: CGFloat = 0, ca: CGFloat = 0
            color.getRed(&cr, green: &cg, blue: &cb, alpha: &ca)
            return pow(r - cr, 2) + pow(g - cg, 2) + pow(b - cb, 2)
        }
        let candidates: [(SummaryKind, UIColor)]
        if stroke.ink.inkType == .marker {
            candidates = [(.key, StudyColor.key.uiColor),
                          // The yellow of the first highlighter, now orange.
                          (.key, UIColor(red: 1, green: 0.86, blue: 0.1, alpha: 1)),
                          (.formula, StudyColor.formula.uiColor),
                          (.review, StudyColor.review.uiColor)]
        } else {
            candidates = [(.term, StudyTool.underlineColor), (.note, StudyTool.penColor)]
        }
        self = candidates.min { distance($0.1) < distance($1.1) }?.0 ?? .key
    }
}

/// One marked zone of one page, as the summary lists it.
struct SummaryEntry: Identifiable, Sendable {
    let page: Int
    let index: Int
    let kind: SummaryKind
    /// Normalized to the page, top-left origin.
    let rect: CGRect
    /// Page height over width, to size the crop before it is drawn.
    let pageAspect: CGFloat
    /// The recognized words under the zone; empty without OCR and for margin notes.
    let text: String

    var id: String { "\(page)-\(index)" }

    /// Width over height of the crop.
    var aspect: CGFloat {
        guard rect.height > 0 else { return 1 }
        return rect.width / (rect.height * pageAspect)
    }
}

// MARK: Renderer

/// Reads the marks of every page and draws the crops, off the main thread. Own PDF instance,
/// as PDFDocument is not thread-safe.
actor SummaryRenderer {
    /// Longest side, in pixels, of the page the crops are cut from.
    private static let pagePixels: CGFloat = 2000
    /// The width of the marks' drawing, as in `StudyCanvasView`, whatever the page's size.
    private static let drawingWidth: CGFloat = 1000

    private let bookID: UUID
    private let pdfURL: URL?
    private let pagesFolder: URL?
    private var pdf: PDFDocument?
    private let pages = NSCache<NSNumber, UIImage>()
    private let crops = NSCache<NSString, UIImage>()

    init(bookID: UUID, pdfURL: URL?, pagesFolder: URL?) {
        self.bookID = bookID
        self.pdfURL = pdfURL
        self.pagesFolder = pagesFolder
        pages.countLimit = 3
        crops.totalCostLimit = 60 * 1024 * 1024
    }

    /// The zones of the given pages, in page order and then in reading order.
    func entries(pages: [Int], ocrURLs: [Int: URL]) -> [SummaryEntry] {
        var entries: [SummaryEntry] = []
        for page in pages {
            if Task.isCancelled { break }
            guard let drawing = AnnotationStore.drawing(of: bookID, page: page), !drawing.strokes.isEmpty,
                  let size = pageSize(page), size.width > 0 else { continue }
            let aspect = size.height / size.width
            let height = Self.drawingWidth * aspect
            let marks = drawing.strokes.map { stroke in
                let b = stroke.renderBounds
                return MarkSummary.Mark(kind: SummaryKind(stroke: stroke).rawValue,
                                        rect: CGRect(x: b.minX / Self.drawingWidth, y: b.minY / height,
                                                     width: b.width / Self.drawingWidth, height: b.height / height))
            }
            let text = ocrURLs[page].flatMap { Library.loadText(at: $0) }
            for (index, zone) in MarkSummary.zones(of: marks).enumerated() {
                let kind = SummaryKind(rawValue: zone.kind) ?? .key
                let words = kind == .note ? "" : text.map { MarkSummary.text(of: zone, in: $0, above: kind.textReach) } ?? ""
                entries.append(SummaryEntry(page: page, index: index, kind: kind, rect: zone.rect,
                                            pageAspect: aspect, text: words))
            }
        }
        return entries
    }

    /// The zone of the page with its marks over it, as on screen.
    func crop(_ entry: SummaryEntry) -> UIImage? {
        if let cached = crops.object(forKey: entry.id as NSString) { return cached }
        if Task.isCancelled { return nil }
        guard let page = pageImage(entry.page), let cgPage = page.cgImage else { return nil }
        let w = CGFloat(cgPage.width), h = CGFloat(cgPage.height)
        let pixels = CGRect(x: entry.rect.minX * w, y: entry.rect.minY * h,
                            width: entry.rect.width * w, height: entry.rect.height * h).integral
        guard let cut = cgPage.cropping(to: pixels) else { return nil }
        let drawing = AnnotationStore.drawing(of: bookID, page: entry.page) ?? PKDrawing()
        let unit = Self.drawingWidth / w
        let area = CGRect(x: pixels.minX * unit, y: pixels.minY * unit, width: pixels.width * unit, height: pixels.height * unit)
        var marks: UIImage?
        // Ink keeps its light-mode colors over the white page, as in study mode.
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            marks = drawing.image(from: area, scale: 1 / unit)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: pixels.size, format: format).image { _ in
            let bounds = CGRect(origin: .zero, size: pixels.size)
            UIImage(cgImage: cut).draw(in: bounds)
            // Multiplied like the highlighter on screen: the words stay black under the color.
            marks?.draw(in: bounds, blendMode: .multiply, alpha: 1)
        }
        crops.setObject(image, forKey: entry.id as NSString, cost: Int(pixels.width * pixels.height * 4))
        return image
    }

    private func pageSize(_ index: Int) -> CGSize? {
        if let pdfURL {
            if pdf == nil { pdf = PDFDocument(url: pdfURL) }
            guard let page = pdf?.page(at: index) else { return nil }
            var size = page.bounds(for: .cropBox).size
            if page.rotation % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
            return size
        }
        // Only the header is read, not the pixels.
        return imageURL(index).flatMap { UIImage(contentsOfFile: $0.path(percentEncoded: false))?.size }
    }

    private func pageImage(_ index: Int) -> UIImage? {
        if let cached = pages.object(forKey: index as NSNumber) { return cached }
        let image: UIImage?
        if let pdfURL {
            if pdf == nil { pdf = PDFDocument(url: pdfURL) }
            image = pdf?.page(at: index).map { PageImages.render($0, maxDimension: Self.pagePixels) }
        } else {
            image = imageURL(index).flatMap { UIImage(contentsOfFile: $0.path(percentEncoded: false)) }
                .map { PageImages.normalized($0, maxDimension: Self.pagePixels) }
        }
        if let image { pages.setObject(image, forKey: index as NSNumber) }
        return image
    }

    private func imageURL(_ index: Int) -> URL? {
        pagesFolder?.appending(path: String(format: "%04d.jpg", index))
    }
}

// MARK: View

/// Everything marked in the book on one page: the highlighted passages cut out of their pages,
/// grouped by what their color means, the underlined terms, the margin notes and the pages with
/// a notebook note. A tap opens the page.
struct MarkSummaryView: View {
    enum Filter: Hashable {
        case all
        case kind(SummaryKind)
        case notebook
    }

    let document: LibraryDocument
    /// The page, and whether to open the notebook beside it.
    let select: (Int, Bool) -> Void

    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var renderer: SummaryRenderer?
    @State private var entries: [SummaryEntry]?
    @State private var notedPages: [Int] = []
    @State private var filter: Filter = .all

    private let columns = [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)]

    var body: some View {
        NavigationStack {
            Group {
                if let entries {
                    if entries.isEmpty && notedPages.isEmpty {
                        ContentUnavailableView(
                            "Ancora niente da riepilogare", systemImage: "highlighter",
                            description: Text("Evidenzia, sottolinea o scrivi a margine in modalità studio: i segni del libro compaiono qui, divisi per colore."))
                    } else {
                        content(entries)
                    }
                } else {
                    ProgressView("Raccolgo i segni…")
                }
            }
            .navigationTitle("Riepilogo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        let renderer = SummaryRenderer(
            bookID: document.id,
            pdfURL: document.kind == .pdf ? library.pdfURL(of: document) : nil,
            pagesFolder: document.kind == .images
                ? library.imageURL(of: document, page: 0).deletingLastPathComponent() : nil)
        self.renderer = renderer
        notedPages = NoteStore.pagesWithNotes(of: document.id).sorted()
        let pages = AnnotationStore.pagesWithMarks(of: document.id).sorted()
        var ocr: [Int: URL] = [:]
        for page in pages { ocr[page] = library.ocrURL(of: document, page: page) }
        entries = await renderer.entries(pages: pages, ocrURLs: ocr)
    }

    private func content(_ entries: [SummaryEntry]) -> some View {
        let byKind = Dictionary(grouping: entries, by: \.kind)
        let kinds = SummaryKind.allCases.filter { byKind[$0] != nil }
        return ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                filterBar(kinds: kinds, byKind: byKind)
                ForEach(kinds) { kind in
                    if filter == .all || filter == .kind(kind) {
                        section(kind, entries: byKind[kind] ?? [])
                    }
                }
                if !notedPages.isEmpty && (filter == .all || filter == .notebook) {
                    notebookSection
                }
            }
            .padding(20)
        }
    }

    private func filterBar(kinds: [SummaryKind], byKind: [SummaryKind: [SummaryEntry]]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(.all, title: "Tutti", color: .accentColor, count: nil)
                ForEach(kinds) { kind in
                    chip(.kind(kind), title: kind.label, color: kind.color, count: byKind[kind]?.count)
                }
                if !notedPages.isEmpty {
                    chip(.notebook, title: "Quaderno", color: .orange, count: notedPages.count)
                }
            }
        }
    }

    private func chip(_ value: Filter, title: String, color: Color, count: Int?) -> some View {
        let selected = filter == value
        return Button {
            filter = value
        } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(title)
                if let count {
                    Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(selected ? color.opacity(0.25) : Color(.secondarySystemBackground), in: Capsule())
            .overlay(Capsule().stroke(selected ? color : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func section(_ kind: SummaryKind, entries: [SummaryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(kind.label, detail: kind.detail, systemImage: kind.systemImage, color: kind.color,
                          count: entries.count)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(entries) { entry in
                    Button {
                        select(entry.page, false)
                        dismiss()
                    } label: {
                        SummaryCard(entry: entry, renderer: renderer)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var notebookSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Note del quaderno", detail: "Pagine con una nota scritta a fianco",
                          systemImage: "square.and.pencil", color: .orange, count: notedPages.count)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 170), spacing: 16)], spacing: 16) {
                ForEach(notedPages, id: \.self) { page in
                    Button {
                        select(page, true)
                        dismiss()
                    } label: {
                        NotebookPageCard(bookID: document.id, page: page)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionHeader(_ title: String, detail: String, systemImage: String, color: Color, count: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .font(.title3)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(count)")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

/// One zone: its crop, the page it comes from and the words under it.
private struct SummaryCard: View {
    let entry: SummaryEntry
    let renderer: SummaryRenderer?

    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Rectangle().fill(.quaternary)
                        .aspectRatio(entry.aspect, contentMode: .fit)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 240)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            if !entry.text.isEmpty {
                Text(entry.text)
                    .font(.callout)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text("Pagina \(entry.page + 1)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                Image(systemName: "arrow.up.forward.square")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                .fill(entry.kind.color)
                .frame(width: 4)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Apre la pagina \(entry.page + 1)")
        .task(id: entry.id) { image = await renderer?.crop(entry) }
    }
}

/// The handwriting of a notebook page, scaled down on white, with its page number.
private struct NotebookPageCard: View {
    let bookID: UUID
    let page: Int

    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().padding(6)
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(height: 170)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
            Text("Pagina \(page + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .task(id: page) {
            guard let drawing = NoteStore.drawing(of: bookID, page: page), !drawing.bounds.isEmpty else { return }
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                image = drawing.image(from: drawing.bounds, scale: 0.5)
            }
        }
    }
}
