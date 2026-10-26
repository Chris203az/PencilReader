import Foundation

/// How well a saved word was remembered when its card was turned.
public enum ReviewGrade: String, Codable, Sendable, CaseIterable {
    /// "Non la sapevo": back to the start, seen again in this session.
    case again
    /// "Difficile": remembered with effort, the interval grows a little.
    case hard
    /// "La sapevo": the interval grows by the word's ease.
    case good
}

/// Spaced-repetition state of one saved word, a simplified SM-2 counted in whole days.
public struct ReviewState: Codable, Sendable, Hashable {
    /// Multiplier of the interval after a "La sapevo"; lower for words that keep being hard.
    public var ease: Double
    /// Days until the next review, 0 while the word is still being learnt.
    public var intervalDays: Int
    /// Reviews in a row without a "Non la sapevo".
    public var streak: Int
    /// Start of the day the word is due again.
    public var due: Date
    public var lastReviewed: Date?
    public var reviews: Int

    public static let startingEase = 2.5
    public static let minimumEase = 1.3

    /// A word never reviewed, due straight away.
    public static func new(on date: Date) -> ReviewState {
        ReviewState(ease: startingEase, intervalDays: 0, streak: 0, due: date, lastReviewed: nil, reviews: 0)
    }

    /// The state after answering on `date`; the next due day is counted on `calendar`.
    public func answered(_ grade: ReviewGrade, on date: Date, calendar: Calendar = .current) -> ReviewState {
        var next = self
        switch grade {
        case .again:
            next.ease = max(Self.minimumEase, ease - 0.2)
            next.streak = 0
            next.intervalDays = 0
        case .hard:
            next.ease = max(Self.minimumEase, ease - 0.15)
            next.streak = streak + 1
            next.intervalDays = max(1, Int((Double(intervalDays) * 1.2).rounded()))
        case .good:
            next.streak = streak + 1
            switch streak {
            case 0: next.intervalDays = 1
            case 1: next.intervalDays = 3
            default: next.intervalDays = max(intervalDays + 1, Int((Double(intervalDays) * ease).rounded()))
            }
        }
        let today = calendar.startOfDay(for: date)
        // A forgotten word stays due today; the rest from the start of their day.
        next.due = next.intervalDays == 0 ? date : calendar.date(byAdding: .day, value: next.intervalDays, to: today) ?? today
        next.lastReviewed = date
        next.reviews = reviews + 1
        return next
    }

    public func isDue(on date: Date) -> Bool { due <= date }
}

public enum ReviewSchedule {
    /// The words to review on `date`: overdue ones first (the most overdue first), then
    /// the never reviewed ones (the earliest saved first).
    public static func due(_ words: [SavedWord], states: [UUID: ReviewState], on date: Date) -> [SavedWord] {
        let reviewed = words
            .compactMap { word in states[word.id].map { (word, $0) } }
            .filter { $0.1.isDue(on: date) }
            .sorted { $0.1.due < $1.1.due }
            .map(\.0)
        let new = words
            .filter { states[$0.id] == nil }
            .sorted { $0.firstLookedUp < $1.firstLookedUp }
        return reviewed + new
    }

    public static func dueCount(_ words: [SavedWord], states: [UUID: ReviewState], on date: Date) -> Int {
        words.count(where: { word in states[word.id].map { $0.isDue(on: date) } ?? true })
    }
}

/// One sitting of flashcards: each card once, plus again at the end each time it is forgotten.
public struct ReviewSession: Sendable {
    public private(set) var queue: [UUID]
    /// Cards answered "Difficile" or "La sapevo"; a forgotten card counts when it is finally known.
    public private(set) var done = 0
    public private(set) var forgotten = 0
    public let total: Int

    public init(cards: [UUID]) {
        queue = cards
        total = cards.count
    }

    public var current: UUID? { queue.first }
    public var isFinished: Bool { queue.isEmpty }

    public mutating func answer(_ grade: ReviewGrade) {
        guard !queue.isEmpty else { return }
        let card = queue.removeFirst()
        if grade == .again {
            forgotten += 1
            queue.append(card)
        } else {
            done += 1
        }
    }
}
