package it.pencilreader.ocr

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import it.pencilreader.core.PageText
import it.pencilreader.data.Library
import it.pencilreader.data.LibraryDocument
import it.pencilreader.render.PageSource
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.coroutines.coroutineContext

/// Riconosce in sottofondo tutte le pagine di un libro, un libro alla volta, così cerchiare una
/// parola non deve mai aspettare l'OCR. Le pagine già riconosciute si saltano: fermare e ripartire
/// riprende da dove si era arrivati. Tutto lo stato si legge e si cambia dal thread principale.
class BookRecognizer(private val library: Library, private val scope: CoroutineScope, private val ocr: OcrService) {
    data class Progress(val documentID: String, val done: Int, val total: Int)

    var current by mutableStateOf<Progress?>(null)
        private set
    var queue by mutableStateOf(emptyList<String>())
        private set
    /// Mentre lavora lo schermo resta acceso, perché altrimenti il sistema sospende l'app a metà libro.
    val isRunning: Boolean get() = runner != null && (current != null || queue.isNotEmpty())

    private var runner by mutableStateOf<Job?>(null)
    private var job: Job? = null

    fun progress(document: LibraryDocument): Progress? = current?.takeIf { it.documentID == document.id }

    fun isQueued(document: LibraryDocument) = document.id in queue

    fun isActive(document: LibraryDocument) = progress(document) != null || isQueued(document)

    fun start(document: LibraryDocument) {
        if (isActive(document)) return
        queue = queue + document.id
        if (runner == null) runner = scope.launch { run() }
    }

    fun stop(document: LibraryDocument) {
        queue = queue.filter { it != document.id }
        if (current?.documentID == document.id) job?.cancel()
    }

    private suspend fun run() {
        while (queue.isNotEmpty()) {
            val id = queue.first()
            queue = queue.drop(1)
            val document = library.document(id) ?: continue
            val job = scope.launch { recognize(document) }
            this.job = job
            job.join()
            this.job = null
            current = null
        }
        runner = null
    }

    private suspend fun recognize(document: LibraryDocument) {
        val pending = (0 until document.pageCount).filter { !library.hasSavedText(document, it) }
        current = Progress(document.id, document.pageCount - pending.size, document.pageCount)
        val source = PageSource(
            if (document.kind == LibraryDocument.Kind.PDF) library.pdfFile(document) else null,
            if (document.kind == LibraryDocument.Kind.IMAGES) library.pagesFolder(document) else null,
        )
        try {
            for (page in pending) {
                coroutineContext.ensureActive()
                // Il lettore potrebbe averla riconosciuta nel frattempo.
                if (!library.hasSavedText(document, page)) {
                    // Un secondo tentativo, poi la pagina resta per la prossima volta.
                    for (attempt in 1..2) {
                        try {
                            val text = withContext(Dispatchers.Default) {
                                val bitmap = source.render(page) ?: return@withContext PageText(emptyList())
                                try {
                                    ocr.recognize(bitmap)
                                } finally {
                                    bitmap.recycle()
                                }
                            }
                            // Sparito se il libro è stato eliminato nel frattempo.
                            if (library.document(document.id) == null) return
                            if (!library.hasSavedText(document, page)) {
                                withContext(Dispatchers.IO) { library.saveText(text, document, page) }
                            }
                            break
                        } catch (e: CancellationException) {
                            throw e
                        } catch (_: Exception) {
                        }
                    }
                }
                current = current?.let { it.copy(done = it.done + 1) }
            }
        } finally {
            source.close()
        }
    }
}
