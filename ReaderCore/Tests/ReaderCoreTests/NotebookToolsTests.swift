import Foundation
import Testing
@testable import ReaderCore

struct NotebookToolStateTests {
    @Test func startsWithTheBlackPen() {
        let state = NotebookToolState()
        #expect(state.current == .pen)
        #expect(state.ink(for: .pen) == InkSetting(color: .black, width: 3))
        #expect(state.ink(for: .eraser) == nil)
        #expect(state.palette.count == 5)
    }

    @Test func choosingTheEraserAgainSwitchesItsKind() {
        var state = NotebookToolState()
        state.select(.eraser)
        #expect(state.current == .eraser && !state.eraserIsPixel)
        state.select(.eraser)
        #expect(state.current == .eraser && state.eraserIsPixel)
    }

    @Test func colorAndWidthBelongToTheLastInkingTool() {
        var state = NotebookToolState()
        state.select(.marker)
        state.select(.lasso)
        state.setColor(.blue)
        state.setWidth(30)
        #expect(state.current == .marker)
        #expect(state.marker == InkSetting(color: .blue, width: 30))
        #expect(state.pen == InkSetting(color: .black, width: 3))
    }

    @Test func pencilDoubleTapGoesToTheEraserAndBack() {
        var state = NotebookToolState()
        state.select(.pencil)
        state.pencilDoubleTap(switchesToEraser: true)
        #expect(state.current == .eraser)
        state.pencilDoubleTap(switchesToEraser: true)
        #expect(state.current == .pencil)
    }

    @Test func pencilDoubleTapCanSwitchToThePreviousTool() {
        var state = NotebookToolState()
        state.select(.lasso)
        state.pencilDoubleTap(switchesToEraser: false)
        #expect(state.current == .pen)
        state.pencilDoubleTap(switchesToEraser: false)
        #expect(state.current == .lasso)
    }

    @Test func savedStateComesBackTheSame() throws {
        var state = NotebookToolState()
        state.select(.marker)
        state.setColor(.green)
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(NotebookToolState.self, from: data) == state)
    }
}

struct NotebookToolbarLayoutTests {
    @Test func standardShowsEverythingAtTheTop() {
        let layout = NotebookToolbarLayout.standard
        #expect(layout.position == .top)
        #expect(layout.visibleItems == NotebookToolbarItem.allCases)
    }

    @Test func hiddenItemsAreLeftOut() {
        var layout = NotebookToolbarLayout.standard
        layout.entries[0].isVisible = false
        #expect(!layout.visibleItems.contains(.pen))
        #expect(layout.visibleItems.count == NotebookToolbarItem.allCases.count - 1)
    }

    @Test func normalizingDropsDuplicatesAndAddsMissingItems() {
        let saved = NotebookToolbarLayout(position: .bottom, entries: [
            .init(item: .undo, isVisible: true),
            .init(item: .pen, isVisible: false),
            .init(item: .undo, isVisible: false)
        ])
        let fixed = saved.normalized()
        #expect(fixed.position == .bottom)
        #expect(fixed.entries.count == NotebookToolbarItem.allCases.count)
        #expect(Array(fixed.entries.prefix(2)) == [.init(item: .undo, isVisible: true), .init(item: .pen, isVisible: false)])
        #expect(fixed.entries.dropFirst(2).allSatisfy(\.isVisible))
    }

    @Test func savedLayoutComesBackTheSame() throws {
        var layout = NotebookToolbarLayout.standard
        layout.position = .bottom
        layout.entries.swapAt(0, 3)
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(NotebookToolbarLayout.self, from: data) == layout)
    }
}
