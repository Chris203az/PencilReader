import Foundation
import Observation
import PencilKit
import ReaderCore

/// The "Fissa la lettura" recaps of every book, in Documents/Libreria/Rielaborazioni/ (backed up with
/// the library): recaps.json lists them, <id>.drawing is the reader's handwritten version.
/// They stay when their book is deleted: they are the reader's own work.
@MainActor
@Observable
final class RecapStore {
    static let shared = RecapStore()

    enum AIState: Equatable {
        case working
        case failed(String)
    }

    /// Newest first.
    private(set) var recaps: [ReadingRecap] = []
    /// The AI's version while it is being written, or why it couldn't be; nothing once it is saved.
    private(set) var aiState: [UUID: AIState] = [:]

    private let folder = URL.documentsDirectory.appending(path: "Libreria")
        .appending(path: "Rielaborazioni", directoryHint: .isDirectory)
    private var listURL: URL { folder.appending(path: "recaps.json") }

    private init() {
        if let data = try? Data(contentsOf: listURL),
           let saved = try? JSONDecoder().decode([ReadingRecap].self, from: data) {
            recaps = saved.sorted { $0.created > $1.created }
        }
    }

    func recap(withID id: UUID) -> ReadingRecap? { recaps.first { $0.id == id } }

    func toReread(of book: UUID) -> ReadingRecap? {
        ReadingRecap.toReread(of: book, in: recaps, now: .now)
    }

    func lastRecapEnd(of book: UUID) -> Int? {
        recaps.first { $0.bookID == book }?.lastPage
    }

    // MARK: Changes

    func create(book: LibraryDocument, title: String, pages: ClosedRange<Int>) -> ReadingRecap {
        let recap = ReadingRecap(bookID: book.id, bookTitle: title, firstPage: pages.lowerBound,
                                 lastPage: pages.upperBound, created: .now)
        recaps.insert(recap, at: 0)
        save()
        return recap
    }

    func markFinished(_ id: UUID) {
        update(id) { if $0.finished == nil { $0.finished = .now } }
    }

    func markOffered(_ id: UUID) {
        update(id) { $0.offered = .now }
    }

    func delete(_ id: UUID) {
        recaps.removeAll { $0.id == id }
        aiState[id] = nil
        try? FileManager.default.removeItem(at: drawingURL(of: id))
        save()
    }

    private func update(_ id: UUID, _ change: (inout ReadingRecap) -> Void) {
        guard let index = recaps.firstIndex(where: { $0.id == id }) else { return }
        change(&recaps[index])
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(recaps).write(to: listURL, options: .atomic)
    }

    // MARK: Handwriting

    private func drawingURL(of id: UUID) -> URL { folder.appending(path: "\(id.uuidString).drawing") }

    func drawing(of id: UUID) -> PKDrawing {
        (try? Data(contentsOf: drawingURL(of: id))).flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
    }

    func saveDrawing(_ drawing: PKDrawing, of id: UUID) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? drawing.dataRepresentation().write(to: drawingURL(of: id), options: .atomic)
    }

    // MARK: The AI's version

    /// Asks the AI for its re-elaboration of the recap's pages, in the background. `recognize` first
    /// makes sure every page has its text (it reads the missing ones); the text is then read from
    /// the library's OCR files, so a retry works with the book closed too.
    func writeAIVersion(of id: UUID, library: Library, recognize: (() async -> Void)? = nil) {
        guard let recap = self.recap(withID: id), recap.ai == nil, aiState[id] != .working else { return }
        aiState[id] = .working
        let hasKey = AIClient.hasKey(for: .study)
        Task {
            await recognize?()
            let urls: [(Int, URL)] = library.document(withID: recap.bookID).map { document in
                (recap.firstPage...recap.lastPage).map { ($0, library.ocrURL(of: document, page: $0)) }
            } ?? []
            let result = await Self.ask(pages: urls, hasKey: hasKey)
            switch result {
            case .success(let ai):
                update(id) { $0.ai = ai }
                aiState[id] = nil
            case .failure(let message):
                aiState[id] = self.recap(withID: id) == nil ? nil : .failed(message)
            }
        }
    }

    private enum Outcome {
        case success(AIRecap)
        case failure(String)
    }

    private nonisolated static func ask(pages urls: [(Int, URL)], hasKey: Bool) async -> Outcome {
        let pages = urls.compactMap { page, url -> (page: Int, text: String)? in
            guard let text = Library.loadText(at: url) else { return nil }
            let joined = text.blocks.map(\.text).joined(separator: "\n")
            return joined.isEmpty ? nil : (page, joined)
        }
        guard !pages.isEmpty else {
            return .failure(urls.isEmpty ? String(localized: "Il libro di queste pagine non c'è più nella libreria.")
                                         : String(localized: "Non ho trovato testo in queste pagine."))
        }
        guard hasKey else { return .failure(ExplanationError.missingKey.message) }
        do {
            return .success(try await RecapWriter.recap(fromModelText: AIClient.ask(RecapWriter.prompt(pages: pages, languages: TranslationLanguages.current),
                                                                                    for: .study)))
        } catch {
            return .failure(error.message)
        }
    }
}
