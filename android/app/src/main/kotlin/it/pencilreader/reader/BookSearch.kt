package it.pencilreader.reader

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import it.pencilreader.core.PageText
import it.pencilreader.core.SearchMatch
import it.pencilreader.core.search
import it.pencilreader.data.Library
import it.pencilreader.data.LibraryDocument
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/// Ricerca in tutto il testo riconosciuto di un libro. Le pagine si leggono dal disco una volta e
/// restano finché il libro è aperto; quelle riconosciute dopo si aggiungono alla ricerca successiva.
class BookSearch(private val document: LibraryDocument, private val library: Library, private val scope: CoroutineScope) {
    data class PageResult(val page: Int, val matches: List<SearchMatch>)

    var query by mutableStateOf("")
        private set
    var results by mutableStateOf(emptyList<PageResult>())
        private set
    var isSearching by mutableStateOf(false)
        private set
    /// Le pagine senza OCR: lì non si può cercare.
    var missingPages by mutableStateOf(document.pageCount - library.recognizedPageCount(document))
        private set

    private val pages = mutableMapOf<Int, PageText>()
    private var job: Job? = null

    fun updateQuery(value: String) {
        if (value == query) return
        query = value
        search()
    }

    fun search() {
        job?.cancel()
        val needle = query
        if (needle.isBlank()) {
            results = emptyList()
            isSearching = false
            return
        }
        isSearching = true
        job = scope.launch {
            // Aspetta una pausa nella scrittura.
            delay(250)
            loadNewPages()
            val snapshot = pages.toMap()
            val found = withContext(Dispatchers.Default) {
                snapshot.keys.sorted().mapNotNull { page ->
                    val matches = snapshot.getValue(page).search(needle)
                    if (matches.isEmpty()) null else PageResult(page, matches)
                }
            }
            results = found
            isSearching = false
        }
    }

    private suspend fun loadNewPages() {
        val toLoad = (0 until document.pageCount).filter { it !in pages && library.hasSavedText(document, it) }
        if (toLoad.isNotEmpty()) {
            val loaded = withContext(Dispatchers.IO) {
                toLoad.mapNotNull { page -> Library.loadText(library.ocrFile(document, page))?.let { page to it } }
            }
            for ((page, text) in loaded) pages[page] = text
        }
        missingPages = document.pageCount - pages.size
    }
}
