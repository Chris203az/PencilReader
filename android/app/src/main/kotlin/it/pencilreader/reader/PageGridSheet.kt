package it.pencilreader.reader

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BorderColor
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.ModeEdit
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import it.pencilreader.notebook.NoteThumbnails
import it.pencilreader.notebook.NotebookModel
import it.pencilreader.render.PageThumbnails
import it.pencilreader.study.StudyColor
import it.pencilreader.ui.NoteOrange
import it.pencilreader.ui.Sheet
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/// Le miniature di tutte le pagine, per saltare subito a una di esse.
@Composable
fun PageGridSheet(
    pageCount: Int,
    currentPage: Int,
    thumbnails: PageThumbnails,
    notedPages: Set<Int>,
    markedPages: Set<Int>,
    onDismiss: () -> Unit,
    select: (Int) -> Unit,
) {
    val state = rememberLazyGridState(initialFirstVisibleItemIndex = maxOf(0, currentPage - 4))
    Sheet("Pagine", onDismiss) {
        LazyVerticalGrid(
            columns = GridCells.Adaptive(130.dp),
            state = state,
            contentPadding = PaddingValues(24.dp),
            horizontalArrangement = Arrangement.spacedBy(20.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            items(pageCount) { index ->
                ThumbnailCell(index, index == currentPage, index in notedPages, index in markedPages, thumbnails) {
                    select(index)
                    onDismiss()
                }
            }
        }
    }
}

@Composable
private fun ThumbnailCell(index: Int, isCurrent: Boolean, hasNote: Boolean, hasMarks: Boolean, thumbnails: PageThumbnails, onClick: () -> Unit) {
    val image by produceState<Bitmap?>(thumbnails.cached(index), index) { value = thumbnails.thumbnail(index) }
    val accent = MaterialTheme.colorScheme.primary
    Column(Modifier.clickable(onClick = onClick), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(190.dp)
                .shadow(2.dp, RoundedCornerShape(4.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant)
                .border(if (isCurrent) 3.dp else 0.dp, if (isCurrent) accent else Color.Transparent, RoundedCornerShape(4.dp)),
        ) {
            image?.let { Image(it.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit) }
            if (hasNote) {
                Box(Modifier.align(Alignment.TopEnd).padding(6.dp).size(28.dp).background(NoteOrange, CircleShape), contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.ModeEdit, contentDescription = "Ha una nota", tint = Color.White, modifier = Modifier.size(16.dp))
                }
            }
            if (hasMarks) {
                Box(
                    Modifier.align(Alignment.TopStart).padding(6.dp).size(26.dp).background(Color(StudyColor.KEY.argb), CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Filled.BorderColor, contentDescription = "Ha segni di studio", tint = Color.Black, modifier = Modifier.size(14.dp))
                }
            }
        }
        Text(
            "${index + 1}",
            style = MaterialTheme.typography.bodySmall,
            fontWeight = if (isCurrent) FontWeight.Bold else FontWeight.Normal,
            color = if (isCurrent) accent else MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/// Tutte le pagine del libro con una nota scritta a mano, per andare dritti a una di esse.
@Composable
fun NotesListSheet(notebook: NotebookModel, pages: List<Int>, onDismiss: () -> Unit, select: (Int) -> Unit) {
    Sheet("Note del libro", onDismiss, maxWidth = 640.dp) {
        if (pages.isEmpty()) {
            Column(Modifier.fillMaxSize().padding(32.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Filled.EditNote, null, Modifier.size(44.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("Nessuna nota", fontWeight = FontWeight.SemiBold)
                Text("Le note scritte sulle pagine del libro compaiono qui.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            LazyColumn(Modifier.fillMaxSize()) {
                items(pages) { page ->
                    Row(
                        Modifier.fillMaxWidth().clickable { select(page); onDismiss() }.padding(horizontal = 16.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        val thumbnail by produceState<Bitmap?>(null, page) {
                            value = withContext(Dispatchers.Default) { notebook.load(page)?.let { NoteThumbnails.render(it, 112, 152) } }
                        }
                        Box(Modifier.size(width = 56.dp, height = 76.dp).background(Color.White).border(1.dp, MaterialTheme.colorScheme.outlineVariant)) {
                            thumbnail?.let { Image(it.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit) }
                        }
                        Spacer(Modifier.width(16.dp))
                        Text("Pagina ${page + 1}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                        Icon(Icons.Filled.ChevronRight, null, tint = MaterialTheme.colorScheme.outline)
                    }
                    HorizontalDivider()
                }
            }
        }
    }
}
