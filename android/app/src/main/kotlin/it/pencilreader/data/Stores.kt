package it.pencilreader.data

import it.pencilreader.notebook.NotePage
import it.pencilreader.study.StudyPage
import java.io.File

/// Le note del quaderno, una per pagina del libro, in files/Notes/<id del libro>/NNNN.ink.json.
class NoteStore(filesDir: File) :
    PageFileStore<NotePage>(File(filesDir, "Notes"), NotePage.serializer(), { it.isEmpty }) {
    fun deleteNotes(bookID: String) = deleteAll(bookID)
}

/// I segni di studio sopra le pagine (evidenziature, sottolineature, note a margine), tenuti
/// a parte dalle note del quaderno, in files/Annotations/<id del libro>/NNNN.ink.json.
class AnnotationStore(filesDir: File) :
    PageFileStore<StudyPage>(File(filesDir, "Annotations"), StudyPage.serializer(), { it.isEmpty }) {
    fun deleteMarks(bookID: String) = deleteAll(bookID)
}
