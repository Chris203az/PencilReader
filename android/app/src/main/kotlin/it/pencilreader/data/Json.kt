package it.pencilreader.data

import kotlinx.serialization.json.Json
import java.io.File

/// Il formato di tutti i file JSON dell'app: tollerante ai campi nuovi o mancanti,
/// così i file scritti da una versione restano leggibili dalle altre.
val AppJson = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
    explicitNulls = false
}

/// Scrive in un file accanto e poi lo rinomina, così un'interruzione non lascia mai un file a metà.
fun File.writeAtomically(bytes: ByteArray) {
    parentFile?.mkdirs()
    val temp = File(parentFile, "$name.tmp")
    temp.writeBytes(bytes)
    if (!temp.renameTo(this)) {
        delete()
        temp.renameTo(this)
    }
}

fun File.writeTextAtomically(text: String) = writeAtomically(text.toByteArray(Charsets.UTF_8))

fun File.readTextOrNull(): String? = try {
    if (isFile) readText(Charsets.UTF_8) else null
} catch (_: Exception) {
    null
}
