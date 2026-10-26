package it.pencilreader.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import it.pencilreader.core.SavedWord
import kotlinx.serialization.builtins.ListSerializer
import java.io.File

/// Ogni parola cerchiata leggendo, salvata in files/Libreria/parole.json.
class WordList(libraryRoot: File) {
    /// Prima quelle cercate più di recente.
    var words by mutableStateOf(emptyList<SavedWord>())
        private set

    private val file = File(libraryRoot, "parole.json")

    init {
        reload()
    }

    fun reload() {
        val json = file.readTextOrNull() ?: return
        val saved = runCatching { AppJson.decodeFromString(ListSerializer(SavedWord.serializer()), json) }.getOrNull() ?: return
        words = saved.sortedByDescending { it.lastLookedUp }
    }

    fun words(documentID: String) = words.filter { it.documentID == documentID }

    /// Aggiunge la parola, o la aggiorna quando era già stata cercata nello stesso libro.
    fun add(word: SavedWord) {
        val index = words.indexOfFirst { it.key == word.key }
        words = if (index >= 0) {
            val merged = words[index].merge(word)
            listOf(merged) + words.filterIndexed { i, _ -> i != index }
        } else {
            listOf(word) + words
        }
        save()
    }

    fun delete(ids: Set<String>) {
        words = words.filter { it.id !in ids }
        save()
    }

    private fun save() {
        file.writeTextAtomically(AppJson.encodeToString(ListSerializer(SavedWord.serializer()), words))
    }
}
