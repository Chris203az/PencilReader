import Foundation
import Testing
@testable import ReaderCore

private let book = UUID(uuidString: "6F1C2B7E-0000-4000-8000-000000000001")!

struct PageNoteTests {
    @Test func pathIsBookFolderAndZeroPaddedPage() {
        #expect(PageNote(bookID: book, pageIndex: 3).relativePath == "\(book.uuidString)/0003.drawing")
        #expect(PageNote(bookID: book, pageIndex: 3).id == PageNote(bookID: book, pageIndex: 3).relativePath)
    }

    @Test func pageIndexComesBackFromFileName() {
        #expect(PageNote.pageIndex(fromFileName: PageNote.fileName(pageIndex: 127)) == 127)
        #expect(PageNote.pageIndex(fromFileName: "0003.jpg") == nil)
        #expect(PageNote.pageIndex(fromFileName: ".DS_Store") == nil)
    }
}

struct SplitRatioTests {
    @Test func keepsBothSidesBetweenThirtyAndSeventyPercent() {
        #expect(SplitRatio.clamped(0.1) == 0.3)
        #expect(SplitRatio.clamped(0.5) == 0.5)
        #expect(SplitRatio.clamped(0.9) == 0.7)
    }

    @Test func standardSplitIsInsideTheRange() {
        #expect(SplitRatio.range.contains(SplitRatio.standard))
    }
}

struct PaperStyleTests {
    @Test func storedValueRoundTrips() {
        for style in PaperStyle.allCases {
            #expect(PaperStyle(rawValue: style.rawValue) == style)
        }
        #expect(PaperStyle(rawValue: "dots") == nil)
    }
}
