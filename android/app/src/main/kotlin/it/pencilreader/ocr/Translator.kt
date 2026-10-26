package it.pencilreader.ocr

import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.TranslateRemoteModel
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.TranslatorOptions
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/// Traduce dall'inglese all'italiano sul dispositivo con ML Kit. Il modello (circa 30 MB) si
/// scarica una volta sola, alla prima traduzione; dopo funziona senza rete.
class EnglishItalianTranslator {
    private val client = Translation.getClient(
        TranslatorOptions.Builder()
            .setSourceLanguage(TranslateLanguage.ENGLISH)
            .setTargetLanguage(TranslateLanguage.ITALIAN)
            .build(),
    )
    private val download = Mutex()
    @Volatile private var isReady = false

    /// Scarica il modello se manca. `onDownloadStarted` viene chiamato solo se serve davvero aspettare.
    suspend fun prepare(onDownloadStarted: () -> Unit = {}) {
        if (isReady) return
        download.withLock {
            if (isReady) return
            val present = runCatching {
                RemoteModelManager.getInstance().getDownloadedModels(TranslateRemoteModel::class.java).awaitResult()
                    .any { it.language == TranslateLanguage.ITALIAN }
            }.getOrDefault(false)
            if (!present) onDownloadStarted()
            client.downloadModelIfNeeded(DownloadConditions.Builder().build()).awaitResult()
            isReady = true
        }
    }

    suspend fun translate(text: String): String {
        prepare()
        return client.translate(text).awaitResult()
    }

    fun close() = client.close()
}
