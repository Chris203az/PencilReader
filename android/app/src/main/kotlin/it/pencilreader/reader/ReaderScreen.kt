package it.pencilreader.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Notes
import androidx.compose.material.icons.filled.BorderColor
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.DocumentScanner
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.ModeEdit
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.StopCircle
import androidx.compose.material.icons.filled.Translate
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import it.pencilreader.PencilReaderApp
import it.pencilreader.core.NotebookToolbarLayout
import it.pencilreader.data.LibraryDocument
import it.pencilreader.notebook.DIVIDER_WIDTH
import it.pencilreader.notebook.NotebookDivider
import it.pencilreader.notebook.NotebookModel
import it.pencilreader.notebook.NotebookPane
import it.pencilreader.render.PageThumbnails
import it.pencilreader.study.StudyColor
import it.pencilreader.study.StudyGuideSheet
import it.pencilreader.study.StudyModel
import it.pencilreader.ui.MessageDialog
import it.pencilreader.ui.NoteOrange
import kotlinx.coroutines.delay

/// Un documento aperto: la pagina, il lazo della penna, la scheda della traduzione, il quaderno accanto.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReaderScreen(app: PencilReaderApp, document: LibraryDocument, close: () -> Unit, openOther: (String) -> Unit) {
    val scope = rememberCoroutineScope()
    val library = app.library
    val recognizer = app.recognizer
    // Creati una volta per libro: il modello comincia l'OCR appena esiste.
    val model = remember(document.id) { ReaderModel(app, document, app.scope) }
    val notebook = remember(document.id) { NotebookModel(document.id, model.pageIndex, app.notes, app.settings, app.scope) }
    val study = remember(document.id) { StudyModel(document.id, app.annotations, app.settings, app.scope) }
    val thumbnails = remember(document.id) {
        PageThumbnails(
            app.cacheDir, document.id, document.pageCount,
            if (document.kind == LibraryDocument.Kind.PDF) library.pdfFile(document) else null,
            if (document.kind == LibraryDocument.Kind.IMAGES) library.pagesFolder(document) else null,
        )
    }
    var search by remember(document.id) { mutableStateOf<BookSearch?>(null) }
    var showNotebook by remember { mutableStateOf(false) }
    var showPages by remember { mutableStateOf(false) }
    var showSearch by remember { mutableStateOf(false) }
    var showWords by remember { mutableStateOf(false) }
    var showNotes by remember { mutableStateOf(false) }
    var moreMenu by remember { mutableStateOf(false) }

    DisposableEffect(document.id) {
        onDispose {
            notebook.flush()
            study.flush()
            model.close()
            thumbnails.close()
        }
    }
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) {
        notebook.flush()
        study.flush()
    }
    LaunchedEffect(model.pageIndex) {
        notebook.show(model.pageIndex)
        study.show(model.pageIndex)
    }
    // Riempie la cache delle miniature mentre il libro è aperto; si ferma quando si chiude.
    LaunchedEffect(document.id) {
        delay(3000)
        thumbnails.prefetch(model.pageIndex)
    }

    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceContainerLow)) {
        TopAppBar(
            navigationIcon = {
                TextButton(onClick = close) {
                    Icon(Icons.Filled.ChevronLeft, null)
                    Text(library.currentCollection.name, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            },
            title = { Text(model.title, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleMedium) },
            actions = {
                IconButton(onClick = model::previousPage, enabled = model.pageIndex > 0) {
                    Icon(Icons.Filled.ChevronLeft, contentDescription = "Pagina precedente")
                }
                TextButton(onClick = { showPages = true }) {
                    Text("${model.pageIndex + 1} / ${model.pageCount}")
                    if (model.pageIndex in notebook.notedPages) {
                        Spacer(Modifier.width(4.dp))
                        Icon(Icons.Filled.ModeEdit, null, Modifier.size(14.dp), tint = NoteOrange)
                    }
                    if (model.pageIndex in study.markedPages) {
                        Spacer(Modifier.width(4.dp))
                        Icon(Icons.Filled.BorderColor, null, Modifier.size(14.dp), tint = Color(StudyColor.KEY.argb))
                    }
                }
                IconButton(onClick = model::nextPage, enabled = model.pageIndex + 1 < model.pageCount) {
                    Icon(Icons.Filled.ChevronRight, contentDescription = "Pagina successiva")
                }
                Spacer(Modifier.width(8.dp))
                // Modalità studio: mentre è attiva la penna segna la pagina invece di tradurre.
                val toggleStudy = {
                    model.clearSelection()
                    study.toggle()
                }
                if (study.isActive) {
                    Button(onClick = toggleStudy, colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFF9500))) {
                        Icon(Icons.Filled.BorderColor, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Esci dallo studio")
                    }
                } else {
                    IconButton(onClick = toggleStudy) { Icon(Icons.Filled.BorderColor, contentDescription = "Modalità studio") }
                }
                RecognitionButton(app, document)
                IconButton(onClick = {
                    // Così la pagina su cui si sta scrivendo compare aggiornata nell'elenco.
                    notebook.flush()
                    showNotes = true
                }) { Icon(Icons.AutoMirrored.Filled.Notes, contentDescription = "Note del libro") }
                IconButton(onClick = {
                    if (search == null) search = BookSearch(document, library, scope)
                    showSearch = true
                }) { Icon(Icons.Filled.Search, contentDescription = "Cerca nel libro") }
                IconButton(onClick = { showWords = true }) { Icon(Icons.Filled.Translate, contentDescription = "Parole cercate") }
                Box {
                    IconButton(onClick = { moreMenu = true }) { Icon(Icons.Filled.MoreVert, contentDescription = "Altro") }
                    DropdownMenu(expanded = moreMenu, onDismissRequest = { moreMenu = false }) {
                        DropdownMenuItem(
                            text = { Text("Riquadri OCR") },
                            leadingIcon = { if (model.showWordBoxes) Icon(Icons.Filled.Check, null) else Spacer(Modifier.size(24.dp)) },
                            onClick = { model.showWordBoxes = !model.showWordBoxes; moreMenu = false },
                        )
                        DropdownMenuItem(
                            text = { Text("Disegna col dito") },
                            leadingIcon = { if (model.allowsFingerDrawing) Icon(Icons.Filled.Check, null) else Spacer(Modifier.size(24.dp)) },
                            onClick = { model.allowsFingerDrawing = !model.allowsFingerDrawing; moreMenu = false },
                        )
                    }
                }
            },
        )
        BoxWithConstraints(Modifier.weight(1f)) {
            val density = LocalDensity.current
            val total = with(density) { maxWidth.toPx() }
            val dividerPx = with(density) { DIVIDER_WIDTH.toPx() }
            val available = total - dividerPx
            Row(Modifier.fillMaxSize()) {
                val pageModifier = if (showNotebook) {
                    Modifier.width(with(density) { (available * app.settings.split.toFloat()).toDp() }).fillMaxHeight()
                } else {
                    Modifier.fillMaxSize()
                }
                PageView(model, study, onExit = close, modifier = pageModifier)
                if (showNotebook) {
                    NotebookDivider(app.settings.split, available) { app.settings.updateSplit(it) }
                    NotebookPane(notebook, Modifier.weight(1f))
                }
            }
            // Apre e chiude il quaderno accanto alla pagina; sopra la barra del quaderno quando sta in basso.
            val raised = showNotebook && app.settings.toolbarLayout.position == NotebookToolbarLayout.Position.BOTTOM
            FloatingActionButton(
                onClick = {
                    // Aprire il quaderno su una pagina è chiederne la nota.
                    if (!showNotebook) notebook.startNote() else notebook.flush()
                    showNotebook = !showNotebook
                },
                shape = CircleShape,
                modifier = Modifier.align(Alignment.BottomEnd).padding(end = 20.dp, bottom = if (raised) 64.dp else 20.dp),
            ) {
                Icon(Icons.Filled.EditNote, contentDescription = if (showNotebook) "Chiudi quaderno" else "Apri quaderno")
            }
        }
    }

    if (showPages) {
        PageGridSheet(model.pageCount, model.pageIndex, thumbnails, notebook.notedPages, study.markedPages, onDismiss = { showPages = false }) {
            model.showPage(it)
        }
    }
    if (showNotes) {
        NotesListSheet(notebook, notebook.notedPages.sorted(), onDismiss = { showNotes = false }) { page ->
            model.showPage(page)
            showNotebook = true
        }
    }
    if (study.showsGuide) StudyGuideSheet(onDismiss = { study.showsGuide = false })
    val currentSearch = search
    if (showSearch && currentSearch != null) {
        SearchSheet(app, document, currentSearch, onDismiss = { showSearch = false }) { page, ids -> model.showMatch(page, ids) }
    }
    if (showWords) {
        WordsSheet(app, currentDocument = document, onDismiss = { showWords = false }) { word ->
            if (word.documentID == document.id) {
                model.showPage(word.page)
            } else {
                // Apre l'altro libro alla pagina della parola.
                val other = library.document(word.documentID) ?: return@WordsSheet
                library.setLastPage(word.page, other)
                openOther(other.id)
            }
        }
    }
    model.alertMessage?.let { MessageDialog("Errore", it) { model.alertMessage = null } }
}

/// Riconosce tutto il libro in sottofondo; mostra l'avanzamento mentre lavora.
@Composable
private fun RecognitionButton(app: PencilReaderApp, document: LibraryDocument) {
    val recognizer = app.recognizer
    val progress = recognizer.progress(document)
    when {
        progress != null -> TextButton(onClick = { recognizer.stop(document) }) {
            Icon(Icons.Filled.StopCircle, null, Modifier.size(18.dp))
            Spacer(Modifier.width(4.dp))
            Text("Testo ${progress.done}/${progress.total}")
        }
        recognizer.isQueued(document) -> TextButton(onClick = { recognizer.stop(document) }) {
            Icon(Icons.Filled.Schedule, null, Modifier.size(18.dp))
            Spacer(Modifier.width(4.dp))
            Text("In coda")
        }
        app.library.recognizedPageCount(document) < document.pageCount ->
            IconButton(onClick = { recognizer.start(document) }) {
                Icon(Icons.Filled.DocumentScanner, contentDescription = "Riconosci tutto il libro")
            }
    }
}

