import CoreGraphics
import Foundation
import Testing
@testable import ReaderCore

struct PDFExportPlanTests {
    @Test func pagesOfEachChoice() {
        #expect(PDFExportPlan.pages(.all, pageCount: 3, annotated: []) == [0, 1, 2])
        #expect(PDFExportPlan.pages(.range(1...5), pageCount: 4, annotated: []) == [1, 2, 3])
        #expect(PDFExportPlan.pages(.range(6...8), pageCount: 4, annotated: []) == [])
        #expect(PDFExportPlan.pages(.annotated, pageCount: 10, annotated: [7, 2, 12]) == [2, 7])
        #expect(PDFExportPlan.pages(.all, pageCount: 0, annotated: []) == [])
    }

    @Test func noteColumnFollowsTheSplit() {
        #expect(PDFExportPlan.noteColumnWidth(pageWidth: 600, split: 0.5) == 600)
        #expect(abs(PDFExportPlan.noteColumnWidth(pageWidth: 600, split: 0.6) - 400) < 0.001)
        // Outside the range of the divider it is clamped as on screen.
        #expect(abs(PDFExportPlan.noteColumnWidth(pageWidth: 300, split: 0.1) - 700) < 0.001)
    }

    @Test func noteSizeKeepsAMarginPastTheInk() {
        let size = PDFExportPlan.noteSize(inkBounds: CGRect(x: 40, y: 30, width: 600, height: 200), minWidth: 500)
        #expect(size == CGSize(width: 640 + PDFExportPlan.noteMargin, height: 230 + PDFExportPlan.noteMargin))
        #expect(PDFExportPlan.noteSize(inkBounds: CGRect(x: 0, y: 0, width: 50, height: 50), minWidth: 500).width == 500)
        #expect(PDFExportPlan.noteSize(inkBounds: .null, minWidth: 500).height == 0)
    }

    @Test func shortNoteTakesOneBand() {
        let slices = PDFExportPlan.slices(noteSize: CGSize(width: 500, height: 300), box: CGSize(width: 250, height: 400))
        #expect(slices == [CGRect(x: 0, y: 0, width: 500, height: 800)])
    }

    @Test func longNoteGoesOnOverMoreBands() {
        let slices = PDFExportPlan.slices(noteSize: CGSize(width: 500, height: 1700), box: CGSize(width: 250, height: 400))
        #expect(slices.count == 3)
        #expect(slices[1].minY == 800)
        #expect(slices.allSatisfy { $0.width == 500 && $0.height == 800 })
        // Just past one band is still one band.
        #expect(PDFExportPlan.slices(noteSize: CGSize(width: 500, height: 805), box: CGSize(width: 250, height: 400)).count == 1)
    }

    @Test func fileNameHasNoPathCharacters() {
        #expect(PDFExportPlan.fileName(for: "Fluid Dynamics: vol 1/2") == "Fluid Dynamics- vol 1-2 - annotato.pdf")
        #expect(PDFExportPlan.fileName(for: "  ") == "Libro - annotato.pdf")
    }
}
