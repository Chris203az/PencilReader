package it.pencilreader.notebook

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import androidx.ink.brush.Brush
import androidx.ink.brush.InputToolType
import androidx.ink.brush.SelfOverlap
import androidx.ink.brush.StockBrushes
import androidx.ink.rendering.android.canvas.CanvasStrokeRenderer
import androidx.ink.strokes.MutableStrokeInputBatch
import androidx.ink.strokes.Stroke
import androidx.ink.strokes.StrokeInput
import it.pencilreader.core.DrawingTool
import it.pencilreader.core.Rect
import java.util.IdentityHashMap
import kotlin.math.max
import kotlin.math.min

/// Come si disegnano i tratti del quaderno con androidx.ink.
object InkBrushes {
    /// L'evidenziatore è trasparente come un pennarello vero: le righe sotto si vedono.
    private const val MARKER_ALPHA = 0.45f
    /// La matita non ha un pennello suo in androidx.ink 1.0: è un tratto pieno un po' più chiaro.
    private const val PENCIL_ALPHA = 0.85f

    fun brush(tool: DrawingTool, argb: Int, width: Float): Brush {
        val family = when (tool) {
            DrawingTool.MARKER -> StockBrushes.highlighter(SelfOverlap.DISCARD)
            DrawingTool.PENCIL -> StockBrushes.marker()
            else -> StockBrushes.pressurePen()
        }
        val color = when (tool) {
            DrawingTool.MARKER -> withAlpha(argb, MARKER_ALPHA)
            DrawingTool.PENCIL -> withAlpha(argb, PENCIL_ALPHA)
            else -> argb
        }
        return Brush.createWithColorIntArgb(family, color, max(width, 0.3f), 0.1f)
    }

    private fun withAlpha(argb: Int, alpha: Float): Int {
        val a = ((argb ushr 24) and 0xFF) * alpha
        return (a.toInt().coerceIn(0, 255) shl 24) or (argb and 0x00FFFFFF)
    }

    /// Il tratto di androidx.ink per un tratto salvato.
    fun stroke(ink: InkStroke): Stroke {
        val batch = MutableStrokeInputBatch()
        val points = if (ink.points.size == 1) ink.points + ink.points[0].copy(time = ink.points[0].time + 1) else ink.points
        var lastTime = -1L
        for (p in points) {
            // I tempi devono crescere: due punti con lo stesso tempo li separa un millisecondo.
            val time = max(p.time, lastTime + 1)
            lastTime = time
            batch.add(InputToolType.STYLUS, p.x, p.y, time, StrokeInput.NO_STROKE_UNIT_LENGTH, p.pressure.coerceIn(0f, 1f))
        }
        return Stroke(brush(ink.tool, ink.color, ink.width), batch)
    }

    /// I punti di un tratto appena finito, nelle unità del quaderno.
    fun points(stroke: Stroke): List<InkPoint> {
        val inputs = stroke.inputs
        val out = StrokeInput()
        val first = if (inputs.size > 0) inputs.populate(0, out).elapsedTimeMillis else 0L
        return (0 until inputs.size).map { i ->
            inputs.populate(i, out)
            InkPoint(out.x, out.y, out.elapsedTimeMillis - first, if (out.hasPressure) out.pressure else 0.5f)
        }
    }
}

/// Disegna i tratti salvati tenendo pronti i tratti di androidx.ink, rifatti solo quando il tratto cambia.
class InkStrokeCache {
    val renderer: CanvasStrokeRenderer = CanvasStrokeRenderer.create()
    private val cache = IdentityHashMap<InkStroke, Stroke>()

    fun get(ink: InkStroke): Stroke = cache.getOrPut(ink) { InkBrushes.stroke(ink) }

    /// Tiene solo i tratti ancora sulla pagina, o nella cronologia vicina.
    fun retain(strokes: Collection<InkStroke>) {
        val keep = java.util.Collections.newSetFromMap(IdentityHashMap<InkStroke, Boolean>()).apply { addAll(strokes) }
        cache.keys.retainAll(keep)
    }

    fun draw(canvas: Canvas, ink: InkStroke, worldToScreen: Matrix) = renderer.draw(canvas, get(ink), worldToScreen)
}

/// Le miniature delle note, per l'elenco delle note del libro.
object NoteThumbnails {
    fun render(page: NotePage, width: Int, height: Int): Bitmap? {
        if (page.strokes.isEmpty()) return null
        var bounds = Rect.NULL
        for (s in page.strokes) bounds = bounds.union(s.bounds)
        if (bounds.isNull || bounds.isEmpty) return null
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(Color.WHITE)
        val canvas = Canvas(bitmap)
        val scale = min(width / bounds.width, height / bounds.height).toFloat()
        val matrix = Matrix().apply {
            setTranslate(-bounds.minX.toFloat(), -bounds.minY.toFloat())
            postScale(scale, scale)
            postTranslate(((width - bounds.width * scale) / 2).toFloat(), ((height - bounds.height * scale) / 2).toFloat())
        }
        val renderer = CanvasStrokeRenderer.create()
        for (s in page.strokes) renderer.draw(canvas, InkBrushes.stroke(s), matrix)
        return bitmap
    }
}
