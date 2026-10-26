package it.pencilreader.library

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DocumentScanner
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.PictureAsPdf
import androidx.compose.material.icons.filled.StopCircle
import androidx.compose.material.icons.filled.Translate
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import it.pencilreader.PencilReaderApp
import it.pencilreader.data.DocumentCollection
import it.pencilreader.data.LibraryDocument
import it.pencilreader.reader.WordsSheet
import it.pencilreader.ui.ConfirmDialog
import it.pencilreader.ui.MessageDialog
import it.pencilreader.ui.TextFieldDialog
import it.pencilreader.ui.rememberBitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private sealed interface CollectionEdit {
    data object Create : CollectionEdit
    data class Rename(val collection: DocumentCollection) : CollectionEdit
}

/// La schermata iniziale: i documenti della raccolta attuale, prima quelli aperti più di recente.
/// Toccando il titolo si cambia raccolta.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(app: PencilReaderApp, open: (LibraryDocument) -> Unit) {
    val library = app.library
    val recognizer = app.recognizer
    val scope = rememberCoroutineScope()
    var isImporting by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf<LibraryDocument?>(null) }
    var deleting by remember { mutableStateOf<LibraryDocument?>(null) }
    var alertMessage by remember { mutableStateOf<String?>(null) }
    var collectionEdit by remember { mutableStateOf<CollectionEdit?>(null) }
    var deletingCollection by remember { mutableStateOf<DocumentCollection?>(null) }
    var showWords by remember { mutableStateOf(false) }
    var showCollections by remember { mutableStateOf(false) }
    var showAdd by remember { mutableStateOf(false) }

    // Riprende le cartelle rimesse a posto da un backup.
    LaunchedEffect(Unit) { library.reload() }

    fun importImages(uris: List<Uri>) {
        if (uris.isEmpty()) return
        isImporting = true
        scope.launch {
            try {
                val title = if (uris.size == 1) "Foto" else "${uris.size} foto"
                val document = withContext(Dispatchers.IO) { library.importImages(uris, title) }
                library.add(document)
                open(document)
            } catch (e: Exception) {
                alertMessage = "Impossibile salvare le pagine: ${e.localizedMessage ?: e.javaClass.simpleName}"
            } finally {
                isImporting = false
            }
        }
    }

    fun importPdf(uri: Uri?) {
        if (uri == null) return
        isImporting = true
        scope.launch {
            try {
                val document = withContext(Dispatchers.IO) { library.importPdf(uri) }
                library.add(document)
                open(document)
            } catch (e: Exception) {
                alertMessage = "Impossibile importare il PDF: ${e.localizedMessage ?: e.javaClass.simpleName}"
            } finally {
                isImporting = false
            }
        }
    }

    // Storage Access Framework: si sceglie da qualunque fornitore di documenti (file, Drive, foto...).
    val pickImages = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { importImages(it) }
    val pickPdf = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { importPdf(it) }

    val openButtons: @Composable (Boolean) -> Unit = { inMenu ->
        if (inMenu) {
            DropdownMenuItem(
                text = { Text("Scegli foto") },
                leadingIcon = { Icon(Icons.Filled.Image, null) },
                onClick = { showAdd = false; pickImages.launch(arrayOf("image/*")) },
            )
            DropdownMenuItem(
                text = { Text("Importa PDF") },
                leadingIcon = { Icon(Icons.Filled.PictureAsPdf, null) },
                onClick = { showAdd = false; pickPdf.launch(arrayOf("application/pdf")) },
            )
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(onClick = { pickImages.launch(arrayOf("image/*")) }) {
                    Icon(Icons.Filled.Image, null)
                    Spacer(Modifier.width(8.dp))
                    Text("Scegli foto")
                }
                OutlinedButton(onClick = { pickPdf.launch(arrayOf("application/pdf")) }) {
                    Icon(Icons.Filled.PictureAsPdf, null)
                    Spacer(Modifier.width(8.dp))
                    Text("Importa PDF")
                }
            }
        }
    }

    val current = library.currentCollection
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Box {
                        TextButton(onClick = { showCollections = true }) {
                            Text(current.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                            Icon(Icons.Filled.ArrowDropDown, contentDescription = "Cambia libreria")
                        }
                        DropdownMenu(expanded = showCollections, onDismissRequest = { showCollections = false }) {
                            for (collection in library.collections) {
                                DropdownMenuItem(
                                    text = { Text("${collection.name} (${library.documentCount(collection)})") },
                                    leadingIcon = {
                                        if (collection.id == current.id) Icon(Icons.Filled.Check, null) else Spacer(Modifier.size(24.dp))
                                    },
                                    onClick = { showCollections = false; library.select(collection) },
                                )
                            }
                            HorizontalDivider()
                            DropdownMenuItem(
                                text = { Text("Nuova libreria…") },
                                leadingIcon = { Icon(Icons.Filled.Add, null) },
                                onClick = { showCollections = false; collectionEdit = CollectionEdit.Create },
                            )
                            DropdownMenuItem(
                                text = { Text("Rinomina “${current.name}”…") },
                                leadingIcon = { Icon(Icons.Filled.Edit, null) },
                                onClick = { showCollections = false; collectionEdit = CollectionEdit.Rename(current) },
                            )
                            if (library.collections.size > 1) {
                                DropdownMenuItem(
                                    text = { Text("Elimina “${current.name}”…", color = MaterialTheme.colorScheme.error) },
                                    leadingIcon = { Icon(Icons.Filled.Delete, null, tint = MaterialTheme.colorScheme.error) },
                                    onClick = { showCollections = false; deletingCollection = current },
                                )
                            }
                        }
                    }
                },
                actions = {
                    IconButton(onClick = { showWords = true }) { Icon(Icons.Filled.Translate, contentDescription = "Parole cercate") }
                    Box {
                        IconButton(onClick = { showAdd = true }) { Icon(Icons.Filled.Add, contentDescription = "Aggiungi") }
                        DropdownMenu(expanded = showAdd, onDismissRequest = { showAdd = false }) { openButtons(true) }
                    }
                },
            )
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            val visible = library.visibleDocuments
            if (visible.isEmpty()) {
                Column(
                    Modifier.fillMaxSize().padding(32.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Icon(Icons.Filled.MenuBook, null, Modifier.size(56.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(12.dp))
                    Text("“${current.name}” è vuota", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Scegli delle foto o importa un PDF. Poi cerchia una parola con la penna.",
                        textAlign = TextAlign.Center,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(16.dp))
                    openButtons(false)
                }
            } else {
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(160.dp),
                    contentPadding = PaddingValues(24.dp),
                    horizontalArrangement = Arrangement.spacedBy(24.dp),
                    verticalArrangement = Arrangement.spacedBy(28.dp),
                ) {
                    items(visible, key = { it.id }) { document ->
                        DocumentCard(
                            app = app,
                            document = document,
                            recognition = recognitionStatus(app, document),
                            onOpen = { open(document) },
                            onRename = { renaming = document },
                            onDelete = { deleting = document },
                        )
                    }
                }
            }
            if (isImporting) {
                Surface(
                    shape = RoundedCornerShape(14.dp),
                    tonalElevation = 6.dp,
                    shadowElevation = 6.dp,
                    modifier = Modifier.align(Alignment.Center),
                ) {
                    Column(Modifier.padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        CircularProgressIndicator()
                        Spacer(Modifier.height(10.dp))
                        Text("Importazione…")
                    }
                }
            }
        }
    }

    if (showWords) {
        WordsSheet(app, currentDocument = null, onDismiss = { showWords = false }) { word ->
            // Apre il libro alla pagina della parola.
            val document = library.document(word.documentID) ?: return@WordsSheet
            library.setLastPage(word.page, document)
            showWords = false
            open(document)
        }
    }
    renaming?.let { document ->
        TextFieldDialog("Rinomina", "Titolo", document.title, "Salva", onDismiss = { renaming = null }) {
            library.rename(document, it)
        }
    }
    deleting?.let { document ->
        ConfirmDialog(
            "Eliminare “${document.title}”?",
            "Il documento e il testo riconosciuto verranno rimossi dall'app.",
            listOf("Elimina" to {
                recognizer.stop(document)
                library.delete(document, app.notes, app.annotations)
            }),
            onDismiss = { deleting = null },
        )
    }
    collectionEdit?.let { edit ->
        when (edit) {
            CollectionEdit.Create -> TextFieldDialog("Nuova libreria", "Nome", "", "Crea", onDismiss = { collectionEdit = null }) {
                library.createCollection(it)
            }
            is CollectionEdit.Rename -> TextFieldDialog(
                "Rinomina libreria", "Nome", edit.collection.name, "Salva", onDismiss = { collectionEdit = null },
            ) { library.rename(edit.collection, it) }
        }
    }
    deletingCollection?.let { doomed ->
        val empty = library.documentCount(doomed) == 0
        ConfirmDialog(
            "Eliminare la libreria “${doomed.name}”?",
            "I libri non vengono cancellati.",
            library.collections.filter { it.id != doomed.id }.map { destination ->
                (if (empty) "Elimina" else "Sposta i libri in “${destination.name}” ed elimina") to {
                    library.delete(doomed, movingDocumentsTo = destination)
                }
            }.let { if (empty) it.take(1) else it },
            onDismiss = { deletingCollection = null },
        )
    }
    alertMessage?.let { MessageDialog("Errore", it) { alertMessage = null } }
}

private fun recognitionStatus(app: PencilReaderApp, document: LibraryDocument): String? {
    app.recognizer.progress(document)?.let { return "Riconoscimento ${it.done}/${it.total}" }
    return if (app.recognizer.isQueued(document)) "In coda per il riconoscimento" else null
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DocumentCard(
    app: PencilReaderApp,
    document: LibraryDocument,
    recognition: String?,
    onOpen: () -> Unit,
    onRename: () -> Unit,
    onDelete: () -> Unit,
) {
    val library = app.library
    val recognizer = app.recognizer
    var menu by remember { mutableStateOf(false) }
    var moveMenu by remember { mutableStateOf(false) }
    val thumbnail by rememberBitmap(library.thumbnailFile(document), document.id)
    Box {
        Column(
            Modifier
                .fillMaxWidth()
                .combinedClickable(onClick = onOpen, onLongClick = { menu = true }),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(210.dp)
                    .shadow(3.dp, RoundedCornerShape(6.dp))
                    .clip(RoundedCornerShape(6.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant),
                contentAlignment = Alignment.Center,
            ) {
                thumbnail?.let {
                    Image(it.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
                }
            }
            Text(document.title, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(
                "Pagina ${document.lastPage + 1} di ${document.pageCount}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            LinearProgressIndicator(
                progress = { (document.lastPage + 1).toFloat() / maxOf(document.pageCount, 1) },
                modifier = Modifier.fillMaxWidth(),
            )
            recognition?.let {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.DocumentScanner, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.width(4.dp))
                    Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(text = { Text("Rinomina") }, leadingIcon = { Icon(Icons.Filled.Edit, null) }, onClick = {
                menu = false
                onRename()
            })
            if (recognizer.isActive(document)) {
                DropdownMenuItem(
                    text = { Text("Interrompi riconoscimento") },
                    leadingIcon = { Icon(Icons.Filled.StopCircle, null) },
                    onClick = { menu = false; recognizer.stop(document) },
                )
            } else {
                val done = library.recognizedPageCount(document)
                if (done < document.pageCount) {
                    DropdownMenuItem(
                        text = { Text("Riconosci tutto il testo ($done/${document.pageCount})") },
                        leadingIcon = { Icon(Icons.Filled.DocumentScanner, null) },
                        onClick = { menu = false; recognizer.start(document) },
                    )
                }
            }
            if (library.collections.size > 1) {
                DropdownMenuItem(
                    text = { Text("Sposta in") },
                    leadingIcon = { Icon(Icons.Filled.Folder, null) },
                    onClick = { menu = false; moveMenu = true },
                )
            }
            DropdownMenuItem(
                text = { Text("Elimina", color = MaterialTheme.colorScheme.error) },
                leadingIcon = { Icon(Icons.Filled.Delete, null, tint = MaterialTheme.colorScheme.error) },
                onClick = { menu = false; onDelete() },
            )
        }
        DropdownMenu(expanded = moveMenu, onDismissRequest = { moveMenu = false }) {
            for (collection in library.collections.filter { it.id != library.collectionID(document) }) {
                DropdownMenuItem(text = { Text(collection.name) }, onClick = {
                    moveMenu = false
                    library.move(document, collection)
                })
            }
        }
    }
}
