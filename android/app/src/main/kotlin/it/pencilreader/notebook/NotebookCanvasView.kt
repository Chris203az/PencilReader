package it.pencilreader.notebook

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.widget.FrameLayout
import androidx.ink.authoring.InProgressStrokeId
import androidx.ink.authoring.InProgressStrokesFinishedListener
import androidx.ink.authoring.InProgressStrokesView
import androidx.ink.strokes.Stroke
import it.pencilreader.core.AffineTransform
import it.pencilreader.core.DrawingTool
import it.pencilreader.core.EraserSizes
import it.pencilreader.core.InkShape
import it.pencilreader.core.PaperStyle
import it.pencilreader.core.Point
import it.pencilreader.core.Rect
import it.pencilreader.core.SelectionFrame
import it.pencilreader.core.SelectionHandle
import it.pencilreader.core.ShapeRecognizer
import it.pencilreader.core.StrokeLasso
import it.pencilreader.core.StrokeSmoother
import it.pencilreader.core.grips
import it.pencilreader.core.moved
import it.pencilreader.core.outlineDistance
import it.pencilreader.core.reshaped
import it.pencilreader.ui.polylineDistance
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max


/// Il foglio del quaderno: la carta, i tratti salvati (disegnati con CanvasStrokeRenderer) e, sopra,
/// l'InProgressStrokesView di androidx.ink, che disegna il tratto in corso con la latenza più bassa.
///
/// Solo la penna scrive; le dita scorrono, ingrandiscono (pizzico, doppio tocco per tornare a 1x),
/// annullano (scorrimento a destra) e ripristinano (a sinistra). Come in GoodNotes: tenendo ferma la
/// penna alla fine di un tratto, il tratto diventa una forma pulita che segue la punta finché si alza;
/// un tocco del dito sulla linea di una forma ne mostra le maniglie; il lazo prende i tratti, li sposta,
/// li ridimensiona e li gira, con un menu sotto la selezione. Il tasto della penna fa da gomma.
///
/// Le coordinate del quaderno sono i dp della pagina a zoom 1: la pagina è larga quanto il foglio.
@SuppressLint("ViewConstructor")
class NotebookCanvasView(context: Context) : FrameLayout(context) {
    /// Il modello della pagina mostrata, con i suoi tratti e gli strumenti.
    var model: NotebookModel? = null
        private set
    var onToast: (String) -> Unit = {}
    /// Il menu della selezione, sotto di essa, nel punto dato del foglio; null lo nasconde.
    var onSelectionMenu: (PointF?) -> Unit = {}
    /// Il menu Incolla, dove si è tenuto premuto.
    var onPasteMenu: (PointF?) -> Unit = {}

    private val density = resources.displayMetrics.density
    private val surface = Surface(context)
    private val inProgress = InProgressStrokesView(context)
    private val cache = InkStrokeCache()

    var paper: PaperStyle = PaperStyle.GRID
        set(value) {
            if (field != value) {
                field = value
                surface.invalidate()
            }
        }

    // Vista

    private var zoom = 1f
    private var scrollPx = PointF(0f, 0f)
    private val worldToScreen = Matrix()
    private val screenToWorld = Matrix()
    private val scale get() = zoom * density

    // Penna

    private enum class PenMode { NONE, INK, SNAPPED, RULER, ERASE, LASSO_LOOP, LASSO_DRAG, SHAPE_DRAG, IGNORE }

    private var penMode = PenMode.NONE
    private var penPointer = -1
    private var strokeID: InProgressStrokeId? = null
    private var strokeTool = DrawingTool.PEN
    private var strokeColor = Color.BLACK
    private var strokeWidth = 3f
    private val strokePoints = mutableListOf<Point>()
    private val pendingInk = mutableMapOf<InProgressStrokeId, Triple<DrawingTool, Int, Float>>()
    private var stillAt = PointF()
    private var penAt: PointF? = null
    private var snapped: Triple<InkShape, Point, Point>? = null
    private var previewShape: InkShape? = null
    private var rulerStart: Point? = null
    private var rulerEnd: Point? = null
    private var eraseBefore: List<InkStroke>? = null
    private val holdRunnable = Runnable { held() }

    // Dita

    private var fingerDrag = false
    private var scaling = false
    private var lastFocus: PointF? = null

    // Lazo

    private data class Selection(val ids: List<Long>, val originals: List<InkStroke>, val frame: SelectionFrame)

    private sealed interface LassoDrag {
        data class Loop(val points: List<Point>) : LassoDrag
        data class Move(val start: Point, val frame: SelectionFrame) : LassoDrag
        data class Resize(val handle: SelectionHandle, val start: Point, val frame: SelectionFrame) : LassoDrag
        data class Rotate(val start: Point, val frame: SelectionFrame) : LassoDrag
    }

    private var selection: Selection? = null
    private var lassoDrag: LassoDrag? = null
    private var lassoLast: Point? = null
    private var pastePoint: Point? = null

    // Forme

    private data class Editing(val id: Long, val stroke: InkStroke, val shape: InkShape)

    private sealed interface ShapeDrag {
        data class Grip(val index: Int) : ShapeDrag
        data class Move(val start: Point) : ShapeDrag
    }

    private var editing: Editing? = null
    private var shapeDrag: ShapeDrag? = null
    private var dragged: InkShape? = null

    /// I tratti come li ha lasciati l'ultima modifica fatta da qui: un altro cambiamento (Annulla dalla barra,
    /// un'altra pagina) lascia andare la selezione e la forma in modifica.
    private var ownStrokes: List<InkStroke>? = null
    private var lastLoad = -1

    init {
        addView(surface, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        addView(inProgress, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        inProgress.eagerInit()
        inProgress.addFinishedStrokesListener(object : InProgressStrokesFinishedListener {
            override fun onStrokesFinished(strokes: Map<InProgressStrokeId, Stroke>) = finished(strokes)
        })
        updateMatrices()
    }

    // Collegamento con Compose

    /// Segue il modello: i tratti, la carta, lo strumento. Chiamato a ogni cambiamento osservato.
    fun bind(model: NotebookModel, paper: PaperStyle) {
        this.model = model
        this.paper = paper
        if (model.loadCount != lastLoad) {
            lastLoad = model.loadCount
            zoom = 1f
            scrollPx = PointF(0f, 0f)
            updateMatrices()
            cancelEverything()
        }
        if (model.strokes !== ownStrokes) {
            ownStrokes = model.strokes
            deselect()
            deselectShape()
        }
        if (model.tools.current != DrawingTool.LASSO) deselect()
        if (model.tools.current == DrawingTool.LASSO) deselectShape()
        cache.retain(model.strokes + (selection?.originals ?: emptyList()))
        clampScroll()
        surface.invalidate()
    }

    private fun commit(strokes: List<InkStroke>, previous: List<InkStroke>? = null) {
        val model = model ?: return
        if (previous != null) model.commit(strokes, previous) else model.commit(strokes)
        ownStrokes = model.strokes
        surface.invalidate()
    }

    private fun cancelEverything() {
        removeCallbacks(holdRunnable)
        strokeID?.let { inProgress.cancelStroke(it, null) }
        strokeID = null
        penMode = PenMode.NONE
        penPointer = -1
        previewShape = null
        snapped = null
        rulerStart = null
        rulerEnd = null
        penAt = null
        deselect()
        deselectShape()
    }

    // Coordinate

    private fun updateMatrices() {
        worldToScreen.setScale(scale, scale)
        worldToScreen.postTranslate(-scrollPx.x, -scrollPx.y)
        worldToScreen.invert(screenToWorld)
    }

    private fun toWorld(x: Float, y: Float): Point {
        val pts = floatArrayOf(x, y)
        screenToWorld.mapPoints(pts)
        return Point(pts[0].toDouble(), pts[1].toDouble())
    }

    private fun toScreen(p: Point): PointF = PointF(p.x.toFloat() * scale - scrollPx.x, p.y.toFloat() * scale - scrollPx.y)

    /// Una distanza sullo schermo (in dp), nelle unità del quaderno allo zoom attuale.
    private fun reach(dp: Float): Double = (dp / zoom).toDouble()

    private val pageWidthWorld get() = width / density
    private val viewHeightWorld get() = height / density

    /// C'è sempre una schermata di carta sotto l'ultimo tratto.
    private val contentHeightWorld: Float
        get() {
            val bottom = model?.strokes?.maxOfOrNull { it.bounds.maxY }?.toFloat() ?: 0f
            return max(viewHeightWorld, bottom + viewHeightWorld / 2)
        }

    private fun clampScroll() {
        val maxX = max(0f, width * zoom - width)
        val maxY = max(0f, contentHeightWorld * scale - height)
        scrollPx = PointF(scrollPx.x.coerceIn(0f, maxX), scrollPx.y.coerceIn(0f, maxY))
        updateMatrices()
    }

    private fun scrollBy(dx: Float, dy: Float) {
        scrollPx = PointF(scrollPx.x + dx, scrollPx.y + dy)
        clampScroll()
        refreshOverlays()
    }

    private fun zoomAround(factor: Float, fx: Float, fy: Float) {
        val world = toWorld(fx, fy)
        zoom = (zoom * factor).coerceIn(1f, MAX_ZOOM)
        scrollPx = PointF(world.x.toFloat() * scale - fx, world.y.toFloat() * scale - fy)
        clampScroll()
        refreshOverlays()
    }

    private fun refreshOverlays() {
        surface.invalidate()
        if (selection != null && lassoDrag == null) showSelectionMenu()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        clampScroll()
    }

    // Tocchi

    private val scaleDetector = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScaleBegin(detector: ScaleGestureDetector): Boolean {
            scaling = true
            lastFocus = PointF(detector.focusX, detector.focusY)
            return true
        }

        override fun onScale(detector: ScaleGestureDetector): Boolean {
            zoomAround(detector.scaleFactor, detector.focusX, detector.focusY)
            lastFocus?.let { scrollBy(it.x - detector.focusX, it.y - detector.focusY) }
            lastFocus = PointF(detector.focusX, detector.focusY)
            return true
        }

        override fun onScaleEnd(detector: ScaleGestureDetector) {
            lastFocus = null
        }
    })

    private val gestures = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
        override fun onDown(e: MotionEvent) = true

        override fun onScroll(e1: MotionEvent?, e2: MotionEvent, distanceX: Float, distanceY: Float): Boolean {
            if (!scaling) scrollBy(distanceX, distanceY)
            return true
        }

        override fun onFling(e1: MotionEvent?, e2: MotionEvent, velocityX: Float, velocityY: Float): Boolean {
            if (e1 == null || scaling || zoom > 1.01f) return false
            val dx = e2.x - e1.x
            val dy = e2.y - e1.y
            if (abs(dx) < 48 * density || abs(dx) < 1.5f * abs(dy) || abs(velocityX) < 600) return false
            val model = model ?: return false
            // Come su iPad: verso destra annulla, verso sinistra ripristina.
            if (dx > 0) {
                if (model.undo()) onToast("Annulla")
            } else {
                if (model.redo()) onToast("Ripristina")
            }
            return true
        }

        override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
            fingerTap(toWorld(e.x, e.y))
            return true
        }

        override fun onDoubleTap(e: MotionEvent): Boolean {
            zoom = 1f
            clampScroll()
            refreshOverlays()
            return true
        }

        override fun onLongPress(e: MotionEvent) {
            if (scaling || NotebookModel.clipboard.isEmpty()) return
            val p = toWorld(e.x, e.y)
            if (grabLasso(p) != null) return
            pastePoint = p
            onPasteMenu(PointF(e.x, e.y))
        }
    })

    override fun onInterceptTouchEvent(ev: MotionEvent) = true

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        val model = model ?: return false
        if (!model.isWriting) return false
        val action = event.actionMasked
        val index = event.actionIndex
        val pointerId = event.getPointerId(index)
        val isPen = isPen(event, index)

        // La penna.
        if ((action == MotionEvent.ACTION_DOWN || action == MotionEvent.ACTION_POINTER_DOWN) && isPen && penPointer == -1) {
            penPointer = pointerId
            penDown(event, index)
            return true
        }
        if (penPointer != -1) {
            val penIndex = event.findPointerIndex(penPointer)
            when {
                penIndex < 0 -> cancelPen()
                action == MotionEvent.ACTION_MOVE -> penMove(event, penIndex)
                (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_POINTER_UP) && pointerId == penPointer -> penUp(event, penIndex)
                action == MotionEvent.ACTION_CANCEL -> cancelPen()
            }
            // Mentre la penna scrive le dita non fanno nulla: è la mano appoggiata.
            return true
        }
        if (isPen) return true

        // Le dita: maniglie della selezione o della forma, altrimenti scorrimento e zoom.
        if (action == MotionEvent.ACTION_DOWN) {
            fingerDrag = false
            scaling = false
            onSelectionMenu(null)
            onPasteMenu(null)
            val p = toWorld(event.x, event.y)
            if (beginDrag(p, pen = false)) {
                fingerDrag = true
                return true
            }
        }
        if (fingerDrag) {
            val p = toWorld(event.x, event.y)
            when (action) {
                MotionEvent.ACTION_MOVE -> dragMove(p)
                MotionEvent.ACTION_UP -> {
                    dragEnd(p)
                    fingerDrag = false
                }
                MotionEvent.ACTION_CANCEL, MotionEvent.ACTION_POINTER_DOWN -> {
                    dragCancel()
                    fingerDrag = false
                }
            }
            return true
        }
        scaleDetector.onTouchEvent(event)
        if (event.pointerCount > 1) scaling = true
        gestures.onTouchEvent(event)
        if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
            scaling = false
            if (selection != null) showSelectionMenu()
        }
        return true
    }

    private fun isPen(event: MotionEvent, index: Int): Boolean {
        val type = event.getToolType(index)
        return type == MotionEvent.TOOL_TYPE_STYLUS || type == MotionEvent.TOOL_TYPE_ERASER
    }

    // La penna

    private fun penDown(event: MotionEvent, index: Int) {
        val model = model ?: return
        onSelectionMenu(null)
        onPasteMenu(null)
        val x = event.getX(index)
        val y = event.getY(index)
        val p = toWorld(x, y)
        penAt = PointF(x, y)
        val tools = model.tools
        val buttonEraser = event.getToolType(index) == MotionEvent.TOOL_TYPE_ERASER ||
            (event.buttonState and MotionEvent.BUTTON_STYLUS_PRIMARY) != 0
        when {
            buttonEraser || tools.current == DrawingTool.ERASER -> {
                deselectShape()
                penMode = PenMode.ERASE
                eraseBefore = model.strokes
                erase(p)
            }
            editing != null -> {
                // Mentre una forma mostra le maniglie la penna le trascina; lontano dalla forma la lascia andare.
                if (beginDrag(p, pen = true)) {
                    penMode = PenMode.SHAPE_DRAG
                } else {
                    deselectShape()
                    penMode = PenMode.IGNORE
                }
            }
            tools.current == DrawingTool.LASSO -> {
                if (beginDrag(p, pen = true)) {
                    penMode = PenMode.LASSO_DRAG
                } else {
                    deselect()
                    lassoDrag = LassoDrag.Loop(listOf(p))
                    penMode = PenMode.LASSO_LOOP
                }
            }
            model.isRulerActive -> {
                setInk(tools.current)
                penMode = PenMode.RULER
                rulerStart = p
                rulerEnd = p
            }
            else -> {
                setInk(tools.current)
                penMode = PenMode.INK
                strokePoints.clear()
                strokePoints.add(p)
                stillAt = PointF(x, y)
                val brush = InkBrushes.brush(strokeTool, strokeColor, strokeWidth)
                val id = inProgress.startStroke(event, event.getPointerId(index), brush, Matrix(screenToWorld), Matrix())
                strokeID = id
                pendingInk[id] = Triple(strokeTool, strokeColor, strokeWidth)
                postDelayed(holdRunnable, HOLD_MS)
            }
        }
        surface.invalidate()
    }

    private fun setInk(tool: DrawingTool) {
        val model = model ?: return
        val inking = if (tool.isInking) tool else model.tools.lastInking
        val ink = model.tools.ink(inking)
        strokeTool = inking
        strokeColor = ink?.color?.toArgb() ?: Color.BLACK
        strokeWidth = (ink?.width ?: 3.0).toFloat()
    }

    private fun penMove(event: MotionEvent, index: Int) {
        val x = event.getX(index)
        val y = event.getY(index)
        val p = toWorld(x, y)
        penAt = PointF(x, y)
        when (penMode) {
            PenMode.INK -> {
                strokeID?.let { inProgress.addToStroke(event, penPointer, it, null) }
                for (h in 0 until event.historySize) {
                    strokePoints.add(toWorld(event.getHistoricalX(index, h), event.getHistoricalY(index, h)))
                }
                strokePoints.add(p)
                if (hypot(x - stillAt.x, y - stillAt.y) > STILLNESS_DP * density) {
                    stillAt = PointF(x, y)
                    removeCallbacks(holdRunnable)
                    postDelayed(holdRunnable, HOLD_MS)
                }
            }
            PenMode.SNAPPED -> snapped?.let { (shape, anchor, tip) ->
                previewShape = shape.dragged(anchor, tip, p)
                surface.invalidate()
            }
            PenMode.RULER -> {
                rulerEnd = p
                surface.invalidate()
            }
            PenMode.ERASE -> {
                for (h in 0 until event.historySize) erase(toWorld(event.getHistoricalX(index, h), event.getHistoricalY(index, h)))
                erase(p)
                surface.invalidate()
            }
            PenMode.LASSO_LOOP -> {
                val loop = lassoDrag as? LassoDrag.Loop
                if (loop != null) lassoDrag = LassoDrag.Loop(loop.points + p)
                surface.invalidate()
            }
            PenMode.LASSO_DRAG, PenMode.SHAPE_DRAG -> dragMove(p)
            PenMode.NONE, PenMode.IGNORE -> {}
        }
    }

    private fun penUp(event: MotionEvent, index: Int) {
        removeCallbacks(holdRunnable)
        val model = model
        val p = toWorld(event.getX(index), event.getY(index))
        when (penMode) {
            PenMode.INK -> {
                // Il tratto finito arriva da `finished`, dopo che androidx.ink l'ha chiuso.
                strokeID?.let { inProgress.finishStroke(event, penPointer, it) }
            }
            PenMode.SNAPPED -> {
                val shape = previewShape
                if (shape != null && model != null) {
                    val stroke = InkStroke.outlining(shape, model.newID(), strokeTool, strokeColor, strokeWidth)
                    commit(model.strokes + stroke)
                }
            }
            PenMode.RULER -> {
                val a = rulerStart
                val b = rulerEnd ?: p
                if (a != null && model != null && hypot(b.x - a.x, b.y - a.y) > 1) {
                    val line = InkShape.Line(a, b)
                    val stroke = InkStroke.outlining(line, model.newID(), strokeTool, strokeColor, strokeWidth).copy(shape = null)
                    commit(model.strokes + stroke)
                }
            }
            PenMode.ERASE -> {
                val before = eraseBefore
                if (model != null && before != null && model.strokes !== before) commit(model.strokes, before)
                eraseBefore = null
            }
            PenMode.LASSO_LOOP -> {
                val loop = (lassoDrag as? LassoDrag.Loop)?.points ?: emptyList()
                lassoDrag = null
                select(loop + p)
            }
            PenMode.LASSO_DRAG, PenMode.SHAPE_DRAG -> dragEnd(p)
            PenMode.NONE, PenMode.IGNORE -> {}
        }
        strokeID = null
        penMode = PenMode.NONE
        penPointer = -1
        previewShape = null
        snapped = null
        rulerStart = null
        rulerEnd = null
        penAt = null
        surface.invalidate()
    }

    private fun cancelPen() {
        removeCallbacks(holdRunnable)
        strokeID?.let { inProgress.cancelStroke(it, null) }
        when (penMode) {
            PenMode.ERASE -> {
                eraseBefore?.let { model?.replaceLive(it) }
                eraseBefore = null
            }
            PenMode.LASSO_DRAG, PenMode.SHAPE_DRAG -> dragCancel()
            PenMode.LASSO_LOOP -> lassoDrag = null
            else -> {}
        }
        strokeID = null
        penMode = PenMode.NONE
        penPointer = -1
        previewShape = null
        snapped = null
        penAt = null
        surface.invalidate()
    }

    /// La penna è rimasta ferma un momento: mostra la forma a cui somiglia il tratto, se ce n'è una.
    private fun held() {
        val model = model ?: return
        if (penMode != PenMode.INK || !model.settings.straightensShapes) return
        val tip = strokePoints.lastOrNull() ?: return
        val shape = ShapeRecognizer.recognize(strokePoints.toList()) ?: return
        strokeID?.let {
            inProgress.cancelStroke(it, null)
            pendingInk.remove(it)
        }
        strokeID = null
        snapped = Triple(shape, shape.anchor(tip), tip)
        previewShape = shape
        penMode = PenMode.SNAPPED
        surface.invalidate()
    }

    /// I tratti finiti da androidx.ink: levigati (salvo l'evidenziatore) e messi sulla pagina, un passo di Annulla ciascuno.
    private fun finished(strokes: Map<InProgressStrokeId, Stroke>) {
        val model = model
        if (model == null) {
            inProgress.removeFinishedStrokes(strokes.keys)
            return
        }
        var page = model.strokes
        for ((id, stroke) in strokes) {
            val (tool, color, width) = pendingInk.remove(id) ?: continue
            var points = InkBrushes.points(stroke)
            if (points.isEmpty()) continue
            val settings = model.settings
            if (settings.smoothsStrokes && tool != DrawingTool.MARKER) {
                val smooth = StrokeSmoother.smoothed(
                    points.map { Point(it.x.toDouble(), it.y.toDouble()) }, settings.smoothingStrength,
                )
                if (smooth != null) points = points.mapIndexed { i, p -> p.copy(x = smooth[i].x.toFloat(), y = smooth[i].y.toFloat()) }
            }
            val ink = InkStroke(model.newID(), tool, color, width, points)
            commit(page + ink)
            page = model.strokes
        }
        // Tolti dallo strato veloce solo dopo che il foglio li ha disegnati, così non sfarfallano.
        val ids = strokes.keys.toSet()
        surface.postOnAnimation { inProgress.removeFinishedStrokes(ids) }
    }

    // Gomma

    private fun erase(p: Point) {
        val model = model ?: return
        val radius = EraserSizes.width(model.tools) / 2
        val strokes = model.strokes
        val changed: List<InkStroke> = if (model.tools.eraserIsPixel) {
            strokes.flatMap { s -> if (touches(s, p, radius)) split(s, p, radius) else listOf(s) }
        } else {
            strokes.filter { !touches(it, p, radius) }
        }
        if (changed.size != strokes.size || changed.zip(strokes).any { (a, b) -> a !== b }) model.replaceLive(changed)
    }

    private fun touches(stroke: InkStroke, p: Point, radius: Double): Boolean {
        val reach = radius + stroke.width / 2
        val b = stroke.bounds
        if (p.x < b.minX - reach || p.x > b.maxX + reach || p.y < b.minY - reach || p.y > b.maxY + reach) return false
        return polylineDistance(p, stroke.corePoints) <= reach
    }

    /// La gomma a pixel: il tratto senza la parte sotto la gomma, in uno o più pezzi.
    private fun split(stroke: InkStroke, p: Point, radius: Double): List<InkStroke> {
        val model = model ?: return emptyList()
        val reach = radius + stroke.width / 2
        val dense = densified(stroke.points, max(0.5, radius / 2))
        val pieces = mutableListOf<MutableList<InkPoint>>()
        var current: MutableList<InkPoint>? = null
        for (point in dense) {
            if (hypot(point.x - p.x, point.y - p.y) <= reach) {
                current = null
            } else {
                if (current == null) current = mutableListOf<InkPoint>().also { pieces.add(it) }
                current.add(point)
            }
        }
        return pieces.filter { it.size >= 2 }.map { InkStroke(model.newID(), stroke.tool, stroke.color, stroke.width, it) }
    }

    private fun densified(points: List<InkPoint>, spacing: Double): List<InkPoint> {
        if (points.size < 2) return points
        val out = mutableListOf(points[0])
        for (i in 1 until points.size) {
            val a = points[i - 1]
            val b = points[i]
            val length = hypot((b.x - a.x).toDouble(), (b.y - a.y).toDouble())
            val steps = (length / spacing).toInt()
            for (s in 1 until steps) {
                val t = s.toFloat() / steps
                out.add(InkPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.time + ((b.time - a.time) * t).toLong(), a.pressure + (b.pressure - a.pressure) * t))
            }
            out.add(b)
        }
        return out
    }

    // Trascinare: lazo e forme, con la penna o con il dito

    /// Comincia a trascinare quello che c'è in `p`: una maniglia o l'interno della selezione, una maniglia
    /// o la linea della forma in modifica. Falso se lì non c'è niente da prendere.
    private fun beginDrag(p: Point, pen: Boolean): Boolean {
        if (selection != null) {
            val grab = grabLasso(p) ?: return false
            lassoDrag = grab
            lassoLast = p
            onSelectionMenu(null)
            surface.invalidate()
            return true
        }
        val editing = editing ?: return false
        val grab = grabShape(editing.shape, p) ?: return false
        shapeDrag = grab
        dragged = editing.shape
        surface.invalidate()
        return true
    }

    private fun dragMove(p: Point) {
        if (lassoDrag != null) {
            lassoLast = p
            surface.invalidate()
            return
        }
        val editing = editing ?: return
        dragged = when (val drag = shapeDrag) {
            is ShapeDrag.Grip -> editing.shape.reshaped(drag.index, p)
            is ShapeDrag.Move -> editing.shape.moved(Point(p.x - drag.start.x, p.y - drag.start.y))
            null -> return
        }
        surface.invalidate()
    }

    private fun dragEnd(p: Point) {
        dragMove(p)
        val model = model ?: return
        val selection = selection
        if (lassoDrag != null && selection != null) {
            val frame = currentFrame() ?: selection.frame
            lassoDrag = null
            lassoLast = null
            val placed = placed(selection.originals, frame)
            val byID = selection.ids.zip(placed).toMap()
            this.selection = selection.copy(frame = frame)
            commit(model.strokes.map { byID[it.id] ?: it })
            showSelectionMenu()
            return
        }
        val editing = editing
        val shape = dragged
        if (editing != null && shape != null && shapeDrag != null) {
            val s = editing.stroke
            val stroke = InkStroke.outlining(shape, s.id, s.tool, s.color, s.width)
            this.editing = Editing(s.id, stroke, shape)
            commit(model.strokes.map { if (it.id == s.id) stroke else it })
        }
        shapeDrag = null
        dragged = null
        surface.invalidate()
    }

    private fun dragCancel() {
        lassoDrag = null
        lassoLast = null
        shapeDrag = null
        dragged = null
        surface.invalidate()
    }

    // Lazo

    private fun grabLasso(p: Point): LassoDrag? {
        val frame = selection?.frame ?: return null
        val handle = frame.handle(p, reach(GRIP_REACH_DP), reach(ROTATION_GAP_DP))
        if (handle != null) {
            return if (handle == SelectionHandle.ROTATE) LassoDrag.Rotate(p, frame) else LassoDrag.Resize(handle, p, frame)
        }
        if (frame.contains(p, reach(4f))) return LassoDrag.Move(p, frame)
        return null
    }

    /// Il riquadro come lo porta il trascinamento in corso, o come è stato lasciato.
    private fun currentFrame(): SelectionFrame? {
        val selection = selection ?: return null
        val last = lassoLast
        return when (val drag = lassoDrag) {
            is LassoDrag.Move -> drag.frame.moved(drag.start, last ?: drag.start)
            is LassoDrag.Resize -> drag.frame.resized(drag.handle, drag.start, last ?: drag.start)
            is LassoDrag.Rotate -> drag.frame.rotated(drag.start, last ?: drag.start)
            is LassoDrag.Loop, null -> selection.frame
        }
    }

    private fun select(loop: List<Point>) {
        val model = model ?: return
        val strokes = model.strokes
        val points = strokes.map { s -> densified(s.points, 4.0).map { Point(it.x.toDouble(), it.y.toDouble()) } }
        val indices = StrokeLasso.selected(points, loop)
        if (indices.isEmpty()) {
            surface.invalidate()
            return
        }
        selectStrokes(indices.map { strokes[it] })
    }

    private fun selectStrokes(chosen: List<InkStroke>) {
        var bounds = Rect.NULL
        for (s in chosen) bounds = bounds.union(s.bounds)
        if (bounds.isNull) return
        selection = Selection(chosen.map { it.id }, chosen, SelectionFrame.around(bounds.insetBy(-4.0, -4.0)))
        surface.invalidate()
        showSelectionMenu()
    }

    fun deselect() {
        if (selection == null && lassoDrag == null) return
        selection = null
        lassoDrag = null
        lassoLast = null
        onSelectionMenu(null)
        surface.invalidate()
    }

    private fun placed(originals: List<InkStroke>, frame: SelectionFrame): List<InkStroke> {
        val t = frame.transform
        return if (t.isIdentity) originals else originals.map { it.applying(t) }
    }

    /// Il menu sotto la selezione, come richiesto: dal suo angolo più in basso.
    private fun showSelectionMenu() {
        val frame = selection?.frame ?: return
        val bottom = frame.corners.map(::toScreen).maxByOrNull { it.y } ?: return
        val left = frame.corners.map(::toScreen).minOf { it.x }
        onSelectionMenu(PointF(left, bottom.y))
    }

    private fun fingerTap(p: Point) {
        val model = model ?: return
        if (model.tools.current == DrawingTool.LASSO) {
            val selection = selection ?: return
            if (selection.frame.contains(p, reach(GRIP_REACH_DP))) showSelectionMenu() else deselect()
            return
        }
        // La forma più in alto, quando si incrociano.
        for (stroke in model.strokes.asReversed()) {
            val shape = stroke.shape ?: continue
            if (shape.outlineDistance(p) <= reach(LINE_REACH_DP)) {
                editing = Editing(stroke.id, stroke, shape)
                surface.invalidate()
                return
            }
        }
        deselectShape()
    }

    fun deselectShape() {
        if (editing == null) return
        editing = null
        shapeDrag = null
        dragged = null
        surface.invalidate()
    }

    private fun grabShape(shape: InkShape, p: Point): ShapeDrag? {
        val grips = shape.grips
        val nearest = grips.indices.minByOrNull { hypot(grips[it].x - p.x, grips[it].y - p.y) }
        if (nearest != null && hypot(grips[nearest].x - p.x, grips[nearest].y - p.y) <= reach(GRIP_REACH_DP)) return ShapeDrag.Grip(nearest)
        return if (shape.outlineDistance(p) <= reach(GRIP_REACH_DP)) ShapeDrag.Move(p) else null
    }

    // Azioni del menu

    fun copySelection() {
        val selection = selection ?: return
        NotebookModel.clipboard = placed(selection.originals, selection.frame)
    }

    fun cutSelection() {
        copySelection()
        deleteSelection()
    }

    fun deleteSelection() {
        val model = model ?: return
        val ids = selection?.ids?.toSet() ?: return
        commit(model.strokes.filter { it.id !in ids })
        deselect()
    }

    fun duplicateSelection() {
        val selection = selection ?: return
        val shift = AffineTransform.translation(DUPLICATE_OFFSET, DUPLICATE_OFFSET)
        add(placed(selection.originals, selection.frame).map { it.applying(shift) })
    }

    fun recolorSelection(argb: Int) {
        val model = model ?: return
        val selection = selection ?: return
        val ids = selection.ids.toSet()
        // Cambia solo il colore: la forma di un tratto pulito resta.
        commit(model.strokes.map { if (it.id in ids) it.copy(color = argb) else it })
        this.selection = selection.copy(originals = selection.originals.map { it.copy(color = argb) })
        surface.invalidate()
        showSelectionMenu()
    }

    fun paste() {
        val point = pastePoint ?: return
        val strokes = NotebookModel.clipboard
        var bounds = Rect.NULL
        for (s in strokes) bounds = bounds.union(s.bounds)
        if (strokes.isEmpty() || bounds.isNull) return
        deselect()
        add(strokes.map { it.applying(AffineTransform.translation(point.x - bounds.midX, point.y - bounds.midY)) })
    }

    /// Mette dei tratti sopra la pagina e, con il lazo in mano, li seleziona.
    private fun add(strokes: List<InkStroke>) {
        val model = model ?: return
        val added = strokes.map { it.copy(id = model.newID()) }
        commit(model.strokes + added)
        if (model.tools.current == DrawingTool.LASSO) selectStrokes(added) else deselect()
    }

    // Disegno

    private inner class Surface(context: Context) : View(context) {
        private val paperPaint = Paint().apply {
            color = Color.rgb(209, 209, 214)
            strokeWidth = 1f
            isAntiAlias = false
        }
        private val accent = Color.rgb(30, 111, 224)
        private val dashed = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            color = accent
            strokeWidth = 1.5f * density
            pathEffect = DashPathEffect(floatArrayOf(6 * density, 4 * density), 0f)
            strokeJoin = Paint.Join.ROUND
        }
        private val loopFill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(15, 30, 111, 224) }
        private val gripFill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
        private val gripStroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            color = accent
            strokeWidth = 1.5f * density
        }
        private val preview = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        private val eraserPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            color = Color.GRAY
            strokeWidth = 1f * density
            pathEffect = DashPathEffect(floatArrayOf(3 * density, 3 * density), 0f)
        }

        override fun onDraw(canvas: Canvas) {
            canvas.drawColor(Color.WHITE)
            drawPaper(canvas)
            val model = model ?: return
            val selection = selection
            val lifted = if (selection != null && lassoDrag != null && lassoDrag !is LassoDrag.Loop) selection.ids.toSet() else emptySet()
            val reshaping = if (shapeDrag != null) editing?.id else null
            for (stroke in model.strokes) {
                if (stroke.id in lifted || stroke.id == reshaping) continue
                cache.draw(canvas, stroke, worldToScreen)
            }
            // I tratti presi dal lazo seguono il riquadro mentre si trascina.
            if (selection != null && lifted.isNotEmpty()) {
                val frame = currentFrame() ?: selection.frame
                val m = toMatrix(frame.transform).apply { postConcat(worldToScreen) }
                for (stroke in selection.originals) cache.draw(canvas, stroke, m)
            }
            // La forma che segue la punta, o quella che si sta rimodellando.
            previewShape?.let { drawShape(canvas, it, strokeColor, strokeWidth) }
            if (reshaping != null) {
                val e = editing
                val d = dragged
                if (e != null && d != null) drawShape(canvas, d, e.stroke.color, e.stroke.width)
            }
            val a = rulerStart
            val b = rulerEnd
            if (a != null && b != null) drawShape(canvas, InkShape.Line(a, b), strokeColor, strokeWidth)
            drawLasso(canvas)
            drawShapeGrips(canvas)
            if (penMode == PenMode.ERASE) {
                penAt?.let { canvas.drawCircle(it.x, it.y, (EraserSizes.width(model.tools) / 2).toFloat() * scale, eraserPaint) }
            }
        }

        private fun drawPaper(canvas: Canvas) {
            if (paper == PaperStyle.BLANK) return
            val step = PAPER_STEP * scale
            var y = floor(scrollPx.y / step) * step - scrollPx.y
            while (y <= height) {
                canvas.drawLine(0f, y, width.toFloat(), y, paperPaint)
                y += step
            }
            if (paper == PaperStyle.GRID) {
                var x = floor(scrollPx.x / step) * step - scrollPx.x
                while (x <= width) {
                    canvas.drawLine(x, 0f, x, height.toFloat(), paperPaint)
                    x += step
                }
            }
        }

        private fun drawShape(canvas: Canvas, shape: InkShape, argb: Int, width: Float) {
            val path = Path()
            shape.outline(4.0).forEachIndexed { i, p ->
                val s = toScreen(p)
                if (i == 0) path.moveTo(s.x, s.y) else path.lineTo(s.x, s.y)
            }
            preview.color = argb
            preview.strokeWidth = width * scale
            canvas.drawPath(path, preview)
        }

        private fun drawLasso(canvas: Canvas) {
            (lassoDrag as? LassoDrag.Loop)?.let { loop ->
                val path = polygon(loop.points)
                canvas.drawPath(path, loopFill)
                canvas.drawPath(path, dashed)
            }
            val frame = currentFrame() ?: return
            canvas.drawPath(polygon(frame.corners), dashed)
            val gap = reach(ROTATION_GAP_DP)
            val top = toScreen(frame.position(SelectionHandle.TOP, gap))
            val knob = toScreen(frame.position(SelectionHandle.ROTATE, gap))
            canvas.drawLine(top.x, top.y, knob.x, knob.y, gripStroke)
            for (handle in SelectionHandle.entries) {
                val c = toScreen(frame.position(handle, gap))
                val radius = (if (handle == SelectionHandle.ROTATE) GRIP_RADIUS_DP + 2 else GRIP_RADIUS_DP) * density
                canvas.drawCircle(c.x, c.y, radius, gripFill)
                canvas.drawCircle(c.x, c.y, radius, gripStroke)
            }
        }

        private fun drawShapeGrips(canvas: Canvas) {
            val editing = editing ?: return
            val shape = dragged ?: editing.shape
            for (grip in shape.grips) {
                val c = toScreen(grip)
                canvas.drawCircle(c.x, c.y, SHAPE_GRIP_RADIUS_DP * density, gripFill)
                canvas.drawCircle(c.x, c.y, SHAPE_GRIP_RADIUS_DP * density, gripStroke)
            }
        }

        private fun polygon(points: List<Point>): Path {
            val path = Path()
            points.forEachIndexed { i, p ->
                val s = toScreen(p)
                if (i == 0) path.moveTo(s.x, s.y) else path.lineTo(s.x, s.y)
            }
            path.close()
            return path
        }
    }

    private fun toMatrix(t: AffineTransform) = Matrix().apply {
        setValues(floatArrayOf(t.a.toFloat(), t.c.toFloat(), t.tx.toFloat(), t.b.toFloat(), t.d.toFloat(), t.ty.toFloat(), 0f, 0f, 1f))
    }

    companion object {
        const val MAX_ZOOM = 4f
        /// La distanza tra le righe stampate, nelle unità del quaderno.
        const val PAPER_STEP = 28f
        private const val HOLD_MS = 500L
        /// Movimenti più piccoli contano ancora come penna ferma.
        private const val STILLNESS_DP = 4f
        private const val GRIP_RADIUS_DP = 6f
        private const val GRIP_REACH_DP = 26f
        private const val ROTATION_GAP_DP = 30f
        private const val DUPLICATE_OFFSET = 24.0
        private const val SHAPE_GRIP_RADIUS_DP = 7f
        private const val LINE_REACH_DP = 14f

    }
}
