import Foundation
import Observation
import ReaderCore

/// Spaced-repetition state of the saved words, by word id, in Documents/Libreria/ripasso.json
/// (next to parole.json, so it is backed up with it). A word never reviewed has no entry.
@MainActor
@Observable
final class ReviewStore {
    private(set) var states: [UUID: ReviewState] = [:]

    private let url = URL.documentsDirectory.appending(path: "Libreria").appending(path: "ripasso.json")

    init() {
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode([UUID: ReviewState].self, from: data) else { return }
        states = saved
    }

    func dueWords(in words: [SavedWord], on date: Date = .now) -> [SavedWord] {
        ReviewSchedule.due(words, states: states, on: date)
    }

    func dueCount(in words: [SavedWord], on date: Date = .now) -> Int {
        ReviewSchedule.dueCount(words, states: states, on: date)
    }

    func record(_ grade: ReviewGrade, for word: SavedWord, on date: Date = .now) {
        let state = states[word.id] ?? .new(on: date)
        states[word.id] = state.answered(grade, on: date)
        save()
    }

    private func save() {
        try? JSONEncoder().encode(states).write(to: url, options: .atomic)
    }
}
