package it.pencilreader.reader

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import it.pencilreader.core.Span

val HighlightYellow = Color(0xFFFFD60A).copy(alpha = 0.45f)

/// La scheda accanto al lazo: la frase tradotta, con evidenziata la traduzione delle parole cerchiate.
@Composable
fun TranslationPanel(selection: ReaderModel.Selection, onClose: () -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(16.dp),
        tonalElevation = 3.dp,
        shadowElevation = 10.dp,
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    selection.context?.let { sentence ->
                        SelectionContainer {
                            Text(
                                highlighted(sentence.text, sentence.selection, MaterialTheme.colorScheme.onSurfaceVariant, MaterialTheme.colorScheme.onSurface),
                                style = MaterialTheme.typography.bodyMedium,
                            )
                        }
                        HorizontalDivider()
                    }
                    TranslationContent(selection)
                }
                IconButton(onClick = onClose, modifier = Modifier.size(32.dp)) {
                    Icon(Icons.Filled.Cancel, contentDescription = "Chiudi", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            val translation = selection.translation
            if (translation != null) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    OutlinedButton(onClick = {
                        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        clipboard.setPrimaryClip(ClipData.newPlainText("Traduzione", translation))
                    }) {
                        Icon(Icons.Filled.ContentCopy, null, Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Copia", style = MaterialTheme.typography.labelMedium)
                    }
                }
            }
        }
    }
}

@Composable
private fun TranslationContent(selection: ReaderModel.Selection) {
    val translation = selection.translation
    val error = selection.error
    when {
        translation != null -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SelectionContainer {
                Text(
                    highlighted(translation, selection.highlight, MaterialTheme.colorScheme.onSurface, MaterialTheme.colorScheme.onSurface),
                    style = MaterialTheme.typography.bodyLarge,
                )
            }
            selection.termTranslation?.let { term ->
                // Il termine non si è trovato nella frase: si mostra a parte.
                Text(
                    term,
                    fontWeight = FontWeight.SemiBold,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.background(HighlightYellow, RoundedCornerShape(4.dp)).padding(horizontal = 6.dp, vertical = 2.dp),
                )
            }
        }
        error != null -> Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Warning, null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text(error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        }
        else -> Row(verticalAlignment = Alignment.CenterVertically) {
            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
            Spacer(Modifier.width(8.dp))
            Text(
                if (selection.isDownloadingModel) {
                    "Scarico il modello di traduzione inglese → italiano (una volta sola, serve la rete)…"
                } else {
                    "Traduzione…"
                },
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

private fun highlighted(text: String, range: Span?, color: Color, strong: Color): AnnotatedString = buildAnnotatedString {
    if (range == null) {
        withStyle(SpanStyle(color = color)) { append(text) }
        return@buildAnnotatedString
    }
    val start = range.start.coerceIn(0, text.length)
    val end = range.end.coerceIn(start, text.length)
    withStyle(SpanStyle(color = color)) { append(text.substring(0, start)) }
    withStyle(SpanStyle(color = strong, background = HighlightYellow, fontWeight = FontWeight.SemiBold)) {
        append(text.substring(start, end))
    }
    withStyle(SpanStyle(color = color)) { append(text.substring(end)) }
}
