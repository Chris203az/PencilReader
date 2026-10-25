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

    @Test func eachKindOfEraserKeepsItsSize() {
        var state = NotebookToolState()
        #expect(state.eraserWidth == nil)
        state.setEraserWidth(30)
        #expect(state.current == .eraser && state.strokeEraserWidth == 30)
        state.eraserIsPixel = true
        #expect(state.eraserWidth == nil)
        state.setEraserWidth(8)
        #expect(state.eraserWidth == 8)
        state.eraserIsPixel = false
        #expect(state.eraserWidth == 30)
        // Choosing the eraser again changes nothing: the bar opens its settings instead.
        state.select(.eraser)
        #expect(state.current == .eraser && !state.eraserIsPixel)
    }

    @Test func thePencilDoubleTapTakesTheEraserAtItsSize() {
        var state = NotebookToolState()
        state.setEraserWidth(25)
        state.select(.pen)
        state.pencilDoubleTap(switchesToEraser: true)
        #expect(state.current == .eraser && state.eraserWidth == 25)
    }

    @Test func toolsSavedBeforeEraserSizesStillLoad() throws {
        let old = #"{"current":"marker","previous":"pen","lastInking":"marker","eraserIsPixel":true,"#
            + #""palette":[{"red":0,"green":0,"blue":0,"alpha":1}],"#
            + #""pen":{"color":{"red":0,"green":0,"blue":0,"alpha":1},"width":3},"#
            + #""pencil":{"color":{"red":0,"green":0,"blue":0,"alpha":1},"width":4},"#
            + #""marker":{"color":{"red":1,"green":1,"blue":0,"alpha":1},"width":20}}"#
        let state = try JSONDecoder().decode(NotebookToolState.self, from: Data(old.utf8))
        #expect(state.current == .marker && state.eraserIsPixel && state.eraserWidth == nil)
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
        #expect(fixed.entries.dropFirst(2).allSatisfy { $0.isVisible })
    }

    @Test func savedLayoutComesBackTheSame() throws {
        var layout = NotebookToolbarLayout.standard
        layout.position = .bottom
        layout.entries.swapAt(0, 3)
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(NotebookToolbarLayout.self, from: data) == layout)
    }
}
