import Foundation
import Testing
@testable import ReaderCore

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

/// 25 October 2026 at `hour` UTC, plus `days`.
private func day(_ days: Int = 0, hour: Int = 15) -> Date {
    let start = utc.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: hour))!
    return utc.date(byAdding: .day, value: days, to: start)!
}

private func word(_ term: String, savedOn date: Date) -> SavedWord {
    SavedWord(term: term, translation: term, sentence: nil, sentenceTranslation: nil,
              documentID: UUID(), documentTitle: "book", page: 0, date: date)
}

struct WordReviewTests {
    @Test func knownWordIntervalsGrow() {
        var state = ReviewState.new(on: day())
        state = state.answered(.good, on: day(), calendar: utc)
        #expect(state.intervalDays == 1)
        #expect(state.due == day(1, hour: 0))
        state = state.answered(.good, on: day(1), calendar: utc)
        #expect(state.intervalDays == 3)
        state = state.answered(.good, on: day(4), calendar: utc)
        #expect(state.intervalDays == 8) // 3 × 2.5 rounded
        #expect(state.due == day(12, hour: 0))
        #expect(state.reviews == 3)
        #expect(state.ease == ReviewState.startingEase)
    }

    @Test func forgottenWordStartsOverAndStaysDue() {
        var state = ReviewState.new(on: day())
        state = state.answered(.good, on: day(), calendar: utc)
        state = state.answered(.good, on: day(1), calendar: utc)
        state = state.answered(.again, on: day(4), calendar: utc)
        #expect(state.intervalDays == 0)
        #expect(state.streak == 0)
        #expect(state.isDue(on: day(4)))
        #expect(abs(state.ease - 2.3) < 0.0001)
        state = state.answered(.good, on: day(4), calendar: utc)
        #expect(state.intervalDays == 1)
    }

    @Test func hardGrowsSlowlyAndLowersEase() {
        var state = ReviewState.new(on: day())
        state = state.answered(.hard, on: day(), calendar: utc)
        #expect(state.intervalDays == 1)
        state.intervalDays = 10
        state = state.answered(.hard, on: day(), calendar: utc)
        #expect(state.intervalDays == 12)
        #expect(abs(state.ease - 2.2) < 0.0001)
    }

    @Test func easeNeverFallsBelowMinimum() {
        var state = ReviewState.new(on: day())
        for _ in 0..<20 { state = state.answered(.again, on: day(), calendar: utc) }
        #expect(state.ease == ReviewState.minimumEase)
    }

    @Test func dueListsOverdueThenNewWords() {
        let old = word("old", savedOn: day(-10))
        let recent = word("recent", savedOn: day(-1))
        let overdue = word("overdue", savedOn: day(-20))
        let later = word("later", savedOn: day(-20))
        let veryOverdue = word("veryOverdue", savedOn: day(-20))
        var states: [UUID: ReviewState] = [:]
        states[overdue.id] = ReviewState(ease: 2.5, intervalDays: 3, streak: 2, due: day(-1, hour: 0), lastReviewed: nil, reviews: 2)
        states[veryOverdue.id] = ReviewState(ease: 2.5, intervalDays: 3, streak: 2, due: day(-5, hour: 0), lastReviewed: nil, reviews: 2)
        states[later.id] = ReviewState(ease: 2.5, intervalDays: 3, streak: 2, due: day(2, hour: 0), lastReviewed: nil, reviews: 2)
        let words = [recent, later, overdue, old, veryOverdue]

        let due = ReviewSchedule.due(words, states: states, on: day())
        #expect(due.map(\.term) == ["veryOverdue", "overdue", "old", "recent"])
        #expect(ReviewSchedule.dueCount(words, states: states, on: day()) == 4)
        #expect(ReviewSchedule.dueCount(words, states: states, on: day(2, hour: 0)) == 5)
    }

    @Test func sessionRepeatsForgottenCardsAtTheEnd() {
        let a = UUID(), b = UUID()
        var session = ReviewSession(cards: [a, b])
        #expect(session.current == a)
        session.answer(.again)
        #expect(session.current == b)
        session.answer(.good)
        #expect(session.current == a)
        session.answer(.hard)
        #expect(session.isFinished)
        #expect(session.done == 2)
        #expect(session.forgotten == 1)
        #expect(session.total == 2)
    }
}
