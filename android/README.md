# PencilReader per Android

Versione Android nativa di PencilReader, pensata per i tablet con penna attiva (S Pen, USI, Wacom…): si cerchia una parola con la penna e compare la traduzione italiana dell'intera frase, con evidenziate le parole cerchiate. Riconoscimento del testo e traduzione girano sul dispositivo.

È scritta in Kotlin con Jetpack Compose; il quaderno usa androidx.ink per disegnare il tratto in corso con la latenza più bassa.

## Struttura

- `core/`: la logica pura, in Kotlin senza Android, portata fedelmente da `ReaderCore` (lazo sulle parole, testo della pagina e frasi, evidenziazione della traduzione, ricerca, parole salvate, riconoscimento delle forme e loro modifica, levigatura dei tratti, lazo del quaderno, strumenti, segni di studio). I test JUnit sono portati da `ReaderCore/Tests`.
- `app/`: l'app Android (Compose, PdfRenderer, ML Kit, androidx.ink).

## Aprire in Android Studio

1. Serve una versione recente di Android Studio (con supporto ad Android Gradle Plugin 8.13) e il JDK 17, che Android Studio include.
2. *File → Open* e scegliere la cartella `android/` (non la radice del repository).
3. Al primo avvio Android Studio scarica Gradle 8.14.3, il plugin Android e le librerie, e chiede di installare la piattaforma Android 36 se manca. Il file `local.properties` con il percorso dell'SDK lo crea Android Studio e non va messo nel repository.

## Compilare

Da terminale, nella cartella `android/`:

```bash
./gradlew :core:test           # i test della logica pura
./gradlew :app:assembleDebug   # l'APK di debug
```

L'APK finisce in `app/build/outputs/apk/debug/app-debug.apk`.

I test della logica pura si possono eseguire anche senza Android SDK e senza Google Maven, perché `core/` ha un suo `settings.gradle.kts`:

```bash
./gradlew -p core test
```

## Installare su un tablet

1. Sul tablet: *Impostazioni → Info sul tablet → Informazioni software*, toccare sette volte *Numero build* per attivare le opzioni sviluppatore, poi attivare *Debug USB*.
2. Collegare il tablet con il cavo e accettare la richiesta di autorizzazione.
3. Da Android Studio premere *Run*, oppure da terminale:

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Serve Android 10 (API 29) o successivo.

## Funzioni incluse

- **Libreria con raccolte**: crea, rinomina ed elimina raccolte (i libri vengono spostati, mai cancellati); sposta, rinomina ed elimina documenti; avanzamento della lettura per libro.
- **Importazione** di PDF e di immagini tramite lo Storage Access Framework (file del dispositivo, Drive, schede SD…). Le foto vengono girate secondo i dati EXIF.
- **Lettura**: pagine PDF disegnate con PdfRenderer; zoom con il pizzico (fino a 5x) e con il doppio tocco (2,5x); scorrimento orizzontale per girare pagina, verso il basso per tornare alla libreria.
- **Traduzione cerchiando con la penna**: ML Kit Text Recognition (modello latino incluso nell'app) riconosce la pagina una volta sola e salva il risultato; il lazo sceglie le parole come sull'iPad; ML Kit Translate traduce in italiano il termine, la frase e la frase con il termine tra virgolette, e la traduzione delle parole cerchiate viene evidenziata nella frase.
- **Riconoscimento di tutto il libro in sottofondo**, con avanzamento, coda e interruzione; lo schermo resta acceso mentre lavora.
- **Ricerca nel libro** nel testo riconosciuto, senza distinguere maiuscole e accenti; un risultato apre la pagina con le parole evidenziate.
- **Parole cercate** salvate per libro, filtrabili, esportabili in un file di testo (condivisione, salvataggio con il selettore di file, copia).
- **Griglia delle pagine** con miniature veloci, tenute in memoria e su disco, preparate in sottofondo mentre il libro è aperto; segnala le pagine con note e con segni di studio.
- **Quaderno accanto alla pagina**, una nota per pagina del libro, con divisore trascinabile:
  - barra degli strumenti in alto o in basso, con elementi da mostrare, nascondere e riordinare;
  - penna, matita, evidenziatore, gomma a tratti interi o a pixel con la sua grandezza, lazo, righello (linee dritte), campioni di colore modificabili tenendoli premuti, spessori;
  - con il dito: scorrimento a destra = Annulla, a sinistra = Ripristina, pizzico per lo zoom (fino a 4x), doppio tocco per tornare a 1x;
  - forme automatiche: tenendo ferma la penna alla fine di un tratto diventa una linea, un poligono, un'ellisse, un arco o una curva pulita, che segue la punta finché la penna si alza; un tocco del dito sulla linea di una forma mostra le maniglie per rimodellarla;
  - lazo come in GoodNotes: sposta, ridimensiona (angoli in proporzione, lati in un verso), ruota con aggancio ai quarti di giro, menu sotto la selezione con Copia, Taglia, Duplica, Elimina, Cambia colore; tenendo premuto sulla carta compare Incolla;
  - levigatura automatica dei tratti, intensità da 1 a 4 (predefinita 3);
  - carta a quadretti, a righe o bianca.
- **Modalità studio** sopra la pagina: evidenziatori arancione (concetto chiave), azzurro (formula / dato) e rosa (da rivedere), sottolineatura dei termini inglesi che si raddrizza da sola, penna per le note a margine, gomma, Annulla e la guida al metodo. L'evidenziatore si aggancia a una riga di testo alla volta e ripassare con lo stesso colore non lo scurisce (unione delle evidenziature, spessore pari a 0,85 volte l'altezza della riga). I segni restano visibili anche a modalità spenta e sono salvati per libro e pagina, separati dalle note del quaderno.

Si scrive e si cerchia solo con la penna (`TOOL_TYPE_STYLUS`); le dita scorrono e ingrandiscono. Nel menu *Altro* del lettore, *Disegna col dito* permette di provare il lazo anche senza penna (per esempio sull'emulatore).

## Escluse, come richiesto

Segnalibri, ripasso delle parole (flashcard), riepilogo delle evidenziature, esportazione in PDF, modalità notte, timer di studio, ritaglio dello schermo nelle note, riordino della scrittura.

## Differenze dall'iPad

- **Modello di traduzione**: alla prima parola cerchiata l'app scarica il modello inglese → italiano di ML Kit (circa 30 MB, serve la rete; la scheda lo dice). Dopo funziona offline. Il riconoscimento del testo invece non scarica niente, perché il modello latino è incluso nell'app.
- **OCR**: ML Kit al posto di Vision. Non ci sono le parole tecniche aggiunte al correttore di Vision, e i risultati possono differire un po' sulle scansioni difficili.
- **Niente scanner di documenti e niente raddrizzamento della prospettiva** delle foto: si importano immagini già scattate.
- **Niente dizionario di sistema** nella scheda della traduzione (resta Copia).
- **Doppio tocco della Apple Pencil**: al suo posto, il tasto laterale della penna (o la punta gomma, sulle penne che ce l'hanno) fa da gomma finché lo si tiene premuto.
- **Matita**: androidx.ink 1.0 non ha un pennello a matita; la matita usa il pennello `marker`, un po' più chiaro della penna.
- **Righello**: semplificato, ogni tratto diventa una linea dritta dal punto di partenza a quello d'arrivo (non c'è un righello da posizionare).
- **Modalità studio**: i segni sono disegnati con Compose sopra la pagina (moltiplicati sull'immagine, come sull'iPad); il tratto in corso non passa da androidx.ink.
- **Dati**: tutto sta nella memoria privata dell'app (`files/Libreria`, `files/Notes`, `files/Annotations`, preferenze in SharedPreferences), in JSON con kotlinx.serialization. Su Android non è visibile nell'app File, quindi non si copia a mano come backup; il backup automatico di Android è attivo. I file dell'iPad non sono compatibili con quelli di Android (le note di PencilKit non hanno un equivalente).
- **Menu**: i menu contestuali dell'iPad diventano menu a comparsa (tenendo premuto un libro nella libreria) e popup sopra il foglio.
