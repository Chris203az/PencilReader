package it.pencilreader.reader

import android.graphics.Bitmap
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DocumentScanner
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.AwaitPointerEventScope
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.PointerType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import it.pencilreader.core.PageText
import it.pencilreader.core.Point
import it.pencilreader.study.StudyMark
import it.pencilreader.study.StudyModel
import it.pencilreader.study.StudyTool
import it.pencilreader.study.StudyToolbar
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import androidx.compose.ui.geometry.Rect as UiRect
import it.pencilreader.core.Rect as CoreRect

private const val MAX_ZOOM = 5f
private const val DOUBLE_TAP_ZOOM = 2.5f
private val LassoOrange = Color(0xFFFF9500)

/// Una pagina: l'immagine, i riquadri delle parole, i segni di studio, il lazo della penna e la scheda
/// della traduzione. Con il dito si sfoglia (scorrimento orizzontale), si esce (scorrimento in basso),
/// si ingrandisce (pizzico o doppio tocco) e, ingranditi, si sposta la pagina. La penna cerchia le parole;
/// in modalità studio segna la pagina, e gli strumenti di studio galleggiano sopra il fondo.
@Composable
fun PageView(model: ReaderModel, study: StudyModel, onExit: () -> Unit, modifier: Modifier = Modifier) {
    val density = LocalDensity.current
    val margin = with(density) { 12.dp.toPx() }
    val panelWidthPx = with(density) { 380.dp.toPx() }
    val swipeDistance = with(density) { 60.dp.toPx() }
    val touchSlop = LocalViewConfiguration.current.touchSlop
    val scope = rememberCoroutineScope()

    /// 1 = la pagina adattata allo schermo.
    var zoom by remember { mutableStateOf(1f) }
    /// La distanza del centro della pagina ingrandita dal centro della pagina adattata.
    var offset by remember { mutableStateOf(Offset.Zero) }
    var panelHeight by remember { mutableStateOf(220f) }
    val strokePoints = remember { mutableStateListOf<Offset>() }
    var strokeKind by remember { mutableStateOf<StudyTool?>(null) }
    val lassoAlpha = remember { Animatable(1f) }

    LaunchedEffect(model.pageIndex) {
        zoom = 1f
        offset = Offset.Zero
    }

    val bitmap = model.pageImage
    val image: ImageBitmap? = remember(bitmap) { bitmap?.asImageBitmap() }

    BoxWithConstraints(
        modifier
            .fillMaxSize()
            .clipToBounds()
            .padding(0.dp),
    ) {
        val size = Size(constraints.maxWidth.toFloat(), constraints.maxHeight.toFloat())
        val base = fit(bitmap, UiRect(margin, margin, size.width - margin, size.height - margin))
        val frame = zoomed(base, zoom, offset, size, margin)

        fun store(newFrame: UiRect) {
            zoom = newFrame.width / base.width
            offset = Offset(newFrame.center.x - base.center.x, newFrame.center.y - base.center.y)
        }

        /// Ingrandisce la pagina tenendo fermo `center`, un punto dello schermo.
        fun zoomBy(scale: Float, center: Offset) {
            val current = zoomed(base, zoom, offset, size, margin)
            val s = min(max(zoom * scale, 1f), MAX_ZOOM) / zoom
            val scaled = UiRect(
                center.x - (center.x - current.left) * s,
                center.y - (center.y - current.top) * s,
                center.x - (center.x - current.left) * s + current.width * s,
                center.y - (center.y - current.top) * s + current.height * s,
            )
            val newZoom = scaled.width / base.width
            val newOffset = Offset(scaled.center.x - base.center.x, scaled.center.y - base.center.y)
            store(zoomed(base, newZoom, newOffset, size, margin))
        }

        val currentFrame by rememberUpdatedState(frame)
        val currentZoom by rememberUpdatedState(zoom)
        val zoomByState by rememberUpdatedState(::zoomBy)
        val panBy by rememberUpdatedState { delta: Offset ->
            store(zoomed(base, zoom, offset + delta, size, margin))
        }
        val text by rememberUpdatedState(model.pageText)
        val allowsFinger by rememberUpdatedState(model.allowsFingerDrawing && !study.isActive)
        val studying by rememberUpdatedState(study.isActive)
        val studyTool by rememberUpdatedState(study.tool)

        Canvas(
            Modifier
                .fillMaxSize()
                .pointerInput(model, study) {
                    awaitEachGesture {
                        val down = awaitFirstDown(requireUnconsumed = false)
                        val isPen = down.type == PointerType.Stylus || down.type == PointerType.Eraser
                        if (isPen || (allowsFinger && down.type == PointerType.Touch)) {
                            // La penna (o il dito, se permesso) disegna: in modalità studio segna, altrimenti cerchia.
                            val erasing = studying && (studyTool == StudyTool.Eraser || down.type == PointerType.Eraser)
                            val pageFrame = currentFrame
                            val toPage = { o: Offset -> pagePoint(o, pageFrame) }
                            scope.launch { lassoAlpha.snapTo(1f) }
                            strokePoints.clear()
                            strokeKind = if (studying && !erasing) studyTool else null
                            if (erasing) study.beginErasing()
                            val radius = 10.0
                            strokePoints.add(down.position)
                            if (erasing) study.erase(toPage(down.position), radius)
                            down.consume()
                            var cancelled = false
                            while (true) {
                                val event = awaitPointerEvent()
                                val change = event.changes.firstOrNull { it.id == down.id }
                                if (change == null) {
                                    cancelled = true
                                    break
                                }
                                if (change.pressed) {
                                    strokePoints.add(change.position)
                                    if (erasing) study.erase(toPage(change.position), radius)
                                    change.consume()
                                } else {
                                    change.consume()
                                    break
                                }
                            }
                            val points = strokePoints.toList()
                            if (cancelled || erasing) {
                                strokePoints.clear()
                            } else if (studying) {
                                strokePoints.clear()
                                val pageHeight = StudyModel.PAGE_WIDTH * pageFrame.height / pageFrame.width
                                study.addStroke(points.map(toPage), pageHeight, text)
                            } else {
                                model.select(points.map { Point(it.x.toDouble(), it.y.toDouble()) }, pageFrame.toCore())
                                // Il segno del lazo resta un attimo e poi svanisce.
                                scope.launch {
                                    delay(400)
                                    lassoAlpha.animateTo(0f, tween(400))
                                    strokePoints.clear()
                                    lassoAlpha.snapTo(1f)
                                }
                            }
                            strokeKind = null
                        } else {
                            fingerGesture(
                                down, touchSlop, swipeDistance,
                                isZoomed = { currentZoom > 1f },
                                allowsSwipes = { !allowsFinger },
                                onZoom = { s, c -> zoomByState(s, c) },
                                onZoomEnded = { if (currentZoom < 1.05f) { zoom = 1f; offset = Offset.Zero } },
                                onPan = { panBy(it) },
                                onTap = { model.clearSelection() },
                                onDoubleTap = { p ->
                                    if (currentZoom > 1f) {
                                        zoom = 1f
                                        offset = Offset.Zero
                                    } else {
                                        zoomByState(DOUBLE_TAP_ZOOM, p)
                                    }
                                },
                                onSwipe = { direction ->
                                    when (direction) {
                                        SwipeDirection.LEFT -> model.nextPage()
                                        SwipeDirection.RIGHT -> model.previousPage()
                                        SwipeDirection.DOWN -> onExit()
                                    }
                                },
                            )
                        }
                    }
                },
        ) {
            if (image != null) {
                drawRect(Color.Black.copy(alpha = 0.08f), frame.topLeft + Offset(0f, 2f), frame.size)
                drawImage(
                    image,
                    srcOffset = IntOffset.Zero,
                    srcSize = IntSize(image.width, image.height),
                    dstOffset = IntOffset(frame.left.roundToInt(), frame.top.roundToInt()),
                    dstSize = IntSize(frame.width.roundToInt(), frame.height.roundToInt()),
                    filterQuality = FilterQuality.High,
                )
                drawStudyMarks(study.marks, frame)
                drawWordBoxes(model.pageText, frame, model.showWordBoxes, model.selection?.wordIDs?.toSet() ?: emptySet(), model.searchHighlightOnPage)
            }
            if (strokePoints.size > 1) {
                val path = Path().apply {
                    moveTo(strokePoints[0].x, strokePoints[0].y)
                    for (i in 1 until strokePoints.size) lineTo(strokePoints[i].x, strokePoints[i].y)
                }
                val kind = strokeKind
                val unit = frame.width / StudyModel.PAGE_WIDTH.toFloat()
                when (kind) {
                    null -> {
                        val a = lassoAlpha.value
                        drawPath(path, LassoOrange.copy(alpha = 0.08f * a), style = Fill)
                        drawPath(path, LassoOrange.copy(alpha = a), style = Stroke(3.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
                    }
                    is StudyTool.Highlighter -> drawPath(
                        path, Color(kind.color.argb).copy(alpha = StudyTool.HIGHLIGHT_ALPHA),
                        style = Stroke(StudyTool.HIGHLIGHT_WIDTH * unit, cap = StrokeCap.Round, join = StrokeJoin.Round),
                        blendMode = BlendMode.Multiply,
                    )
                    StudyTool.Underline -> drawPath(
                        path, Color(StudyTool.UNDERLINE_COLOR),
                        style = Stroke(StudyTool.UNDERLINE_WIDTH * unit, cap = StrokeCap.Round, join = StrokeJoin.Round),
                    )
                    StudyTool.Pen, StudyTool.Eraser -> drawPath(
                        path, Color(StudyTool.PEN_COLOR),
                        style = Stroke(StudyTool.PEN_WIDTH * unit, cap = StrokeCap.Round, join = StrokeJoin.Round),
                    )
                }
            }
        }

        if (bitmap == null) {
            CircularProgressIndicator(Modifier.align(Alignment.Center))
        }

        model.selection?.let { selection ->
            val width = min(panelWidthPx, size.width - 2 * margin)
            val anchor = selection.anchor.denormalized(frame.toCore())
            val center = panelCenter(anchor, width, panelHeight, size, margin)
            TranslationPanel(
                selection,
                onClose = model::clearSelection,
                modifier = Modifier
                    .offset { IntOffset((center.x - width / 2).roundToInt(), (center.y - panelHeight / 2).roundToInt()) }
                    .width(with(density) { width.toDp() })
                    .onSizeChanged { panelHeight = it.height.toFloat() },
            )
        }

        if (study.isActive) {
            StudyToolbar(study, Modifier.align(Alignment.BottomCenter).padding(bottom = 20.dp, start = 12.dp, end = 12.dp))
        }

        if (model.isRecognizing) {
            Surface(
                shape = RoundedCornerShape(50),
                tonalElevation = 4.dp,
                shadowElevation = 4.dp,
                modifier = Modifier.align(Alignment.TopCenter).padding(top = 12.dp),
            ) {
                Row(Modifier.padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.DocumentScanner, null, Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Riconoscimento testo…", style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
    }
}

enum class SwipeDirection { LEFT, RIGHT, DOWN }

/// I gesti del dito: pizzico e trascinamento insieme, tocco, doppio tocco e scorrimenti rapidi.
private suspend fun AwaitPointerEventScope.fingerGesture(
    down: PointerInputChange,
    touchSlop: Float,
    swipeDistance: Float,
    isZoomed: () -> Boolean,
    allowsSwipes: () -> Boolean,
    onZoom: (Float, Offset) -> Unit,
    onZoomEnded: () -> Unit,
    onPan: (Offset) -> Unit,
    onTap: () -> Unit,
    onDoubleTap: (Offset) -> Unit,
    onSwipe: (SwipeDirection) -> Unit,
) {
    val start = down.position
    val startTime = down.uptimeMillis
    var last = start
    var lastTime = startTime
    var moved = false
    var multi = false
    while (true) {
        val event = awaitPointerEvent()
        val pressed = event.changes.filter { it.pressed && it.type != PointerType.Stylus }
        if (pressed.isEmpty()) {
            event.changes.firstOrNull { it.id == down.id }?.let {
                last = it.position
                lastTime = it.uptimeMillis
            }
            break
        }
        if (pressed.size >= 2) {
            multi = true
            moved = true
            val zoomChange = event.calculateZoom()
            val pan = event.calculatePan()
            val centroid = event.calculateCentroid(useCurrent = true)
            if (zoomChange != 1f) onZoom(zoomChange, centroid)
            if (pan != Offset.Zero) onPan(pan)
            event.changes.forEach { it.consume() }
        } else if (!multi) {
            val change = pressed[0]
            if ((change.position - start).getDistance() > touchSlop) moved = true
            if (moved && isZoomed()) {
                onPan(change.positionChange())
                change.consume()
            }
            last = change.position
            lastTime = change.uptimeMillis
        }
    }
    if (multi) {
        onZoomEnded()
        return
    }
    val duration = lastTime - startTime
    if (!moved && duration < 350) {
        // Un tocco: aspetta un attimo per vedere se è un doppio tocco.
        val second = withTimeoutOrNull(280) { awaitFirstDown(requireUnconsumed = false) }
        if (second == null || second.type == PointerType.Stylus) {
            onTap()
            return
        }
        val position = second.position
        while (true) {
            val event = awaitPointerEvent()
            if (event.changes.none { it.pressed }) break
        }
        onDoubleTap(position)
        return
    }
    if (!moved || isZoomed() || !allowsSwipes() || duration > 700) return
    val dx = last.x - start.x
    val dy = last.y - start.y
    when {
        abs(dx) > swipeDistance && abs(dx) > 1.5f * abs(dy) -> onSwipe(if (dx < 0) SwipeDirection.LEFT else SwipeDirection.RIGHT)
        dy > swipeDistance * 1.3f && dy > 1.5f * abs(dx) -> onSwipe(SwipeDirection.DOWN)
    }
}

// Geometria della pagina sullo schermo

private fun fit(bitmap: Bitmap?, rect: UiRect): UiRect {
    val w = bitmap?.width?.toFloat() ?: return rect
    val h = bitmap.height.toFloat()
    if (w <= 0 || h <= 0 || rect.width <= 0 || rect.height <= 0) return rect
    val scale = min(rect.width / w, rect.height / h)
    val sw = w * scale
    val sh = h * scale
    return UiRect(rect.center.x - sw / 2, rect.center.y - sh / 2, rect.center.x + sw / 2, rect.center.y + sh / 2)
}

/// La pagina sullo schermo; i suoi bordi non entrano mai dentro i margini dello schermo,
/// e resta centrata lungo un lato dove è più piccola dello schermo.
private fun zoomed(base: UiRect, zoom: Float, offset: Offset, size: Size, margin: Float): UiRect {
    if (zoom <= 1f) return base
    val w = base.width * zoom
    val h = base.height * zoom
    fun clamp(origin: Float, length: Float, available: Float): Float {
        val inner = available - 2 * margin
        if (length <= inner) return margin + (inner - length) / 2
        return min(margin, max(available - margin - length, origin))
    }
    val x = clamp(base.center.x - w / 2 + offset.x, w, size.width)
    val y = clamp(base.center.y - h / 2 + offset.y, h, size.height)
    return UiRect(x, y, x + w, y + h)
}

/// Sotto il lazo se ci sta, altrimenti sopra; sempre sullo schermo.
private fun panelCenter(anchor: CoreRect, width: Float, height: Float, size: Size, margin: Float): Offset {
    val half = width / 2
    val x = min(max(anchor.midX.toFloat(), half + margin), size.width - half - margin)
    val below = anchor.maxY.toFloat() + 16 + height / 2
    val above = anchor.minY.toFloat() - 16 - height / 2
    val y = when {
        below + height / 2 <= size.height - margin -> below
        above - height / 2 >= margin -> above
        else -> size.height - margin - height / 2
    }
    return Offset(x, y)
}

private fun UiRect.toCore() = CoreRect(left.toDouble(), top.toDouble(), width.toDouble(), height.toDouble())

/// Da un punto dello schermo alle unità della pagina dei segni di studio.
private fun pagePoint(o: Offset, frame: UiRect): Point {
    val unit = StudyModel.PAGE_WIDTH / frame.width
    return Point((o.x - frame.left) * unit, (o.y - frame.top) * unit)
}

// Disegno

/// I segni di studio, moltiplicati sulla pagina come un evidenziatore vero: il testo sotto resta nero.
fun DrawScope.drawStudyMarks(marks: List<StudyMark>, frame: UiRect) {
    val unit = frame.width / StudyModel.PAGE_WIDTH.toFloat()
    for (mark in marks) {
        if (mark.points.isEmpty()) continue
        val path = Path()
        val first = mark.points[0]
        path.moveTo(frame.left + first.x * unit, frame.top + first.y * unit)
        if (mark.points.size == 1) path.lineTo(frame.left + first.x * unit + 0.01f, frame.top + first.y * unit)
        for (i in 1 until mark.points.size) {
            val p = mark.points[i]
            path.lineTo(frame.left + p.x * unit, frame.top + p.y * unit)
        }
        val highlight = mark.kind == StudyMark.Kind.HIGHLIGHT
        drawPath(
            path,
            Color(mark.argb).copy(alpha = if (highlight) StudyTool.HIGHLIGHT_ALPHA else 1f),
            style = Stroke(mark.width * unit, cap = StrokeCap.Round, join = StrokeJoin.Round),
            blendMode = if (highlight) BlendMode.Multiply else BlendMode.SrcOver,
        )
    }
}

/// Le parole selezionate e i risultati della ricerca; con i riquadri OCR attivi, anche ogni parola riconosciuta.
private fun DrawScope.drawWordBoxes(text: PageText?, frame: UiRect, showAll: Boolean, selected: Set<Int>, found: Set<Int>) {
    text ?: return
    val core = frame.toCore()
    for (word in text.words) {
        val r = word.rect.denormalized(core)
        val padded = Offset(r.minX.toFloat() - 2, r.minY.toFloat() - 1)
        val paddedSize = Size(r.width.toFloat() + 4, r.height.toFloat() + 2)
        if (word.id in found) drawRoundRect(LassoOrange.copy(alpha = 0.35f), padded, paddedSize, CornerRadius(3f, 3f))
        if (word.id in selected) drawRoundRect(Color(0xFFFFD60A).copy(alpha = 0.4f), padded, paddedSize, CornerRadius(3f, 3f))
        if (showAll) {
            drawRect(
                Color(0xFF34C759).copy(alpha = 0.8f),
                Offset(r.minX.toFloat(), r.minY.toFloat()),
                Size(r.width.toFloat(), r.height.toFloat()),
                style = Stroke(0.75f),
            )
        }
    }
}

