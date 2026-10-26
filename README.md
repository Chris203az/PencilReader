# PencilReader

App per iPad per studiare libri tecnici in inglese (anche scansioni) con la Apple Pencil: traduci una parola cerchiandola, prendi appunti in un quaderno accanto alla pagina, evidenzia e ripassa. Tutto sul dispositivo e gratis.

## Funzionalità

### Lettura e traduzione
- Si cerchia una parola con la Pencil e compare la traduzione italiana (framework Translation di Apple): frase intera, con le parole cerchiate evidenziate.
- Riconoscimento del testo con Vision, una volta per pagina (anche per tutto il libro in sottofondo).
- Ricerca nel libro, zoom, griglia delle pagine con miniature in cache.
- Tema della pagina: Normale, Seppia, Notte o come il sistema.
- Segnalibri: aggiungi o togli la pagina dalla barra, con elenco, filtro e nastrino nelle anteprime.
- Ritaglio dello schermo con la Pencil, copiato negli appunti.
- Tenendo premuto un comando della barra compare cosa fa; i comandi meno usati stanno nel menu Altro.

### Quaderno affiancato
- Quaderno accanto alla pagina del libro, con divisore regolabile; una pagina di quaderno per pagina del libro.
- Barra degli strumenti fissa e configurabile; gomma con grandezza regolabile.
- Forme riconosciute alla pausa della penna (come in Note e GoodNotes) e modificabili dopo, anche archi e curve.
- Lazo stile GoodNotes: sposta, ridimensiona, ruota, con menu delle azioni.
- Levigatura automatica dei tratti; swipe per annulla e ripristina, zoom con le dita.
- Elenco delle note del libro.

### Modalità studio
- Evidenziatore a colori trasparente, sottolineatura e note a margine sopra la pagina; i segni restano visibili a modalità spenta.
- Riepilogo del libro: i segni della modalità studio ritagliati dalle pagine e raggruppati per colore.
- Esportazione del libro annotato in PDF (segni della modalità studio e note del quaderno, affiancate o in pagine a parte).

### Parole e ripasso
- Parole cercate salvate per libro, esportabili in un file di testo.
- Ripasso a flashcard delle parole salvate, con ripetizione spaziata (SM-2 semplificato) e badge delle parole da ripassare oggi.

### Tempo di studio
- Timer di studio (Pomodoro, 25/5 regolabile) nella barra del lettore, con notifica a fine blocco.
- Statistiche di lettura: tempo per libro e per giorno, pagine viste, grafico degli ultimi 7 giorni.

### Libreria
- Importazione di PDF e scansioni con la fotocamera, raggruppati in collezioni.

## Struttura

- `PencilReader/`: l'app SwiftUI.
- `ReaderCore/`: logica pura (lazo, testo della pagina, traduzione evidenziata, ricerca, quaderno e forme, levigatura, modalità studio, segnalibri, esportazione PDF, ripasso, Pomodoro, statistiche), testabile su macOS con `swift test`.
- `project.yml`: progetto Xcode generato con [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Installazione sull'iPad

Serve un Mac con Xcode e XcodeGen (`brew install xcodegen`). Con l'iPad collegato e sbloccato:

```bash
./installa.sh
```

Con un account Apple gratuito l'app va reinstallata ogni 7 giorni.

## Da sviluppare

- **Riordino della scrittura nel quaderno**: raddrizza le righe scritte a mano e le mette dentro i quadretti. Tolto dall'app finché non funziona bene; il codice (HandwritingTidier, NotebookTidying) è nel ramo locale `riordino-da-sviluppare` sul Mac, non pubblicato.
