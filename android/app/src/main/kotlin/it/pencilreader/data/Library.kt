package it.pencilreader.data

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.net.Uri
import android.provider.OpenableColumns
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import it.pencilreader.core.PageText
import it.pencilreader.core.RawLine
import it.pencilreader.render.PageImages
import it.pencilreader.render.PageThumbnails
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import java.util.UUID

/// Un libro o un insieme di pagine salvato nell'app.
@Serializable
data class LibraryDocument(
    val id: String,
    val title: String,
    val kind: Kind,
    val pageCount: Int,
    val createdAt: Long,
    val lastOpenedAt: Long,
    val lastPage: Int = 0,
    /// Null per i documenti salvati prima delle raccolte: stanno nella prima.
    val collectionID: String? = null,
) {
    @Serializable
    enum class Kind {
        @SerialName("pdf") PDF,
        @SerialName("images") IMAGES,
    }
}

/// Un gruppo di documenti scelto da chi legge ("Università", "Privati", …).
@Serializable
data class DocumentCollection(val id: String, val name: String)

/// I documenti stanno in files/Libreria/<id>/:
///   meta.json, thumbnail.jpg, document.pdf oppure pages/NNNN.jpg, ocr/NNNN.json
/// Le raccolte sono elencate in files/Libreria/collections.json.
/// Lo stato è osservabile da Compose; tutte le modifiche vanno fatte dal thread principale.
class Library(context: Context) {
    var documents by mutableStateOf(emptyList<LibraryDocument>())
        private set
    var collections by mutableStateOf(emptyList<DocumentCollection>())
        private set
    var currentCollectionID by mutableStateOf<String?>(null)
        private set

    val root = File(context.filesDir, "Libreria").also { it.mkdirs() }
    private val resolver = context.contentResolver
    private val cacheRoot = context.cacheDir
    private val prefs: SharedPreferences = context.getSharedPreferences("library", Context.MODE_PRIVATE)
    private val collectionsFile = File(root, "collections.json")

    init {
        reload()
    }

    fun reload() {
        loadCollections()
        documents = (root.listFiles() ?: emptyArray())
            .filter { it.isDirectory }
            .mapNotNull { File(it, "meta.json").readTextOrNull() }
            .mapNotNull { runCatching { AppJson.decodeFromString(LibraryDocument.serializer(), it) }.getOrNull() }
            .sortedByDescending { it.lastOpenedAt }
    }

    // Raccolte

    val currentCollection: DocumentCollection
        get() = collections.firstOrNull { it.id == currentCollectionID } ?: collections[0]

    /// I documenti della raccolta attuale, prima quelli aperti più di recente.
    val visibleDocuments: List<LibraryDocument>
        get() = documents.filter { collectionID(it) == currentCollection.id }

    fun collectionID(document: LibraryDocument): String {
        val id = document.collectionID
        if (id != null && collections.any { it.id == id }) return id
        return collections[0].id
    }

    fun documentCount(collection: DocumentCollection) = documents.count { collectionID(it) == collection.id }

    fun select(collection: DocumentCollection) {
        currentCollectionID = collection.id
        prefs.edit().putString(CURRENT_COLLECTION_KEY, collection.id).apply()
    }

    fun createCollection(name: String) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        val collection = DocumentCollection(UUID.randomUUID().toString().uppercase(Locale.ROOT), trimmed)
        collections = collections + collection
        saveCollections()
        select(collection)
    }

    fun rename(collection: DocumentCollection, name: String) {
        val trimmed = name.trim()
        if (trimmed.isEmpty() || collections.none { it.id == collection.id }) return
        collections = collections.map { if (it.id == collection.id) it.copy(name = trimmed) else it }
        saveCollections()
    }

    /// Toglie la raccolta; i suoi documenti vengono spostati, mai cancellati.
    fun delete(collection: DocumentCollection, movingDocumentsTo: DocumentCollection) {
        val destination = movingDocumentsTo
        if (collection.id == destination.id || collections.size <= 1) return
        for (document in documents.filter { collectionID(it) == collection.id }) {
            update(document.id) { it.copy(collectionID = destination.id) }
        }
        collections = collections.filter { it.id != collection.id }
        saveCollections()
        select(destination)
    }

    fun move(document: LibraryDocument, collection: DocumentCollection) {
        update(document.id) { it.copy(collectionID = collection.id) }
    }

    private fun loadCollections() {
        val saved = collectionsFile.readTextOrNull()?.let {
            runCatching { AppJson.decodeFromString(ListSerializer(DocumentCollection.serializer()), it) }.getOrNull()
        }
        if (!saved.isNullOrEmpty()) {
            collections = saved
        } else if (collections.isEmpty()) {
            collections = listOf(DocumentCollection(UUID.randomUUID().toString().uppercase(Locale.ROOT), "Libreria"))
            saveCollections()
        }
        val stored = prefs.getString(CURRENT_COLLECTION_KEY, null)
        currentCollectionID = if (collections.any { it.id == stored }) stored else collections[0].id
    }

    private fun saveCollections() {
        collectionsFile.writeTextAtomically(
            AppJson.encodeToString(ListSerializer(DocumentCollection.serializer()), collections),
        )
    }

    // Percorsi

    fun folder(document: LibraryDocument) = folder(document.id)
    fun folder(id: String) = File(root, id)
    fun pdfFile(document: LibraryDocument) = File(folder(document), "document.pdf")
    fun thumbnailFile(document: LibraryDocument) = File(folder(document), "thumbnail.jpg")
    fun pagesFolder(document: LibraryDocument) = File(folder(document), "pages")
    fun imageFile(document: LibraryDocument, page: Int) = File(pagesFolder(document), pageName(page, "jpg"))
    fun ocrFile(document: LibraryDocument, page: Int) = File(File(folder(document), "ocr"), pageName(page, "json"))

    // Importazione

    /// Copia un PDF nella libreria. Da chiamare fuori dal thread principale; poi `add`.
    fun importPdf(uri: Uri): LibraryDocument {
        val id = UUID.randomUUID().toString().uppercase(Locale.ROOT)
        val folder = folder(id)
        folder.mkdirs()
        try {
            val destination = File(folder, "document.pdf")
            val input = resolver.openInputStream(uri) ?: throw IllegalStateException("il file non si apre")
            input.use { inp -> FileOutputStream(destination).use { inp.copyTo(it) } }
            val pageCount = PageImages.pdfPageCount(destination)
            if (pageCount <= 0) throw IllegalStateException("il PDF non ha pagine leggibili")
            PageImages.renderPdfPage(destination, 0, 400)?.let { saveJpeg(it, File(folder, "thumbnail.jpg"), 80) }
            val now = System.currentTimeMillis()
            val title = displayName(uri)?.substringBeforeLast('.')?.takeIf { it.isNotBlank() } ?: "Documento"
            val document = LibraryDocument(id, title, LibraryDocument.Kind.PDF, pageCount, now, now, 0, currentCollection.id)
            writeMeta(document)
            return document
        } catch (e: Exception) {
            folder.deleteRecursively()
            throw e
        }
    }

    /// Salva foto o pagine fotografate come JPEG, una pagina per immagine, nell'ordine scelto.
    /// Da chiamare fuori dal thread principale; poi `add`.
    fun importImages(uris: List<Uri>, title: String): LibraryDocument {
        val id = UUID.randomUUID().toString().uppercase(Locale.ROOT)
        val folder = folder(id)
        val pages = File(folder, "pages")
        pages.mkdirs()
        try {
            var count = 0
            for (uri in uris) {
                val bitmap = PageImages.decodeUpright(resolver, uri, PageImages.MAX_DIMENSION) ?: continue
                saveJpeg(bitmap, File(pages, pageName(count, "jpg")), 90)
                if (count == 0) saveJpeg(PageImages.scaled(bitmap, 400), File(folder, "thumbnail.jpg"), 80)
                bitmap.recycle()
                count += 1
            }
            if (count == 0) throw IllegalStateException("nessuna immagine leggibile")
            val now = System.currentTimeMillis()
            val document = LibraryDocument(id, title, LibraryDocument.Kind.IMAGES, count, now, now, 0, currentCollection.id)
            writeMeta(document)
            return document
        } catch (e: Exception) {
            folder.deleteRecursively()
            throw e
        }
    }

    /// Aggiunge alla lista un documento appena importato.
    fun add(document: LibraryDocument) {
        documents = listOf(document) + documents.filter { it.id != document.id }
    }

    private fun displayName(uri: Uri): String? = try {
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    } catch (_: Exception) {
        null
    }

    // Modifiche

    fun markOpened(document: LibraryDocument) = update(document.id) { it.copy(lastOpenedAt = System.currentTimeMillis()) }

    fun setLastPage(page: Int, document: LibraryDocument) = update(document.id) { it.copy(lastPage = page) }

    fun rename(document: LibraryDocument, title: String) {
        val trimmed = title.trim()
        if (trimmed.isEmpty()) return
        update(document.id) { it.copy(title = trimmed) }
    }

    fun delete(document: LibraryDocument, notes: NoteStore, marks: AnnotationStore) {
        folder(document).deleteRecursively()
        notes.deleteNotes(document.id)
        marks.deleteMarks(document.id)
        PageThumbnails.deleteCache(cacheRoot, document.id)
        documents = documents.filter { it.id != document.id }
    }

    fun document(id: String): LibraryDocument? = documents.firstOrNull { it.id == id }

    private fun update(id: String, change: (LibraryDocument) -> LibraryDocument) {
        val existing = document(id) ?: return
        val changed = change(existing)
        runCatching { writeMeta(changed) }
        documents = documents.map { if (it.id == id) changed else it }.sortedByDescending { it.lastOpenedAt }
    }

    private fun writeMeta(document: LibraryDocument) {
        File(folder(document), "meta.json").writeTextAtomically(AppJson.encodeToString(LibraryDocument.serializer(), document))
    }

    // Testo riconosciuto

    fun savedText(document: LibraryDocument, page: Int): PageText? = loadText(ocrFile(document, page))

    fun hasSavedText(document: LibraryDocument, page: Int) = ocrFile(document, page).isFile

    /// Si può chiamare da qualunque thread.
    fun saveText(text: PageText, document: LibraryDocument, page: Int) {
        // Un risultato in ritardo non deve ricreare la cartella di un documento eliminato.
        if (!folder(document).isDirectory) return
        ocrFile(document, page).writeTextAtomically(AppJson.encodeToString(ListSerializer(RawLine.serializer()), text.rawLines))
    }

    fun recognizedPageCount(document: LibraryDocument): Int =
        File(folder(document), "ocr").list()?.count { it.endsWith(".json") } ?: 0

    companion object {
        private const val CURRENT_COLLECTION_KEY = "currentCollectionID"

        fun pageName(page: Int, extension: String) = String.format(Locale.ROOT, "%04d.%s", page, extension)

        /// Si può chiamare da qualunque thread.
        fun loadText(file: File): PageText? {
            val json = file.readTextOrNull() ?: return null
            val lines = runCatching { AppJson.decodeFromString(ListSerializer(RawLine.serializer()), json) }.getOrNull() ?: return null
            return PageText(lines)
        }

        fun saveJpeg(bitmap: Bitmap, file: File, quality: Int) {
            file.parentFile?.mkdirs()
            FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.JPEG, quality, it) }
        }
    }
}
