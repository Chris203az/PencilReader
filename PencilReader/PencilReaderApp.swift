import SwiftUI

@main
struct PencilReaderApp: App {
    @State private var library: Library
    @State private var recognizer: BookRecognizer
    @State private var wordList = WordList()
    @State private var reviews = ReviewStore()

    init() {
        let library = Library()
        _library = State(initialValue: library)
        _recognizer = State(initialValue: BookRecognizer(library: library))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                .environment(recognizer)
                .environment(wordList)
                .environment(reviews)
        }
    }
}
