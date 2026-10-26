# PencilReader

App per iPad per studiare sui libri tecnici in inglese (PDF e scansioni) con la Apple Pencil: si cerchia una parola e compare la traduzione italiana, si evidenzia e si prendono appunti a fianco della pagina, si ripassa e si tiene traccia dello studio. Tutto gira sul dispositivo, gratis e senza account.

### Libreria

- Importazione di PDF, foto e scansioni fatte con la fotocamera; collezioni per organizzare i libri.
- Copertine e anteprime delle pagine veloci, con la griglia di tutte le pagine per saltare dove si vuole.
- Tempo di lettura su ogni libro e statistiche di lettura: tempo per libro e per giorno, pagine viste, grafico degli ultimi 7 giorni.

### Lettura e traduzione

- Riconoscimento del testo con Vision, una volta per pagina, anche per tutto il libro in sottofondo.
- Si cerchia una parola con la Pencil: traduzione EN→IT con il framework Translation di Apple, frase intera con le parole cerchiate evidenziate.
- Ricerca di una parola in tutto il libro, zoom con le dita (da zoomati, uno scorrimento rapido a due dita cambia pagina), uscita dal libro scorrendo verso il basso.
- Tema della pagina: Normale, Seppia, Notte o come il sistema.
- Segnalibri con nome, elenco e filtro nella griglia delle pagine (nastrino sulle anteprime).
- Ritaglio dello schermo: si disegna attorno a una zona con la Pencil e il rettangolo viene copiato negli appunti (mai salvato in galleria).
- Barra dei comandi leggera: i comandi meno usati stanno nel menu Altro (⋯) e tenendo premuto un comando compare cosa fa.

### Modalità studio

- Evidenziatori arancione, azzurro e rosa che seguono una riga alla volta e non si scuriscono ripassando, sottolineatura e penna per il margine, sopra la pagina.
- Riepilogo del libro: tutti i segni ritagliati dalle pagine e raggruppati per colore, con salto alla pagina.
- Timer di studio (Pomodoro, 25/5 regolabile) nella barra del lettore, con notifica a fine blocco.

### Quaderno degli appunti

- Un quaderno a fianco di ogni pagina, con barra degli strumenti in alto o in basso, zoom e note del libro elencate per pagina.
- Scorrere a destra annulla, a sinistra ripete.
- Tenendo fermo il tratto diventa una forma (linee, archi, curve, figure), modificabile toccandola.
- Lazo come in GoodNotes con il menu sotto la selezione; gomma a pixel di varie grandezze o a tratto intero.
- Levigatura automatica dei tratti, di intensità regolabile.

### Parole e ripasso

- Parole cercate salvate per libro, esportabili in un file di testo.
- Ripasso a flashcard delle parole salvate, con ripetizione spaziata (SM-2 semplificato) e badge delle parole da ripassare oggi.

### Esportazione

- Esportazione del libro annotato in PDF: segni della modalità studio e note del quaderno, affiancate o in pagine a parte.

## Struttura

- `PencilReader/`: l'app SwiftUI.
- `ReaderCore/`: logica pura (selezione col lazo, testo della pagina, evidenziazione, ricerca, parole salvate e ripasso, forme e levigatura del quaderno, segni di studio e riepilogo, segnalibri, ritaglio, esportazione PDF, Pomodoro e statistiche), testabile su macOS con `swift test`.
- `project.yml`: progetto Xcode generato con [XcodeGen](https://github.com/yonaskolb/XcodeGen).
- `android/`: la versione Android nativa (vedi sotto).

## Installazione sull'iPad

Serve un Mac con Xcode e XcodeGen (`brew install xcodegen`). Con l'iPad collegato e sbloccato:

```bash
./installa.sh
```

Con un account Apple gratuito l'app va reinstallata ogni 7 giorni.

## Versione Android

In `android/` c'è una versione nativa per i tablet Android con penna (Kotlin, Jetpack Compose, ML Kit per OCR e traduzione, androidx.ink per il quaderno), con la stessa logica di `ReaderCore` portata in Kotlin nel modulo `android/core`. Come aprirla in Android Studio, compilarla e installarla, e le differenze dall'iPad, sono in [android/README.md](android/README.md).

## Da sviluppare

- **Riordino della scrittura nel quaderno**: raddrizza le righe scritte a mano e le mette dentro i quadretti. Tolto dall'app finché non funziona bene; il codice (HandwritingTidier, NotebookTidying) è nel ramo locale `riordino-da-sviluppare` sul Mac, non pubblicato.
