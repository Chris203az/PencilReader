package it.pencilreader.study

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import it.pencilreader.core.PageText
import it.pencilreader.core.Point
import it.pencilreader.core.StudyMarks
import it.pencilreader.data.AnnotationStore
import it.pencilreader.data.Settings
import it.pencilreader.ui.polylineDistance
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlin.math.min

// Metodo

/// I colori dell'evidenziatore del metodo di studio, ognuno con un significato fisso.
@Serializable
enum class StudyColor(val label: String, val shortLabel: String, val detail: String, val argb: Int) {
    @SerialName("key") KEY("Concetto chiave", "Concetto", "Definizioni e idee principali", rgb(1.0, 0.62, 0.15)),
    @SerialName("formula") FORMULA("Formula / dato", "Formula", "Equazioni, valori, ipotesi e unità", rgb(0.35, 0.75, 1.0)),
    @SerialName("review") REVIEW("Da rivedere", "Rivedere", "Non chiaro: da rivedere o chiedere", rgb(1.0, 0.45, 0.7)),
}

/// Che cosa fa la penna nella modalità studio.
sealed interface StudyTool {
    data class Highlighter(val color: StudyColor) : StudyTool
    /// Una riga sottile sotto i termini inglesi da imparare, raddrizzata quando la penna si alza.
    data object Underline : StudyTool
    /// Domande e note a margine, con parole proprie.
    data object Pen : StudyTool
    data object Eraser : StudyTool

    companion object {
        val UNDERLINE_COLOR = rgb(0.85, 0.15, 0.1)
        val PEN_COLOR = rgb(0.1, 0.2, 0.6)
        /// Trasparente, e moltiplicato sulla pagina, così le parole restano nere sotto il colore.
        const val HIGHLIGHT_ALPHA = 0.58f
        /// Spessori in unità della pagina: la pagina è larga `StudyModel.PAGE_WIDTH`.
        const val UNDERLINE_WIDTH = 2.5f
        const val PEN_WIDTH = 2.2f
        /// Lo spessore dell'evidenziatore, in unità della pagina.
        const val HIGHLIGHT_WIDTH = 18f
    }
}

internal fun rgb(r: Double, g: Double, b: Double): Int =
    (0xFF shl 24) or ((r * 255 + 0.5).toInt() shl 16) or ((g * 255 + 0.5).toInt() shl 8) or (b * 255 + 0.5).toInt()

// Dati

@Serializable
data class StudyPoint(val x: Float, val y: Float)

/// Un segno sopra la pagina, in unità della pagina: larga `StudyModel.PAGE_WIDTH`, alta in proporzione.
@Serializable
data class StudyMark(
    val id: Long,
    val kind: Kind,
    val points: List<StudyPoint>,
    /// Lo spessore della linea, in unità della pagina.
    val width: Float,
    /// Solo per le evidenziature.
    val color: StudyColor? = null,
) {
    @Serializable
    enum class Kind {
        @SerialName("highlight") HIGHLIGHT,
        @SerialName("underline") UNDERLINE,
        @SerialName("pen") PEN,
    }

    val argb: Int
        get() = when (kind) {
            Kind.HIGHLIGHT -> color?.argb ?: StudyColor.KEY.argb
            Kind.UNDERLINE -> StudyTool.UNDERLINE_COLOR
            Kind.PEN -> StudyTool.PEN_COLOR
        }

    /// Un'evidenziatura dritta di quel colore, come segmento in unità della pagina; null per tutto il resto,
    /// come un'evidenziatura lasciata a mano libera.
    fun segment(colored: StudyColor): StudyMarks.Segment? {
        if (kind != Kind.HIGHLIGHT || color != colored || points.isEmpty()) return null
        val ys = points.map { it.y.toDouble() }
        val xs = points.map { it.x.toDouble() }
        if (ys.max() - ys.min() >= 0.5) return null
        return StudyMarks.Segment((ys.min() + ys.max()) / 2, xs.min(), xs.max(), width.toDouble())
    }
}

/// I segni di studio di una pagina.
@Serializable
data class StudyPage(val marks: List<StudyMark> = emptyList()) {
    val isEmpty: Boolean get() = marks.isEmpty()
}

// Modello

/// La modalità studio di un libro aperto: se è attiva, lo strumento in mano, quali pagine hanno segni,
/// i segni della pagina mostrata. I segni si salvano un momento dopo l'ultimo tratto, quando la pagina
/// cambia, quando la modalità si spegne e quando l'app esce dallo schermo.
class StudyModel(
    private val bookID: String,
    private val store: AnnotationStore,
    private val settings: Settings,
    private val scope: CoroutineScope,
) {
    var isActive by mutableStateOf(false)
        private set
    var tool by mutableStateOf<StudyTool>(StudyTool.Highlighter(StudyColor.KEY))
    var markedPages by mutableStateOf(store.pages(bookID))
        private set
    var showsGuide by mutableStateOf(false)
    /// La pagina di cui si mostrano i segni, e i segni.
    var page by mutableStateOf<Int?>(null)
        private set
    var marks by mutableStateOf(emptyList<StudyMark>())
        private set
    val canUndo: Boolean get() = history.isNotEmpty()

    /// I segni prima di ogni modifica, per Annulla: una voce per tratto o passata di gomma.
    private var history by mutableStateOf(emptyList<List<StudyMark>>())
    private var saveJob: Job? = null
    private var nextID = System.currentTimeMillis()
    private var erasingStarted = false

    /// La prima volta si apre anche la guida.
    fun toggle() {
        if (isActive) {
            flush()
            isActive = false
        } else {
            isActive = true
            if (!settings.studyGuideSeen) {
                settings.markStudyGuideSeen()
                showsGuide = true
            }
        }
    }

    /// Segue il lettore: carica i segni della pagina mostrata, dopo aver salvato quelli della precedente.
    fun show(newPage: Int) {
        if (newPage == page) return
        flush()
        page = newPage
        history = emptyList()
        marks = store.load(bookID, newPage)?.marks ?: emptyList()
    }

    // Tratti

    /// Un tratto finito, in unità della pagina, alta `pageHeight`. L'evidenziatura diventa una fascia
    /// dritta sulla riga di testo a cui era destinata, unita alle evidenziature dello stesso colore già lì;
    /// la sottolineatura diventa dritta.
    fun addStroke(points: List<Point>, pageHeight: Double, text: PageText?) {
        if (points.isEmpty() || page == null) return
        val before = marks
        val current = tool
        val normalized = points.map { Point(it.x / PAGE_WIDTH, it.y / pageHeight) }
        var updated = marks
        when (current) {
            is StudyTool.Highlighter -> {
                val rect = StudyMarks.highlightBand(normalized, text, StudyTool.HIGHLIGHT_WIDTH / pageHeight)
                if (rect == null) {
                    updated = updated + mark(StudyMark.Kind.HIGHLIGHT, points, StudyTool.HIGHLIGHT_WIDTH, current.color)
                } else {
                    val bandMinX = rect.minX * PAGE_WIDTH
                    val bandMaxX = rect.maxX * PAGE_WIDTH
                    val bandMinY = rect.minY * pageHeight
                    val bandHeight = rect.height * pageHeight
                    // Un po' più sottile del riquadro della riga, che va già oltre le lettere: la fascia
                    // non sconfina mai sulle righe sopra e sotto. Le estremità tonde restano dentro le parole.
                    val size = bandHeight * 0.85
                    val inset = min(size * 0.35, (bandMaxX - bandMinX) / 2)
                    val segment = StudyMarks.Segment(bandMinY + bandHeight / 2, bandMinX + inset, bandMaxX - inset, size)
                    // Le evidenziature dritte dello stesso colore: quelle che si toccano diventano un tratto solo,
                    // così una seconda passata lascia il colore com'era.
                    val others = updated.mapIndexedNotNull { i, m -> m.segment(current.color)?.let { i to it } }
                    val merged = StudyMarks.merge(segment, others.map { it.second })
                    val removed = merged.absorbed.map { others[it].first }.toSet()
                    val s = merged.segment
                    updated = updated.filterIndexed { i, _ -> i !in removed } + StudyMark(
                        newID(), StudyMark.Kind.HIGHLIGHT,
                        listOf(StudyPoint(s.minX.toFloat(), s.y.toFloat()), StudyPoint(s.maxX.toFloat(), s.y.toFloat())),
                        s.height.toFloat(), current.color,
                    )
                }
            }
            StudyTool.Underline -> {
                val line = StudyMarks.underline(normalized, text)
                updated = if (line == null) {
                    updated + mark(StudyMark.Kind.UNDERLINE, points, StudyTool.UNDERLINE_WIDTH, null)
                } else {
                    val (a, b) = line
                    updated + StudyMark(
                        newID(), StudyMark.Kind.UNDERLINE,
                        listOf(
                            StudyPoint((a.x * PAGE_WIDTH).toFloat(), (a.y * pageHeight).toFloat()),
                            StudyPoint((b.x * PAGE_WIDTH).toFloat(), (b.y * pageHeight).toFloat()),
                        ),
                        StudyTool.UNDERLINE_WIDTH,
                    )
                }
            }
            StudyTool.Pen -> updated = updated + mark(StudyMark.Kind.PEN, points, StudyTool.PEN_WIDTH, null)
            StudyTool.Eraser -> return
        }
        // Una voce sola nella cronologia: un Annulla toglie tutto il tratto, anche se è stato unito ad altri.
        history = history + listOf(before)
        marks = updated
        changed()
    }

    /// La gomma toglie i segni interi che tocca. Una passata è una voce sola di Annulla.
    fun beginErasing() {
        erasingStarted = false
    }

    fun erase(at: Point, radius: Double) {
        val kept = marks.filter { distance(it, at) > radius + it.width / 2 }
        if (kept.size == marks.size) return
        if (!erasingStarted) {
            history = history + listOf(marks)
            erasingStarted = true
        }
        marks = kept
        changed()
    }

    fun undo() {
        val previous = history.lastOrNull() ?: return
        history = history.dropLast(1)
        marks = previous
        changed()
    }

    // Salvataggio

    private fun changed() {
        saveJob?.cancel()
        saveJob = scope.launch {
            delay(SAVE_DELAY_MS)
            flush()
        }
    }

    fun flush() {
        saveJob?.cancel()
        saveJob = null
        val current = page ?: return
        val snapshot = StudyPage(marks)
        val hasMarks = !snapshot.isEmpty
        markedPages = if (hasMarks) markedPages + current else markedPages - current
        scope.launch { withContext(Dispatchers.IO) { store.save(snapshot, bookID, current) } }
    }

    private fun mark(kind: StudyMark.Kind, points: List<Point>, width: Float, color: StudyColor?) =
        StudyMark(newID(), kind, points.map { StudyPoint(it.x.toFloat(), it.y.toFloat()) }, width, color)

    private fun newID(): Long = nextID++

    private fun distance(mark: StudyMark, p: Point): Double =
        polylineDistance(p, mark.points.map { Point(it.x.toDouble(), it.y.toDouble()) })

    companion object {
        /// La pagina è sempre larga così, qualunque sia la sua misura sullo schermo: i segni restano
        /// sul loro testo quando la pagina si ingrandisce, si sposta o si stringe accanto al quaderno.
        const val PAGE_WIDTH = 1000.0
        private const val SAVE_DELAY_MS = 1000L
    }
}
