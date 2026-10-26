package it.pencilreader.notebook

import it.pencilreader.core.AffineTransform
import it.pencilreader.core.DrawingTool
import it.pencilreader.core.InkShape
import it.pencilreader.core.Point
import it.pencilreader.core.Rect
import it.pencilreader.core.applying
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlin.math.max

/// Un punto di un tratto: dove (in unità del quaderno, i dp della pagina a zoom 1),
/// quando (millisecondi dall'inizio del tratto) e con che pressione.
@Serializable
data class InkPoint(
    val x: Float,
    val y: Float,
    @SerialName("t") val time: Long = 0,
    @SerialName("p") val pressure: Float = 0.5f,
)

/// Un tratto del quaderno. Le forme pulite tengono anche la loro geometria, così si possono
/// rimodellare dopo; i loro punti sono il contorno della forma.
@Serializable
data class InkStroke(
    val id: Long,
    val tool: DrawingTool,
    /// ARGB.
    val color: Int,
    val width: Float,
    val points: List<InkPoint>,
    val shape: InkShape? = null,
) {
    val corePoints: List<Point> get() = points.map { Point(it.x.toDouble(), it.y.toDouble()) }

    val bounds: Rect
        get() {
            if (points.isEmpty()) return Rect.NULL
            val half = width / 2.0
            return Rect.bounding(corePoints).insetBy(-half, -half)
        }

    /// Il tratto portato altrove da una trasformazione affine, come fa il lazo: lo spessore segue la scala.
    fun applying(t: AffineTransform): InkStroke = copy(
        points = points.map { p ->
            val q = Point(p.x.toDouble(), p.y.toDouble()).applying(t)
            p.copy(x = q.x.toFloat(), y = q.y.toFloat())
        },
        width = (width * t.scaleFactor).toFloat().coerceAtLeast(0.3f),
        shape = shape?.applying(t),
    )

    companion object {
        /// Un tratto che segue il contorno di una forma.
        fun outlining(shape: InkShape, id: Long, tool: DrawingTool, color: Int, width: Float, pressure: Float = 0.5f): InkStroke {
            val outline = shape.outline(max(1.0, width / 2.0))
            return InkStroke(
                id, tool, color, width,
                outline.mapIndexed { i, p -> InkPoint(p.x.toFloat(), p.y.toFloat(), i * 4L, pressure) },
                shape,
            )
        }
    }
}

/// La nota scritta a mano di una pagina del libro.
@Serializable
data class NotePage(val strokes: List<InkStroke> = emptyList()) {
    val isEmpty: Boolean get() = strokes.isEmpty()
}
