package it.pencilreader.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val Accent = Color(0xFF1E6FE0)
val NoteOrange = Color(0xFFFF9500)

@Composable
fun PencilReaderTheme(content: @Composable () -> Unit) {
    val colors = if (isSystemInDarkTheme()) {
        darkColorScheme(primary = Color(0xFF6EA8FF), secondary = NoteOrange)
    } else {
        lightColorScheme(primary = Accent, secondary = NoteOrange)
    }
    MaterialTheme(colorScheme = colors, content = content)
}
