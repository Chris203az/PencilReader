import SwiftUI
import UserNotifications

@main
struct PencilReaderApp: App {
    @State private var library: Library
    @State private var recognizer: BookRecognizer
    @State private var wordList = WordList()
    @State private var reviews = ReviewStore()
    @State private var stats: ReadingStats
    @State private var studyTimer: StudyTimer
    /// Kept for the whole run: the notification center holds its delegate weakly.
    private static let notificationPresenter = NotificationPresenter()

    init() {
        let library = Library()
        _library = State(initialValue: library)
        _recognizer = State(initialValue: BookRecognizer(library: library))
        let stats = ReadingStats()
        _stats = State(initialValue: stats)
        _studyTimer = State(initialValue: StudyTimer(stats: stats))
        UNUserNotificationCenter.current().delegate = Self.notificationPresenter
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                .environment(recognizer)
                .environment(wordList)
                .environment(reviews)
                .environment(stats)
                .environment(studyTimer)
        }
    }
}
