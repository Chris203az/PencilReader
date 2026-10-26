package it.pencilreader.reader

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
import androidx.compose.material.icons.filled.DocumentScanner
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import it.pencilreader.PencilReaderApp
import it.pencilreader.core.SearchMatch
import it.pencilreader.data.LibraryDocument
import it.pencilreader.ui.Sheet

/// Ricerca in tutto il libro; toccando un risultato si apre la sua pagina con le parole evidenziate.
@Composable
fun SearchSheet(
    app: PencilReaderApp,
    document: LibraryDocument,
    search: BookSearch,
    onDismiss: () -> Unit,
    select: (page: Int, wordIDs: List<Int>) -> Unit,
) {
    val recognizer = app.recognizer
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) {
        if (search.query.isEmpty()) runCatching { focus.requestFocus() } else search.search()
    }
    val matchCount = search.results.sumOf { it.matches.size }
    Sheet("Cerca in “${document.title}”", onDismiss) {
        Column(Modifier.fillMaxSize()) {
            OutlinedTextField(
                value = search.query,
                onValueChange = search::updateQuery,
                placeholder = { Text("Cerca nel libro") },
                leadingIcon = { Icon(Icons.Filled.Search, null) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).focusRequester(focus),
            )
            Box(Modifier.weight(1f)) {
                LazyColumn(Modifier.fillMaxSize()) {
                    if (search.missingPages > 0) {
                        item {
                            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Filled.Warning, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                    Spacer(Modifier.width(8.dp))
                                    Text(
                                        if (search.missingPages == 1) "1 pagina non è ancora stata riconosciuta: lì la ricerca non trova nulla."
                                        else "${search.missingPages} pagine non sono ancora state riconosciute: lì la ricerca non trova nulla.",
                                        style = MaterialTheme.typography.bodySmall,
                                    )
                                }
                                val progress = recognizer.progress(document)
                                when {
                                    progress != null -> Text(
                                        "Riconoscimento in corso: ${progress.done}/${progress.total}",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                    recognizer.isQueued(document) -> Text(
                                        "In coda per il riconoscimento",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                    else -> TextButton(onClick = { recognizer.start(document) }) {
                                        Icon(Icons.Filled.DocumentScanner, null)
                                        Spacer(Modifier.width(6.dp))
                                        Text("Riconosci tutto il libro")
                                    }
                                }
                            }
                            HorizontalDivider()
                        }
                    }
                    if (search.results.isNotEmpty()) {
                        item {
                            Text(
                                if (matchCount == 1) "1 risultato" else "$matchCount risultati in ${search.results.size} pagine",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                            )
                        }
                    }
                    for (result in search.results) {
                        item(key = "h${result.page}") {
                            Text(
                                "Pagina ${result.page + 1}",
                                style = MaterialTheme.typography.labelLarge,
                                color = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 4.dp),
                            )
                        }
                        items(result.matches) { match ->
                            val snippet = highlighted(match, MaterialTheme.colorScheme.onSurfaceVariant, MaterialTheme.colorScheme.onSurface)
                            Text(
                                snippet,
                                style = MaterialTheme.typography.bodyMedium,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable {
                                        select(result.page, match.wordIDs)
                                        onDismiss()
                                    }
                                    .padding(horizontal = 16.dp, vertical = 10.dp),
                            )
                        }
                    }
                }
                if (search.isSearching) {
                    CircularProgressIndicator(Modifier.align(Alignment.Center))
                } else if (search.results.isEmpty() && search.query.isNotBlank()) {
                    Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(Icons.Filled.Search, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text("Nessun risultato per “${search.query}”", fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }
    }
}

private fun highlighted(match: SearchMatch, secondary: Color, primary: Color): AnnotatedString = buildAnnotatedString {
    val s = match.snippet
    val start = match.highlight.start.coerceIn(0, s.length)
    val end = match.highlight.end.coerceIn(start, s.length)
    withStyle(SpanStyle(color = secondary)) { append(s.substring(0, start)) }
    withStyle(SpanStyle(color = primary, background = Color(0xFFFF9500).copy(alpha = 0.35f), fontWeight = FontWeight.SemiBold)) {
        append(s.substring(start, end))
    }
    withStyle(SpanStyle(color = secondary)) { append(s.substring(end)) }
}

