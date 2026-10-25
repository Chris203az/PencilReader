import Foundation
import Observation
import ReaderCore

/// Every word circled while reading, saved in Documents/Libreria/parole.json
/// (backed up together with the library through the Files app).
@MainActor
@Observable
final class WordList {
    /// Most recently looked up first.
    private(set) var words: [SavedWord] = []

    private let url = URL.documentsDirectory.appending(path: "Libreria").appending(path: "parole.json")

    init() {
        reload()
    }

    func reload() {
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode([SavedWord].self, from: data) else { return }
        words = saved.sorted { $0.lastLookedUp > $1.lastLookedUp }
    }

    func words(in documentID: UUID) -> [SavedWord] {
        words.filter { $0.documentID == documentID }
    }

    /// Adds the word, or updates it when it was already looked up in the same book.
    func add(_ word: SavedWord) {
        if let index = words.firstIndex(where: { $0.key == word.key }) {
            var existing = words.remove(at: index)
            existing.merge(word)
            words.insert(existing, at: 0)
        } else {
            words.insert(word, at: 0)
        }
        save()
    }

    func delete(_ ids: Set<UUID>) {
        words.removeAll { ids.contains($0.id) }
        save()
    }

    private func save() {
        try? JSONEncoder().encode(words).write(to: url, options: .atomic)
    }
}
