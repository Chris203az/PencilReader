import SwiftUI
import Translation

/// One open document: page, Pencil lasso, translation panel.
struct ReaderView: View {
    let document: LibraryDocument
    @Environment(Library.self) private var library
    @Environment(BookRecognizer.self) private var recognizer
    @Environment(WordList.self) private var wordList
    @Environment(\.dismiss) private var dismiss
    @State private var model: ReaderModel?
    @State private var showPages = false
    /// Created the first time the page grid opens, then kept for this document.
    @State private var thumbnails: PageThumbnails?
    @State private var showSearch = false
    /// Kept while the book is open, so the last search is still there.
    @State private var search: BookSearch?
    @State private var showWords = false

    var body: some View {
        Group {
            if let model {
                PageView(model: model, onExit: { dismiss() })
                    .background(PopGestureDisabler())
                    .toolbar { toolbar(model) }
                    .translationTask(model.translationConfig) { session in
                        await model.translate(using: session)
                    }
                    .sheet(isPresented: $showPages) {
                        if let thumbnails {
                            PageGridView(pageCount: model.pageCount, currentPage: model.pageIndex,
                                         thumbnails: thumbnails, select: model.showPage)
                                .presentationSizing(.page)
                        }
                    }
                    .sheet(isPresented: $showSearch) {
                        if let search {
                            SearchView(document: document, search: search, select: model.showMatch)
                                .presentationSizing(.page)
                        }
                    }
                    .sheet(isPresented: $showWords) {
                        WordsView(currentDocument: document) { word in
                            if word.documentID == document.id { model.showPage(word.page) }
                        }
                        .presentationSizing(.page)
                    }
                    .alert("Errore", isPresented: Binding(get: { model.alertMessage != nil },
                                                          set: { if !$0 { model.alertMessage = nil } })) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text(model.alertMessage ?? "")
                    }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(model?.title ?? document.title)
        .navigationBarTitleDisplayMode(.inline)
        // Own back button: the system one comes with the swipe-back gesture.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(library.currentCollection.name, systemImage: "chevron.left") { dismiss() }
            }
        }
        .onAppear {
            // Created once here, not in init: the model starts OCR as soon as it exists.
            if model == nil { model = ReaderModel(document: document, library: library, wordList: wordList) }
        }
    }

    /// Recognizes the whole book in the background; shows the progress while it runs.
    @ViewBuilder private func recognitionButton(_ document: LibraryDocument) -> some View {
        if let progress = recognizer.progress(of: document) {
            Button { recognizer.stop(document) } label: {
                Label("Testo \(progress.done)/\(progress.total)", systemImage: "stop.circle")
                    .labelStyle(.titleAndIcon)
                    .monospacedDigit()
            }
        } else if recognizer.isQueued(document) {
            Button("In coda", systemImage: "clock") { recognizer.stop(document) }
                .labelStyle(.titleAndIcon)
        } else if library.recognizedPageCount(of: document) < document.pageCount {
            Button("Riconosci tutto il libro", systemImage: "text.viewfinder") { recognizer.start(document) }
        }
    }

    @ToolbarContentBuilder private func toolbar(_ model: ReaderModel) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Pagina precedente", systemImage: "chevron.left") { model.previousPage() }
                .disabled(model.pageIndex == 0)
            Button {
                if thumbnails == nil {
                    thumbnails = switch document.kind {
                    case .pdf: PageThumbnails(pdfURL: library.pdfURL(of: document), pagesFolder: nil)
                    case .images: PageThumbnails(pdfURL: nil, pagesFolder: library.imageURL(of: document, page: 0).deletingLastPathComponent())
                    }
                }
                showPages = true
            } label: {
                Text("\(model.pageIndex + 1) / \(model.pageCount)")
                    .monospacedDigit()
                    .font(.callout)
            }
            .accessibilityLabel("Tutte le pagine")
            Button("Pagina successiva", systemImage: "chevron.right") { model.nextPage() }
                .disabled(model.pageIndex + 1 >= model.pageCount)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            recognitionButton(model.document)
            Button("Cerca nel libro", systemImage: "magnifyingglass") {
                if search == nil { search = BookSearch(document: document, library: library) }
                showSearch = true
            }
            Button("Parole cercate", systemImage: "character.book.closed") { showWords = true }
            Menu("Altro", systemImage: "ellipsis") {
                Toggle(isOn: Bindable(model).showWordBoxes) {
                    Label("Riquadri OCR", systemImage: "square.dashed")
                }
                Toggle(isOn: Bindable(model).allowsFingerDrawing) {
                    Label("Disegna col dito", systemImage: "hand.draw")
                }
            }
        }
    }
}
