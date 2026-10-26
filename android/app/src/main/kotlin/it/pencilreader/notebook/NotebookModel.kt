package it.pencilreader.notebook

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import it.pencilreader.core.DrawingTool
import it.pencilreader.core.EraserSizes
import it.pencilreader.core.InkColor
import it.pencilreader.core.NotebookToolState
import it.pencilreader.data.NoteStore
import it.pencilreader.data.Settings
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/// Il quaderno accanto a una pagina del libro. Tiene la pagina che mostra e salva ciò che c'è scritto
/// un momento dopo l'ultimo tratto, quando la pagina cambia, quando il quaderno si chiude e quando l'app
/// esce dallo schermo. Una pagina ha una nota solo quando la si comincia: sfogliare non ne crea mai.
class NotebookModel(
    val bookID: String,
    pageIndex: Int,
    private val store: NoteStore,
    val settings: Settings,
    private val scope: CoroutineScope,
) {
    var pageIndex by mutableStateOf(pageIndex)
        private set
    /// Le pagine di questo libro con qualcosa scritto sopra.
    var notedPages by mutableStateOf(store.pages(bookID))
        private set
    /// Se la pagina mostra la sua nota, cioè il foglio su cui scrivere.
    var isWriting by mutableStateOf(pageIndex in notedPages)
        private set
    /// I tratti della pagina mostrata, dal più vecchio al più recente (quello più in alto).
    var strokes by mutableStateOf(emptyList<InkStroke>())
        private set
    /// Non si salva: il righello si mette via quando il quaderno si chiude.
    var isRulerActive by mutableStateOf(false)
    /// Cambia a ogni pagina caricata, così il foglio torna a zoom 1 e in cima.
    var loadCount by mutableStateOf(0)
        private set

    private var undoStack by mutableStateOf(emptyList<List<InkStroke>>())
    private var redoStack by mutableStateOf(emptyList<List<InkStroke>>())
    val canUndo: Boolean get() = undoStack.isNotEmpty()
    val canRedo: Boolean get() = redoStack.isNotEmpty()

    /// La pagina i cui tratti sono in `strokes`: si salva sempre sulla pagina su cui si è scritto.
    private var loadedPage: Int? = null
    private var saveJob: Job? = null
    private var nextID = System.currentTimeMillis() * 1000

    init {
        if (isWriting) load()
    }

    // Strumenti

    val tools: NotebookToolState get() = settings.toolState

    fun updateTools(change: (NotebookToolState) -> NotebookToolState) = settings.updateToolState(change(settings.toolState))

    fun select(tool: DrawingTool) = updateTools { it.select(tool) }

    val eraserWidth: Double get() = EraserSizes.width(tools)

    /// Colore e spessore dell'ultima penna, matita o evidenziatore, mostrati dai campioni e dagli spessori.
    val currentInk get() = tools.ink(tools.lastInking)

    fun setColor(color: InkColor) = updateTools { it.withColor(color) }

    // Pagine

    /// Gira su un'altra pagina del libro: salva quella attuale, poi mostra la nota della nuova se ce l'ha.
    fun show(page: Int) {
        if (page == pageIndex) return
        flush()
        pageIndex = page
        isWriting = page in notedPages
        if (isWriting) load() else unload()
    }

    /// Comincia una nota sulla pagina attuale, quando la si chiede.
    fun startNote() {
        if (isWriting) return
        isWriting = true
        load()
    }

    private fun load() {
        loadedPage = pageIndex
        strokes = store.load(bookID, pageIndex)?.strokes ?: emptyList()
        undoStack = emptyList()
        redoStack = emptyList()
        loadCount += 1
    }

    private fun unload() {
        loadedPage = null
        strokes = emptyList()
        undoStack = emptyList()
        redoStack = emptyList()
    }

    // Modifiche

    fun newID(): Long = nextID++

    /// Un passo di Annulla: torna a `previous` (o ai tratti attuali), e Ripristina rimette `newStrokes`.
    fun commit(newStrokes: List<InkStroke>, previous: List<InkStroke> = strokes) {
        undoStack = (undoStack + listOf(previous)).takeLast(MAX_UNDO)
        redoStack = emptyList()
        strokes = newStrokes
        changed()
    }

    /// Cambia i tratti senza un passo di Annulla, per le modifiche in corso (la gomma mentre passa):
    /// alla fine, `commit` con i tratti di partenza ne fa un passo solo.
    fun replaceLive(newStrokes: List<InkStroke>) {
        strokes = newStrokes
    }

    fun undo(): Boolean {
        val previous = undoStack.lastOrNull() ?: return false
        undoStack = undoStack.dropLast(1)
        redoStack = redoStack + listOf(strokes)
        strokes = previous
        changed()
        return true
    }

    fun redo(): Boolean {
        val next = redoStack.lastOrNull() ?: return false
        redoStack = redoStack.dropLast(1)
        undoStack = undoStack + listOf(strokes)
        strokes = next
        changed()
        return true
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
        val page = loadedPage ?: return
        val snapshot = NotePage(strokes)
        notedPages = if (snapshot.isEmpty) notedPages - page else notedPages + page
        scope.launch { withContext(Dispatchers.IO) { store.save(snapshot, bookID, page) } }
    }

    fun load(page: Int): NotePage? = store.load(bookID, page)

    companion object {
        private const val SAVE_DELAY_MS = 1000L
        private const val MAX_UNDO = 100

        /// I tratti copiati o tagliati, da incollare su qualunque pagina di qualunque libro.
        var clipboard: List<InkStroke> = emptyList()
    }
}
