import Foundation
import Testing
@testable import ReaderCore

private let day = Date(timeIntervalSince1970: 1_800_000_000)

struct BookmarksTests {
    @Test func defaultTitleCountsFromOne() {
        let mark = Bookmark(page: 0, created: day)
        #expect(mark.title == "Pagina 1")
        #expect(mark.customTitle == nil)
    }

    @Test func blankOrDefaultTitleIsNoCustomTitle() {
        #expect(Bookmark(page: 4, title: "   ", created: day).customTitle == nil)
        #expect(Bookmark(page: 4, title: "Pagina 5", created: day).customTitle == nil)
        #expect(Bookmark(page: 4, title: "  Equazioni di Navier  ", created: day).title == "Equazioni di Navier")
    }

    @Test func toggleAddsThenRemoves() {
        var list = BookmarkList()
        #expect(list.toggle(page: 7, date: day))
        #expect(list.contains(page: 7))
        #expect(!list.toggle(page: 7, date: day))
        #expect(list.isEmpty)
    }

    @Test func keptInPageOrderOnePerPage() {
        var list = BookmarkList()
        list.add(page: 30, date: day)
        list.add(page: 2, date: day)
        list.add(page: 15, title: "Capitolo 2", date: day)
        list.add(page: 2, title: "Indice", date: day)
        #expect(list.bookmarks.map(\.page) == [2, 15, 30])
        #expect(list.bookmark(at: 2)?.title == "Indice")
        #expect(list.pages == [2, 15, 30])
    }

    @Test func renameAndClearTitle() {
        var list = BookmarkList()
        list.add(page: 3, date: day)
        list.rename(page: 3, to: "Teorema")
        #expect(list.bookmark(at: 3)?.title == "Teorema")
        list.rename(page: 3, to: "")
        #expect(list.bookmark(at: 3)?.title == "Pagina 4")
        list.rename(page: 99, to: "nessuno")
        #expect(list.bookmarks.count == 1)
    }

    @Test func previousAndNext() {
        let list = BookmarkList([Bookmark(page: 10, created: day), Bookmark(page: 2, created: day),
                                 Bookmark(page: 20, created: day)])
        #expect(list.previous(before: 10)?.page == 2)
        #expect(list.next(after: 10)?.page == 20)
        #expect(list.next(after: 20) == nil)
        #expect(list.previous(before: 2) == nil)
    }

    @Test func keepDropsPagesPastTheEnd() {
        var list = BookmarkList([Bookmark(page: 1, created: day), Bookmark(page: 9, created: day)])
        list.keep(pageCount: 5)
        #expect(list.pages == [1])
    }

    @Test func jsonRoundTripRestoresOrderAndDuplicates() throws {
        var list = BookmarkList()
        list.add(page: 8, title: "Fluidi", date: day)
        list.add(page: 1, date: day)
        let data = try JSONEncoder().encode(list)
        #expect(try JSONDecoder().decode(BookmarkList.self, from: data) == list)

        // A hand-edited file out of order, with the same page twice.
        let messy = try JSONEncoder().encode([Bookmark(page: 5, created: day), Bookmark(page: 1, created: day),
                                              Bookmark(page: 5, title: "doppio", created: day)])
        let decoded = try JSONDecoder().decode(BookmarkList.self, from: messy)
        #expect(decoded.bookmarks.map(\.page) == [1, 5])
    }
}
