import Foundation
import Observation
import ReaderCore

/// The bookmarks of the open book, saved on every change in
/// Application Support/Bookmarks/<book id>.json. A book without bookmarks has no file.
@MainActor
@Observable
final class BookmarkStore {
    let bookID: UUID
    private(set) var list: BookmarkList

    init(bookID: UUID, pageCount: Int) {
        self.bookID = bookID
        var list = (try? Data(contentsOf: Self.url(of: bookID)))
            .flatMap { try? JSONDecoder().decode(BookmarkList.self, from: $0) } ?? BookmarkList()
        list.keep(pageCount: pageCount)
        self.list = list
    }

    var bookmarks: [Bookmark] { list.bookmarks }
    var pages: Set<Int> { list.pages }

    func contains(_ page: Int) -> Bool { list.contains(page: page) }

    func toggle(_ page: Int) {
        list.toggle(page: page, date: .now)
        save()
    }

    /// Adds the page with a name, or renames it when it is already marked.
    func add(_ page: Int, title: String?) {
        list.add(page: page, title: title, date: .now)
        save()
    }

    func remove(_ page: Int) {
        list.remove(page: page)
        save()
    }

    private func save() {
        let file = Self.url(of: bookID)
        guard !list.isEmpty, let data = try? JSONEncoder().encode(list) else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        try? FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    nonisolated private static var root: URL {
        URL.applicationSupportDirectory.appending(path: "Bookmarks", directoryHint: .isDirectory)
    }

    nonisolated private static func url(of bookID: UUID) -> URL {
        root.appending(path: "\(bookID.uuidString).json")
    }

    /// Called when the book itself is deleted.
    nonisolated static func deleteBookmarks(of bookID: UUID) {
        try? FileManager.default.removeItem(at: url(of: bookID))
    }
}
