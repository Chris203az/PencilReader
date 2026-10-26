package it.pencilreader.ocr

import android.graphics.Bitmap
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import it.pencilreader.core.PageText
import it.pencilreader.core.RawLine
import it.pencilreader.core.RawWord
import it.pencilreader.core.Rect

/// Riconosce il testo di una pagina intera con ML Kit (modello latino incluso nell'app, niente rete),
/// una volta sola: chi chiama salva il risultato.
class OcrService {
    private val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

    suspend fun recognize(bitmap: Bitmap): PageText {
        val width = bitmap.width.toDouble()
        val height = bitmap.height.toDouble()
        if (width <= 0 || height <= 0) return PageText(emptyList())
        val result = recognizer.process(InputImage.fromBitmap(bitmap, 0)).awaitResult()
        val lines = mutableListOf<RawLine>()
        for (block in result.textBlocks) {
            for (line in block.lines) {
                val box = line.boundingBox ?: continue
                val words = mutableListOf<RawWord>()
                for (element in line.elements) {
                    val r = element.boundingBox ?: continue
                    // ML Kit separa già le parole sugli spazi, come fa l'iPad.
                    for (piece in splitOnWhitespace(element.text)) {
                        words.add(RawWord(piece, normalized(r, width, height)))
                    }
                }
                if (words.isEmpty()) continue
                lines.add(RawLine(line.text, normalized(box, width, height), words))
            }
        }
        return PageText(lines)
    }

    fun close() = recognizer.close()

    private fun splitOnWhitespace(text: String) = text.split(Regex("\\s+")).filter { it.isNotEmpty() }

    /// Rettangoli in [0,1] con l'origine in alto a sinistra, come quelli salvati sull'iPad.
    private fun normalized(r: android.graphics.Rect, width: Double, height: Double): Rect {
        val left = (r.left / width).coerceIn(0.0, 1.0)
        val top = (r.top / height).coerceIn(0.0, 1.0)
        val right = (r.right / width).coerceIn(0.0, 1.0)
        val bottom = (r.bottom / height).coerceIn(0.0, 1.0)
        return Rect(left, top, right - left, bottom - top)
    }
}
