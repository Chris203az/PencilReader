import PhotosUI
import ReaderCore
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// Home screen: the documents of the current collection, most recently opened
/// first. Tapping the title switches collection.
struct LibraryView: View {
    private enum CollectionEdit: Identifiable {
        case create
        case rename(DocumentCollection)
        var id: String {
            switch self {
            case .create: "create"
            case .rename(let collection): collection.id.uuidString
            }
        }
    }

    let open: (LibraryDocument) -> Void

    @Environment(Library.self) private var library
    @Environment(BookRecognizer.self) private var recognizer
    @Environment(WordList.self) private var wordList
    @Environment(ReviewStore.self) private var reviews
    @Environment(ReadingStats.self) private var stats
    @Environment(\.scenePhase) private var scenePhase
    @State private var showScanner = false
    @State private var showPDFImporter = false
    @State private var showPhotoPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var renaming: LibraryDocument?
    @State private var newTitle = ""
    @State private var deleting: LibraryDocument?
    @State private var alertMessage: String?
    @State private var collectionEdit: CollectionEdit?
    @State private var collectionName = ""
    @State private var deletingCollection: DocumentCollection?
    @State private var showWords = false
    @State private var showReview = false
    @State private var showStats = false
    @State private var showRecaps = false
    @State private var showSettings = false
    @AppStorage(AppSettings.continueReadingKey) private var showsContinueReading = true

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 24)]

    var body: some View {
        Group {
            if library.visibleDocuments.isEmpty {
                ContentUnavailableView {
                    Label("“\(library.currentCollection.name)” è vuota", systemImage: "books.vertical")
                } description: {
                    Text("Scansiona delle pagine, scegli delle foto o importa un PDF. Poi cerchia una parola con la Pencil.")
                } actions: {
                    openButtons.buttonStyle(.bordered)
                }
            } else {
                ScrollView {
                    if let current = continueReading {
                        ContinueReadingCard(document: current, thumbnail: library.thumbnailURL(of: current),
                                            readingTime: stats.log.totalSeconds(of: current.id)) { open(current) }
                            .padding([.horizontal, .top], 24)
                        if !gridDocuments.isEmpty {
                            Text("Altri libri")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                                .padding(.top, 28)
                        }
                    }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                        ForEach(gridDocuments) { document in
                            Button { open(document) } label: {
                                DocumentCard(document: document, thumbnail: library.thumbnailURL(of: document),
                                             recognition: recognitionStatus(of: document),
                                             readingTime: stats.log.totalSeconds(of: document.id))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Rinomina", systemImage: "pencil") {
                                    newTitle = document.title
                                    renaming = document
                                }
                                recognitionButton(for: document)
                                if library.collections.count > 1 {
                                    Menu("Sposta in", systemImage: "folder") {
                                        ForEach(library.collections.filter { $0.id != library.collectionID(of: document) }) { c in
                                            Button(c.name) { library.move(document, to: c) }
                                        }
                                    }
                                }
                                Button("Elimina", systemImage: "trash", role: .destructive) { deleting = document }
                            }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .navigationTitle(library.currentCollection.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleMenu { collectionMenu }
        // Picks up folders restored through the Files app.
        .onAppear { library.reload() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { library.reload() } }
        .toolbar {
            // Always first, top left: the statistics are looked at every day.
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showStats = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.bar.xaxis")
                        Text("Statistiche")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ReviewButton(count: reviews.dueCount(in: wordList.words), showsTitle: true) { showReview = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Rielaborazioni", systemImage: "brain.head.profile") { showRecaps = true }
                    Button("Parole cercate", systemImage: "character.book.closed") { showWords = true }
                } label: {
                    // Written out: a bare symbol would not say what is inside.
                    HStack(spacing: 6) {
                        Image(systemName: "graduationcap")
                        Text("Studio")
                    }
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Impostazioni", systemImage: "gearshape") { showSettings = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Aggiungi", systemImage: "plus") { openButtons }
            }
        }
        .overlay {
            if isImporting {
                ProgressView("Importazione…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().presentationSizing(.page)
        }
        .sheet(isPresented: $showWords) {
            WordsView(currentDocument: nil) { word in
                // Opens the book at the word's page.
                guard let document = library.document(withID: word.documentID) else { return }
                library.setLastPage(word.page, of: document)
                open(document)
            }
            .presentationSizing(.page)
        }
        .sheet(isPresented: $showReview) {
            ReviewView(words: wordList.words) { word in
                guard let document = library.document(withID: word.documentID) else { return }
                library.setLastPage(word.page, of: document)
                open(document)
            }
            .presentationSizing(.page)
        }
        .sheet(isPresented: $showRecaps) {
            RecapListView().presentationSizing(.page)
        }
        .sheet(isPresented: $showStats) {
            ReadingStatsView { document in open(document) }
                .presentationSizing(.form)
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView { pages in
                Task { await importImages(pages, title: "Scansione \(Date.now.formatted(date: .abbreviated, time: .shortened))") }
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showPDFImporter, allowedContentTypes: [.pdf]) { importPDF($0) }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems, maxSelectionCount: 200,
                      selectionBehavior: .ordered, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .alert("Rinomina", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Titolo", text: $newTitle)
            Button("Annulla", role: .cancel) {}
            Button("Salva") { if let renaming { library.rename(renaming, to: newTitle) } }
        }
        .confirmationDialog("Eliminare “\(deleting?.title ?? "")”?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                if let deleting {
                    recognizer.stop(deleting)
                    stats.remove(deleting.id)
                    library.delete(deleting)
                }
            }
        } message: {
            Text("Il documento e il testo riconosciuto verranno rimossi dall'app.")
        }
        .alert(collectionEditTitle, isPresented: Binding(get: { collectionEdit != nil },
                                                         set: { if !$0 { collectionEdit = nil } })) {
            TextField("Nome", text: $collectionName)
            Button("Annulla", role: .cancel) {}
            Button(collectionEditButton) { saveCollectionEdit() }
        }
        .confirmationDialog("Eliminare la libreria “\(deletingCollection?.name ?? "")”?",
                            isPresented: Binding(get: { deletingCollection != nil },
                                                 set: { if !$0 { deletingCollection = nil } }),
                            titleVisibility: .visible) {
            if let doomed = deletingCollection {
                ForEach(library.collections.filter { $0.id != doomed.id }) { destination in
                    Button(library.documentCount(in: doomed) == 0 ? "Elimina" : "Sposta i libri in “\(destination.name)” ed elimina",
                           role: .destructive) {
                        library.delete(doomed, movingDocumentsTo: destination)
                    }
                }
            }
        } message: {
            Text("I libri non vengono cancellati.")
        }
        .alert("Errore", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    /// The book opened last, shown large at the top.
    private var continueReading: LibraryDocument? {
        showsContinueReading ? library.visibleDocuments.first : nil
    }

    private var gridDocuments: [LibraryDocument] {
        continueReading == nil ? library.visibleDocuments : Array(library.visibleDocuments.dropFirst())
    }

    @ViewBuilder private var collectionMenu: some View {
        ForEach(library.collections) { collection in
            Button {
                library.select(collection)
            } label: {
                if collection.id == library.currentCollection.id {
                    Label("\(collection.name) (\(library.documentCount(in: collection)))", systemImage: "checkmark")
                } else {
                    Text("\(collection.name) (\(library.documentCount(in: collection)))")
                }
            }
        }
        Divider()
        Button("Nuova libreria…", systemImage: "plus") {
            collectionName = ""
            collectionEdit = .create
        }
        Button("Rinomina “\(library.currentCollection.name)”…", systemImage: "pencil") {
            collectionName = library.currentCollection.name
            collectionEdit = .rename(library.currentCollection)
        }
        if library.collections.count > 1 {
            Button("Elimina “\(library.currentCollection.name)”…", systemImage: "trash", role: .destructive) {
                deletingCollection = library.currentCollection
            }
        }
    }

    @ViewBuilder private func recognitionButton(for document: LibraryDocument) -> some View {
        if recognizer.isActive(for: document) {
            Button("Interrompi riconoscimento", systemImage: "stop.circle") { recognizer.stop(document) }
        } else {
            let done = library.recognizedPageCount(of: document)
            if done < document.pageCount {
                Button("Riconosci tutto il testo (\(done)/\(document.pageCount))", systemImage: "text.viewfinder") {
                    recognizer.start(document)
                }
            }
        }
    }

    private func recognitionStatus(of document: LibraryDocument) -> String? {
        if let progress = recognizer.progress(of: document) {
            return "Riconoscimento \(progress.done)/\(progress.total)"
        }
        return recognizer.isQueued(document) ? "In coda per il riconoscimento" : nil
    }

    private var collectionEditTitle: String {
        if case .rename = collectionEdit { return "Rinomina libreria" }
        return "Nuova libreria"
    }

    private var collectionEditButton: String {
        if case .rename = collectionEdit { return "Salva" }
        return "Crea"
    }

    private func saveCollectionEdit() {
        switch collectionEdit {
        case .create: library.createCollection(named: collectionName)
        case .rename(let collection): library.rename(collection, to: collectionName)
        case nil: break
        }
    }

    @ViewBuilder private var openButtons: some View {
        if VNDocumentCameraViewController.isSupported {
            Button("Scansiona pagine", systemImage: "doc.viewfinder") { showScanner = true }
        }
        Button("Scegli foto", systemImage: "photo.on.rectangle") { showPhotoPicker = true }
        Button("Importa PDF", systemImage: "doc.richtext") { showPDFImporter = true }
    }

    // MARK: Import

    private func importPDF(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            open(try library.importPDF(from: url))
        } catch {
            alertMessage = "Impossibile importare il PDF: \(error.localizedDescription)"
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        isImporting = true
        defer { photoItems = [] }
        var images: [UIImage] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            let page = await Task.detached(priority: .userInitiated) {
                PageImages.straightened(PageImages.normalized(image))
            }.value
            images.append(page)
        }
        await importImages(images, title: images.count == 1 ? "Foto" : "\(images.count) foto")
    }

    private func importImages(_ images: [UIImage], title: String) async {
        isImporting = true
        defer { isImporting = false }
        guard !images.isEmpty else {
            alertMessage = "Nessuna pagina importata."
            return
        }
        do {
            open(try await library.importImages(images, title: title))
        } catch {
            alertMessage = "Impossibile salvare le pagine: \(error.localizedDescription)"
        }
    }
}

private struct DocumentCard: View {
    let document: LibraryDocument
    let thumbnail: URL
    let recognition: String?
    let readingTime: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BookCover(thumbnail: thumbnail)

            Text(document.displayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
            Text("Pagina \(document.lastPage + 1) di \(document.pageCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(document.lastPage + 1), total: Double(max(document.pageCount, 1)))
                .tint(.accentColor)
            if readingTime >= 60 {
                Label("\(ReadingLog.duration(readingTime)) di lettura", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let recognition {
                Label(recognition, systemImage: "text.viewfinder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .contentShape(Rectangle())
    }
}

/// A page thumbnail as a book cover: always 3:4, so the shelf lines up whatever the page shape.
private struct BookCover: View {
    let thumbnail: URL

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                AsyncImage(url: thumbnail) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "book.closed")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.black.opacity(0.08)))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
    }
}

/// The book opened last: cover, title, where it was left and a button to go on.
private struct ContinueReadingCard: View {
    let document: LibraryDocument
    let thumbnail: URL
    let readingTime: TimeInterval
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .center, spacing: 24) {
                BookCover(thumbnail: thumbnail)
                    .frame(width: 120)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Continua a leggere")
                        .font(.footnote.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.accentColor)
                    Text(document.displayTitle)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                    Text("Pagina \(document.lastPage + 1) di \(document.pageCount)"
                         + (readingTime >= 60 ? " · \(ReadingLog.duration(readingTime)) di lettura" : ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(document.lastPage + 1), total: Double(max(document.pageCount, 1)))
                        .frame(maxWidth: 320)
                    Label("Riprendi", systemImage: "book")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: Capsule())
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

extension LibraryDocument {
    /// The title as shown: a file name like "nasa_systems_engineering_handbook_0" becomes
    /// "Nasa systems engineering handbook". The saved title does not change.
    var displayTitle: String {
        var words = title.replacingOccurrences(of: "_", with: " ").split(separator: " ").map(String.init)
        // A lone trailing "0" or "1" is a copy number added to the file, not part of the title.
        if title.contains("_"), words.count > 1, let last = words.last, last.count == 1, last.allSatisfy(\.isNumber) {
            words.removeLast()
        }
        let cleaned = words.joined(separator: " ")
        guard let first = cleaned.first, first.isLowercase else { return cleaned.isEmpty ? title : cleaned }
        return first.uppercased() + cleaned.dropFirst()
    }
}
