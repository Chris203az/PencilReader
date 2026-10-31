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
    @State private var showSettings = false
    @State private var renaming = false
    /// The chapters column on the left; stays open from one book to the next.
    @AppStorage("reader.showsOutline") private var showOutline = false
    @State private var newTitle = ""
    @AppStorage(AppSettings.progressBarKey) private var showsProgressBar = true
    @AppStorage(AppSettings.keepsScreenOnKey) private var keepsScreenOn = false
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
    /// "Fissa la lettura": a new recap of the pages just read, or one to reread.
    @State private var recapSheet: RecapSheet?
    @State private var showRecaps = false
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
                HStack(spacing: 0) {
                    if showOutline && !model.outline.isEmpty {
                        HStack(spacing: 0) {
                            OutlineView(entries: model.outline, currentPage: model.pageIndex, select: model.showPage) {
                                showOutline = false
                            }
                            Divider()
                        }
                        .transition(.move(edge: .leading))
                    }
                    GeometryReader { geo in
                        // Upright, the notebook goes below the page: beside it, both would be too narrow.
                        let stacked = geo.size.height > geo.size.width
                        let length = stacked ? geo.size.height : geo.size.width
                        let layout = stacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
                        layout {
                            PageView(model: model, study: study, theme: theme.resolved(for: colorScheme),
                                     onExit: { dismiss() })
                                .overlay(alignment: .bottom) {
                                    if showsProgressBar { ReadingProgressBar(page: model.pageIndex, pageCount: model.pageCount) }
                                }
                                .overlay(alignment: .bottomLeading) { backButton(model) }
                            .overlay(alignment: .leading) { if !model.outline.isEmpty { outlineTab } }
                                .frame(width: stacked ? nil : pageLength(in: length),
                                       height: stacked ? pageLength(in: length) : nil)
                            if showNotebook, let notebook {
                                NotebookDivider(split: $split, available: length - NotebookDivider.width, stacked: stacked)
                                    // Drawn over the notebook while it is dragged across it.
                                    .zIndex(1)
                                NotebookPane(notebook: notebook)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .animation(.snappy, value: showNotebook)
                        .overlay(alignment: .bottomTrailing) {
                            VStack(spacing: 14) {
                                clipButton
                                notebookButton
                            }
                            .padding(20)
                            // Above the notebook's tool bar when that sits at the bottom.
                            .padding(.bottom, showNotebook && notebook?.tools.layout.position == .bottom ? 44 : 0)
                        }
                    }
                }
                .animation(.snappy, value: showOutline)
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
                    MarkSummaryView(document: document, currentPage: model.pageIndex, pageCount: model.pageCount,
                                    pageInfo: model.highlightPage) { page, openNotebook in
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
                .fullScreenCover(item: $recapSheet) { sheet in
                    switch sheet {
                    case .new(let pages): FixReadingView(model: model, suggested: pages)
                    case .open(let recap): FixReadingView(recap: recap)
                    }
                }
                .sheet(isPresented: $showRecaps) {
                    RecapListView(currentBookID: document.id)
                        .presentationSizing(.page)
                }
                .sheet(isPresented: $showSettings, onDismiss: {
                    model.reloadSettings()
                    notebook?.reloadSettings()
                    keepScreenOn(true)
                }) {
                    SettingsView().presentationSizing(.page)
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // Own back button: the system one comes with the swipe-back gesture.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(library.currentCollection.name, systemImage: "chevron.left") { dismiss() }
            }
            ToolbarItem(placement: .topBarLeading) {
                StudyTimerButton(bookID: document.id, onFix: fixReading) { recap in
                    recapSheet = .open(recap)
                }
            }
            // On the left, away from the notebook divider; tapped, it renames the book.
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    newTitle = displayTitle
                    renaming = true
                } label: {
                    Text(displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .frame(maxWidth: 320, alignment: .leading)
                }
                .accessibilityHint("Rinomina il libro")
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .alert("Rinomina", isPresented: $renaming) {
            TextField("Titolo", text: $newTitle)
            Button("Annulla", role: .cancel) {}
            Button("Salva") {
                if let current = library.document(withID: document.id) { library.rename(current, to: newTitle) }
            }
        }
        // Reading time counts only while the book is open and the app is in front.
        .onAppear {
            if scenePhase == .active { stats.startReading(document.id) }
            keepScreenOn(true)
        }
        .onDisappear {
            stats.stopReading()
            keepScreenOn(false)
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

    private var displayTitle: String {
        library.document(withID: document.id)?.displayTitle ?? document.displayTitle
    }

    /// The reader has finished reading: the pages seen today up to this one, after the last recap.
    private func fixReading() {
        guard let model else { return }
        notebook?.flush()
        study?.flush()
        recapSheet = .new(ReadingRecap.suggestedRange(
            current: model.pageIndex,
            pagesSeenToday: stats.log.pagesViewed(on: .now, of: document.id),
            lastRecapEnd: RecapStore.shared.lastRecapEnd(of: document.id)))
    }

    /// The book page takes the first share of the width (or, upright, of the height) while the notebook is open.
    private func pageLength(in total: CGFloat) -> CGFloat? {
        guard showNotebook else { return nil }
        return (total - NotebookDivider.width) * split
    }

    /// "Schermo sempre acceso" holds only while a book is open.
    private func keepScreenOn(_ open: Bool) {
        UIApplication.shared.isIdleTimerDisabled = open && keepsScreenOn
    }

    /// Opens and closes the notebook beside the page.
    private var notebookButton: some View {
        HintButton(hint: String(localized: "Apre il quaderno accanto alla pagina, per prendere appunti con la Pencil")) {
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
    }

    /// A tab half way down the left edge: opens the chapters column, and closes it from its edge.
    private var outlineTab: some View {
        HintButton(hint: String(localized: "Apre e chiude l'indice dei capitoli")) {
            showOutline.toggle()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "list.bullet.indent")
                    .font(.body.weight(.semibold))
                Image(systemName: showOutline ? "chevron.left" : "chevron.right")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(width: 36, height: 88)
            .background(Color.accentColor.gradient,
                        in: UnevenRoundedRectangle(bottomTrailingRadius: 14, topTrailingRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 4, x: 1)
        }
        .accessibilityLabel(showOutline ? "Chiudi indice" : "Apri indice")
    }

    /// After a jump (search, thumbnails, index, bookmark…): back to the page it started from.
    @ViewBuilder private func backButton(_ model: ReaderModel) -> some View {
        if let page = model.returnPage, page != model.pageIndex {
            HStack(spacing: 0) {
                Button {
                    withAnimation(.snappy) { model.goBack() }
                } label: {
                    Label("Torna a pag. \(page + 1)", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .padding(.leading, 16)
                        .padding(.trailing, 8)
                        .padding(.vertical, 10)
                }
                Button {
                    withAnimation(.snappy) { model.forgetReturnPage() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 14)
                        .padding(.vertical, 10)
                }
                .accessibilityLabel("Nascondi")
            }
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            .padding(20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Copies a part of the screen, page and notebook alike, cut out with the Pencil.
    /// Big and always there, above the notebook button: it is used all the time.
    private var clipButton: some View {
        HintButton(hint: String(localized: "Ritaglia una parte dello schermo con la Pencil e la copia, pagina e quaderno insieme")) {
            ScreenClipper.start()
        } label: {
            Image(systemName: "scissors")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor.gradient, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        }
        .accessibilityLabel("Ritaglia schermo")
    }

    /// Recognizes the whole book in the background; shows the progress while it runs.
    @ViewBuilder private func recognitionButton(_ document: LibraryDocument) -> some View {
        if let progress = recognizer.progress(of: document) {
            HintButton(hint: String(localized: "Sto leggendo il testo di tutte le pagine: tocca per fermare")) {
                recognizer.stop(document)
            } label: {
                Label("Testo \(progress.done)/\(progress.total)", systemImage: "stop.circle")
                    .labelStyle(.titleAndIcon)
                    .monospacedDigit()
            }
        } else if recognizer.isQueued(document) {
            HintButton(String(localized: "In coda"), systemImage: "clock",
                       hint: String(localized: "In attesa di leggere il testo del libro: tocca per annullare")) { recognizer.stop(document) }
                .labelStyle(.titleAndIcon)
        } else if library.recognizedPageCount(of: document) < document.pageCount {
            HintButton(String(localized: "Riconosci tutto il libro"), systemImage: "text.viewfinder",
                       hint: String(localized: "Legge il testo di tutte le pagine in sottofondo, così ricerca e traduzione sono subito pronte")) {
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
            Button(current == nil ? String(localized: "Aggiungi con un nome…") : String(localized: "Rinomina…"), systemImage: "pencil") {
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
            HintButton(String(localized: "Esci dalla modalità studio"), systemImage: "highlighter",
                       hint: String(localized: "Torna alla traduzione: la Pencil cerchia di nuovo le parole"), action: toggle)
                .buttonStyle(.borderedProminent)
                .tint(.orange)
        } else {
            HintButton(String(localized: "Modalità studio"), systemImage: "highlighter",
                       hint: String(localized: "Con la Pencil evidenzi, sottolinei e scrivi a margine invece di tradurre"), action: toggle)
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
            HintButton(String(localized: "Pagina precedente"), systemImage: "chevron.left", hint: String(localized: "Torna alla pagina precedente")) { model.previousPage() }
                .disabled(model.pageIndex == 0)
            HintButton(hint: String(localized: "Tutte le pagine in miniatura, per saltare a quella che vuoi")) {
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
            HintButton(String(localized: "Pagina successiva"), systemImage: "chevron.right", hint: String(localized: "Va alla pagina successiva")) { model.nextPage() }
                .disabled(model.pageIndex + 1 >= model.pageCount)
            if let bookmarks { bookmarkButton(bookmarks, model: model) }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let study { studyButton(study, model: model) }
            recognitionButton(model.document)
            Button("Riepilogo", systemImage: "list.bullet.rectangle.portrait") {
                // So the marks and the note being written show up to date in the summary.
                study?.flush()
                notebook?.flush()
                // The page open now joins the summary's groups as soon as the AI answers.
                model.groupHighlights(of: model.pageIndex)
                showSummary = true
            }
            HintButton(String(localized: "Cerca nel libro"), systemImage: "magnifyingglass", hint: String(localized: "Cerca una parola in tutto il libro")) {
                if search == nil { search = BookSearch(document: document, library: library) }
                showSearch = true
            }
            // Less used: kept in the menu so the bar stays light.
            Menu("Altro", systemImage: "ellipsis") {
                Section {
                    Button("Note del libro", systemImage: "note.text") {
                        // So the page being written on shows up to date in the list.
                        notebook?.flush()
                        showNotes = true
                    }
                    Button("Segnalibri", systemImage: "bookmark") { showBookmarks = true }
                    Button("Parole cercate", systemImage: "character.book.closed") { showWords = true }
                    Button("Rielaborazioni", systemImage: "brain.head.profile") { showRecaps = true }
                }
                Section {
                    themeMenu
                    Button("Esporta PDF", systemImage: "square.and.arrow.up") {
                        // So what was just written is in the PDF.
                        notebook?.flush()
                        study?.flush()
                        showExport = true
                    }
                }
                Button("Impostazioni", systemImage: "gearshape") { showSettings = true }
            }
        }
    }
}

/// How far into the book the open page is: a thin line along the bottom of the page.
private struct ReadingProgressBar: View {
    let page: Int
    let pageCount: Int

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.accentColor)
                .frame(width: geo.size.width * Double(page + 1) / Double(max(pageCount, 1)))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 3)
        .background(Color.secondary.opacity(0.15))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.snappy, value: page)
    }
}
