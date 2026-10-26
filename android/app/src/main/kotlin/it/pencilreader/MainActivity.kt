package it.pencilreader

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import it.pencilreader.library.LibraryScreen
import it.pencilreader.reader.ReaderScreen
import it.pencilreader.ui.PencilReaderTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = application as PencilReaderApp
        setContent {
            PencilReaderTheme {
                AppRoot(app)
                // Lo schermo non si spegne mentre si riconosce un libro intero: il sistema sospenderebbe l'app.
                val running = app.recognizer.isRunning
                LaunchedEffect(running) {
                    if (running) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
            }
        }
    }
}

/// La libreria, e sopra di essa il libro aperto.
@Composable
fun AppRoot(app: PencilReaderApp) {
    var openID by rememberSaveable { mutableStateOf<String?>(null) }
    val document = openID?.let { app.library.document(it) }
    if (document == null) {
        LibraryScreen(app, open = { openID = it.id })
    } else {
        BackHandler { openID = null }
        ReaderScreen(app, document, close = { openID = null }, openOther = { openID = it })
    }
}
