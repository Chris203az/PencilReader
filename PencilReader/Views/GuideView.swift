import SwiftUI

/// Settings › Guida: how each feature works, one page per topic, gestures included.
/// The gestures are those the views actually recognize; keep them in step when one changes.
struct GuideView: View {
    var body: some View {
        List {
            Section {
                ForEach(GuideTopic.features) { topic in
                    NavigationLink { GuideTopicView(topic: topic) } label: { GuideTopicRow(topic: topic) }
                }
            } header: {
                Text("Funzioni")
            }
            Section {
                ForEach(GuideTopic.gestures) { topic in
                    NavigationLink { GuideTopicView(topic: topic) } label: { GuideTopicRow(topic: topic) }
                }
            } header: {
                Text("Gesti")
            }
        }
        .navigationTitle("Guida")
    }
}

/// One page of the guide: a few items, each a title and what to know.
struct GuideTopic: Identifiable {
    struct Item: Identifiable {
        let id = UUID()
        let title: LocalizedStringResource
        let text: LocalizedStringResource
    }

    let id: String
    let title: LocalizedStringResource
    let systemImage: String
    let color: Color
    let items: [Item]

    static let features: [GuideTopic] = [
        GuideTopic(id: "library", title: "Libreria", systemImage: "books.vertical", color: .accentColor, items: [
            Item(title: "Aggiungere un libro",
                 text: "Con + in alto: scansiona pagine con la fotocamera, scegli foto o importa un PDF."),
            Item(title: "Librerie",
                 text: "Dal titolo in alto crei, rinomini ed elimini librerie, e scegli quale vedere. Un libro si sposta in un'altra libreria dal suo menu."),
            Item(title: "Menu del libro",
                 text: "Il pulsante ··· su un libro, o tenerlo premuto, apre Rinomina, Sposta in, riconoscimento del testo ed Elimina."),
            Item(title: "Continua a leggere",
                 text: "In cima c'è l'ultimo libro aperto, con la pagina e il tempo di lettura. Si nasconde dalle Impostazioni.")
        ]),
        GuideTopic(id: "translate", title: "Tradurre una parola", systemImage: "character.bubble", color: .teal, items: [
            Item(title: "Cerchia con la Pencil",
                 text: "Disegna un cerchio intorno a una o più parole: compare la traduzione della frase intera, con le parole cerchiate evidenziate."),
            Item(title: "Nel riquadro",
                 text: "Ascolta legge la parola con la pronuncia della lingua del libro; Dizionario apre quello di sistema; Copia la mette negli appunti; Chiedi all'IA spiega il termine nel contesto."),
            Item(title: "Le lingue",
                 text: "In Impostazioni › Traduzione scegli la lingua dei libri e quella in cui tradurre. La prima volta che usi una lingua, l'iPad chiede di scaricarla."),
            Item(title: "Parole cercate",
                 text: "Ogni parola tradotta finisce tra le parole cercate, con la sua frase: le ritrovi nel menu ··· del libro, nel menu Studio della libreria e nel Ripasso."),
            Item(title: "Col dito",
                 text: "Con «Cerchia le parole col dito» nelle Impostazioni si cerchia anche col dito. Le pagine allora si girano con le frecce in alto.")
        ]),
        GuideTopic(id: "reading", title: "Leggere un libro", systemImage: "book", color: .indigo, items: [
            Item(title: "Pagine",
                 text: "Le frecce in alto girano pagina; toccare il numero mostra tutte le pagine in miniatura, con i filtri Solo segnalibri e Solo annotate."),
            Item(title: "Indice",
                 text: "La linguetta a sinistra apre l'indice dei capitoli del PDF. Dopo un salto, «Torna a pag.» riporta dove eri."),
            Item(title: "Cerca",
                 text: "La lente cerca una parola in tutto il libro, nel testo riconosciuto delle pagine: «Riconosci tutto il libro» lo prepara in sottofondo."),
            Item(title: "Segnalibri",
                 text: "Un tocco sul segnalibro in alto segna o toglie la pagina aperta. Tenendolo premuto puoi darle un nome, andare al segnalibro prima o dopo e vedere l'elenco."),
            Item(title: "Tema della pagina",
                 text: "Dal menu ··· scegli Normale, Seppia, Notte o Segui il sistema per il libro aperto."),
            Item(title: "Ritaglia schermo",
                 text: "Le forbici in basso: disegna con la Pencil intorno a una parte dello schermo, pagina e quaderno insieme, e viene copiata negli appunti.")
        ]),
        GuideTopic(id: "study", title: "Modalità studio", systemImage: "highlighter", color: .orange, items: [
            Item(title: "Accenderla",
                 text: "Il pulsante con l'evidenziatore in alto: la Pencil segna invece di tradurre, finché non la spegni."),
            Item(title: "Gli strumenti",
                 text: "Tre evidenziatori con un significato fisso (concetto chiave, formula o dato, da rivedere), il sottolineato per i termini da imparare, la penna per le note a margine e la gomma."),
            Item(title: "Segni puliti",
                 text: "L'evidenziatore si aggancia alla riga di testo e il sottolineato si raddrizza quando stacchi la Pencil."),
            Item(title: "Il metodo",
                 text: "«Come studiare» nella barra spiega come usare i segni per ricordare davvero, non solo per colorare.")
        ]),
        GuideTopic(id: "notebook", title: "Quaderno", systemImage: "square.and.pencil", color: .orange, items: [
            Item(title: "Aprirlo",
                 text: "Il pulsante in basso a destra apre il quaderno accanto alla pagina. Ogni pagina del libro ha la sua nota."),
            Item(title: "Strumenti",
                 text: "Penna, matita, evidenziatore, gomma, lasso e righello, con colori e spessori. «Barra strumenti…» sceglie quali pulsanti mostrare e in che ordine."),
            Item(title: "Forme automatiche",
                 text: "Con le forme automatiche attive, disegna una linea, un cerchio o un rettangolo e tieni ferma la punta: diventa una forma pulita. Toccando la sua linea col dito la puoi modificare."),
            Item(title: "Sfondo",
                 text: "Quadretti, righe o bianco, dalle Impostazioni o dalla barra del quaderno.")
        ]),
        GuideTopic(id: "summary", title: "Riepilogo e IA", systemImage: "sparkles", color: .purple, items: [
            Item(title: "Riepilogo",
                 text: "Il pulsante Riepilogo nella barra del libro raccoglie i segni di studio e le note del quaderno, divisi per colore e per pagina; un tocco porta alla pagina."),
            Item(title: "Unisci con l'IA",
                 text: "L'IA unisce le evidenziazioni dello stesso concetto, anche su pagine vicine, e ne scrive una sintesi."),
            Item(title: "Chiedi all'IA",
                 text: "Dal riquadro della traduzione: cosa vuol dire il termine e cosa intende l'autore in quella frase."),
            Item(title: "Le chiavi",
                 text: "In Impostazioni › Intelligenza artificiale scegli il servizio per ogni funzione e incolli la sua chiave API, che resta solo sull'iPad.")
        ]),
        GuideTopic(id: "review", title: "Ripasso delle parole", systemImage: "rectangle.on.rectangle", color: .red, items: [
            Item(title: "Le carte",
                 text: "Ripasso, in libreria, mostra le parole cercate da ripassare oggi. Il numero rosso dice quante sono."),
            Item(title: "Rispondere",
                 text: "Tocca la carta per vedere la traduzione, poi scegli Non la sapevo, Difficile o La sapevo: la parola torna più o meno presto."),
            Item(title: "Esportare",
                 text: "Dalle parole cercate (menu Studio della libreria) puoi condividere l'elenco come file di testo, comodo anche da dare a un'IA.")
        ]),
        GuideTopic(id: "timer", title: "Timer e rielaborazione", systemImage: "timer", color: .green, items: [
            Item(title: "Timer di studio",
                 text: "Il cronometro accanto al titolo del libro alterna blocchi di studio e pause; le durate si cambiano nelle Impostazioni."),
            Item(title: "Leggi per un tempo preciso",
                 text: "Scegli quanto vuoi leggere: l'app divide il tempo in blocchi e pause e ti avvisa alla fine."),
            Item(title: "Fissa la lettura",
                 text: "Alla fine riscrivi a mano, senza guardare, le pagine lette; intanto l'IA prepara la sua versione da confrontare. Le rielaborazioni sono nel menu ··· del libro e nel menu Studio della libreria.")
        ]),
        GuideTopic(id: "export", title: "Esportare e backup", systemImage: "externaldrive", color: .blue, items: [
            Item(title: "Esporta PDF",
                 text: "Dal menu ··· del libro: tutto il libro, un intervallo o solo le pagine annotate, con i segni di studio e le note del quaderno accanto o dopo ogni pagina."),
            Item(title: "Backup",
                 text: "In Impostazioni › Backup scegli una cartella, anche in iCloud Drive: libri, note, segni, parole, statistiche e impostazioni vengono copiati ogni giorno o quando vuoi."),
            Item(title: "Ripristino",
                 text: "«Ripristina da un backup…» sostituisce tutti i dati con quelli della cartella scelta; poi l'app va riaperta.")
        ]),
        GuideTopic(id: "settings", title: "Impostazioni utili", systemImage: "gearshape", color: .gray, items: [
            Item(title: "Lingua dell'app",
                 text: "Sistema, Italiano o English: la nuova lingua si vede alla riapertura dell'app."),
            Item(title: "Suggerimenti tenendo premuto",
                 text: "Tenendo premuto un pulsante della barra del libro, compare cosa fa invece di eseguirlo."),
            Item(title: "Schermo sempre acceso",
                 text: "L'iPad non si spegne mentre un libro è aperto.")
        ])
    ]

    static let gestures: [GuideTopic] = [
        GuideTopic(id: "fingers", title: "Gesti con le dita", systemImage: "hand.point.up.left", color: .teal, items: [
            Item(title: "Scorri a sinistra o a destra",
                 text: "Sulla pagina del libro: pagina successiva o precedente."),
            Item(title: "Scorri verso il basso",
                 text: "Sulla pagina del libro: chiude il libro e torna alla libreria."),
            Item(title: "Pizzica",
                 text: "Ingrandisce o rimpicciolisce la pagina; sotto la grandezza normale torna da sola."),
            Item(title: "Doppio tocco",
                 text: "Sulla pagina ingrandisce dove tocchi; se è già ingrandita torna normale. Nel quaderno riporta lo zoom a 1x."),
            Item(title: "Pagina ingrandita",
                 text: "Un dito la sposta; per girare pagina scorri velocemente con due dita."),
            Item(title: "Tocco sulla pagina",
                 text: "Chiude il riquadro della traduzione."),
            Item(title: "Cerchiare col dito",
                 text: "Con l'opzione attiva un dito cerchia le parole e due dita spostano la pagina ingrandita; lo scorrimento per girare pagina è spento."),
            Item(title: "Nel quaderno",
                 text: "Scorri a destra con un dito per annullare e a sinistra per ripristinare; su e giù scorre la nota, il pizzico la ingrandisce fino a 4x. Ingrandita, il dito la sposta invece di annullare."),
            Item(title: "Divisore",
                 text: "Trascina la barretta tra pagina e quaderno per dare più spazio all'uno o all'altro."),
            Item(title: "Tenere premuto",
                 text: "Su un pulsante della barra del libro: spiega cosa fa. Sul segnalibro in alto: nome e altri segnalibri. Su un libro in libreria: apre il suo menu. Su un colore del quaderno: lo cambia. Su un segnalibro dell'elenco: Rinomina e Rimuovi."),
            Item(title: "Scorrere in un elenco",
                 text: "Verso sinistra su un segnalibro mostra Rinomina e Rimuovi; su una rielaborazione, Elimina."),
            Item(title: "Nel ripasso",
                 text: "Tocca la carta per girarla.")
        ]),
        GuideTopic(id: "pencil", title: "Gesti con la Pencil", systemImage: "applepencil", color: .indigo, items: [
            Item(title: "Cerchiare",
                 text: "Sulla pagina del libro, un cerchio intorno a una o più parole le traduce."),
            Item(title: "Segnare in modalità studio",
                 text: "Con la modalità studio accesa la Pencil evidenzia, sottolinea o scrive a margine; le dita continuano a girare e ingrandire la pagina."),
            Item(title: "Scrivere nel quaderno",
                 text: "Nel quaderno scrive solo la Pencil: le dita scorrono e ingrandiscono, senza lasciare segni."),
            Item(title: "Tenere ferma la punta",
                 text: "Nel quaderno, con le forme automatiche attive: alla fine di un tratto, mezzo secondo fermi e il tratto diventa una forma pulita. Senza staccare, muovi la punta per regolarla."),
            Item(title: "Doppio tocco sulla Pencil",
                 text: "Nel quaderno segue la scelta di Impostazioni › Apple Pencil: passa alla gomma e ritorno, o allo strumento usato prima."),
            Item(title: "Lasso",
                 text: "Disegna un anello intorno ai tratti per selezionarli. Nel riquadro: trascina dentro per spostarli, un angolo per ridimensionarli, un lato per allungarli, la maniglia sopra per ruotarli. Funziona anche col dito."),
            Item(title: "Menu del lasso",
                 text: "Un tocco nel riquadro apre Copia, Taglia, Duplica, Elimina e Cambia colore; un tocco fuori lascia la selezione; tenendo premuto sulla carta vuota compare Incolla."),
            Item(title: "Modificare una forma",
                 text: "Dopo aver toccato la linea di una forma col dito, la Pencil trascina i suoi punti: estremi, angoli, lati o assi. Trascinare la linea la sposta."),
            Item(title: "Ritagliare lo schermo",
                 text: "Dopo le forbici, disegna intorno alla parte da copiare.")
        ])
    ]
}

private struct GuideTopicRow: View {
    let topic: GuideTopic

    var body: some View {
        Label {
            Text(topic.title)
        } icon: {
            Image(systemName: topic.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(topic.color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

private struct GuideTopicView: View {
    let topic: GuideTopic

    var body: some View {
        List(topic.items) { item in
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.headline)
                Text(item.text).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle(Text(topic.title))
    }
}
