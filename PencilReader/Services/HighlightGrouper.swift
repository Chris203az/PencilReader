import Foundation
import Observation
import PencilKit
import ReaderCore

/// The AI's groups of each page of a book, in Application Support/HighlightGroups/<book>.json.
enum HighlightGroupStore {
    private static var root: URL {
        URL.applicationSupportDirectory.appending(path: "HighlightGroups", directoryHint: .isDirectory)
    }

    private static func url(of bookID: UUID) -> URL {
        root.appending(path: "\(bookID.uuidString).json")
    }

    /// Keyed by page index.
    static func pages(of bookID: UUID) -> [Int: HighlightGrouping.Page] {
        guard let data = try? Data(contentsOf: url(of: bookID)),
              let saved = try? JSONDecoder().decode([String: HighlightGrouping.Page].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: saved.compactMap { key, page in Int(key).map { ($0, page) } })
    }

    /// Nil removes the page.
    static func set(_ page: HighlightGrouping.Page?, of bookID: UUID, page index: Int) {
        var all = pages(of: bookID)
        guard all[index] != page else { return }
        all[index] = page
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let saved = Dictionary(uniqueKeysWithValues: all.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: url(of: bookID), options: .atomic)
        }
    }

    /// Called when the book itself is deleted.
    static func delete(of bookID: UUID) {
        try? FileManager.default.removeItem(at: url(of: bookID))
    }
}

/// When a page is left, sends its highlighted passages to Gemini, which joins the separate pieces
/// that say the same thing. Runs in the background and never interrupts reading: without a key,
/// offline or on an error nothing happens, and the page is tried again the next time it is left.
/// A page whose highlights haven't changed since its last answer is not sent again.
@MainActor
@Observable
final class HighlightGrouper {
    static let shared = HighlightGrouper()

    /// Bumped when a page's groups are saved, so an open summary can reload.
    private(set) var revision = 0

    @ObservationIgnored private var running: Set<String> = []
    /// The marks of the page just left are saved a moment after the page changes.
    private static let delay = Duration.seconds(2)

    private init() {}

    /// `aspect` is the page's height over its width.
    func pageLeft(_ page: Int, of bookID: UUID, aspect: CGFloat?, ocrURL: URL) {
        guard let aspect, aspect > 0 else { return }
        let key = "\(bookID)-\(page)"
        guard running.insert(key).inserted else { return }
        let apiKey = APIKeyStore.shared.googleKey
        Task {
            try? await Task.sleep(for: Self.delay)
            // Saved here, on the main actor, so two pages of one book never write the file at once.
            if case .some(let result) = await Self.group(page, of: bookID, aspect: aspect, ocrURL: ocrURL, apiKey: apiKey) {
                HighlightGroupStore.set(result, of: bookID, page: page)
                revision += 1
            }
            running.remove(key)
        }
    }

    /// The highlighted passages of a page as sent to the AI: the summary's zones of the three
    /// highlighter colors that have words under them.
    nonisolated static func fragments(of entries: [SummaryEntry]) -> [HighlightGrouping.Fragment] {
        entries.filter { $0.kind.isHighlight && !$0.text.isEmpty }
            .map { HighlightGrouping.Fragment(id: $0.index, kind: $0.kind.rawValue, text: $0.text) }
    }

    /// The page's new groups (nil when it has no highlights left), or nothing when the saved ones stay.
    private nonisolated static func group(_ page: Int, of bookID: UUID, aspect: CGFloat, ocrURL: URL,
                                          apiKey: String?) async -> HighlightGrouping.Page?? {
        let drawing = AnnotationStore.drawing(of: bookID, page: page) ?? PKDrawing()
        let text = Library.loadText(at: ocrURL)
        let fragments = fragments(of: SummaryRenderer.entries(page: page, drawing: drawing, aspect: aspect, text: text))
        let saved = HighlightGroupStore.pages(of: bookID)[page]
        if fragments.isEmpty {
            let removed: HighlightGrouping.Page?? = saved == nil ? .none : .some(nil)
            return removed
        }
        let signature = HighlightGrouping.signature(of: fragments)
        guard saved?.signature != signature else { return .none }
        let groups: [HighlightGrouping.Group]
        if HighlightGrouping.needsAsking(fragments) {
            guard let apiKey else { return .none }
            do {
                let pageText = text?.blocks.map(\.text).joined(separator: "\n")
                groups = try await WordExplainer.group(fragments, pageText: pageText, apiKey: apiKey)
            } catch {
                return .none
            }
        } else {
            groups = HighlightGrouping.separate(fragments)
        }
        return .some(HighlightGrouping.Page(signature: signature, groups: groups))
    }
}

extension WordExplainer {
    /// The meaning of each highlighter color, as the AI reads it.
    static let kindNames = Dictionary(uniqueKeysWithValues: StudyColor.allCases.map { ($0.rawValue, $0.label) })

    static func group(_ fragments: [HighlightGrouping.Fragment], pageText: String?,
                      apiKey: String) async throws(ExplanationError) -> [HighlightGrouping.Group] {
        try await firstAnswer { model in
            try await HighlightGrouping.parse(send(HighlightGrouping.request(fragments: fragments, kindNames: kindNames,
                                                                             pageText: pageText, apiKey: apiKey,
                                                                             model: model)),
                                              fragments: fragments)
        }
    }
}
