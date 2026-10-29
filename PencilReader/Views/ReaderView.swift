import ReaderCore
import SwiftUI
import Translation

/// One open document: page, Pencil lasso, translation panel.
struct ReaderView: View {
    let document: LibraryDocument
    @Environment(Library.self) private var library
    @Environment(BookRecognizer.self) private var recognizer
    @Environment(WordList.self) private var wordList
    @Environment(ReadingStats.self) private var stats
    @Environment(StudyTimer.self) private var studyTimer
    @Environment(\.dismiss) private var dismiss
    @State private var model: ReaderModel?
    @State private var showPages = false
    /// Created with the model; fills its disk cache in the background while the book is open.
    @State private var thumbnails: PageThumbnails?
    @State private var showSearch = false
    /// Kept while the book is open, so the last search is still there.
    @State private var search: BookSearch?
    @State private var showWords = false
    @State private var showAISettings = false
    /// Created with the model, so the notes of every page are known before the notebook opens.
    @State private var notebook: NotebookModel?
    @State private var showNotebook = false
    @State private var showNotes = false
    @State private var bookmarks: BookmarkStore?
    @State private var showBookmarks = false
    /// The bookmark being named, from the bookmark button's menu.
    @State private var namingBookmark: Bookmark?
    /// Every study mark of the book, cut out of its page and grouped by color.
    @State private var showSummary = false
    @State private var showExport = false
    /// Highlighter, underline and margin notes over the page, in place of the lasso.
    @State private var study: StudyModel?
    @State private var split = NotebookSettings.split
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    /// Normal, sepia or night page; remembered per book.
    @State private var theme: ReadingTheme

    init(document: LibraryDocument) {
        self.document = document
        _theme = State(initialValue: ReadingTheme.saved(for: document.id))
    }

    var body: some View {
        Group {
            if let model {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        PageView(model: model, study: study, theme: theme.resolved(for: colorScheme),
                                 onExit: { dismiss() })
                            .frame(width: pageWidth(in: geo.size.width))
                        if showNotebook, let notebook {
                            NotebookDivider(split: $split, available: geo.size.width - NotebookDivider.width)
                                // Drawn over the notebook while it is dragged across it.
                                .zIndex(1)
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
                .onChange(of: model.pageIndex) { old, page in
                    // The page just left counts as read: its highlights go to the AI.
                    model.groupHighlights(of: old)
                    notebook?.show(page)
                    stats.pageShown(page, of: document.id)
                }
                .onChange(of: theme) { _, theme in ReadingTheme.save(theme, for: document.id) }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active {
                        notebook?.flush()
                        study?.flush()
                        stats.stopReading()
                    } else {
                        stats.startReading(document.id)
                        studyTimer.refresh()
                    }
                }
                .sheet(isPresented: $showPages) {
                    if let thumbnails {
                        PageGridView(pageCount: model.pageCount, currentPage: model.pageIndex,
                                     thumbnails: thumbnails, notedPages: notebook?.notedPages ?? [],
                                     markedPages: study?.markedPages ?? [],
                                     bookmarks: bookmarkTitles,
                                     select: model.showPage)
                            .presentationSizing(.page)
                    }
                }
                .sheet(isPresented: $showBookmarks) {
                    if let bookmarks {
                        BookmarksListView(bookmarks: bookmarks, thumbnails: thumbnails,
                                          currentPage: model.pageIndex, select: model.showPage)
                            .presentationSizing(.page)
                    }
                }
                .bookmarkTitleAlert(item: $namingBookmark) { mark, title in bookmarks?.add(mark.page, title: title) }
                .sheet(isPresented: $showNotes) {
                    NotesListView(bookID: document.id, pages: notebook?.notedPages.sorted() ?? []) { page in
                        model.showPage(page)
                        showNotebook = true
                    }
                    .presentationSizing(.page)
                }
                .sheet(isPresented: $showSummary) {
                    MarkSummaryView(document: document) { page, openNotebook in
                        model.showPage(page)
                        if openNotebook { showNotebook = true }
                    }
                    .presentationSizing(.page)
                }
                .sheet(isPresented: Binding(get: { study?.showsGuide == true },
                                            set: { study?.showsGuide = $0 })) {
                    StudyGuideView()
                        .presentationSizing(.form)
                }
                .sheet(isPresented: $showExport) {
                    PDFExportView(document: document, currentPage: model.pageIndex,
                                  annotatedPages: (notebook?.notedPages ?? []).union(study?.markedPages ?? []),
                                  paper: notebook?.paper ?? .grid)
                        .presentationSizing(.form)
                }
                .sheet(isPresented: $showSearch) {
                    if let search {
                        SearchView(document: document, search: search, select: model.showMatch)
                            .presentationSizing(.page)
                    }
                }
                .sheet(isPresented: $showAISettings) {
                    AISettingsView().presentationSizing(.form)
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
            ToolbarItem(placement: .topBarLeading) {
                StudyTimerButton(bookID: document.id)
            }
        }
        // Reading time counts only while the book is open and the app is in front.
        .onAppear { if scenePhase == .active { stats.startReading(document.id) } }
        .onDisappear {
            stats.stopReading()
            if let model { model.groupHighlights(of: model.pageIndex) }
        }
        .onAppear {
            // Created once here, not in init: the model starts OCR as soon as it exists.
            if model == nil {
                let reader = ReaderModel(document: document, library: library, wordList: wordList)
                model = reader
                notebook = NotebookModel(bookID: document.id, pageIndex: reader.pageIndex)
                study = StudyModel(bookID: document.id)
                bookmarks = BookmarkStore(bookID: document.id, pageCount: document.pageCount)
                stats.pageShown(reader.pageIndex, of: document.id)
                thumbnails = PageThumbnails(
                    bookID: document.id, pageCount: document.pageCount,
                    pdfURL: document.kind == .pdf ? library.pdfURL(of: document) : nil,
                    pagesFolder: document.kind == .images
                        ? library.imageURL(of: document, page: 0).deletingLastPathComponent() : nil)
            }
        }
        // Fills the thumbnail cache while the book is open; cancelled when it closes.
        .task(priority: .background) {
            // The first page and its OCR go first.
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            await thumbnails?.prefetch(from: model?.pageIndex ?? document.lastPage)
        }
    }

    /// The book page takes the left share of the width while the notebook is open.
    private func pageWidth(in total: CGFloat) -> CGFloat? {
        guard showNotebook else { return nil }
        return (total - NotebookDivider.width) * split
    }

    /// Opens and closes the notebook beside the page.
    private var notebookButton: some View {
        HintButton(hint: "Apre il quaderno accanto alla pagina, per prendere appunti con la Pencil") {
            // Opening the notebook on a page is asking for its note.
            if !showNotebook { notebook?.startNote() }
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
        // Above the notebook's tool bar when that sits at the bottom.
        .padding(.bottom, showNotebook && notebook?.tools.layout.position == .bottom ? 44 : 0)
    }

    /// Recognizes the whole book in the background; shows the progress while it runs.
    @ViewBuilder private func recognitionButton(_ document: LibraryDocument) -> some View {
        if let progress = recognizer.progress(of: document) {
            HintButton(hint: "Sto leggendo il testo di tutte le pagine: tocca per fermare") {
                recognizer.stop(document)
            } label: {
                Label("Testo \(progress.done)/\(progress.total)", systemImage: "stop.circle")
                    .labelStyle(.titleAndIcon)
                    .monospacedDigit()
            }
        } else if recognizer.isQueued(document) {
            HintButton("In coda", systemImage: "clock",
                       hint: "In attesa di leggere il testo del libro: tocca per annullare") { recognizer.stop(document) }
                .labelStyle(.titleAndIcon)
        } else if library.recognizedPageCount(of: document) < document.pageCount {
            HintButton("Riconosci tutto il libro", systemImage: "text.viewfinder",
                       hint: "Legge il testo di tutte le pagine in sottofondo, così ricerca e traduzione sono subito pronte") {
                recognizer.start(document)
            }
        }
    }

    private var bookmarkTitles: [Int: String] {
        Dictionary(uniqueKeysWithValues: (bookmarks?.bookmarks ?? []).map { ($0.page, $0.title) })
    }

    /// Tap marks or unmarks the page; held, it offers a name and the list of bookmarks.
    @ViewBuilder private func bookmarkButton(_ bookmarks: BookmarkStore, model: ReaderModel) -> some View {
        let page = model.pageIndex
        let current = bookmarks.list.bookmark(at: page)
        Menu {
            Button(current == nil ? "Aggiungi con un nome…" : "Rinomina…", systemImage: "pencil") {
                namingBookmark = current ?? Bookmark(page: page, created: .now)
            }
            if current != nil {
                Button("Togli segnalibro", systemImage: "bookmark.slash", role: .destructive) {
                    bookmarks.remove(page)
                }
            }
            Divider()
            if let previous = bookmarks.list.previous(before: page) {
                Button("Precedente: \(previous.title)", systemImage: "chevron.up") { model.showPage(previous.page) }
            }
            if let next = bookmarks.list.next(after: page) {
                Button("Successivo: \(next.title)", systemImage: "chevron.down") { model.showPage(next.page) }
            }
            Button("Tutti i segnalibri (\(bookmarks.bookmarks.count))", systemImage: "list.bullet") {
                showBookmarks = true
            }
        } label: {
            Label(current == nil ? "Aggiungi segnalibro" : "Togli segnalibro",
                  systemImage: current == nil ? "bookmark" : "bookmark.fill")
        } primaryAction: {
            bookmarks.toggle(page)
        }
        .tint(current == nil ? nil : BookmarkRibbon.color)
    }

    /// Turns study mode on and off: while on, the Pencil marks the page instead of translating.
    @ViewBuilder private func studyButton(_ study: StudyModel, model: ReaderModel) -> some View {
        let toggle = {
            model.clearSelection()
            study.toggle()
        }
        if study.isActive {
            HintButton("Esci dalla modalità studio", systemImage: "highlighter",
                       hint: "Torna alla traduzione: la Pencil cerchia di nuovo le parole", action: toggle)
                .buttonStyle(.borderedProminent)
                .tint(.orange)
        } else {
            HintButton("Modalità studio", systemImage: "highlighter",
                       hint: "Con la Pencil evidenzi, sottolinei e scrivi a margine invece di tradurre", action: toggle)
        }
    }

    /// Quick pick of the page theme: a submenu of Altro, to keep the bar light.
    private var themeMenu: some View {
        Menu {
            Picker("Tema della pagina", selection: $theme) {
                ForEach(ReadingTheme.allCases) { theme in
                    Label(theme.label, systemImage: theme.systemImage).tag(theme)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Tema della pagina", systemImage: theme.resolved(for: colorScheme).systemImage)
        }
    }

    @ToolbarContentBuilder private func toolbar(_ model: ReaderModel) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            HintButton("Pagina precedente", systemImage: "chevron.left", hint: "Torna alla pagina precedente") { model.previousPage() }
                .disabled(model.pageIndex == 0)
            HintButton(hint: "Tutte le pagine in miniatura, per saltare a quella che vuoi") {
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
                    if study?.markedPages.contains(model.pageIndex) == true {
                        Image(systemName: "highlighter")
                            .font(.caption)
                            .foregroundStyle(Color(uiColor: StudyColor.key.uiColor))
                    }
                }
            }
            .accessibilityLabel("Tutte le pagine")
            HintButton("Pagina successiva", systemImage: "chevron.right", hint: "Va alla pagina successiva") { model.nextPage() }
                .disabled(model.pageIndex + 1 >= model.pageCount)
            if let bookmarks { bookmarkButton(bookmarks, model: model) }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let study { studyButton(study, model: model) }
            // Copies a part of the screen, page and notebook alike, cut out with the Pencil.
            Button("Ritaglia schermo", systemImage: "scissors") { ScreenClipper.start() }
            recognitionButton(model.document)
            Button("Riepilogo", systemImage: "list.bullet.rectangle.portrait") {
                // So the marks and the note being written show up to date in the summary.
                study?.flush()
                notebook?.flush()
                // The page open now joins the summary's groups as soon as the AI answers.
                model.groupHighlights(of: model.pageIndex)
                showSummary = true
            }
            HintButton("Note del libro", systemImage: "note.text",
                       hint: "Elenco delle pagine con appunti nel quaderno") {
                // So the page being written on shows up to date in the list.
                notebook?.flush()
                showNotes = true
            }
            HintButton("Cerca nel libro", systemImage: "magnifyingglass", hint: "Cerca una parola in tutto il libro") {
                if search == nil { search = BookSearch(document: document, library: library) }
                showSearch = true
            }
            // Less used: kept in the menu so the bar stays light.
            Menu("Altro", systemImage: "ellipsis") {
                Button("Parole cercate", systemImage: "character.book.closed") { showWords = true }
                themeMenu
                Button("Segnalibri", systemImage: "bookmark") { showBookmarks = true }
                Button("Impostazioni IA", systemImage: "sparkles") { showAISettings = true }
                Toggle(isOn: Bindable(model).showWordBoxes) {
                    Label("Riquadri OCR", systemImage: "square.dashed")
                }
                Toggle(isOn: Bindable(model).allowsFingerDrawing) {
                    Label("Disegna col dito", systemImage: "hand.draw")
                }
                Button("Esporta PDF", systemImage: "square.and.arrow.up") {
                    // So what was just written is in the PDF.
                    notebook?.flush()
                    study?.flush()
                    showExport = true
                }
            }
        }
    }
}
