import Foundation
import Testing
@testable import ReaderCore

private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Rome")!
    return c
}()

private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

struct ReadingLogTests {
    let book = UUID()
    let other = UUID()

    @Test func readingTimeAddsUpPerBookAndDay() {
        var log = ReadingLog()
        log.addReading(of: book, from: date(20, 9), to: date(20, 9, 30), calendar: calendar)
        log.addReading(of: book, from: date(20, 15), to: date(20, 15, 10), calendar: calendar)
        log.addReading(of: other, from: date(20, 16), to: date(20, 16, 5), calendar: calendar)
        #expect(log.seconds(on: date(20, 12), of: book, calendar: calendar) == 40 * 60)
        #expect(log.seconds(on: date(20, 12), calendar: calendar) == 45 * 60)
        #expect(log.totalSeconds(of: book) == 40 * 60)
        #expect(log.seconds(on: date(21, 12), calendar: calendar) == 0)
    }

    @Test func sessionAcrossMidnightIsSplit() {
        var log = ReadingLog()
        log.addReading(of: book, from: date(20, 23, 50), to: date(21, 0, 20), calendar: calendar)
        #expect(log.seconds(on: date(20, 12), calendar: calendar) == 10 * 60)
        #expect(log.seconds(on: date(21, 12), calendar: calendar) == 20 * 60)
    }

    @Test func pagesCountOncePerDay() {
        var log = ReadingLog()
        for page in [3, 4, 3, 5, 4] { log.addPage(page, of: book, on: date(20, 10), calendar: calendar) }
        log.addPage(3, of: book, on: date(21, 10), calendar: calendar)
        log.addPage(0, of: other, on: date(20, 10), calendar: calendar)
        #expect(log.pages(on: date(20, 1), of: book, calendar: calendar) == 3)
        #expect(log.pages(on: date(20, 1), calendar: calendar) == 4)
        #expect(log.pages(on: date(21, 1), calendar: calendar) == 1)
    }

    @Test func lastSevenDaysIncludeEmptyDaysOldestFirst() {
        var log = ReadingLog()
        log.addReading(of: book, from: date(18, 9), to: date(18, 10), calendar: calendar)
        log.addReading(of: book, from: date(24, 9), to: date(24, 9, 15), calendar: calendar)
        log.addFocusBlock(on: date(24, 9, 25), calendar: calendar)
        let week = log.lastDays(7, endingOn: date(24, 20), calendar: calendar)
        #expect(week.count == 7)
        #expect(week.first?.date == calendar.startOfDay(for: date(18, 0)))
        #expect(week.first?.seconds == 3600)
        #expect(week.last?.seconds == TimeInterval(15 * 60))
        #expect(week.last?.focusBlocks == 1)
        #expect(week.dropFirst().dropLast().allSatisfy { $0.seconds == 0 })
    }

    @Test func bookTotalsMostReadFirst() {
        var log = ReadingLog()
        log.addReading(of: book, from: date(23, 9), to: date(23, 9, 10), calendar: calendar)
        log.addReading(of: other, from: date(24, 9), to: date(24, 10), calendar: calendar)
        log.addReading(of: book, from: date(1, 9), to: date(1, 12), calendar: calendar)
        let totals = log.bookTotals(lastDays: 7, endingOn: date(24, 20), calendar: calendar)
        #expect(totals.map(\.bookID) == [other, book])
        #expect(totals.last?.seconds == TimeInterval(10 * 60))
    }

    @Test func removingABookForgetsIt() {
        var log = ReadingLog()
        log.addReading(of: book, from: date(20, 9), to: date(20, 10), calendar: calendar)
        log.remove(book)
        #expect(log.days.isEmpty)
    }

    @Test func survivesEncoding() throws {
        var log = ReadingLog()
        log.addReading(of: book, from: date(20, 9), to: date(20, 10), calendar: calendar)
        log.addPage(2, of: book, on: date(20, 9), calendar: calendar)
        log.addFocusBlock(on: date(20, 9), calendar: calendar)
        let decoded = try JSONDecoder().decode(ReadingLog.self, from: JSONEncoder().encode(log))
        #expect(decoded == log)
    }

    @Test func durations() {
        #expect(ReadingLog.duration(30) == "meno di 1 min")
        #expect(ReadingLog.duration(42 * 60 + 30) == "42 min")
        #expect(ReadingLog.duration(65 * 60) == "1 h 5 min")
        #expect(ReadingLog.duration(3 * 3600) == "3 h")
    }
}

struct PomodoroTests {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let settings = PomodoroSettings()

    @Test func countsDownFromTheFullBlock() {
        var timer = PomodoroTimer()
        #expect(timer.isWaiting)
        #expect(timer.remaining(at: start, settings: settings) == 25 * 60)
        timer.start(at: start, settings: settings)
        #expect(timer.remaining(at: start.addingTimeInterval(60), settings: settings) == 24 * 60)
        let ended = timer.finishIfDue(at: start.addingTimeInterval(60), settings: settings)
        #expect(ended?.phase == nil)
    }

    @Test func pauseKeepsTheTimeLeft() {
        var timer = PomodoroTimer()
        timer.start(at: start, settings: settings)
        timer.pause(at: start.addingTimeInterval(10 * 60))
        #expect(!timer.isRunning && !timer.isWaiting)
        // Time spent paused doesn't count.
        #expect(timer.remaining(at: start.addingTimeInterval(3600), settings: settings) == 15 * 60)
        timer.start(at: start.addingTimeInterval(3600), settings: settings)
        #expect(timer.remaining(at: start.addingTimeInterval(3600 + 60), settings: settings) == 14 * 60)
    }

    @Test func blockThenShortBreakThenLongBreakAfterFour() {
        var timer = PomodoroTimer()
        var phases: [PomodoroPhase] = []
        var now = start
        for _ in 0..<8 {
            timer.start(at: now, settings: settings)
            now = now.addingTimeInterval(settings.duration(of: timer.phase))
            let ended = timer.finishIfDue(at: now, settings: settings)
            #expect(ended?.end == now)
            #expect(!timer.isRunning)
            phases.append(timer.phase)
        }
        #expect(phases == [.shortBreak, .focus, .shortBreak, .focus, .shortBreak, .focus, .longBreak, .focus])
    }

    @Test func finishingLateReportsTheRealEnd() {
        var timer = PomodoroTimer()
        timer.start(at: start, settings: settings)
        let ended = timer.finishIfDue(at: start.addingTimeInterval(5 * 3600), settings: settings)
        #expect(ended?.phase == .focus)
        #expect(ended?.end == start.addingTimeInterval(25 * 60))
        #expect(timer.phase == .shortBreak)
    }

    @Test func skippingABlockDoesNotCountIt() {
        var timer = PomodoroTimer()
        timer.skip(settings: settings)
        #expect(timer.phase == .shortBreak)
        #expect(timer.blocksInCycle == 0)
        timer.skip(settings: settings)
        #expect(timer.phase == .focus)
    }

    @Test func changedLengthsApplyToAWaitingPhase() {
        var timer = PomodoroTimer()
        var custom = settings
        custom.focusMinutes = 50
        #expect(timer.remaining(at: start, settings: custom) == 50 * 60)
        timer.start(at: start, settings: custom)
        custom.focusMinutes = 10
        #expect(timer.remaining(at: start, settings: custom) == 50 * 60)
    }
}
