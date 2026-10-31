import Foundation

/// A page of a book marked to come back to, with an optional name.
public struct Bookmark: Codable, Sendable, Hashable, Identifiable {
    /// Zero-based page.
    public let page: Int
    /// Nil when the bookmark keeps the default name, "Pagina N".
    public private(set) var customTitle: String?
    public let created: Date

    public var id: Int { page }

    public init(page: Int, title: String? = nil, created: Date) {
        self.page = page
        self.created = created
        customTitle = Self.normalized(title, page: page)
    }

    public var title: String { customTitle ?? Self.defaultTitle(page: page) }

    public static func defaultTitle(page: Int) -> String { String(localized: "Pagina \(page + 1)") }

    public mutating func rename(_ title: String?) {
        customTitle = Self.normalized(title, page: page)
    }

    /// Blank text, or the default name typed again, means no custom name.
    private static func normalized(_ title: String?, page: Int) -> String? {
        guard let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, trimmed != defaultTitle(page: page) else { return nil }
        return trimmed
    }
}

/// The bookmarks of one book, at most one per page, in page order.
public struct BookmarkList: Codable, Sendable, Equatable {
    public private(set) var bookmarks: [Bookmark]

    public init(_ bookmarks: [Bookmark] = []) {
        var seen = Set<Int>()
        self.bookmarks = bookmarks
            .sorted { $0.page < $1.page }
            .filter { seen.insert($0.page).inserted }
    }

    public var isEmpty: Bool { bookmarks.isEmpty }
    public var pages: Set<Int> { Set(bookmarks.map(\.page)) }

    public func contains(page: Int) -> Bool { bookmark(at: page) != nil }

    public func bookmark(at page: Int) -> Bookmark? { bookmarks.first { $0.page == page } }

    /// Adds the page, or renames it when it is already there.
    public mutating func add(page: Int, title: String? = nil, date: Date) {
        if let index = bookmarks.firstIndex(where: { $0.page == page }) {
            bookmarks[index].rename(title)
            return
        }
        let at = bookmarks.firstIndex { $0.page > page } ?? bookmarks.endIndex
        bookmarks.insert(Bookmark(page: page, title: title, created: date), at: at)
    }

    public mutating func remove(page: Int) {
        bookmarks.removeAll { $0.page == page }
    }

    /// Returns whether the page is bookmarked afterwards.
    @discardableResult
    public mutating func toggle(page: Int, date: Date) -> Bool {
        if contains(page: page) {
            remove(page: page)
            return false
        }
        add(page: page, date: date)
        return true
    }

    public mutating func rename(page: Int, to title: String?) {
        guard let index = bookmarks.firstIndex(where: { $0.page == page }) else { return }
        bookmarks[index].rename(title)
    }

    /// Drops bookmarks past the end of the book, in case pages were removed.
    public mutating func keep(pageCount: Int) {
        bookmarks.removeAll { $0.page < 0 || $0.page >= pageCount }
    }

    /// The bookmark before or after `page`, to jump between them.
    public func previous(before page: Int) -> Bookmark? { bookmarks.last { $0.page < page } }
    public func next(after page: Int) -> Bookmark? { bookmarks.first { $0.page > page } }

    // Saved as a plain array, sorted again when read.
    public init(from decoder: Decoder) throws {
        self.init(try decoder.singleValueContainer().decode([Bookmark].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(bookmarks)
    }
}
