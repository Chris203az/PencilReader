import Foundation
import Observation
import ReaderCore

/// Reading time and pages viewed, counted only while a book is open and the app is in front.
/// Saved in Documents/Libreria/statistiche.json, so it is backed up with the library.
@MainActor
@Observable
final class ReadingStats {
    private(set) var log = ReadingLog()
    /// The book being read now and since when; its time is added to the log when reading stops.
    private var session: (book: UUID, start: Date)?

    private let url = URL.documentsDirectory.appending(path: "Libreria").appending(path: "statistiche.json")

    init() {
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(ReadingLog.self, from: data) {
            log = saved
        }
    }

    func startReading(_ book: UUID) {
        if session?.book == book { return }
        stopReading()
        session = (book, .now)
    }

    func stopReading() {
        guard let session else { return }
        self.session = nil
        log.addReading(of: session.book, from: session.start, to: .now)
        save()
    }

    func pageShown(_ page: Int, of book: UUID) {
        log.addPage(page, of: book, on: .now)
        // Turning the page also saves the time read so far, so little is lost if the app is closed.
        if let session, session.book == book, Date.now.timeIntervalSince(session.start) > 60 {
            log.addReading(of: book, from: session.start, to: .now)
            self.session = (book, .now)
            save()
        }
    }

    func focusBlockFinished(at date: Date) {
        log.addFocusBlock(on: date)
        save()
    }

    /// Today's time on the book, including the reading going on now.
    func secondsToday(of book: UUID) -> TimeInterval {
        var seconds = log.seconds(on: .now, of: book)
        if let session, session.book == book {
            let today = Calendar.current.startOfDay(for: .now)
            seconds += Date.now.timeIntervalSince(max(session.start, today))
        }
        return seconds
    }

    func remove(_ book: UUID) {
        if session?.book == book { session = nil }
        log.remove(book)
        save()
    }

    private func save() {
        try? JSONEncoder().encode(log).write(to: url, options: .atomic)
    }
}
