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
    /// Created with the model, so the notes of every page are known before the notebook opens.
    @State private var notebook: NotebookModel?
    @State private var showNotebook = false
    @State private var showNotes = false
    @State private var split = NotebookSettings.split
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let model {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        PageView(model: model, onExit: { dismiss() })
                            .frame(width: pageWidth(in: geo.size.width))
                        if showNotebook, let notebook {
                            NotebookDivider(split: $split, available: geo.size.width - NotebookDivider.width)
                            NotebookPane(notebook: notebook)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .animation(.snappy, value: showNotebook)
                    .overlay(alignment: .bottomTrailing) { notebookButton }
                }
                .background(PopGestureDisabler())
                .toolbar { toolbar(model) }
                .translationTask(model.translationConfig) { session in
                    await model.translate(using: session)
                }
                .onChange(of: model.pageIndex) { _, page in notebook?.show(page) }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { notebook?.flush() }
                }
                .sheet(isPresented: $showPages) {
                    if let thumbnails {
                        PageGridView(pageCount: model.pageCount, currentPage: model.pageIndex,
                                     thumbnails: thumbnails, notedPages: notebook?.notedPages ?? [],
                                     select: model.showPage)
                            .presentationSizing(.page)
                    }
                }
                .sheet(isPresented: $showNotes) {
                    NotesListView(bookID: document.id, pages: notebook?.notedPages.sorted() ?? []) { page in
                        model.showPage(page)
                        showNotebook = true
                    }
                    .presentationSizing(.page)
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
            if model == nil {
                let reader = ReaderModel(document: document, library: library, wordList: wordList)
                model = reader
                notebook = NotebookModel(bookID: document.id, pageIndex: reader.pageIndex)
            }
        }
    }

    /// The book page takes the left share of the width while the notebook is open.
    private func pageWidth(in total: CGFloat) -> CGFloat? {
        guard showNotebook else { return nil }
        return (total - NotebookDivider.width) * split
    }

    /// Opens and closes the notebook beside the page.
    private var notebookButton: some View {
        Button {
            showNotebook.toggle()
        } label: {
            Image(systemName: showNotebook ? "square.and.pencil.circle.fill" : "square.and.pencil")
                .font(.title2)
                .frame(width: 56, height: 56)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        }
        .accessibilityLabel(showNotebook ? "Chiudi quaderno" : "Apri quaderno")
        .padding(20)
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
                HStack(spacing: 4) {
                    Text("\(model.pageIndex + 1) / \(model.pageCount)")
                        .monospacedDigit()
                        .font(.callout)
                    if notebook?.notedPages.contains(model.pageIndex) == true {
                        Image(systemName: "pencil.tip")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .accessibilityLabel("Tutte le pagine")
            Button("Pagina successiva", systemImage: "chevron.right") { model.nextPage() }
                .disabled(model.pageIndex + 1 >= model.pageCount)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            recognitionButton(model.document)
            Button("Note del libro", systemImage: "note.text") { showNotes = true }
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
