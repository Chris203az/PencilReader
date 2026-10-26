package it.pencilreader.core

import org.junit.Test

private const val BOOK = "6f1c2b7e-0000-4000-8000-000000000001"

class PageNoteTest {
    @Test fun pathIsBookFolderAndZeroPaddedPage() {
        expect(PageNote(BOOK, 3).relativePath == "$BOOK/0003.ink.json")
        expect(PageNote(BOOK, 3).id == PageNote(BOOK, 3).relativePath)
    }

    @Test fun pageIndexComesBackFromFileName() {
        expect(PageNote.pageIndex(PageNote.fileName(127)) == 127)
        expect(PageNote.pageIndex("0003.jpg") == null)
        expect(PageNote.pageIndex(".DS_Store") == null)
        expect(PageNote.pageIndex("0003.shapes.json") == null)
    }
}

class SplitRatioTest {
    @Test fun keepsBothSidesBetweenThirtyAndSeventyPercent() {
        expect(SplitRatio.clamped(0.1) == 0.3)
        expect(SplitRatio.clamped(0.5) == 0.5)
        expect(SplitRatio.clamped(0.9) == 0.7)
    }

    @Test fun standardSplitIsInsideTheRange() {
        expect(SplitRatio.STANDARD in SplitRatio.range)
    }
}

class PaperStyleTest {
    @Test fun storedValueRoundTrips() {
        for (style in PaperStyle.entries) expect(PaperStyle.fromRaw(style.rawValue) == style)
        expect(PaperStyle.fromRaw("dots") == null)
    }
}
