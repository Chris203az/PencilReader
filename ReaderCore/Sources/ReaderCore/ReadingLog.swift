import Foundation

/// Reading time and pages viewed, per day and per book, plus the study blocks completed each day.
/// Days are keyed by the local calendar date ("2026-10-25"), books by their id.
public struct ReadingLog: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var seconds: TimeInterval = 0
        /// Zero-based pages shown at least once that day.
        public var pages: Set<Int> = []
    }

    /// One day of the chart: everything read that day, or only one book.
    public struct Day: Sendable, Equatable, Identifiable {
        public let date: Date
        public let seconds: TimeInterval
        public let pages: Int
        public let focusBlocks: Int
        public var id: Date { date }
    }

    public struct BookTotal: Sendable, Equatable, Identifiable {
        public let bookID: UUID
        public let seconds: TimeInterval
        public let pages: Int
        public var id: UUID { bookID }
    }

    /// Day key → book id → entry.
    public private(set) var days: [String: [String: Entry]] = [:]
    /// Day key → study blocks (Pomodoro) completed.
    public private(set) var focusBlocks: [String: Int] = [:]

    public init() {}

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: Recording

    /// Adds the time from `start` to `end`, split at midnight so each day gets its own share.
    public mutating func addReading(of book: UUID, from start: Date, to end: Date, calendar: Calendar = .current) {
        var from = start
        while from < end {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: from)) ?? end
            let to = min(end, nextDay)
            // Whole seconds: differences between dates carry tiny floating point errors.
            days[Self.dayKey(from, calendar: calendar), default: [:]][book.uuidString, default: Entry()].seconds
                += to.timeIntervalSince(from).rounded()
            from = to
        }
    }

    public mutating func addPage(_ page: Int, of book: UUID, on date: Date, calendar: Calendar = .current) {
        days[Self.dayKey(date, calendar: calendar), default: [:]][book.uuidString, default: Entry()].pages.insert(page)
    }

    public mutating func addFocusBlock(on date: Date, calendar: Calendar = .current) {
        focusBlocks[Self.dayKey(date, calendar: calendar), default: 0] += 1
    }

    /// Forgets a deleted book.
    public mutating func remove(_ book: UUID) {
        for key in days.keys { days[key]?[book.uuidString] = nil }
        days = days.filter { !$0.value.isEmpty }
    }

    // MARK: Reading

    /// Seconds read on the day of `date`, by every book or only `book`.
    public func seconds(on date: Date, of book: UUID? = nil, calendar: Calendar = .current) -> TimeInterval {
        entries(on: date, of: book, calendar: calendar).map(\.seconds).reduce(0, +)
    }

    /// Distinct pages viewed on the day of `date` (summed over books).
    public func pages(on date: Date, of book: UUID? = nil, calendar: Calendar = .current) -> Int {
        entries(on: date, of: book, calendar: calendar).map(\.pages.count).reduce(0, +)
    }

    /// The pages of `book` viewed on the day of `date`.
    public func pagesViewed(on date: Date, of book: UUID, calendar: Calendar = .current) -> Set<Int> {
        days[Self.dayKey(date, calendar: calendar)]?[book.uuidString]?.pages ?? []
    }

    public func focusBlocks(on date: Date, calendar: Calendar = .current) -> Int {
        focusBlocks[Self.dayKey(date, calendar: calendar)] ?? 0
    }

    /// All the time ever spent on the book.
    public func totalSeconds(of book: UUID) -> TimeInterval {
        days.values.compactMap { $0[book.uuidString]?.seconds }.reduce(0, +)
    }

    /// The `count` days ending with the day of `date`, oldest first, including days with nothing read.
    public func lastDays(_ count: Int, endingOn date: Date, of book: UUID? = nil,
                         calendar: Calendar = .current) -> [Day] {
        let today = calendar.startOfDay(for: date)
        return (0..<max(count, 0)).reversed().compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            return Day(date: day,
                       seconds: seconds(on: day, of: book, calendar: calendar),
                       pages: pages(on: day, of: book, calendar: calendar),
                       focusBlocks: book == nil ? focusBlocks(on: day, calendar: calendar) : 0)
        }
    }

    /// Time and pages per book over the `count` days ending with `date`, most read first.
    public func bookTotals(lastDays count: Int, endingOn date: Date, calendar: Calendar = .current) -> [BookTotal] {
        let today = calendar.startOfDay(for: date)
        var seconds: [String: TimeInterval] = [:]
        var pages: [String: Int] = [:]
        for back in 0..<max(count, 0) {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today),
                  let books = days[Self.dayKey(day, calendar: calendar)] else { continue }
            for (book, entry) in books {
                seconds[book, default: 0] += entry.seconds
                pages[book, default: 0] += entry.pages.count
            }
        }
        return seconds.compactMap { key, value in
            UUID(uuidString: key).map { BookTotal(bookID: $0, seconds: value, pages: pages[key] ?? 0) }
        }
        .sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.bookID.uuidString < $1.bookID.uuidString }
    }

    private func entries(on date: Date, of book: UUID?, calendar: Calendar) -> [Entry] {
        guard let books = days[Self.dayKey(date, calendar: calendar)] else { return [] }
        if let book { return books[book.uuidString].map { [$0] } ?? [] }
        return Array(books.values)
    }

    // MARK: Formatting

    /// "meno di 1 min", "42 min", "1 h 5 min", "3 h".
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return String(localized: "meno di 1 min") }
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(minutes) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}
