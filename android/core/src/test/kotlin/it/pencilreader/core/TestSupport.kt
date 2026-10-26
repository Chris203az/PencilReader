package it.pencilreader.core

import org.junit.Assert.assertTrue

fun expect(condition: Boolean, message: String = "aspettativa non soddisfatta") = assertTrue(message, condition)

fun pt(x: Number, y: Number) = Point(x.toDouble(), y.toDouble())

fun rect(x: Number, y: Number, w: Number, h: Number) = Rect(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble())

/// Righe con parole a passo regolare (coordinate normalizzate), come nei test Swift.
fun makeLines(texts: List<String>, lineHeight: Double = 0.02, gap: Double = 0.008): List<RawLine> =
    texts.mapIndexed { i, text ->
        val y = 0.1 + i * (lineHeight + gap)
        val tokens = text.split(" ").filter { it.isNotEmpty() }
        val words = tokens.mapIndexed { j, t -> RawWord(t, Rect(0.1 + j * 0.08, y, 0.07, lineHeight)) }
        RawLine(text, Rect(0.1, y, 0.8, lineHeight), words)
    }
