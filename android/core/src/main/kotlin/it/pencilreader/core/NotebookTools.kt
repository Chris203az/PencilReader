package it.pencilreader.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/// Che cosa fa la penna nel quaderno.
@Serializable
enum class DrawingTool(val label: String) {
    @SerialName("pen") PEN("Penna"),
    @SerialName("pencil") PENCIL("Matita"),
    @SerialName("marker") MARKER("Evidenziatore"),
    @SerialName("eraser") ERASER("Gomma"),
    @SerialName("lasso") LASSO("Lasso");

    /// Lascia inchiostro, quindi ha un colore e uno spessore.
    val isInking: Boolean get() = this == PEN || this == PENCIL || this == MARKER

    /// I tre spessori offerti nella barra, dal sottile allo spesso.
    val widthPresets: List<Double>
        get() = when (this) {
            PEN -> listOf(1.5, 3.0, 6.0)
            PENCIL -> listOf(2.0, 4.0, 8.0)
            MARKER -> listOf(12.0, 20.0, 30.0)
            ERASER, LASSO -> emptyList()
        }

    /// Gli spessori del cursore.
    val widthRange: ClosedFloatingPointRange<Double>
        get() = when (this) {
            PENCIL -> 1.0..16.0
            MARKER -> 5.0..40.0
            else -> 0.5..12.0
        }
}

/// Un colore d'inchiostro, salvato per componenti.
@Serializable
data class InkColor(val red: Double, val green: Double, val blue: Double, val alpha: Double = 1.0) {
    /// Il colore come intero ARGB di Android.
    fun toArgb(): Int {
        fun c(v: Double) = (v.coerceIn(0.0, 1.0) * 255 + 0.5).toInt()
        return (c(alpha) shl 24) or (c(red) shl 16) or (c(green) shl 8) or c(blue)
    }

    fun sameColor(o: InkColor): Boolean =
        kotlin.math.abs(red - o.red) < 0.02 && kotlin.math.abs(green - o.green) < 0.02 &&
            kotlin.math.abs(blue - o.blue) < 0.02

    companion object {
        val BLACK = InkColor(0.1, 0.1, 0.1)
        val BLUE = InkColor(0.12, 0.36, 0.85)
        val RED = InkColor(0.84, 0.15, 0.24)
        val GREEN = InkColor(0.18, 0.55, 0.34)
        val YELLOW = InkColor(1.0, 0.85, 0.2)

        /// I cinque campioni di un quaderno nuovo.
        val PALETTE = listOf(BLACK, BLUE, RED, GREEN, YELLOW)

        fun fromArgb(argb: Int) = InkColor(
            ((argb shr 16) and 0xFF) / 255.0,
            ((argb shr 8) and 0xFF) / 255.0,
            (argb and 0xFF) / 255.0,
            ((argb ushr 24) and 0xFF) / 255.0,
        )
    }
}

/// Colore e spessore di uno strumento che scrive.
@Serializable
data class InkSetting(val color: InkColor, val width: Double)

/// Gli strumenti scelti nel quaderno, ricordati tra una sessione e l'altra.
/// Ogni strumento che scrive tiene il suo colore e il suo spessore. Immutabile: ogni modifica
/// restituisce un nuovo stato.
@Serializable
data class NotebookToolState(
    val current: DrawingTool = DrawingTool.PEN,
    /// Lo strumento prima di quello attuale.
    val previous: DrawingTool = DrawingTool.ERASER,
    /// L'ultima penna, matita o evidenziatore usati, a cui si applicano colori e spessori.
    val lastInking: DrawingTool = DrawingTool.PEN,
    /// La gomma cancella i pixel invece dei tratti interi.
    val eraserIsPixel: Boolean = false,
    /// Quanto è larga ciascun tipo di gomma; null finché non si sceglie, per la misura predefinita.
    val strokeEraserWidth: Double? = null,
    val pixelEraserWidth: Double? = null,
    val palette: List<InkColor> = InkColor.PALETTE,
    val pen: InkSetting = InkSetting(InkColor.BLACK, 3.0),
    val pencil: InkSetting = InkSetting(InkColor.BLACK, 4.0),
    val marker: InkSetting = InkSetting(InkColor.YELLOW, 20.0),
) {
    fun ink(tool: DrawingTool): InkSetting? = when (tool) {
        DrawingTool.PEN -> pen
        DrawingTool.PENCIL -> pencil
        DrawingTool.MARKER -> marker
        DrawingTool.ERASER, DrawingTool.LASSO -> null
    }

    /// La misura della gomma in uso, a tratti o a pixel; null per quella predefinita.
    val eraserWidth: Double? get() = if (eraserIsPixel) pixelEraserWidth else strokeEraserWidth

    /// Imposta la misura del tipo di gomma in uso, e prende la gomma.
    fun withEraserWidth(width: Double): NotebookToolState =
        (if (eraserIsPixel) copy(pixelEraserWidth = width) else copy(strokeEraserWidth = width)).select(DrawingTool.ERASER)

    fun withEraserPixel(isPixel: Boolean): NotebookToolState = copy(eraserIsPixel = isPixel).select(DrawingTool.ERASER)

    fun select(tool: DrawingTool): NotebookToolState {
        if (tool == current) return this
        return copy(previous = current, current = tool, lastInking = if (tool.isInking) tool else lastInking)
    }

    /// Vale per la penna, la matita o l'evidenziatore usati per ultimi, e li riprende in mano.
    fun withColor(color: InkColor) = update { it.copy(color = color) }.select(lastInking)

    fun withWidth(width: Double) = update { it.copy(width = width) }.select(lastInking)

    /// Cambia un campione e scrive con quel colore.
    fun withPaletteColor(color: InkColor, index: Int): NotebookToolState {
        if (index !in palette.indices) return this
        return copy(palette = palette.toMutableList().also { it[index] = color }).withColor(color)
    }

    /// Il doppio tocco sulla penna: alla gomma e ritorno, o allo strumento precedente.
    fun stylusDoubleTap(switchesToEraser: Boolean): NotebookToolState =
        if (switchesToEraser) select(if (current == DrawingTool.ERASER) lastInking else DrawingTool.ERASER)
        else select(previous)

    private fun update(change: (InkSetting) -> InkSetting): NotebookToolState = when (lastInking) {
        DrawingTool.PEN -> copy(pen = change(pen))
        DrawingTool.PENCIL -> copy(pencil = change(pencil))
        DrawingTool.MARKER -> copy(marker = change(marker))
        DrawingTool.ERASER, DrawingTool.LASSO -> this
    }
}

/// Le misure possibili della gomma, sullo schermo del quaderno a 1x.
object EraserSizes {
    val strokeRange = 4.0..60.0
    val pixelRange = 4.0..60.0
    const val STROKE_DEFAULT = 16.0
    const val PIXEL_DEFAULT = 12.0

    fun range(isPixel: Boolean) = if (isPixel) pixelRange else strokeRange

    /// La misura scelta per quel tipo, altrimenti quella predefinita, entro i limiti.
    fun width(state: NotebookToolState): Double {
        val r = range(state.eraserIsPixel)
        val chosen = state.eraserWidth ?: if (state.eraserIsPixel) PIXEL_DEFAULT else STROKE_DEFAULT
        return chosen.coerceIn(r.start, r.endInclusive)
    }

    /// Piccola, media e grande, distribuite sulle misure possibili.
    fun presets(isPixel: Boolean): List<Double> {
        val r = range(isPixel)
        return listOf(0.08, 0.3, 0.7).map { r.start + it * (r.endInclusive - r.start) }
    }
}

/// I controlli della barra del quaderno, ognuno si può mostrare, nascondere e spostare.
@Serializable
enum class NotebookToolbarItem(val label: String) {
    @SerialName("pen") PEN("Penna"),
    @SerialName("pencil") PENCIL("Matita"),
    @SerialName("marker") MARKER("Evidenziatore"),
    @SerialName("eraser") ERASER("Gomma"),
    @SerialName("lasso") LASSO("Lasso"),
    @SerialName("ruler") RULER("Righello"),
    @SerialName("colors") COLORS("Colori"),
    @SerialName("width") WIDTH("Spessore"),
    @SerialName("undo") UNDO("Annulla"),
    @SerialName("redo") REDO("Ripristina"),
    @SerialName("shapes") SHAPES("Forme automatiche"),
    @SerialName("paper") PAPER("Sfondo"),
}

/// Dove sta la barra degli strumenti, cosa mostra e in che ordine.
@Serializable
data class NotebookToolbarLayout(
    val position: Position = Position.TOP,
    val entries: List<Entry>,
) {
    @Serializable
    enum class Position(val label: String) {
        @SerialName("top") TOP("In alto"),
        @SerialName("bottom") BOTTOM("In basso"),
    }

    @Serializable
    data class Entry(val item: NotebookToolbarItem, val isVisible: Boolean)

    val visibleItems: List<NotebookToolbarItem> get() = entries.filter { it.isVisible }.map { it.item }

    /// Ogni elemento una volta: i doppioni spariscono, e quelli aggiunti in una versione
    /// successiva compaiono in fondo, visibili.
    fun normalized(): NotebookToolbarLayout {
        val seen = mutableSetOf<NotebookToolbarItem>()
        val fixed = entries.filter { seen.add(it.item) }.toMutableList()
        for (item in NotebookToolbarItem.entries) {
            if (item !in seen) fixed.add(Entry(item, true))
        }
        return NotebookToolbarLayout(position, fixed)
    }

    companion object {
        /// In alto, tutto visibile, nell'ordine di `NotebookToolbarItem`.
        val STANDARD = NotebookToolbarLayout(entries = NotebookToolbarItem.entries.map { Entry(it, true) })
    }
}
