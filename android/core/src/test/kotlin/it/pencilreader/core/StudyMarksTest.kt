package it.pencilreader.core

import org.junit.Test
import kotlin.math.abs

/// Due righe di quattro parole, ogni parola larga 0,07 ogni 0,08, righe alte 0,02.
private fun page(): PageText {
    val lines = (0 until 2).map { i ->
        val y = 0.1 + i * 0.03
        val words = (0 until 4).map { j -> RawWord("w$i$j", Rect(0.1 + j * 0.08, y, 0.07, 0.02)) }
        RawLine(words.joinToString(" ") { it.text }, Rect(0.1, y, 0.31, 0.02), words)
    }
    return PageText(lines)
}

class StudyMarksTest {
    @Test fun highlightCoversTouchedWordsOfOneLine() {
        val stroke = listOf(pt(0.2, 0.11), pt(0.3, 0.112))
        val band = StudyMarks.highlightBand(stroke, page(), 0.02)!!
        // Dalla seconda parola (0,18) alla terza (finisce a 0,33).
        expect(abs(band.minX - 0.18) < 0.0001)
        expect(abs(band.maxX - 0.33) < 0.0001)
        expect(abs(band.minY - 0.1) < 0.0001)
        expect(abs(band.height - 0.02) < 0.0001)
    }

    @Test fun shakyHighlightStaysOnTheMainLine() {
        // Quasi tutto sulla seconda riga, con una sola uscita sulla prima.
        val stroke = listOf(pt(0.12, 0.14), pt(0.16, 0.141), pt(0.2, 0.118), pt(0.24, 0.139), pt(0.3, 0.14))
        val band = StudyMarks.highlightBand(stroke, page(), 0.02)!!
        expect(abs(band.minY - 0.13) < 0.0001)
        expect(abs(band.minX - 0.1) < 0.0001)
        expect(abs(band.maxX - 0.33) < 0.0001)
    }

    @Test fun highlightAcrossTwoLinesTakesOnlyOne() {
        val stroke = listOf(pt(0.35, 0.11), pt(0.3, 0.112), pt(0.12, 0.14))
        val band = StudyMarks.highlightBand(stroke, page(), 0.02)!!
        expect(abs(band.minY - 0.1) < 0.0001)
        expect(band.height < 0.021)
    }

    @Test fun highlightOffTheTextIsStraightAtItsMedian() {
        val stroke = listOf(pt(0.2, 0.5), pt(0.25, 0.51), pt(0.3, 0.52))
        val band = StudyMarks.highlightBand(stroke, page(), 0.05)!!
        // L'altezza media delle righe della pagina, centrata sulla mediana.
        expect(abs(band.midY - 0.51) < 0.0001)
        expect(abs(band.height - 0.02) < 0.0001)
        expect(abs(band.minX - 0.2) < 0.0001 && abs(band.maxX - 0.3) < 0.0001)
    }

    @Test fun highlightWithoutTextUsesTheFallbackHeight() {
        val stroke = listOf(pt(0.2, 0.5), pt(0.3, 0.5))
        val band = StudyMarks.highlightBand(stroke, null, 0.03)!!
        expect(abs(band.height - 0.03) < 0.0001)
        expect(StudyMarks.highlightBand(listOf(pt(0.2, 0.5)), null, 0.03) == null)
    }

    @Test fun secondPassJoinsTheFirst() {
        val first = StudyMarks.Segment(y = 100.0, minX = 100.0, maxX = 300.0, height = 20.0)
        val again = StudyMarks.Segment(y = 101.0, minX = 250.0, maxX = 400.0, height = 20.0)
        val merged = StudyMarks.merge(again, listOf(first))
        expect(merged.absorbed == listOf(0))
        expect(merged.segment.minX == 100.0 && merged.segment.maxX == 400.0)
        expect(merged.segment.y == 101.0)
    }

    @Test fun mergeBridgesHighlightsAndLeavesOtherLines() {
        val left = StudyMarks.Segment(100.0, 100.0, 200.0, 20.0)
        val right = StudyMarks.Segment(100.0, 300.0, 400.0, 20.0)
        val below = StudyMarks.Segment(130.0, 100.0, 400.0, 20.0)
        val far = StudyMarks.Segment(100.0, 600.0, 700.0, 20.0)
        val middle = StudyMarks.Segment(100.0, 190.0, 310.0, 20.0)
        val merged = StudyMarks.merge(middle, listOf(left, below, right, far))
        expect(merged.absorbed == listOf(0, 2))
        expect(merged.segment.minX == 100.0 && merged.segment.maxX == 400.0)
    }

    @Test fun roundEndsThatTouchAreJoined() {
        // A 15 di distanza: le estremità arrotondate, 10 ciascuna, si sovrappongono.
        val first = StudyMarks.Segment(100.0, 100.0, 200.0, 20.0)
        val next = StudyMarks.Segment(100.0, 215.0, 300.0, 20.0)
        expect(StudyMarks.merge(next, listOf(first)).absorbed == listOf(0))
        val apart = StudyMarks.Segment(100.0, 225.0, 300.0, 20.0)
        expect(StudyMarks.merge(apart, listOf(first)).absorbed.isEmpty())
    }

    @Test fun underlineIsHorizontalUnderTheLine() {
        val stroke = listOf(pt(0.12, 0.121), pt(0.2, 0.124), pt(0.3, 0.122))
        val (start, end) = StudyMarks.underline(stroke, page())!!
        expect(start.y == end.y)
        expect(start.x == 0.12 && end.x == 0.3)
        expect(start.y > 0.12 && start.y < 0.125)
    }

    @Test fun underlineWithoutTextKeepsItsHeight() {
        val stroke = listOf(pt(0.1, 0.5), pt(0.2, 0.52), pt(0.3, 0.51))
        val (start, _) = StudyMarks.underline(stroke, null)!!
        expect(start.y == 0.51)
    }
}
