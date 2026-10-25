import Foundation
import Observation
import PDFKit
import ReaderCore
import UIKit

/// A book or set of pages stored inside the app.
struct LibraryDocument: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case pdf
        case images
    }

    let id: UUID
    var title: String
    let kind: Kind
    let pageCount: Int
    let createdAt: Date
    var lastOpenedAt: Date
    var lastPage: Int
    /// Nil for documents saved before collections existed: they belong to the first one.
    var collectionID: UUID?
}

/// A user-defined group of documents ("Università", "Privati", …).
struct DocumentCollection: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
}

/// Documents live in Documents/Libreria/<id>/ (visible in the Files app, so
/// the folder can be copied out as a backup and copied back to restore):
///   meta.json, thumbnail.jpg, document.pdf or pages/NNNN.jpg, ocr/NNNN.json
/// Collections are listed in Documents/Libreria/collections.json.
@MainActor
@Observable
final class Library {
    private(set) var documents: [LibraryDocument] = []
    private(set) var collections: [DocumentCollection] = []
    private(set) var currentCollectionID: UUID?

    private let root: URL
    private let fileManager = FileManager.default

    init() {
        root = URL.documentsDirectory.appending(path: "Libreria", directoryHint: .isDirectory)
        // First versions kept the library hidden in Application Support.
        let legacy = URL.applicationSupportDirectory.appending(path: "Library", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: legacy.path(percentEncoded: false)),
           !fileManager.fileExists(atPath: root.path(percentEncoded: false)) {
            try? fileManager.moveItem(at: legacy, to: root)
        }
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        loadCollections()
        let folders = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        documents = folders
            .compactMap { try? Data(contentsOf: $0.appending(path: "meta.json")) }
            .compactMap { try? JSONDecoder().decode(LibraryDocument.self, from: $0) }
            .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    // MARK: Collections

    private static let currentCollectionKey = "currentCollectionID"
    private var collectionsURL: URL { root.appending(path: "collections.json") }

    var currentCollection: DocumentCollection {
        collections.first { $0.id == currentCollectionID } ?? collections[0]
    }

    /// Documents of the current collection, most recently opened first.
    var visibleDocuments: [LibraryDocument] {
        documents.filter { collectionID(of: $0) == currentCollection.id }
    }

    func collectionID(of document: LibraryDocument) -> UUID {
        if let id = document.collectionID, collections.contains(where: { $0.id == id }) { return id }
        return collections[0].id
    }

    func documentCount(in collection: DocumentCollection) -> Int {
        documents.filter { collectionID(of: $0) == collection.id }.count
    }

    func select(_ collection: DocumentCollection) {
        currentCollectionID = collection.id
        UserDefaults.standard.set(collection.id.uuidString, forKey: Self.currentCollectionKey)
    }

    func createCollection(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let collection = DocumentCollection(id: UUID(), name: trimmed)
        collections.append(collection)
        saveCollections()
        select(collection)
    }

    func rename(_ collection: DocumentCollection, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        collections[index].name = trimmed
        saveCollections()
    }

    /// Removes the collection; its documents are moved, never deleted.
    func delete(_ collection: DocumentCollection, movingDocumentsTo destination: DocumentCollection) {
        guard collection.id != destination.id, collections.count > 1 else { return }
        for document in documents where collectionID(of: document) == collection.id {
            update(document.id) { $0.collectionID = destination.id }
        }
        collections.removeAll { $0.id == collection.id }
        saveCollections()
        select(destination)
    }

    func move(_ document: LibraryDocument, to collection: DocumentCollection) {
        update(document.id) { $0.collectionID = collection.id }
    }

    private func loadCollections() {
        if let data = try? Data(contentsOf: collectionsURL),
           let saved = try? JSONDecoder().decode([DocumentCollection].self, from: data), !saved.isEmpty {
            collections = saved
        } else if collections.isEmpty {
            collections = [DocumentCollection(id: UUID(), name: "Libreria")]
            saveCollections()
        }
        let stored = UserDefaults.standard.string(forKey: Self.currentCollectionKey).flatMap(UUID.init)
        currentCollectionID = collections.contains { $0.id == stored } ? stored : collections[0].id
    }

    private func saveCollections() {
        try? JSONEncoder().encode(collections).write(to: collectionsURL, options: .atomic)
    }

    // MARK: Paths

    func folder(of document: LibraryDocument) -> URL { root.appending(path: document.id.uuidString) }
    func pdfURL(of document: LibraryDocument) -> URL { folder(of: document).appending(path: "document.pdf") }
    func thumbnailURL(of document: LibraryDocument) -> URL { folder(of: document).appending(path: "thumbnail.jpg") }

    func imageURL(of document: LibraryDocument, page: Int) -> URL {
        folder(of: document).appending(path: "pages").appending(path: String(format: "%04d.jpg", page))
    }

    func ocrURL(of document: LibraryDocument, page: Int) -> URL {
        folder(of: document).appending(path: "ocr").appending(path: String(format: "%04d.json", page))
    }

    // MARK: Import

    /// Copies a PDF into the library. `url` must be readable (security scope already started).
    func importPDF(from url: URL) throws -> LibraryDocument {
        let id = UUID()
        let folder = root.appending(path: id.uuidString)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let destination = folder.appending(path: "document.pdf")
            try fileManager.copyItem(at: url, to: destination)
            guard let pdf = PDFDocument(url: destination), pdf.pageCount > 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            if let first = pdf.page(at: 0) {
                try? PageImages.render(first, maxDimension: 400).jpegData(compressionQuality: 0.8)?
                    .write(to: folder.appending(path: "thumbnail.jpg"))
            }
            let document = LibraryDocument(id: id, title: url.deletingPathExtension().lastPathComponent,
                                           kind: .pdf, pageCount: pdf.pageCount, createdAt: .now,
                                           lastOpenedAt: .now, lastPage: 0, collectionID: currentCollection.id)
            try save(document)
            return document
        } catch {
            try? fileManager.removeItem(at: folder)
            throw error
        }
    }

    /// Stores scanned or photographed pages as JPEG files.
    func importImages(_ images: [UIImage], title: String) async throws -> LibraryDocument {
        let id = UUID()
        let folder = root.appending(path: id.uuidString)
        let pages = folder.appending(path: "pages")
        try fileManager.createDirectory(at: pages, withIntermediateDirectories: true)
        do {
            try await Task.detached(priority: .userInitiated) {
                for (i, image) in images.enumerated() {
                    guard let data = image.jpegData(compressionQuality: 0.9) else { throw CocoaError(.fileWriteUnknown) }
                    try data.write(to: pages.appending(path: String(format: "%04d.jpg", i)))
                }
                if let first = images.first {
                    try? PageImages.normalized(first, maxDimension: 400).jpegData(compressionQuality: 0.8)?
                        .write(to: folder.appending(path: "thumbnail.jpg"))
                }
            }.value
            let document = LibraryDocument(id: id, title: title, kind: .images, pageCount: images.count,
                                           createdAt: .now, lastOpenedAt: .now, lastPage: 0,
                                           collectionID: currentCollection.id)
            try save(document)
            return document
        } catch {
            try? fileManager.removeItem(at: folder)
            throw error
        }
    }

    // MARK: Updates

    func markOpened(_ document: LibraryDocument) {
        update(document.id) { $0.lastOpenedAt = .now }
    }

    func setLastPage(_ page: Int, of document: LibraryDocument) {
        update(document.id) { $0.lastPage = page }
    }

    func rename(_ document: LibraryDocument, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(document.id) { $0.title = trimmed }
    }

    func delete(_ document: LibraryDocument) {
        try? fileManager.removeItem(at: folder(of: document))
        documents.removeAll { $0.id == document.id }
    }

    func document(withID id: UUID) -> LibraryDocument? { documents.first { $0.id == id } }

    private func update(_ id: UUID, _ change: (inout LibraryDocument) -> Void) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        change(&documents[index])
        try? save(documents[index])
        documents.sort { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    private func save(_ document: LibraryDocument) throws {
        let data = try JSONEncoder().encode(document)
        try data.write(to: folder(of: document).appending(path: "meta.json"), options: .atomic)
        if let index = documents.firstIndex(where: { $0.id == document.id }) {
            documents[index] = document
        } else {
            documents.insert(document, at: 0)
        }
    }

    // MARK: OCR cache

    func savedText(of document: LibraryDocument, page: Int) -> PageText? {
        Self.loadText(at: ocrURL(of: document, page: page))
    }

    /// Callable off the main actor, for loading many pages at once.
    nonisolated static func loadText(at url: URL) -> PageText? {
        guard let data = try? Data(contentsOf: url),
              let lines = try? JSONDecoder().decode([RawLine].self, from: data) else { return nil }
        return PageText(lines: lines)
    }

    func hasSavedText(of document: LibraryDocument, page: Int) -> Bool {
        fileManager.fileExists(atPath: ocrURL(of: document, page: page).path(percentEncoded: false))
    }

    func saveText(_ text: PageText, of document: LibraryDocument, page: Int) {
        // A late OCR result must not recreate the folder of a deleted document.
        guard self.document(withID: document.id) != nil else { return }
        let url = ocrURL(of: document, page: page)
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(text.rawLines).write(to: url, options: .atomic)
    }

    func recognizedPageCount(of document: LibraryDocument) -> Int {
        let folder = folder(of: document).appending(path: "ocr")
        return (try? fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false)))?.count ?? 0
    }
}
