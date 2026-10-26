package it.pencilreader.notebook

import android.graphics.PointF
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.ContentCut
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.LibraryAdd
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Popup
import it.pencilreader.core.NotebookToolbarLayout
import it.pencilreader.core.PaperStyle
import it.pencilreader.core.SplitRatio
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

/// Il quaderno accanto alla pagina del libro: un'intestazione, la barra degli strumenti in alto o in basso,
/// e il foglio su cui scrive la penna.
@Composable
fun NotebookPane(notebook: NotebookModel, modifier: Modifier = Modifier) {
    val settings = notebook.settings
    var showsToolbarSettings by remember { mutableStateOf(false) }
    val position = settings.toolbarLayout.position
    Column(modifier.fillMaxHeight().background(MaterialTheme.colorScheme.surface)) {
        NotebookHeader(notebook, onToolbarSettings = { showsToolbarSettings = true })
        HorizontalDivider()
        if (position == NotebookToolbarLayout.Position.TOP) {
            NotebookToolbar(notebook, enabled = notebook.isWriting)
            HorizontalDivider()
        }
        Box(Modifier.weight(1f).fillMaxWidth()) {
            if (notebook.isWriting) {
                NotebookSheet(notebook)
            } else {
                Column(
                    Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Icon(Icons.Filled.EditNote, null, Modifier.size(44.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(8.dp))
                    Text("Nessuna nota su questa pagina", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.height(12.dp))
                    Button(onClick = notebook::startNote) { Text("Nuova nota") }
                }
            }
        }
        if (position == NotebookToolbarLayout.Position.BOTTOM) {
            HorizontalDivider()
            NotebookToolbar(notebook, enabled = notebook.isWriting)
        }
    }
    if (showsToolbarSettings) ToolbarSettingsSheet(settings, onDismiss = { showsToolbarSettings = false })
}

@Composable
private fun NotebookHeader(notebook: NotebookModel, onToolbarSettings: () -> Unit) {
    val settings = notebook.settings
    var menu by remember { mutableStateOf(false) }
    var paperMenu by remember { mutableStateOf(false) }
    var strengthMenu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("Note · pag. ${notebook.pageIndex + 1}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.weight(1f))
        Box {
            IconButton(onClick = { menu = true }) { Icon(Icons.Filled.Tune, contentDescription = "Opzioni") }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text("Barra strumenti…") }, onClick = { menu = false; onToolbarSettings() })
                DropdownMenuItem(text = { Text("Sfondo: ${settings.paper.label}") }, onClick = { menu = false; paperMenu = true })
                DropdownMenuItem(
                    text = { Text("Raddrizza le forme") },
                    trailingIcon = { Switch(settings.straightensShapes, onCheckedChange = null) },
                    onClick = { settings.updateStraightensShapes(!settings.straightensShapes) },
                )
                DropdownMenuItem(
                    text = { Text("Leviga i tratti") },
                    trailingIcon = { Switch(settings.smoothsStrokes, onCheckedChange = null) },
                    onClick = { settings.updateSmoothsStrokes(!settings.smoothsStrokes) },
                )
                DropdownMenuItem(
                    text = { Text("Intensità levigatura: ${settings.smoothingStrength.roundToInt()} pt") },
                    enabled = settings.smoothsStrokes,
                    onClick = { menu = false; strengthMenu = true },
                )
            }
            DropdownMenu(expanded = paperMenu, onDismissRequest = { paperMenu = false }) {
                for (style in PaperStyle.entries) {
                    DropdownMenuItem(
                        text = { Text(style.label) },
                        leadingIcon = { if (style == settings.paper) Icon(Icons.Filled.Check, null) else Spacer(Modifier.size(24.dp)) },
                        onClick = { paperMenu = false; settings.updatePaper(style) },
                    )
                }
            }
            DropdownMenu(expanded = strengthMenu, onDismissRequest = { strengthMenu = false }) {
                for (points in listOf(1.0, 2.0, 3.0, 4.0)) {
                    DropdownMenuItem(
                        text = { Text("${points.toInt()} pt") },
                        leadingIcon = {
                            if (points == settings.smoothingStrength) Icon(Icons.Filled.Check, null) else Spacer(Modifier.size(24.dp))
                        },
                        onClick = { strengthMenu = false; settings.updateSmoothingStrength(points) },
                    )
                }
            }
        }
    }
}

/// Il foglio: la vista con androidx.ink, il messaggio "Annulla"/"Ripristina" e i menu del lazo.
@Composable
private fun NotebookSheet(notebook: NotebookModel) {
    var toast by remember { mutableStateOf<Pair<String, Long>?>(null) }
    var selectionMenu by remember { mutableStateOf<PointF?>(null) }
    var pasteMenu by remember { mutableStateOf<PointF?>(null) }
    var colorsMenu by remember { mutableStateOf(false) }
    var view by remember { mutableStateOf<NotebookCanvasView?>(null) }
    val settings = notebook.settings

    Box(Modifier.fillMaxSize()) {
        AndroidView(
            factory = { context ->
                NotebookCanvasView(context).also { v ->
                    v.onToast = { toast = it to System.nanoTime() }
                    v.onSelectionMenu = { selectionMenu = it }
                    v.onPasteMenu = { pasteMenu = it }
                    view = v
                }
            },
            modifier = Modifier.fillMaxSize(),
            update = { v ->
                // Letti qui, così ogni cambiamento dei tratti, della carta o degli strumenti arriva alla vista.
                notebook.strokes
                notebook.loadCount
                notebook.tools
                notebook.isRulerActive
                v.bind(notebook, settings.paper)
            },
        )
        toast?.let { (text, stamp) ->
            LaunchedEffect(stamp) {
                delay(700)
                toast = null
            }
            Surface(
                color = Color.Black.copy(alpha = 0.7f),
                shape = RoundedCornerShape(14.dp),
                modifier = Modifier.align(Alignment.TopCenter).padding(top = 20.dp),
            ) {
                Text(text, color = Color.White, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(horizontal = 18.dp, vertical = 8.dp))
            }
        }
        selectionMenu?.let { anchor ->
            Popup(offset = IntOffset(anchor.x.roundToInt(), anchor.y.roundToInt() + 12), onDismissRequest = { selectionMenu = null }) {
                Surface(shape = RoundedCornerShape(12.dp), tonalElevation = 6.dp, shadowElevation = 8.dp) {
                    Row(Modifier.padding(4.dp), verticalAlignment = Alignment.CenterVertically) {
                        MenuAction(Icons.Filled.ContentCopy, "Copia") { view?.copySelection() }
                        MenuAction(Icons.Filled.ContentCut, "Taglia") { view?.cutSelection() }
                        MenuAction(Icons.Filled.LibraryAdd, "Duplica") { view?.duplicateSelection() }
                        MenuAction(Icons.Filled.Delete, "Elimina", destructive = true) { view?.deleteSelection() }
                        Box {
                            MenuAction(Icons.Filled.Palette, "Cambia colore") { colorsMenu = true }
                            DropdownMenu(expanded = colorsMenu, onDismissRequest = { colorsMenu = false }) {
                                notebook.tools.palette.forEachIndexed { index, color ->
                                    DropdownMenuItem(
                                        text = { Text("Colore ${index + 1}") },
                                        leadingIcon = { Box(Modifier.size(20.dp).background(Color(color.toArgb()), CircleShape)) },
                                        onClick = {
                                            colorsMenu = false
                                            view?.recolorSelection(color.toArgb())
                                        },
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        pasteMenu?.let { anchor ->
            Popup(offset = IntOffset(anchor.x.roundToInt(), anchor.y.roundToInt()), onDismissRequest = { pasteMenu = null }) {
                Surface(shape = RoundedCornerShape(12.dp), tonalElevation = 6.dp, shadowElevation = 8.dp) {
                    MenuAction(Icons.Filled.ContentPaste, "Incolla") {
                        pasteMenu = null
                        view?.paste()
                    }
                }
            }
        }
    }
}

@Composable
private fun MenuAction(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, destructive: Boolean = false, action: () -> Unit) {
    val color = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface
    androidx.compose.material3.TextButton(onClick = action) {
        Icon(icon, null, tint = color, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(4.dp))
        Text(label, color = color, style = MaterialTheme.typography.labelLarge)
    }
}

/// La linea trascinabile tra la pagina del libro e il quaderno. Segue il dito; i due lati si
/// ridimensionano una volta sola, quando la si lascia, così non tremano mentre si sposta.
@Composable
fun NotebookDivider(split: Double, available: Float, onSplit: (Double) -> Unit) {
    var drag by remember { mutableFloatStateOf(0f) }
    var dragging by remember { mutableStateOf(false) }
    val density = LocalDensity.current
    fun limited(offset: Float): Float =
        ((SplitRatio.clamped(split + offset / available) - split) * available).toFloat()
    Box(
        Modifier
            .width(DIVIDER_WIDTH)
            .fillMaxHeight()
            .offset { IntOffset(limited(drag).roundToInt(), 0) }
            .pointerInput(split, available) {
                detectHorizontalDragGestures(
                    onDragStart = { dragging = true; drag = 0f },
                    onDragEnd = {
                        onSplit(SplitRatio.clamped(split + drag / available))
                        dragging = false
                        drag = 0f
                    },
                    onDragCancel = { dragging = false; drag = 0f },
                    onHorizontalDrag = { change, amount ->
                        change.consume()
                        drag += amount
                    },
                )
            },
        contentAlignment = Alignment.Center,
    ) {
        with(density) {
            Box(
                Modifier
                    .width(if (dragging) 6.dp else 4.dp)
                    .height(if (dragging) 120.dp else 44.dp)
                    .background(
                        if (dragging) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline.copy(alpha = 0.5f),
                        RoundedCornerShape(50),
                    ),
            )
        }
    }
}

val DIVIDER_WIDTH = 24.dp
