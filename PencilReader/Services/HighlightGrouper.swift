import Foundation
import Observation
import PencilKit
import ReaderCore

/// The key concepts of each book, in Application Support/HighlightGroups/<book>.json.
enum HighlightGroupStore {
    private static var root: URL {
        URL.applicationSupportDirectory.appending(path: "HighlightGroups", directoryHint: .isDirectory)
    }

    private static func url(of bookID: UUID) -> URL {
        root.appending(path: "\(bookID.uuidString).json")
    }

    /// Empty when nothing was compacted yet, or when the file is from the first version (grouped
    /// page by page): those pages are compacted again.
    static func book(_ bookID: UUID) -> HighlightGrouping.Book {
        guard let data = try? Data(contentsOf: url(of: bookID)),
              let saved = try? JSONDecoder().decode(HighlightGrouping.Book.self, from: data) else { return .init() }
        return saved
    }

    static func save(_ book: HighlightGrouping.Book, of bookID: UUID) {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(book) {
            try? data.write(to: url(of: bookID), options: .atomic)
        }
    }

    /// Called when the book itself is deleted.
    static func delete(of bookID: UUID) {
        try? FileManager.default.removeItem(at: url(of: bookID))
    }
}

/// What the grouper needs to read a page's highlights: its height over its width and its OCR file.
struct HighlightPage: Sendable {
    let aspect: CGFloat
    let ocrURL: URL
}

/// Compacts the highlights of a book into key concepts with the AI chosen for the study functions.
///
/// Automatically, when a page is left: its highlights go to the AI with those of the page before,
/// so a list or a sentence that continues across the page break is joined. This runs in the
/// background and never interrupts reading: without a key, offline or on an error nothing happens,
/// and the page is tried again the next time it is left. A page whose highlights haven't changed
/// since it was last compacted is not sent again.
///
/// By hand, from the summary, on a range of pages: always sent, and errors are shown.
///
/// One request at a time, so two answers never overwrite each other's concepts.
@MainActor
@Observable
final class HighlightGrouper {
    static let shared = HighlightGrouper()

    /// Bumped when a book's concepts are saved, so an open summary can reload.
    private(set) var revision = 0

    /// The last request, which the next one waits for.
    @ObservationIgnored private var queue: Task<Void, Never>?
    /// Automatic requests waiting in the queue, so leaving a page twice asks only once.
    @ObservationIgnored private var waiting: Set<String> = []
    /// The marks of the page just left are saved a moment after the page changes.
    private static let delay = Duration.seconds(2)

    private init() {}

    /// Compacts the page just left, with the one before. `info` describes any page of the book.
    func pageLeft(_ page: Int, of bookID: UUID, info: @escaping @MainActor (Int) -> HighlightPage?) {
        let key = "\(bookID)-\(page)"
        guard waiting.insert(key).inserted else { return }
        let hasKey = AIClient.hasKey(for: .study)
        schedule {
            try? await Task.sleep(for: Self.delay)
            self.waiting.remove(key)
            _ = try? await self.compact(pages: Set([page - 1, page].filter { $0 >= 0 }), changed: page,
                                        of: bookID, hasKey: hasKey, info: info)
        }
    }

    /// Compacts the given pages by hand; returns how many concepts of more than one passage they have now.
    func compact(pages: ClosedRange<Int>, of bookID: UUID,
                 info: @escaping @MainActor (Int) -> HighlightPage?) async throws(ExplanationError) -> Int {
        guard AIClient.hasKey(for: .study) else { throw .missingKey }
        let result = await schedule { () -> Result<Int, ExplanationError> in
            do throws(ExplanationError) {
                return .success(try await self.compact(pages: Set(pages), changed: nil, of: bookID,
                                                       hasKey: true, info: info))
            } catch {
                return .failure(error)
            }
        }.value
        return try result.get()
    }

    /// Runs `work` after the requests before it.
    @discardableResult
    private func schedule<T: Sendable>(_ work: @escaping @MainActor () async -> T) -> Task<T, Never> {
        let previous = queue
        let task = Task {
            await previous?.value
            return await work()
        }
        queue = Task { _ = await task.value }
        return task
    }

    /// Sends `pages` (with the passages of concepts reaching outside them) and saves the answer.
    /// With `changed`, nothing is sent unless that page's highlights changed since it was compacted.
    private func compact(pages: Set<Int>, changed: Int?, of bookID: UUID, hasKey: Bool,
                         info: @MainActor (Int) -> HighlightPage?) async throws(ExplanationError) -> Int {
        let book = HighlightGroupStore.book(bookID)
        let all = pages.union(HighlightGrouping.linkedPages(of: pages, in: book))
        let infos = Dictionary(uniqueKeysWithValues: all.compactMap { page in info(page).map { (page, $0) } })
        let read = await Self.read(infos, of: bookID)
        if let changed, !book.needsCompacting(changed, fragments: read.fragments[changed] ?? []) {
            return 0
        }
        let scope = HighlightGrouping.scope(of: pages, fragments: read.fragments, book: book)
        var answer: [HighlightGrouping.Concept] = []
        if HighlightGrouping.needsAsking(scope) {
            guard hasKey else { throw .missingKey }
            answer = try await AIClient.compact(scope, pageTexts: read.texts.filter { pages.contains($0.key) })
        }
        // Read again: nothing else writes while this runs, but the book may have been deleted.
        let merged = HighlightGrouping.merging(answer, compacted: pages, fragments: read.fragments,
                                               into: HighlightGroupStore.book(bookID))
        HighlightGroupStore.save(merged, of: bookID)
        revision += 1
        return merged.concepts.filter { !$0.pages.isDisjoint(with: pages) }.count
    }

    /// The highlighted passages and the text of each page, off the main thread.
    private nonisolated static func read(_ pages: [Int: HighlightPage], of bookID: UUID) async
        -> (fragments: [Int: [HighlightGrouping.Fragment]], texts: [Int: String]) {
        var fragments: [Int: [HighlightGrouping.Fragment]] = [:]
        var texts: [Int: String] = [:]
        for (page, info) in pages {
            let drawing = AnnotationStore.drawing(of: bookID, page: page) ?? PKDrawing()
            let text = Library.loadText(at: info.ocrURL)
            fragments[page] = Self.fragments(of: SummaryRenderer.entries(page: page, drawing: drawing,
                                                                         aspect: info.aspect, text: text))
            texts[page] = text?.blocks.map(\.text).joined(separator: "\n")
        }
        return (fragments, texts)
    }

    /// The highlighted passages of a page as sent to the AI: the summary's zones of the three
    /// highlighter colors that have words under them, in reading order.
    nonisolated static func fragments(of entries: [SummaryEntry]) -> [HighlightGrouping.Fragment] {
        guard let page = entries.first?.page else { return [] }
        return HighlightGrouping.fragments(page: page, passages: entries.filter(\.kind.isHighlight)
            .sorted { $0.index < $1.index }
            .map { ($0.kind.rawValue, $0.text) })
    }
}

extension AIClient {
    /// The meaning of each highlighter color, as the AI reads it.
    static let kindNames = Dictionary(uniqueKeysWithValues: StudyColor.allCases.map { ($0.rawValue, $0.label) })

    static func compact(_ fragments: [HighlightGrouping.Fragment],
                        pageTexts: [Int: String]) async throws(ExplanationError) -> [HighlightGrouping.Concept] {
        let prompt = HighlightGrouping.prompt(fragments: fragments, kindNames: kindNames, pageTexts: pageTexts)
        return try HighlightGrouping.concepts(fromModelText: await ask(prompt, for: .study), fragments: fragments)
    }
}
