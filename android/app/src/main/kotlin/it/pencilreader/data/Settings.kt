package it.pencilreader.data

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import it.pencilreader.core.NotebookToolState
import it.pencilreader.core.NotebookToolbarLayout
import it.pencilreader.core.PaperStyle
import it.pencilreader.core.SplitRatio
import it.pencilreader.core.StrokeSmoother

/// Le preferenze ricordate tra una sessione e l'altra, come le UserDefaults dell'iPad.
/// Ogni valore è osservabile da Compose e si salva quando cambia.
class Settings(context: Context) {
    private val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    var paper by mutableStateOf(PaperStyle.fromRaw(prefs.getString("notebookPaper", null)) ?: PaperStyle.GRID)
        private set
    /// Tenere ferma la penna alla fine di un tratto lo trasforma in una linea, un poligono o un'ellisse pulita.
    var straightensShapes by mutableStateOf(prefs.getBoolean("notebookShapes", true))
        private set
    /// Ogni tratto perde il tremolio quando la penna si alza.
    var smoothsStrokes by mutableStateOf(prefs.getBoolean("notebookSmoothStrokes", true))
        private set
    /// Di quanto la levigatura può spostare i punti di un tratto: da 1 a 4.
    var smoothingStrength by mutableStateOf(
        prefs.getFloat("notebookSmoothingStrength", StrokeSmoother.MAX_SHIFT.toFloat()).toDouble()
            .coerceIn(StrokeSmoother.strengths.start, StrokeSmoother.strengths.endInclusive),
    )
        private set
    var toolState by mutableStateOf(
        prefs.getString("notebookTools", null)
            ?.let { runCatching { AppJson.decodeFromString(NotebookToolState.serializer(), it) }.getOrNull() }
            ?: NotebookToolState(),
    )
        private set
    var toolbarLayout by mutableStateOf(
        (prefs.getString("notebookToolbar", null)
            ?.let { runCatching { AppJson.decodeFromString(NotebookToolbarLayout.serializer(), it) }.getOrNull() }
            ?: NotebookToolbarLayout.STANDARD).normalized(),
    )
        private set
    /// La parte della larghezza data alla pagina del libro quando il quaderno è aperto.
    var split by mutableStateOf(SplitRatio.clamped(prefs.getFloat("notebookSplit", SplitRatio.STANDARD.toFloat()).toDouble()))
        private set
    /// La guida della modalità studio si apre da sola solo la prima volta.
    var studyGuideSeen by mutableStateOf(prefs.getBoolean("studyGuideSeen", false))
        private set

    fun updatePaper(value: PaperStyle) {
        paper = value
        prefs.edit().putString("notebookPaper", value.rawValue).apply()
    }

    fun updateStraightensShapes(value: Boolean) {
        straightensShapes = value
        prefs.edit().putBoolean("notebookShapes", value).apply()
    }

    fun updateSmoothsStrokes(value: Boolean) {
        smoothsStrokes = value
        prefs.edit().putBoolean("notebookSmoothStrokes", value).apply()
    }

    fun updateSmoothingStrength(value: Double) {
        smoothingStrength = value.coerceIn(StrokeSmoother.strengths.start, StrokeSmoother.strengths.endInclusive)
        prefs.edit().putFloat("notebookSmoothingStrength", smoothingStrength.toFloat()).apply()
    }

    fun updateToolState(value: NotebookToolState) {
        if (value == toolState) return
        toolState = value
        prefs.edit().putString("notebookTools", AppJson.encodeToString(NotebookToolState.serializer(), value)).apply()
    }

    fun updateToolbarLayout(value: NotebookToolbarLayout) {
        toolbarLayout = value
        prefs.edit().putString("notebookToolbar", AppJson.encodeToString(NotebookToolbarLayout.serializer(), value)).apply()
    }

    fun updateSplit(value: Double) {
        split = SplitRatio.clamped(value)
        prefs.edit().putFloat("notebookSplit", split.toFloat()).apply()
    }

    fun markStudyGuideSeen() {
        studyGuideSeen = true
        prefs.edit().putBoolean("studyGuideSeen", true).apply()
    }
}
