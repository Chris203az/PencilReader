import Foundation
import Observation
import ReaderCore

/// Full-text search over the recognized pages of one book. Pages are loaded
/// from disk once and kept while the book is open; pages recognized later
/// (e.g. by "Riconosci tutto il libro") are picked up on the next search.
@MainActor
@Observable
final class BookSearch {
    struct PageResult: Identifiable {
        let page: Int
        let matches: [SearchMatch]
        var id: Int { page }
    }

    var query = "" {
        didSet { if query != oldValue { search() } }
    }
    private(set) var results: [PageResult] = []
    private(set) var isSearching = false
    /// Pages without OCR yet: they can't be searched.
    private(set) var missingPages = 0

    private let document: LibraryDocument
    private let library: Library
    private var pages: [Int: PageText] = [:]
    private var task: Task<Void, Never>?

    init(document: LibraryDocument, library: Library) {
        self.document = document
        self.library = library
        missingPages = document.pageCount - library.recognizedPageCount(of: document)
    }

    func search() {
        task?.cancel()
        let needle = query
        guard !needle.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        task = Task {
            // Wait for a pause in typing.
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
            await loadNewPages()
            let pages = self.pages
            let found = await Task.detached(priority: .userInitiated) {
                pages.keys.sorted().compactMap { page -> PageResult? in
                    let matches = pages[page]!.search(needle)
                    return matches.isEmpty ? nil : PageResult(page: page, matches: matches)
                }
            }.value
            if Task.isCancelled { return }
            results = found
            isSearching = false
        }
    }

    private func loadNewPages() async {
        let toLoad = (0..<document.pageCount)
            .filter { pages[$0] == nil && library.hasSavedText(of: document, page: $0) }
            .map { ($0, library.ocrURL(of: document, page: $0)) }
        if !toLoad.isEmpty {
            let loaded = await Task.detached(priority: .userInitiated) {
                toLoad.compactMap { page, url in Library.loadText(at: url).map { (page, $0) } }
            }.value
            for (page, text) in loaded { pages[page] = text }
        }
        missingPages = document.pageCount - pages.count
    }
}
