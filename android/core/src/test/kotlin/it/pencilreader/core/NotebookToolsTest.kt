package it.pencilreader.core

import kotlinx.serialization.json.Json
import org.junit.Test

private val json = Json { ignoreUnknownKeys = true }

class NotebookToolStateTest {
    @Test fun startsWithTheBlackPen() {
        val state = NotebookToolState()
        expect(state.current == DrawingTool.PEN)
        expect(state.ink(DrawingTool.PEN) == InkSetting(InkColor.BLACK, 3.0))
        expect(state.ink(DrawingTool.ERASER) == null)
        expect(state.palette.size == 5)
    }

    @Test fun eachKindOfEraserKeepsItsSize() {
        var state = NotebookToolState()
        expect(state.eraserWidth == null)
        state = state.withEraserWidth(30.0)
        expect(state.current == DrawingTool.ERASER && state.strokeEraserWidth == 30.0)
        state = state.copy(eraserIsPixel = true)
        expect(state.eraserWidth == null)
        state = state.withEraserWidth(8.0)
        expect(state.eraserWidth == 8.0)
        state = state.copy(eraserIsPixel = false)
        expect(state.eraserWidth == 30.0)
        // Scegliere di nuovo la gomma non cambia nulla: la barra ne apre invece le impostazioni.
        state = state.select(DrawingTool.ERASER)
        expect(state.current == DrawingTool.ERASER && !state.eraserIsPixel)
    }

    @Test fun theDoubleTapTakesTheEraserAtItsSize() {
        val state = NotebookToolState().withEraserWidth(25.0).select(DrawingTool.PEN).stylusDoubleTap(switchesToEraser = true)
        expect(state.current == DrawingTool.ERASER && state.eraserWidth == 25.0)
    }

    @Test fun toolsSavedBeforeEraserSizesStillLoad() {
        val old = """{"current":"marker","previous":"pen","lastInking":"marker","eraserIsPixel":true,""" +
            """"palette":[{"red":0,"green":0,"blue":0,"alpha":1}],""" +
            """"pen":{"color":{"red":0,"green":0,"blue":0,"alpha":1},"width":3},""" +
            """"pencil":{"color":{"red":0,"green":0,"blue":0,"alpha":1},"width":4},""" +
            """"marker":{"color":{"red":1,"green":1,"blue":0,"alpha":1},"width":20}}"""
        val state = json.decodeFromString(NotebookToolState.serializer(), old)
        expect(state.current == DrawingTool.MARKER && state.eraserIsPixel && state.eraserWidth == null)
    }

    @Test fun colorAndWidthBelongToTheLastInkingTool() {
        val state = NotebookToolState().select(DrawingTool.MARKER).select(DrawingTool.LASSO)
            .withColor(InkColor.BLUE).withWidth(30.0)
        expect(state.current == DrawingTool.MARKER)
        expect(state.marker == InkSetting(InkColor.BLUE, 30.0))
        expect(state.pen == InkSetting(InkColor.BLACK, 3.0))
    }

    @Test fun doubleTapGoesToTheEraserAndBack() {
        var state = NotebookToolState().select(DrawingTool.PENCIL)
        state = state.stylusDoubleTap(switchesToEraser = true)
        expect(state.current == DrawingTool.ERASER)
        state = state.stylusDoubleTap(switchesToEraser = true)
        expect(state.current == DrawingTool.PENCIL)
    }

    @Test fun doubleTapCanSwitchToThePreviousTool() {
        var state = NotebookToolState().select(DrawingTool.LASSO)
        state = state.stylusDoubleTap(switchesToEraser = false)
        expect(state.current == DrawingTool.PEN)
        state = state.stylusDoubleTap(switchesToEraser = false)
        expect(state.current == DrawingTool.LASSO)
    }

    @Test fun savedStateComesBackTheSame() {
        val state = NotebookToolState().select(DrawingTool.MARKER).withColor(InkColor.GREEN)
        val data = json.encodeToString(NotebookToolState.serializer(), state)
        expect(json.decodeFromString(NotebookToolState.serializer(), data) == state)
    }

    @Test fun eraserSizesStayInRange() {
        val state = NotebookToolState().withEraserWidth(1000.0)
        expect(EraserSizes.width(state) == EraserSizes.strokeRange.endInclusive)
        expect(EraserSizes.width(NotebookToolState()) == EraserSizes.STROKE_DEFAULT)
        expect(EraserSizes.presets(isPixel = true).size == 3)
    }

    @Test fun colorsConvertToAndroid() {
        expect(InkColor(1.0, 0.0, 0.0).toArgb() == 0xFFFF0000.toInt())
        expect(InkColor.fromArgb(0xFF336699.toInt()).sameColor(InkColor(0.2, 0.4, 0.6)))
    }
}

class NotebookToolbarLayoutTest {
    @Test fun standardShowsEverythingAtTheTop() {
        val layout = NotebookToolbarLayout.STANDARD
        expect(layout.position == NotebookToolbarLayout.Position.TOP)
        expect(layout.visibleItems == NotebookToolbarItem.entries.toList())
    }

    @Test fun hiddenItemsAreLeftOut() {
        val standard = NotebookToolbarLayout.STANDARD
        val layout = standard.copy(entries = standard.entries.mapIndexed { i, e -> if (i == 0) e.copy(isVisible = false) else e })
        expect(NotebookToolbarItem.PEN !in layout.visibleItems)
        expect(layout.visibleItems.size == NotebookToolbarItem.entries.size - 1)
    }

    @Test fun normalizingDropsDuplicatesAndAddsMissingItems() {
        val saved = NotebookToolbarLayout(NotebookToolbarLayout.Position.BOTTOM, listOf(
            NotebookToolbarLayout.Entry(NotebookToolbarItem.UNDO, true),
            NotebookToolbarLayout.Entry(NotebookToolbarItem.PEN, false),
            NotebookToolbarLayout.Entry(NotebookToolbarItem.UNDO, false),
        ))
        val fixed = saved.normalized()
        expect(fixed.position == NotebookToolbarLayout.Position.BOTTOM)
        expect(fixed.entries.size == NotebookToolbarItem.entries.size)
        expect(fixed.entries.take(2) == listOf(
            NotebookToolbarLayout.Entry(NotebookToolbarItem.UNDO, true),
            NotebookToolbarLayout.Entry(NotebookToolbarItem.PEN, false),
        ))
        expect(fixed.entries.drop(2).all { it.isVisible })
    }

    @Test fun savedLayoutComesBackTheSame() {
        val entries = NotebookToolbarLayout.STANDARD.entries.toMutableList()
        val first = entries[0]
        entries[0] = entries[3]
        entries[3] = first
        val layout = NotebookToolbarLayout(NotebookToolbarLayout.Position.BOTTOM, entries)
        val data = json.encodeToString(NotebookToolbarLayout.serializer(), layout)
        expect(json.decodeFromString(NotebookToolbarLayout.serializer(), data) == layout)
    }
}
