package it.pencilreader.notebook

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Redo
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.AutoFixNormal
import androidx.compose.material.icons.filled.BorderColor
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Draw
import androidx.compose.material.icons.filled.Gesture
import androidx.compose.material.icons.filled.Grid4x4
import androidx.compose.material.icons.filled.Interests
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.LineWeight
import androidx.compose.material.icons.filled.ModeEdit
import androidx.compose.material.icons.filled.Straighten
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import it.pencilreader.core.DrawingTool
import it.pencilreader.core.EraserSizes
import it.pencilreader.core.InkColor
import it.pencilreader.core.NotebookToolbarItem
import it.pencilreader.core.NotebookToolbarLayout
import it.pencilreader.core.PaperStyle
import it.pencilreader.data.Settings
import it.pencilreader.ui.Sheet
import java.util.Locale
import kotlin.math.abs
import kotlin.math.sqrt

/// La barra degli strumenti del quaderno, fissa in alto o in basso, con i controlli scelti nelle sue
/// impostazioni, nel loro ordine. Scorre di lato quando non ci stanno tutti.
@Composable
fun NotebookToolbar(notebook: NotebookModel, enabled: Boolean) {
    val settings = notebook.settings
    Surface(tonalElevation = 2.dp, modifier = Modifier.fillMaxWidth().height(48.dp).alpha(if (enabled) 1f else 0.4f)) {
        Row(
            Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            for (item in settings.toolbarLayout.visibleItems) {
                Control(notebook, item, enabled)
            }
        }
    }
}

@Composable
private fun Control(notebook: NotebookModel, item: NotebookToolbarItem, enabled: Boolean) {
    val tools = notebook.tools
    when (item) {
        NotebookToolbarItem.PEN -> ToolButton(notebook, DrawingTool.PEN, enabled)
        NotebookToolbarItem.PENCIL -> ToolButton(notebook, DrawingTool.PENCIL, enabled)
        NotebookToolbarItem.MARKER -> ToolButton(notebook, DrawingTool.MARKER, enabled)
        NotebookToolbarItem.ERASER -> EraserButton(notebook, enabled)
        NotebookToolbarItem.LASSO -> ToolButton(notebook, DrawingTool.LASSO, enabled)
        NotebookToolbarItem.RULER -> BarButton("Righello", Icons.Filled.Straighten, notebook.isRulerActive, enabled) {
            notebook.isRulerActive = !notebook.isRulerActive
        }
        NotebookToolbarItem.COLORS -> Row(Modifier.padding(horizontal = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            tools.palette.forEachIndexed { index, color -> ColorSwatch(notebook, index, color, enabled) }
        }
        NotebookToolbarItem.WIDTH -> WidthButtons(notebook, enabled)
        NotebookToolbarItem.UNDO -> BarButton("Annulla", Icons.AutoMirrored.Filled.Undo, false, enabled && notebook.canUndo) { notebook.undo() }
        NotebookToolbarItem.REDO -> BarButton("Ripristina", Icons.AutoMirrored.Filled.Redo, false, enabled && notebook.canRedo) { notebook.redo() }
        NotebookToolbarItem.SHAPES -> BarButton("Forme automatiche", Icons.Filled.Interests, notebook.settings.straightensShapes, enabled) {
            notebook.settings.updateStraightensShapes(!notebook.settings.straightensShapes)
        }
        NotebookToolbarItem.PAPER -> {
            var menu by remember { mutableStateOf(false) }
            Box {
                BarButton("Sfondo", Icons.Filled.Grid4x4, false, enabled) { menu = true }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    for (style in PaperStyle.entries) {
                        DropdownMenuItem(
                            text = { Text(style.label) },
                            leadingIcon = { if (style == notebook.settings.paper) Icon(Icons.Filled.Check, null) else Spacer(Modifier.size(24.dp)) },
                            onClick = { menu = false; notebook.settings.updatePaper(style) },
                        )
                    }
                }
            }
        }
    }
}

fun DrawingTool.icon(): ImageVector = when (this) {
    DrawingTool.PEN -> Icons.Filled.Draw
    DrawingTool.PENCIL -> Icons.Filled.ModeEdit
    DrawingTool.MARKER -> Icons.Filled.BorderColor
    DrawingTool.ERASER -> Icons.Filled.AutoFixNormal
    DrawingTool.LASSO -> Icons.Filled.Gesture
}

@Composable
private fun ToolButton(notebook: NotebookModel, tool: DrawingTool, enabled: Boolean) {
    BarButton(tool.label, tool.icon(), notebook.tools.current == tool, enabled) { notebook.select(tool) }
}

/// Un controllo della barra; lo strumento in mano è colorato.
@Composable
private fun BarButton(label: String, icon: ImageVector, isActive: Boolean, enabled: Boolean, badge: (@Composable () -> Unit)? = null, action: () -> Unit) {
    val accent = MaterialTheme.colorScheme.primary
    Box(
        Modifier
            .size(width = 38.dp, height = 36.dp)
            .background(if (isActive) accent.copy(alpha = 0.18f) else Color.Transparent, RoundedCornerShape(8.dp))
            .clickable(enabled = enabled, onClickLabel = label, onClick = action),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = label, tint = if (isActive) accent else LocalContentColor.current, modifier = Modifier.size(22.dp))
        badge?.let { Box(Modifier.align(Alignment.BottomEnd).padding(3.dp)) { it() } }
    }
}

/// La gomma: un tocco la prende, un tocco mentre è in mano apre tipo e grandezza.
/// Il pallino sull'icona cresce con la grandezza.
@Composable
private fun EraserButton(notebook: NotebookModel, enabled: Boolean) {
    val tools = notebook.tools
    val isActive = tools.current == DrawingTool.ERASER
    var showsSettings by remember { mutableStateOf(false) }
    val range = EraserSizes.range(tools.eraserIsPixel)
    val share = ((notebook.eraserWidth - range.start) / (range.endInclusive - range.start)).coerceIn(0.0, 1.0)
    val accent = MaterialTheme.colorScheme.primary
    val dotColor = if (isActive) accent else LocalContentColor.current
    Box {
        BarButton(
            "Gomma", DrawingTool.ERASER.icon(), isActive, enabled,
            badge = {
                val size = (4 + 6 * sqrt(share)).dp
                Box(Modifier.size(size).background(dotColor, CircleShape))
            },
        ) {
            if (isActive) showsSettings = true else notebook.select(DrawingTool.ERASER)
        }
        if (showsSettings) {
            Popup(onDismissRequest = { showsSettings = false }) {
                Surface(shape = RoundedCornerShape(14.dp), tonalElevation = 6.dp, shadowElevation = 8.dp) {
                    EraserSettings(notebook)
                }
            }
        }
    }
}

/// Tratti interi o pixel, tre grandezze veloci, un cursore per le altre, e la grandezza disegnata come un cerchio.
@Composable
private fun EraserSettings(notebook: NotebookModel) {
    val tools = notebook.tools
    val width = notebook.eraserWidth
    val range = EraserSizes.range(tools.eraserIsPixel)
    Column(Modifier.width(320.dp).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(!tools.eraserIsPixel, onClick = { notebook.updateTools { it.withEraserPixel(false) } }, label = { Text("Tratto intero") })
            FilterChip(tools.eraserIsPixel, onClick = { notebook.updateTools { it.withEraserPixel(true) } }, label = { Text("Pixel") })
        }
        Box(Modifier.fillMaxWidth().height(96.dp), contentAlignment = Alignment.Center) {
            val size = minOf(width, 96.0).dp
            Box(
                Modifier.size(size)
                    .background(MaterialTheme.colorScheme.outline.copy(alpha = 0.12f), CircleShape)
                    .border(1.dp, MaterialTheme.colorScheme.outline, CircleShape),
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("Piccola", "Media", "Grande").zip(EraserSizes.presets(tools.eraserIsPixel)).forEach { (name, preset) ->
                val chosen = abs(width - preset) < 0.05
                OutlinedButton(onClick = { notebook.updateTools { it.withEraserWidth(preset) } }, modifier = Modifier.weight(1f)) {
                    Text(name, color = if (chosen) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        Slider(
            value = width.toFloat(),
            onValueChange = { v -> notebook.updateTools { it.withEraserWidth(v.toDouble()) } },
            valueRange = range.start.toFloat()..range.endInclusive.toFloat(),
        )
        Text(
            "Grandezza " + String.format(Locale.ITALIAN, "%.1f", width) + " pt",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/// Un colore preimpostato: un tocco scrive con quello, tenerlo premuto lo cambia.
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ColorSwatch(notebook: NotebookModel, index: Int, color: InkColor, enabled: Boolean) {
    val tools = notebook.tools
    var editing by remember { mutableStateOf(false) }
    val selected = tools.current.isInking && notebook.currentInk?.color?.sameColor(color) == true
    val accent = MaterialTheme.colorScheme.primary
    Box {
        Box(
            Modifier
                .size(30.dp)
                .border(2.dp, if (selected) accent else Color.Transparent, CircleShape)
                .padding(3.dp)
                .background(Color(color.toArgb()), CircleShape)
                .border(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.25f), CircleShape)
                .combinedClickable(
                    enabled = enabled,
                    onClickLabel = "Colore ${index + 1}",
                    onLongClickLabel = "Cambia il colore",
                    onLongClick = { editing = true },
                    onClick = { notebook.setColor(color) },
                ),
        )
        if (editing) {
            Popup(onDismissRequest = { editing = false }) {
                Surface(shape = RoundedCornerShape(14.dp), tonalElevation = 6.dp, shadowElevation = 8.dp) {
                    Column(Modifier.width(300.dp).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("Colore del campione", style = MaterialTheme.typography.titleSmall)
                        LazyVerticalGrid(GridCells.Fixed(6), Modifier.height(200.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            items(SWATCH_CHOICES) { argb ->
                                Box(
                                    Modifier.size(36.dp).background(Color(argb), CircleShape)
                                        .border(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.25f), CircleShape)
                                        .clickable {
                                            notebook.updateTools { it.withPaletteColor(InkColor.fromArgb(argb), index) }
                                            editing = false
                                        },
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

/// I colori tra cui scegliere un campione.
private val SWATCH_CHOICES = listOf(
    0xFF1A1A1A, 0xFF5E5E5E, 0xFF9E9E9E, 0xFF1F5CD9, 0xFF0A84FF, 0xFF64D2FF,
    0xFFD62639, 0xFFFF453A, 0xFFFF9F0A, 0xFFFFD60A, 0xFFFFD933, 0xFFB8860B,
    0xFF2E8B57, 0xFF30D158, 0xFF00897B, 0xFF6A1B9A, 0xFFBF5AF2, 0xFFFF6FB1,
    0xFF8B4513, 0xFF003366, 0xFF800020, 0xFF556B2F, 0xFFFFFFFF, 0xFF000000,
).map { it.toInt() }

/// Tre spessori preimpostati e un cursore per gli altri: della penna, matita o evidenziatore in uso, o,
/// con la gomma in mano, piccola, media e grande di quel tipo di gomma, disegnate come cerchi vuoti.
@Composable
private fun WidthButtons(notebook: NotebookModel, enabled: Boolean) {
    val tools = notebook.tools
    val isEraser = tools.current == DrawingTool.ERASER
    val tool = tools.lastInking
    val presets = if (isEraser) EraserSizes.presets(tools.eraserIsPixel) else tool.widthPresets
    val width = if (isEraser) notebook.eraserWidth else notebook.currentInk?.width
    val range = if (isEraser) EraserSizes.range(tools.eraserIsPixel) else tool.widthRange
    var showsSlider by remember { mutableStateOf(false) }
    val accent = MaterialTheme.colorScheme.primary
    val content = LocalContentColor.current
    fun setWidth(value: Double) {
        if (isEraser) notebook.updateTools { it.withEraserWidth(value) } else notebook.updateTools { it.withWidth(value) }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
        presets.forEachIndexed { step, preset ->
            val chosen = width?.let { abs(it - preset) < 0.05 } == true
            Box(
                Modifier.size(width = 30.dp, height = 36.dp)
                    .background(if (chosen) accent.copy(alpha = 0.18f) else Color.Transparent, RoundedCornerShape(8.dp))
                    .clickable(enabled = enabled, onClickLabel = if (isEraser) listOf("Gomma piccola", "Gomma media", "Gomma grande")[step] else "Spessore ${step + 1}") {
                        setWidth(preset)
                    },
                contentAlignment = Alignment.Center,
            ) {
                val size = (5 + step * 5).dp
                if (isEraser) Box(Modifier.size(size + 2.dp).border(1.5.dp, content, CircleShape))
                else Box(Modifier.size(size).background(content, CircleShape))
            }
        }
        Box {
            BarButton(if (isEraser) "Altra grandezza della gomma" else "Altro spessore", Icons.Filled.LineWeight, false, enabled) { showsSlider = true }
            if (showsSlider) {
                Popup(onDismissRequest = { showsSlider = false }) {
                    Surface(shape = RoundedCornerShape(14.dp), tonalElevation = 6.dp, shadowElevation = 8.dp) {
                        Column(Modifier.width(300.dp).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text(if (isEraser) "Grandezza gomma" else "Spessore ${tool.label.lowercase(Locale.ITALIAN)}", style = MaterialTheme.typography.titleSmall)
                            Slider(
                                value = (width ?: range.start).toFloat(),
                                onValueChange = { setWidth(it.toDouble()) },
                                valueRange = range.start.toFloat()..range.endInclusive.toFloat(),
                            )
                            Text(
                                String.format(Locale.ITALIAN, "%.1f", width ?: 0.0) + " pt",
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        }
    }
}

/// Dove sta la barra e quali controlli mostra, in che ordine.
@Composable
fun ToolbarSettingsSheet(settings: Settings, onDismiss: () -> Unit) {
    val layout = settings.toolbarLayout
    Sheet("Barra strumenti", onDismiss, maxWidth = 560.dp) {
        LazyColumn(Modifier.padding(horizontal = 16.dp)) {
            item {
                Text("Posizione", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
                Row(Modifier.padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (position in NotebookToolbarLayout.Position.entries) {
                        FilterChip(layout.position == position, onClick = { settings.updateToolbarLayout(layout.copy(position = position)) }, label = { Text(position.label) })
                    }
                }
                HorizontalDivider()
                Text("Elementi", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 12.dp))
            }
            itemsIndexed(layout.entries, key = { _, e -> e.item.name }) { index, entry ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(entry.isVisible, onCheckedChange = { visible ->
                        settings.updateToolbarLayout(layout.copy(entries = layout.entries.toMutableList().also { it[index] = entry.copy(isVisible = visible) }))
                    })
                    Text(entry.item.label, Modifier.weight(1f))
                    IconButton(onClick = { settings.updateToolbarLayout(layout.copy(entries = moved(layout.entries, index, -1))) }, enabled = index > 0) {
                        Icon(Icons.Filled.KeyboardArrowUp, contentDescription = "Sposta su")
                    }
                    IconButton(onClick = { settings.updateToolbarLayout(layout.copy(entries = moved(layout.entries, index, 1))) }, enabled = index < layout.entries.size - 1) {
                        Icon(Icons.Filled.KeyboardArrowDown, contentDescription = "Sposta giù")
                    }
                }
            }
            item {
                Text(
                    "Usa le frecce per cambiare l'ordine.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(vertical = 8.dp),
                )
                HorizontalDivider()
                TextButton(onClick = { settings.updateToolbarLayout(NotebookToolbarLayout.STANDARD) }) { Text("Ripristina predefiniti") }
                Spacer(Modifier.height(16.dp))
            }
        }
    }
}

private fun <T> moved(list: List<T>, index: Int, by: Int): List<T> {
    val target = index + by
    if (target !in list.indices) return list
    return list.toMutableList().also {
        val item = it.removeAt(index)
        it.add(target, item)
    }
}

