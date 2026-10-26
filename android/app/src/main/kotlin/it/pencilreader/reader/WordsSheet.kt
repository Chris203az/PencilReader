package it.pencilreader.reader

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Translate
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import it.pencilreader.PencilReaderApp
import it.pencilreader.core.SavedWord
import it.pencilreader.core.TextFolding
import it.pencilreader.core.WordExport
import it.pencilreader.data.LibraryDocument
import it.pencilreader.ui.Sheet
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/// Le parole salvate, di un libro o di tutti, con l'esportazione in un file di testo.
@Composable
fun WordsSheet(
    app: PencilReaderApp,
    currentDocument: LibraryDocument?,
    onDismiss: () -> Unit,
    select: (SavedWord) -> Unit,
) {
    val context = LocalContext.current
    var onlyThisBook by remember { mutableStateOf(true) }
    var filter by remember { mutableStateOf("") }
    var exportMenu by remember { mutableStateOf(false) }

    var shown = app.wordList.words
    if (currentDocument != null && onlyThisBook) shown = shown.filter { it.documentID == currentDocument.id }
    val query = filter.trim()
    if (query.isNotEmpty()) {
        val needle = TextFolding.fold(query)
        shown = shown.filter { TextFolding.fold(it.term).contains(needle) || TextFolding.fold(it.translation).contains(needle) }
    }
    val words = shown
    val saveFile = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/plain")) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val ok = runCatching {
            context.contentResolver.openOutputStream(uri)?.use { it.write(exportText(words).toByteArray(Charsets.UTF_8)) }
        }.isSuccess
        Toast.makeText(context, if (ok) "File salvato" else "Impossibile salvare il file", Toast.LENGTH_SHORT).show()
    }

    Sheet(
        "Parole cercate",
        onDismiss,
        leading = {
            Box {
                IconButton(onClick = { exportMenu = true }, enabled = words.isNotEmpty()) {
                    Icon(Icons.Filled.Share, contentDescription = "Esporta")
                }
                DropdownMenu(expanded = exportMenu, onDismissRequest = { exportMenu = false }) {
                    DropdownMenuItem(
                        text = { Text("Condividi file…") },
                        leadingIcon = { Icon(Icons.Filled.Description, null) },
                        onClick = { exportMenu = false; share(context, words) },
                    )
                    DropdownMenuItem(
                        text = { Text("Salva come file…") },
                        leadingIcon = { Icon(Icons.Filled.Save, null) },
                        onClick = { exportMenu = false; saveFile.launch("Parole cercate.txt") },
                    )
                    DropdownMenuItem(
                        text = { Text("Copia tutto") },
                        leadingIcon = { Icon(Icons.Filled.ContentCopy, null) },
                        onClick = {
                            exportMenu = false
                            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                            clipboard.setPrimaryClip(ClipData.newPlainText("Parole cercate", exportText(words)))
                            Toast.makeText(context, "Copiate", Toast.LENGTH_SHORT).show()
                        },
                    )
                }
            }
        },
    ) {
        Column(Modifier.fillMaxSize()) {
            OutlinedTextField(
                value = filter,
                onValueChange = { filter = it },
                placeholder = { Text("Filtra parole") },
                leadingIcon = { Icon(Icons.Filled.FilterList, null) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            )
            if (currentDocument != null) {
                Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(selected = onlyThisBook, onClick = { onlyThisBook = true }, label = { Text("Questo libro") })
                    FilterChip(selected = !onlyThisBook, onClick = { onlyThisBook = false }, label = { Text("Tutti i libri") })
                }
            }
            if (words.isEmpty()) {
                Column(
                    Modifier.fillMaxSize().padding(32.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Icon(Icons.Filled.Translate, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(if (filter.isEmpty()) "Nessuna parola" else "Nessun risultato", fontWeight = FontWeight.SemiBold)
                    Text(
                        if (filter.isEmpty()) "Le parole che cerchi con la penna compaiono qui."
                        else "Nessuna parola salvata contiene “$filter”.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                LazyColumn(Modifier.fillMaxSize()) {
                    items(words, key = { it.id }) { word ->
                        val available = app.library.document(word.documentID) != null
                        WordRow(
                            word,
                            showsBook = currentDocument == null || !onlyThisBook,
                            enabled = available,
                            onClick = { select(word); onDismiss() },
                            onDelete = { app.wordList.delete(setOf(word.id)) },
                        )
                        HorizontalDivider()
                    }
                }
            }
        }
    }
}

@Composable
private fun WordRow(word: SavedWord, showsBook: Boolean, enabled: Boolean, onClick: () -> Unit, onDelete: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(enabled = enabled, onClick = onClick).padding(start = 16.dp, top = 10.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.Bottom) {
                Text(word.term, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.width(6.dp))
                Text("→ ${word.translation}", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f, fill = false))
                if (word.lookups > 1) {
                    Spacer(Modifier.width(8.dp))
                    Text("×${word.lookups}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            word.sentence?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Text(
                if (showsBook) "${word.documentTitle} · pagina ${word.page + 1}" else "Pagina ${word.page + 1}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.outline,
            )
        }
        IconButton(onClick = onDelete) { Icon(Icons.Filled.Delete, contentDescription = "Elimina") }
    }
}

/// Le parole in Markdown semplice, come le esporta l'iPad.
fun exportText(words: List<SavedWord>): String =
    WordExport.markdown(words, SimpleDateFormat("d MMMM yyyy", Locale.ITALIAN).format(Date()))

/// Il file di testo, condiviso con il foglio di condivisione di Android.
private fun share(context: Context, words: List<SavedWord>) {
    val folder = File(context.cacheDir, "export").also { it.mkdirs() }
    val file = File(folder, "Parole cercate.txt")
    file.writeText(exportText(words), Charsets.UTF_8)
    val uri = FileProvider.getUriForFile(context, context.packageName + ".files", file)
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_STREAM, uri)
        putExtra(Intent.EXTRA_SUBJECT, "Parole cercate (${words.size})")
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(send, "Parole cercate (${words.size})"))
}
