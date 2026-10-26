# PencilReader

App per iPad per leggere libri tecnici in inglese (soprattutto scansioni): si cerchia una parola con la Apple Pencil e compare la traduzione italiana, tutto sul dispositivo e gratis.

- Riconoscimento del testo con Vision, una volta per pagina (anche per tutto il libro in sottofondo).
- Traduzione EN→IT con il framework Translation di Apple: frase intera con le parole cerchiate evidenziate.
- Libreria con collezioni, griglia delle pagine, zoom, ricerca nel libro.
- Parole cercate salvate per libro, esportabili in un file di testo.

## Struttura

- `PencilReader/`: l'app SwiftUI.
- `ReaderCore/`: logica pura (selezione col lazo, testo della pagina, evidenziazione, ricerca, parole salvate), testabile su macOS con `swift test`.
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
