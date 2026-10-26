package it.pencilreader

import android.app.Application
import it.pencilreader.data.AnnotationStore
import it.pencilreader.data.Library
import it.pencilreader.data.NoteStore
import it.pencilreader.data.Settings
import it.pencilreader.data.WordList
import it.pencilreader.ocr.BookRecognizer
import it.pencilreader.ocr.EnglishItalianTranslator
import it.pencilreader.ocr.OcrService
import kotlinx.coroutines.MainScope

/// Gli oggetti condivisi da tutta l'app, creati una volta sola.
class PencilReaderApp : Application() {
    val scope = MainScope()
    lateinit var library: Library
        private set
    lateinit var wordList: WordList
        private set
    lateinit var settings: Settings
        private set
    lateinit var notes: NoteStore
        private set
    lateinit var annotations: AnnotationStore
        private set
    lateinit var recognizer: BookRecognizer
        private set
    val ocr: OcrService by lazy { OcrService() }
    val translator: EnglishItalianTranslator by lazy { EnglishItalianTranslator() }

    override fun onCreate() {
        super.onCreate()
        library = Library(this)
        wordList = WordList(library.root)
        settings = Settings(this)
        notes = NoteStore(filesDir)
        annotations = AnnotationStore(filesDir)
        recognizer = BookRecognizer(library, scope, ocr)
    }
}
