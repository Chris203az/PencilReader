package it.pencilreader.render

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlinx.coroutines.yield
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import kotlin.coroutines.coroutineContext

/// Le miniature delle pagine, preparate fuori dal thread principale. Restano in memoria
/// finché il libro è aperto e su disco in cache/Thumbnails/<id del libro>/, così la griglia
/// si apre subito dalla seconda volta.
class PageThumbnails(cacheRoot: File, bookID: String, private val pageCount: Int, pdf: File?, pagesFolder: File?) {
    private val source = PageSource(pdf, pagesFolder)
    private val diskFolder = cacheFolder(cacheRoot, bookID).also { it.mkdirs() }
    private val memory = object : LruCache<Int, Bitmap>(40 * 1024 * 1024) {
        override fun sizeOf(key: Int, value: Bitmap) = value.byteCount
    }

    fun cached(index: Int): Bitmap? = memory.get(index)

    suspend fun thumbnail(index: Int): Bitmap? {
        memory.get(index)?.let { return it }
        return withContext(Dispatchers.IO) {
            // Le celle passate prima del loro turno non vanno disegnate.
            coroutineContext.ensureActive()
            val image = fromDisk(index) ?: renderAndSave(index)
            if (image != null) memory.put(index, image)
            image
        }
    }

    /// Salva su disco, con calma, le pagine che non ci sono ancora: prima quelle dopo `page`,
    /// poi quelle prima. Si ferma appena la coroutine viene annullata.
    suspend fun prefetch(page: Int) = withContext(Dispatchers.IO) {
        val start = page.coerceIn(0, pageCount)
        for (index in (start until pageCount) + (0 until start).reversed()) {
            coroutineContext.ensureActive()
            if (!diskFile(index).isFile) renderAndSave(index)
            // Lascia passare prima le celle della griglia.
            yield()
        }
    }

    fun close() = source.close()

    private fun diskFile(index: Int) = File(diskFolder, String.format(Locale.ROOT, "%04d.jpg", index))

    private fun fromDisk(index: Int): Bitmap? {
        val file = diskFile(index)
        if (!file.isFile) return null
        return BitmapFactory.decodeFile(file.path)?.also { it.prepareToDraw() }
    }

    private fun renderAndSave(index: Int): Bitmap? {
        val image = source.render(index, MAX_PIXELS) ?: return null
        try {
            val file = diskFile(index)
            val temp = File(diskFolder, file.name + ".tmp")
            FileOutputStream(temp).use { image.compress(Bitmap.CompressFormat.JPEG, 70, it) }
            temp.renameTo(file)
        } catch (_: Exception) {
        }
        return image
    }

    companion object {
        /// Il lato lungo di una miniatura, l'altezza della cella a 2x.
        const val MAX_PIXELS = 380

        fun cacheFolder(cacheRoot: File, bookID: String) = File(File(cacheRoot, "Thumbnails"), bookID)

        fun deleteCache(cacheRoot: File, bookID: String) {
            cacheFolder(cacheRoot, bookID).deleteRecursively()
        }
    }
}
