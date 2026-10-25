import PhotosUI
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
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                        ForEach(library.visibleDocuments) { document in
                            Button { open(document) } label: {
                                DocumentCard(document: document, thumbnail: library.thumbnailURL(of: document),
                                             recognition: recognitionStatus(of: document))
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
            ToolbarItem(placement: .topBarTrailing) {
                Button("Parole cercate", systemImage: "character.book.closed") { showWords = true }
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
        .sheet(isPresented: $showWords) {
            WordsView(currentDocument: nil) { word in
                // Opens the book at the word's page.
                guard let document = library.document(withID: word.documentID) else { return }
                library.setLastPage(word.page, of: document)
                open(document)
            }
            .presentationSizing(.page)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: thumbnail) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 220)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

            Text(document.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text("Pagina \(document.lastPage + 1) di \(document.pageCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(document.lastPage + 1), total: Double(max(document.pageCount, 1)))
                .tint(.accentColor)
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
