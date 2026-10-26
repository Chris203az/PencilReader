package it.pencilreader.study

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.BorderColor
import androidx.compose.material.icons.filled.DocumentScanner
import androidx.compose.material.icons.filled.Draw
import androidx.compose.material.icons.filled.FormatUnderlined
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.HelpOutline
import androidx.compose.material.icons.filled.PanTool
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.AutoFixNormal
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import it.pencilreader.ui.Sheet

/// Gli strumenti di studio, che galleggiano sopra il fondo della pagina mentre la modalità è attiva.
@Composable
fun StudyToolbar(study: StudyModel, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(50),
        tonalElevation = 4.dp,
        shadowElevation = 6.dp,
    ) {
        Row(
            Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 10.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            for (color in StudyColor.entries) {
                ToolButton(study, StudyTool.Highlighter(color), color.shortLabel, color.label, Icons.Filled.BorderColor, Color(color.argb))
            }
            VerticalDivider(Modifier.height(28.dp))
            ToolButton(study, StudyTool.Underline, "Termine", "Sottolinea un termine inglese", Icons.Filled.FormatUnderlined, Color(StudyTool.UNDERLINE_COLOR))
            ToolButton(study, StudyTool.Pen, "Nota", "Nota a margine", Icons.Filled.Edit, Color(StudyTool.PEN_COLOR))
            ToolButton(study, StudyTool.Eraser, "Gomma", "Gomma", Icons.Filled.AutoFixNormal, null)
            VerticalDivider(Modifier.height(28.dp))
            IconButton(onClick = study::undo, enabled = study.canUndo) {
                Icon(Icons.AutoMirrored.Filled.Undo, contentDescription = "Annulla")
            }
            IconButton(onClick = { study.showsGuide = true }) {
                Icon(Icons.Filled.HelpOutline, contentDescription = "Come studiare")
            }
        }
    }
}

@Composable
private fun ToolButton(study: StudyModel, tool: StudyTool, label: String, help: String, icon: ImageVector, tint: Color?) {
    val selected = study.tool == tool
    Column(
        Modifier
            .background(if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.18f) else Color.Transparent, RoundedCornerShape(10.dp))
            .clickable { study.tool = tool }
            .padding(horizontal = 6.dp, vertical = 2.dp)
            .widthIn(min = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(icon, contentDescription = help, tint = tint ?: LocalContentColor.current, modifier = Modifier.size(24.dp))
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/// Come studiare con i segni, dalla ricerca sull'apprendimento dai testi.
@Composable
fun StudyGuideSheet(onDismiss: () -> Unit) {
    val steps = listOf(
        "Leggi prima, segna dopo" to
            "Leggi tutto il paragrafo senza la penna. Solo alla fine decidi cosa conta: così scegli, invece di colorare tutto.",
        "Poco e sempre con lo stesso significato" to
            "Al massimo una frase per paragrafo. Ogni colore vuol dire sempre la stessa cosa (legenda sotto).",
        "Sottolinea i termini inglesi" to
            "Una riga sotto le parole tecniche da imparare. La riga si raddrizza da sola.",
        "Scrivi una domanda a margine" to
            "Con la penna, con parole tue: «Perché il CL crolla dopo lo stallo?». Riformulare fissa il concetto molto più del colore.",
        "Ripassa provando a ricordare" to
            "Nei giorni seguenti copri il testo e rispondi alle domande a margine. Comincia dalle pagine con il rosa e torna su quelle che sbagli.",
    )
    Sheet("Come studiare con questa modalità", onDismiss, maxWidth = 640.dp) {
        LazyColumn(Modifier.fillMaxSize().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                Text(
                    "Evidenziare da solo aiuta poco a ricordare. Funziona quando è selettivo e soprattutto quando lo usi per farti domande e poi provare a ricordare senza guardare.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            item { SectionTitle("Il metodo") }
            items(steps.size) { index ->
                val (title, detail) = steps[index]
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Box(Modifier.size(26.dp).background(MaterialTheme.colorScheme.primary, CircleShape), contentAlignment = Alignment.Center) {
                        Text("${index + 1}", color = MaterialTheme.colorScheme.onPrimary, fontWeight = FontWeight.Bold)
                    }
                    Column {
                        Text(title, fontWeight = FontWeight.SemiBold)
                        Text(detail, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            item { SectionTitle("Legenda") }
            for (color in StudyColor.entries) {
                item { LegendRow(Color(color.argb).copy(alpha = StudyTool.HIGHLIGHT_ALPHA), color.label, color.detail, thin = false) }
            }
            item { LegendRow(Color(StudyTool.UNDERLINE_COLOR), "Sottolineato", "Termine inglese da imparare", thin = true) }
            item { LegendRow(Color(StudyTool.PEN_COLOR), "Penna", "Domande e note a margine", thin = true) }
            item { SectionTitle("Come si usa") }
            item { UsageRow(Icons.Filled.Draw, "La penna segna; il cerchio per tradurre è spento finché la modalità è attiva.") }
            item { UsageRow(Icons.Filled.PanTool, "Con il dito sfogli, zoomi e giri pagina come sempre.") }
            item { UsageRow(Icons.Filled.DocumentScanner, "L'evidenziatore si aggancia a una riga alla volta; ripassare con lo stesso colore non lo scurisce.") }
            item { UsageRow(Icons.Filled.GridView, "Le pagine segnate hanno l'evidenziatore nella griglia delle pagine.") }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

@Composable
private fun SectionTitle(text: String) {
    Column {
        Spacer(Modifier.height(8.dp))
        Text(text, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
        HorizontalDivider(Modifier.padding(top = 4.dp))
    }
}

@Composable
private fun LegendRow(color: Color, title: String, detail: String, thin: Boolean) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.width(34.dp).height(18.dp), contentAlignment = Alignment.Center) {
            Box(Modifier.width(34.dp).height(if (thin) 3.dp else 18.dp).background(color, RoundedCornerShape(if (thin) 1.dp else 4.dp)))
        }
        Column {
            Text(title)
            Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun UsageRow(icon: ImageVector, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(icon, null, tint = MaterialTheme.colorScheme.primary)
        Text(text)
    }
}
