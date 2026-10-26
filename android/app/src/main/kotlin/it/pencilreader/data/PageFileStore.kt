package it.pencilreader.data

import it.pencilreader.core.PageNote
import kotlinx.serialization.KSerializer
import java.io.File

/// Un file JSON per pagina di libro, in <root>/<id del libro>/NNNN.ink.json. Una pagina vuota non ha file.
/// Usato per le note del quaderno (files/Notes) e per i segni di studio (files/Annotations), che restano separati.
open class PageFileStore<T>(
    private val root: File,
    private val serializer: KSerializer<T>,
    private val isEmpty: (T) -> Boolean,
) {
    private fun folder(bookID: String) = File(root, bookID)

    fun file(bookID: String, page: Int) = File(root, PageNote(bookID, page).relativePath)

    /// Si può chiamare da qualunque thread.
    fun load(bookID: String, page: Int): T? {
        val json = file(bookID, page).readTextOrNull() ?: return null
        return runCatching { AppJson.decodeFromString(serializer, json) }.getOrNull()
    }

    /// Scrive la pagina, o toglie il file quando non c'è più niente. Restituisce se la pagina ha contenuto.
    fun save(value: T, bookID: String, page: Int): Boolean {
        val file = file(bookID, page)
        if (isEmpty(value)) {
            file.delete()
            return false
        }
        file.writeTextAtomically(AppJson.encodeToString(serializer, value))
        return true
    }

    fun pages(bookID: String): Set<Int> =
        (folder(bookID).list() ?: emptyArray()).mapNotNull { PageNote.pageIndex(it) }.toSet()

    /// Quando si elimina il libro stesso.
    fun deleteAll(bookID: String) {
        folder(bookID).deleteRecursively()
    }
}
