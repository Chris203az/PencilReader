import Observation
import PDFKit
import ReaderCore
import SwiftUI
import Translation

/// State of one open document: current page, its OCR, the lasso selection.
@MainActor
@Observable
final class ReaderModel {
    enum Source {
        case images
        case pdf(PDFDocument)
    }

    struct Selection: Identifiable {
        let id = UUID()
        let wordIDs: [Int]
        /// Bounding box of the lasso, normalized to the page image.
        let anchor: CGRect
        let text: String
        let context: SentenceContext?
        /// The translated sentence (or just the term when there's no sentence).
        var translation: String?
        /// Part of `translation` corresponding to the circled words.
        var highlight: Range<String.Index>?
        /// Shown separately only when it couldn't be located in the sentence.
        var termTranslation: String?
        var error: String?
    }

    let document: LibraryDocument
    let pageCount: Int
    private(set) var pageIndex = 0
    private(set) var pageImage: UIImage?
    private(set) var pageText: PageText?
    private(set) var selection: Selection?
    var showWordBoxes = false
    var allowsFingerDrawing = false
    var translationConfig: TranslationSession.Configuration?
    var alertMessage: String?
    /// Words found by the book search, highlighted on their page.
    private(set) var searchHighlight: (page: Int, wordIDs: Set<Int>)?

    private let library: Library
    private let wordList: WordList
    private let source: Source?
    private var imageCache: [Int: UIImage] = [:]
    private var textCache: [Int: PageText] = [:]
    private var ocrTasks: [Int: Task<PageText, Error>] = [:]
    private let ocr = OCRService()

    var title: String { library.document(withID: document.id)?.title ?? document.title }
    var isRecognizing: Bool { pageImage != nil && pageText == nil }

    init(document: LibraryDocument, library: Library, wordList: WordList) {
        self.document = document
        self.library = library
        self.wordList = wordList
        pageCount = document.pageCount
        switch document.kind {
        case .images: source = .images
        case .pdf: source = PDFDocument(url: library.pdfURL(of: document)).map(Source.pdf)
        }
        library.markOpened(document)
        if source == nil {
            alertMessage = "Impossibile aprire il documento."
        } else {
            showPage(min(max(document.lastPage, 0), pageCount - 1))
        }
    }

    // MARK: Pages

    func showPage(_ index: Int) {
        guard source != nil, (0..<pageCount).contains(index) else { return }
        pageIndex = index
        selection = nil
        searchHighlight = nil
        pageImage = image(at: index)
        pageText = textCache[index]
        imageCache = imageCache.filter { abs($0.key - index) <= 1 }
        library.setLastPage(index, of: document)
        Task { await recognizeCurrentPage() }
    }

    /// Opens the page of a search result with its words highlighted.
    func showMatch(page: Int, wordIDs: [Int]) {
        showPage(page)
        searchHighlight = (page, Set(wordIDs))
    }

    var searchHighlightOnPage: Set<Int> {
        guard let searchHighlight, searchHighlight.page == pageIndex else { return [] }
        return searchHighlight.wordIDs
    }

    func nextPage() { showPage(pageIndex + 1) }
    func previousPage() { showPage(pageIndex - 1) }

    private func image(at index: Int) -> UIImage? {
        if let cached = imageCache[index] { return cached }
        let image: UIImage?
        switch source {
        case .images:
            image = UIImage(contentsOfFile: library.imageURL(of: document, page: index).path(percentEncoded: false))
        case .pdf(let pdf):
            image = pdf.page(at: index).map { PageImages.render($0) }
        case nil:
            image = nil
        }
        imageCache[index] = image
        return image
    }

    /// OCR runs once per page and is saved with the document; the next page
    /// is prepared in the background so turning the page doesn't wait for it.
    private func recognizeCurrentPage() async {
        let index = pageIndex
        do {
            let text = try await recognizedText(for: index)
            if pageIndex == index { pageText = text }
            if index + 1 < pageCount { _ = try? await recognizedText(for: index + 1) }
        } catch is CancellationError {
        } catch {
            if pageIndex == index { alertMessage = "Riconoscimento del testo non riuscito: \(error.localizedDescription)" }
        }
    }

    private func recognizedText(for index: Int) async throws -> PageText {
        if let cached = textCache[index] { return cached }
        if let saved = library.savedText(of: document, page: index) {
            textCache[index] = saved
            return saved
        }
        let task: Task<PageText, Error>
        if let running = ocrTasks[index] {
            task = running
        } else {
            guard let cgImage = image(at: index)?.cgImage else { return PageText(lines: []) }
            let ocr = self.ocr
            task = Task.detached(priority: .userInitiated) { try await ocr.recognize(cgImage) }
            ocrTasks[index] = task
        }
        let text = try await task.value
        if textCache[index] == nil {
            textCache[index] = text
            library.saveText(text, of: document, page: index)
        }
        ocrTasks[index] = nil
        return text
    }

    // MARK: Selection

    /// `stroke` and `imageFrame` are in the same view coordinates.
    func select(stroke: [CGPoint], imageFrame: CGRect) {
        guard let pageText, stroke.count >= 2 else {
            selection = nil
            return
        }
        let rects = pageText.words.map { $0.rect.denormalized(in: imageFrame) }
        let ids = LassoSelector.select(stroke: stroke, wordRects: rects)
        let text = pageText.text(for: ids)
        guard !ids.isEmpty, !text.isEmpty else {
            selection = nil
            return
        }
        selection = Selection(wordIDs: ids,
                              anchor: CGRect(boundingPoints: stroke).normalized(in: imageFrame),
                              text: text,
                              context: pageText.contextSentences(for: ids))
        if translationConfig == nil {
            translationConfig = .init(source: Locale.Language(identifier: "en"),
                                      target: Locale.Language(identifier: "it"))
        } else {
            translationConfig?.invalidate()
        }
    }

    func clearSelection() { selection = nil }

    /// Called by `.translationTask` every time the configuration is (re)triggered.
    func translate(using session: TranslationSession) async {
        guard let current = selection, current.translation == nil else { return }
        let marked = current.context.flatMap(TranslationHighlighter.marked)
        var requests = [TranslationSession.Request(sourceText: current.text, clientIdentifier: "term")]
        if let context = current.context {
            requests.append(.init(sourceText: context.text, clientIdentifier: "sentence"))
        }
        if let marked {
            requests.append(.init(sourceText: marked.text, clientIdentifier: "marked"))
        }
        do {
            let responses = try await session.translations(from: requests)
            guard selection?.id == current.id else { return }
            var output: [String: String] = [:]
            for response in responses {
                if let id = response.clientIdentifier { output[id] = response.targetText }
            }
            let term = output["term"] ?? current.text
            let result = Self.highlightedSentence(term: term, sentence: output["sentence"],
                                                  marked: output["marked"], markers: marked,
                                                  source: current)
            selection?.translation = result.text
            selection?.highlight = result.highlight
            selection?.termTranslation = result.highlight == nil ? term : nil
            wordList.add(SavedWord(term: current.text,
                                   translation: result.highlight.map { String(result.text[$0]) } ?? term,
                                   sentence: current.context?.text,
                                   sentenceTranslation: current.context == nil ? nil : result.text,
                                   documentID: document.id, documentTitle: title,
                                   page: pageIndex, date: .now))
        } catch {
            guard selection?.id == current.id else { return }
            selection?.error = "Traduzione non disponibile: \(error.localizedDescription)"
        }
    }

    /// Prefers the quoted translation (exact alignment); falls back to finding
    /// the separately translated term in the plain sentence translation.
    private static func highlightedSentence(term: String, sentence: String?, marked: String?,
                                            markers: TranslationHighlighter.Marked?,
                                            source: Selection) -> (text: String, highlight: Range<String.Index>?) {
        guard let sentence else { return (term, term.startIndex..<term.endIndex) }

        if let marked, let markers,
           let unmarked = TranslationHighlighter.unmark(marked, open: markers.open, close: markers.close) {
            // Quotes can make the engine keep the word in English; then the plain sentence is better.
            let inside = unmarked.text[unmarked.highlight]
            let leftUntranslated = inside.caseInsensitiveCompare(source.text) == .orderedSame
                && term.caseInsensitiveCompare(source.text) != .orderedSame
            if !leftUntranslated { return unmarked }
        }

        let position = source.context?.selectionPosition
        if let range = TranslationHighlighter.fuzzyRange(of: term, in: sentence, expectedPosition: position) {
            return (sentence, range)
        }
        return (sentence, nil)
    }
}
