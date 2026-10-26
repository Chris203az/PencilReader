package it.pencilreader.reader

import android.graphics.Bitmap
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import it.pencilreader.PencilReaderApp
import it.pencilreader.core.LassoSelector
import it.pencilreader.core.PageText
import it.pencilreader.core.Point
import it.pencilreader.core.Rect
import it.pencilreader.core.SavedWord
import it.pencilreader.core.SentenceContext
import it.pencilreader.core.Span
import it.pencilreader.core.TranslationHighlighter
import it.pencilreader.data.LibraryDocument
import it.pencilreader.render.PageSource
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext


/// Lo stato di un documento aperto: la pagina, il suo testo riconosciuto, la selezione del lazo.
/// Tutto si legge e si cambia dal thread principale; il lavoro pesante va su altri thread.
class ReaderModel(
    private val app: PencilReaderApp,
    val document: LibraryDocument,
    private val scope: CoroutineScope,
) {
    data class Selection(
        val id: Long,
        val wordIDs: List<Int>,
        /// Il riquadro del lazo, normalizzato sull'immagine della pagina.
        val anchor: Rect,
        val text: String,
        val context: SentenceContext?,
        /// La frase tradotta (o solo il termine, quando non c'è una frase).
        val translation: String? = null,
        /// La parte di `translation` che corrisponde alle parole cerchiate.
        val highlight: Span? = null,
        /// Mostrata a parte solo quando non si è trovata nella frase.
        val termTranslation: String? = null,
        val error: String? = null,
        /// Il modello di traduzione si sta scaricando (solo la prima volta).
        val isDownloadingModel: Boolean = false,
    )

    private val library = app.library
    val pageCount = document.pageCount
    var pageIndex by mutableStateOf(0)
        private set
    var pageImage by mutableStateOf<Bitmap?>(null)
        private set
    var pageText by mutableStateOf<PageText?>(null)
        private set
    var selection by mutableStateOf<Selection?>(null)
        private set
    var showWordBoxes by mutableStateOf(false)
    var allowsFingerDrawing by mutableStateOf(false)
    var alertMessage by mutableStateOf<String?>(null)
    /// Le parole trovate dalla ricerca nel libro, evidenziate sulla loro pagina.
    private var searchHighlight by mutableStateOf<Pair<Int, Set<Int>>?>(null)

    private val source = PageSource(
        if (document.kind == LibraryDocument.Kind.PDF) library.pdfFile(document) else null,
        if (document.kind == LibraryDocument.Kind.IMAGES) library.pagesFolder(document) else null,
    )
    private val imageCache = mutableMapOf<Int, Bitmap>()
    private val imageJobs = mutableMapOf<Int, Deferred<Bitmap?>>()
    private val textCache = mutableMapOf<Int, PageText>()
    private val ocrJobs = mutableMapOf<Int, Deferred<PageText>>()
    private var pageJob: Job? = null
    private var translationJob: Job? = null
    private var nextSelectionID = 0L

    val title: String get() = library.document(document.id)?.title ?: document.title
    val isRecognizing: Boolean get() = pageImage != null && pageText == null

    init {
        library.markOpened(document)
        showPage(document.lastPage.coerceIn(0, maxOf(pageCount - 1, 0)))
    }

    // Pagine

    fun showPage(index: Int) {
        if (index !in 0 until pageCount) return
        pageIndex = index
        clearSelection()
        searchHighlight = null
        pageImage = imageCache[index]
        pageText = textCache[index]
        library.setLastPage(index, document)
        pageJob?.cancel()
        pageJob = scope.launch {
            val image = image(index)
            if (pageIndex != index) return@launch
            if (image == null) {
                alertMessage = "Impossibile aprire il documento."
                return@launch
            }
            pageImage = image
            // Tiene solo le pagine accanto a quella mostrata.
            val keep = (index - 1)..(index + 1)
            imageCache.keys.filter { it !in keep }.forEach { imageCache.remove(it) }
            recognizeCurrentPage(index)
        }
    }

    /// Apre la pagina di un risultato della ricerca, con le sue parole evidenziate.
    fun showMatch(page: Int, wordIDs: List<Int>) {
        showPage(page)
        searchHighlight = page to wordIDs.toSet()
    }

    val searchHighlightOnPage: Set<Int>
        get() = searchHighlight?.takeIf { it.first == pageIndex }?.second ?: emptySet()

    fun nextPage() = showPage(pageIndex + 1)
    fun previousPage() = showPage(pageIndex - 1)

    private suspend fun image(index: Int): Bitmap? {
        imageCache[index]?.let { return it }
        val job = imageJobs[index] ?: scope.async(Dispatchers.Default) { source.render(index, DISPLAY_DIMENSION) }
            .also { imageJobs[index] = it }
        val image = try {
            job.await()
        } finally {
            if (imageJobs[index] === job) imageJobs.remove(index)
        }
        if (image != null) imageCache[index] = image
        return image
    }

    /// L'OCR gira una volta per pagina e si salva con il documento; la pagina dopo si prepara
    /// in sottofondo, così girare pagina non la aspetta.
    private suspend fun recognizeCurrentPage(index: Int) {
        try {
            val text = recognizedText(index)
            if (pageIndex == index) pageText = text
            if (index + 1 < pageCount) runCatching { recognizedText(index + 1) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (pageIndex == index) alertMessage = "Riconoscimento del testo non riuscito: ${e.localizedMessage ?: e.javaClass.simpleName}"
        }
    }

    private suspend fun recognizedText(index: Int): PageText {
        textCache[index]?.let { return it }
        withContext(Dispatchers.IO) { library.savedText(document, index) }?.let {
            textCache[index] = it
            return it
        }
        val job = ocrJobs[index] ?: run {
            val bitmap = image(index) ?: return PageText(emptyList())
            scope.async(Dispatchers.Default) { app.ocr.recognize(bitmap) }.also { ocrJobs[index] = it }
        }
        val text = try {
            job.await()
        } finally {
            if (ocrJobs[index] === job) ocrJobs.remove(index)
        }
        if (textCache[index] == null) {
            textCache[index] = text
            withContext(Dispatchers.IO) { library.saveText(text, document, index) }
        }
        return text
    }

    // Selezione

    /// `stroke` e `imageFrame` sono nelle stesse coordinate della vista.
    fun select(stroke: List<Point>, imageFrame: Rect) {
        val text = pageText
        if (text == null || stroke.size < 2) {
            clearSelection()
            return
        }
        val rects = text.words.map { it.rect.denormalized(imageFrame) }
        val ids = LassoSelector.select(stroke, rects)
        val selected = text.text(ids)
        if (ids.isEmpty() || selected.isEmpty()) {
            clearSelection()
            return
        }
        val chosen = Selection(
            id = ++nextSelectionID,
            wordIDs = ids,
            anchor = Rect.bounding(stroke).normalized(imageFrame),
            text = selected,
            context = text.contextSentences(ids),
        )
        selection = chosen
        translate(chosen)
    }

    fun clearSelection() {
        translationJob?.cancel()
        selection = null
    }

    private fun translate(current: Selection) {
        translationJob?.cancel()
        translationJob = scope.launch {
            val translator = app.translator
            try {
                translator.prepare(onDownloadStarted = {
                    scope.launch { update(current.id) { it.copy(isDownloadingModel = true) } }
                })
                update(current.id) { it.copy(isDownloadingModel = false) }
                val marked = current.context?.let { TranslationHighlighter.marked(it) }
                val term = translator.translate(current.text)
                val sentence = current.context?.let { translator.translate(it.text) }
                val markedTranslation = marked?.let { translator.translate(it.text) }
                if (selection?.id != current.id) return@launch
                val result = highlightedSentence(term, sentence, markedTranslation, marked, current)
                update(current.id) {
                    it.copy(
                        translation = result.first,
                        highlight = result.second,
                        termTranslation = if (result.second == null) term else null,
                    )
                }
                val now = System.currentTimeMillis()
                app.wordList.add(
                    SavedWord(
                        term = current.text,
                        translation = result.second?.let { result.first.substring(it.start, it.end) } ?: term,
                        sentence = current.context?.text,
                        sentenceTranslation = if (current.context == null) null else result.first,
                        documentID = document.id,
                        documentTitle = title,
                        page = pageIndex,
                        firstLookedUp = now,
                    ),
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                update(current.id) {
                    it.copy(
                        isDownloadingModel = false,
                        error = "Traduzione non disponibile: ${e.localizedMessage ?: e.javaClass.simpleName}",
                    )
                }
            }
        }
    }

    private fun update(id: Long, change: (Selection) -> Selection) {
        val current = selection ?: return
        if (current.id == id) selection = change(current)
    }

    fun close() {
        translationJob?.cancel()
        pageJob?.cancel()
        scope.launch(Dispatchers.Default) { source.close() }
    }

    companion object {
        /// Il lato lungo delle pagine PDF disegnate per lo schermo e per l'OCR.
        const val DISPLAY_DIMENSION = 2200

        /// Preferisce la traduzione con le virgolette (allineamento esatto); altrimenti cerca il termine
        /// tradotto a parte dentro la traduzione della frase senza virgolette.
        internal fun highlightedSentence(
            term: String,
            sentence: String?,
            marked: String?,
            markers: TranslationHighlighter.Marked?,
            source: Selection,
        ): Pair<String, Span?> {
            if (sentence == null) return term to Span(0, term.length)
            if (marked != null && markers != null) {
                val unmarked = TranslationHighlighter.unmark(marked, markers.open, markers.close)
                if (unmarked != null) {
                    // Le virgolette possono far lasciare la parola in inglese; allora è meglio la frase semplice.
                    val inside = unmarked.text.substring(unmarked.highlight.start, unmarked.highlight.end)
                    val leftUntranslated = inside.equals(source.text, ignoreCase = true) &&
                        !term.equals(source.text, ignoreCase = true)
                    if (!leftUntranslated) return unmarked.text to unmarked.highlight
                }
            }
            val position = source.context?.selectionPosition
            val range = TranslationHighlighter.fuzzyRange(term, sentence, position)
            return sentence to range
        }

    }
}
