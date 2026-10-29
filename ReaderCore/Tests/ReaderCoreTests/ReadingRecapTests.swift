import Foundation
import Testing
@testable import ReaderCore

private let book = UUID()
private let start = Date(timeIntervalSince1970: 1_800_000_000)

private func recap(created: Date, finished: Bool = true, offered: Date? = nil, of bookID: UUID = book) -> ReadingRecap {
    ReadingRecap(bookID: bookID, bookTitle: "Rocket Propulsion", firstPage: 4, lastPage: 9, created: created,
                 finished: finished ? created : nil, offered: offered)
}

struct ReadingRecapTests {
    @Test func pagesAreOrderedAndLabeledFromOne() {
        let swapped = ReadingRecap(bookID: book, bookTitle: "", firstPage: 9, lastPage: 4, created: start)
        #expect(swapped.firstPage == 4 && swapped.lastPage == 9)
        #expect(swapped.pageCount == 6)
        #expect(swapped.pagesLabel == "pag. 5–10")
        let single = ReadingRecap(bookID: book, bookTitle: "", firstPage: 2, lastPage: 2, created: start)
        #expect(single.pagesLabel == "pag. 3")
    }

    @Test func suggestedRangeGoesBackOverTodaysPagesWithoutGaps() {
        #expect(ReadingRecap.suggestedRange(current: 12, pagesSeenToday: [3, 9, 10, 11, 12], lastRecapEnd: nil) == 9...12)
        #expect(ReadingRecap.suggestedRange(current: 12, pagesSeenToday: [], lastRecapEnd: nil) == 12...12)
    }

    @Test func suggestedRangeStartsAfterTheLastRecap() {
        #expect(ReadingRecap.suggestedRange(current: 12, pagesSeenToday: Set(5...12), lastRecapEnd: 8) == 9...12)
        // A recap of later pages, or of this very page, doesn't shrink the range.
        #expect(ReadingRecap.suggestedRange(current: 12, pagesSeenToday: Set(5...12), lastRecapEnd: 20) == 5...12)
        #expect(ReadingRecap.suggestedRange(current: 12, pagesSeenToday: Set(5...12), lastRecapEnd: 12) == 5...12)
    }

    @Test func rereadOnlyTheLatestFinishedRecapOfAnEarlierSession() {
        let old = recap(created: start)
        let newer = recap(created: start.addingTimeInterval(600))
        let now = start.addingTimeInterval(2 * 3600)
        #expect(ReadingRecap.toReread(of: book, in: [old, newer], now: now)?.id == newer.id)
        // Just made: same session.
        #expect(ReadingRecap.toReread(of: book, in: [newer], now: start.addingTimeInterval(900)) == nil)
        // Already offered once.
        #expect(ReadingRecap.toReread(of: book, in: [recap(created: start, offered: now)], now: now) == nil)
        // Not finished, or of another book.
        #expect(ReadingRecap.toReread(of: book, in: [recap(created: start, finished: false)], now: now) == nil)
        #expect(ReadingRecap.toReread(of: book, in: [recap(created: start, of: UUID())], now: now) == nil)
    }

    @Test func pointCountGrowsWithPagesButStaysShort() {
        #expect(RecapWriter.pointCount(pages: 1) == 3)
        #expect(RecapWriter.pointCount(pages: 4) == 5)
        #expect(RecapWriter.pointCount(pages: 40) == 8)
    }

    @Test func promptCarriesEveryPageAndTheLengthLimits() {
        let prompt = RecapWriter.prompt(pages: [(4, "Specific impulse is the thrust"), (5, "Frozen flow")])
        #expect(prompt.json)
        #expect(prompt.schema != nil)
        #expect(prompt.user.contains("[Pagina 5]\nSpecific impulse is the thrust"))
        #expect(prompt.user.contains("[Pagina 6]\nFrozen flow"))
        #expect(prompt.user.contains("al massimo 4 punti"))
        // DeepSeek answers in JSON only when the prompt says "json".
        #expect(prompt.user.contains("json"))
    }

    @Test func longTextIsCutEvenlyAcrossPages() {
        let long = String(repeating: "a", count: RecapWriter.textLimit)
        let text = RecapWriter.promptText(pages: [(0, long), (1, long)])
        #expect(text.count < RecapWriter.textLimit + 2000)
        #expect(text.contains("[Pagina 2]"))
    }

    @Test func readsTheAnswer() throws {
        let recap = try RecapWriter.recap(fromModelText: """
            ```json
            {"titolo": "Impulso specifico", "idea": "Misura l'efficienza del propellente.",
             "punti": ["Isp = F/(ṁ·g₀)", "  ", "Si misura in secondi"]}
            ```
            """)
        #expect(recap.title == "Impulso specifico")
        #expect(recap.points == ["Isp = F/(ṁ·g₀)", "Si misura in secondi"])
    }

    @Test func emptyAnswerIsAnError() {
        #expect(throws: ExplanationError.badResponse) {
            try RecapWriter.recap(fromModelText: #"{"titolo": "x", "idea": "", "punti": []}"#)
        }
        #expect(throws: ExplanationError.badResponse) { try RecapWriter.recap(fromModelText: "niente") }
    }

    @Test func pagesViewedTodayComeFromTheLog() {
        var log = ReadingLog()
        log.addPage(3, of: book, on: start)
        log.addPage(4, of: book, on: start)
        log.addPage(9, of: UUID(), on: start)
        #expect(log.pagesViewed(on: start, of: book) == [3, 4])
    }
}
