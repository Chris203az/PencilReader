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

    /// What `undo(_:)` needs to take back one `add`.
    struct Addition {
        let key: String
        /// The entry as it was before, nil when the word was new.
        let previous: SavedWord?
    }

    /// Adds the word, or updates it when it was already looked up in the same book.
    @discardableResult
    func add(_ word: SavedWord) -> Addition {
        let addition: Addition
        if let index = words.firstIndex(where: { $0.key == word.key }) {
            var existing = words.remove(at: index)
            addition = Addition(key: word.key, previous: existing)
            existing.merge(word)
            words.insert(existing, at: 0)
        } else {
            addition = Addition(key: word.key, previous: nil)
            words.insert(word, at: 0)
        }
        save()
        return addition
    }

    /// Takes back a lookup: removes a new word, or restores the entry as it was.
    func undo(_ addition: Addition) {
        words.removeAll { $0.key == addition.key }
        if let previous = addition.previous {
            words.append(previous)
            words.sort { $0.lastLookedUp > $1.lastLookedUp }
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
