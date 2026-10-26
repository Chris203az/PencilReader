package it.pencilreader.render

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import android.media.ExifInterface
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/// Trasforma foto e pagine PDF in bitmap dritte, pronte per l'OCR e per lo schermo.
object PageImages {
    /// Come su iPad: OCR e schermo usano la stessa griglia di pixel.
    const val MAX_DIMENSION = 2600

    fun pdfPageCount(file: File): Int = try {
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
            PdfRenderer(fd).use { it.pageCount }
        }
    } catch (_: Exception) {
        0
    }

    /// Una pagina sola, con un renderer aperto per l'occasione (per la copertina all'importazione).
    fun renderPdfPage(file: File, index: Int, maxDimension: Int): Bitmap? = try {
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
            PdfRenderer(fd).use { renderer -> render(renderer, index, maxDimension) }
        }
    } catch (_: Exception) {
        null
    }

    /// La pagina su fondo bianco, con il lato lungo di `maxDimension` pixel. Il renderer non è
    /// thread-safe: chi lo condivide deve sincronizzarsi.
    fun render(renderer: PdfRenderer, index: Int, maxDimension: Int): Bitmap? {
        if (index !in 0 until renderer.pageCount) return null
        renderer.openPage(index).use { page ->
            val scale = maxDimension.toFloat() / max(page.width, page.height)
            val width = max(1, (page.width * scale).roundToInt())
            val height = max(1, (page.height * scale).roundToInt())
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(Color.WHITE)
            val matrix = Matrix().apply { setScale(width.toFloat() / page.width, height.toFloat() / page.height) }
            page.render(bitmap, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            return bitmap
        }
    }

    /// Un'immagine scelta dall'utente, girata secondo i dati EXIF e con il lato lungo al più `maxDimension`.
    fun decodeUpright(resolver: ContentResolver, uri: Uri, maxDimension: Int): Bitmap? {
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) } ?: return null
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
            var sample = 1
            while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxDimension) sample *= 2
            val options = BitmapFactory.Options().apply { inSampleSize = sample }
            val decoded = resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) } ?: return null
            val orientation = try {
                resolver.openInputStream(uri)?.use {
                    ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
                } ?: ExifInterface.ORIENTATION_NORMAL
            } catch (_: Exception) {
                ExifInterface.ORIENTATION_NORMAL
            }
            val matrix = Matrix()
            when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> { matrix.postRotate(90f); matrix.postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_TRANSVERSE -> { matrix.postRotate(270f); matrix.postScale(-1f, 1f) }
            }
            val longest = max(decoded.width, decoded.height)
            val scale = min(1f, maxDimension.toFloat() / longest)
            if (scale < 1f) matrix.postScale(scale, scale)
            if (matrix.isIdentity) return decoded
            val upright = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
            if (upright != decoded) decoded.recycle()
            upright
        } catch (_: Exception) {
            null
        }
    }

    /// Una copia rimpicciolita con il lato lungo di `maxDimension` pixel (mai ingrandita).
    fun scaled(bitmap: Bitmap, maxDimension: Int): Bitmap {
        val scale = min(1f, maxDimension.toFloat() / max(bitmap.width, bitmap.height))
        if (scale >= 1f) return bitmap
        return Bitmap.createScaledBitmap(
            bitmap, max(1, (bitmap.width * scale).roundToInt()), max(1, (bitmap.height * scale).roundToInt()), true,
        )
    }
}

/// Le pagine di un documento come bitmap, da un PDF o da una cartella di JPEG.
/// Ogni utente (la pagina sullo schermo, l'OCR, le miniature) ne apre una sua,
/// perché PdfRenderer apre una pagina alla volta.
class PageSource(private val pdf: File?, private val pagesFolder: File?) : AutoCloseable {
    private var descriptor: ParcelFileDescriptor? = null
    private var renderer: PdfRenderer? = null
    private val lock = Any()

    /// Da chiamare fuori dal thread principale.
    fun render(index: Int, maxDimension: Int = PageImages.MAX_DIMENSION): Bitmap? = synchronized(lock) {
        try {
            if (pdf != null) {
                if (renderer == null) {
                    val fd = ParcelFileDescriptor.open(pdf, ParcelFileDescriptor.MODE_READ_ONLY)
                    descriptor = fd
                    renderer = PdfRenderer(fd)
                }
                renderer?.let { PageImages.render(it, index, maxDimension) }
            } else {
                val folder = pagesFolder ?: return null
                decodeFile(File(folder, String.format(java.util.Locale.ROOT, "%04d.jpg", index)), maxDimension)
            }
        } catch (_: Exception) {
            null
        }
    }

    override fun close() = synchronized(lock) {
        try {
            renderer?.close()
            descriptor?.close()
        } catch (_: Exception) {
        }
        renderer = null
        descriptor = null
    }

    companion object {
        fun decodeFile(file: File, maxDimension: Int): Bitmap? {
            if (!file.isFile) return null
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.path, bounds)
            if (bounds.outWidth <= 0) return null
            var sample = 1
            while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxDimension) sample *= 2
            val bitmap = BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
            return PageImages.scaled(bitmap, maxDimension)
        }
    }
}
