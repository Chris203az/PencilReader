import ReaderCore
import SwiftUI
import UniformTypeIdentifiers

/// The saved words, of one book or of all of them, with export.
struct WordsView: View {
    /// The open book, if any: then the list can show just its words.
    let currentDocument: LibraryDocument?
    /// Called when a word is tapped, to go to its page.
    let select: (SavedWord) -> Void

    @Environment(WordList.self) private var wordList
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var onlyThisBook = true
    @State private var filter = ""

    private var shown: [SavedWord] {
        var words = wordList.words
        if let currentDocument, onlyThisBook { words = words.filter { $0.documentID == currentDocument.id } }
        let query = filter.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            words = words.filter {
                $0.term.localizedStandardContains(query) || $0.translation.localizedStandardContains(query)
            }
        }
        return words
    }

    var body: some View {
        NavigationStack {
            List {
                if currentDocument != nil {
                    Picker("Mostra", selection: $onlyThisBook) {
                        Text("Questo libro").tag(true)
                        Text("Tutti i libri").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                ForEach(shown) { word in
                    Button {
                        select(word)
                        dismiss()
                    } label: {
                        WordRow(word: word, showsBook: currentDocument == nil || !onlyThisBook)
                    }
                    .disabled(library.document(withID: word.documentID) == nil)
                }
                .onDelete { offsets in
                    let words = shown
                    wordList.delete(Set(offsets.map { words[$0].id }))
                }
            }
            .overlay {
                if shown.isEmpty {
                    ContentUnavailableView(filter.isEmpty ? "Nessuna parola" : "Nessun risultato",
                                           systemImage: "character.book.closed",
                                           description: Text(filter.isEmpty
                                                             ? "Le parole che cerchi con la Pencil compaiono qui."
                                                             : "Nessuna parola salvata contiene “\(filter)”."))
                }
            }
            .searchable(text: $filter, prompt: "Filtra parole")
            .navigationTitle("Parole cercate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Menu("Esporta", systemImage: "square.and.arrow.up") {
                        let export = WordsExport(words: shown)
                        ShareLink(item: export, preview: SharePreview("Parole cercate (\(shown.count))")) {
                            Label("Condividi file…", systemImage: "doc.text")
                        }
                        Button("Copia tutto", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = export.markdown
                        }
                    }
                    .disabled(shown.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
    }
}

private struct WordRow: View {
    let word: SavedWord
    let showsBook: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(word.term).font(.body.weight(.semibold))
                Text("→ \(word.translation)").foregroundStyle(Color(uiColor: .secondaryLabel))
                Spacer()
                if word.lookups > 1 {
                    Text("×\(word.lookups)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }
            if let sentence = word.sentence {
                Text(sentence)
                    .font(.footnote)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .lineLimit(2)
            }
            Text(showsBook ? "\(word.documentTitle) · pagina \(word.page + 1)" : "Pagina \(word.page + 1)")
                .font(.caption)
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
        }
        .contentShape(Rectangle())
    }
}

/// The words as a Markdown text file, for the share sheet.
struct WordsExport: Transferable {
    let words: [SavedWord]

    var markdown: String {
        WordExport.markdown(words, exportedOn: Date.now.formatted(.dateTime.day().month(.wide).year()
            .locale(Locale(identifier: "it_IT"))))
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { export in
            let url = URL.temporaryDirectory.appending(path: "Parole cercate.txt")
            try export.markdown.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
