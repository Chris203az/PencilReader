package it.pencilreader.core

/// Dove sta la nota scritta a mano di una pagina del libro: un file per pagina,
/// in una cartella con il nome del libro.
data class PageNote(val bookID: String, val pageIndex: Int) {
    val id: String get() = relativePath

    /// `<id del libro>/<pagina>.ink.json`, relativo alla cartella delle note.
    val relativePath: String get() = relativePath(bookID, pageIndex)

    companion object {
        const val SUFFIX = ".ink.json"

        fun relativePath(bookID: String, pageIndex: Int) = bookID + "/" + fileName(pageIndex)

        fun fileName(pageIndex: Int) = String.format(java.util.Locale.ROOT, "%04d", pageIndex) + SUFFIX

        /// La pagina di un file di note, o null per qualunque altro file.
        fun pageIndex(fileName: String): Int? {
            if (!fileName.endsWith(SUFFIX)) return null
            val number = fileName.dropLast(SUFFIX.length)
            if (number.isEmpty() || !number.all { it.isDigit() }) return null
            return number.toIntOrNull()
        }
    }
}

/// La carta dietro il quaderno. Il valore grezzo è quello salvato nelle impostazioni.
enum class PaperStyle(val rawValue: String, val label: String) {
    GRID("grid", "Quadretti"),
    LINES("lines", "Righe"),
    BLANK("blank", "Bianco");

    companion object {
        fun fromRaw(raw: String?): PaperStyle? = entries.firstOrNull { it.rawValue == raw }
    }
}

/// La parte della larghezza data alla pagina del libro quando il quaderno è aperto.
object SplitRatio {
    val range = 0.3..0.7
    const val STANDARD = 0.5

    fun clamped(value: Double) = value.coerceIn(range.start, range.endInclusive)
}
