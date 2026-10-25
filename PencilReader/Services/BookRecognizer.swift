import Foundation
import Observation
import PDFKit
import ReaderCore
import UIKit

/// Recognizes every page of a book in the background, one book at a time,
/// so circling a word never has to wait for OCR. Pages already recognized
/// are skipped: stopping and starting again resumes where it left off.
@MainActor
@Observable
final class BookRecognizer {
    struct Progress {
        let documentID: UUID
        var done: Int
        let total: Int
    }

    private(set) var current: Progress?
    private(set) var queue: [UUID] = []

    private let library: Library
    private let ocr = OCRService()
    private var runner: Task<Void, Never>?
    private var job: Task<Void, Never>?

    init(library: Library) {
        self.library = library
    }

    func progress(of document: LibraryDocument) -> Progress? {
        current?.documentID == document.id ? current : nil
    }

    func isQueued(_ document: LibraryDocument) -> Bool { queue.contains(document.id) }

    func isActive(for document: LibraryDocument) -> Bool {
        progress(of: document) != nil || isQueued(document)
    }

    func start(_ document: LibraryDocument) {
        guard !isActive(for: document) else { return }
        queue.append(document.id)
        if runner == nil { runner = Task { await run() } }
    }

    func stop(_ document: LibraryDocument) {
        queue.removeAll { $0 == document.id }
        if current?.documentID == document.id { job?.cancel() }
    }

    private func run() async {
        // The screen would otherwise lock and suspend the app halfway through a book.
        UIApplication.shared.isIdleTimerDisabled = true
        while !queue.isEmpty {
            let id = queue.removeFirst()
            guard let document = library.document(withID: id) else { continue }
            let job = Task { await recognize(document) }
            self.job = job
            await job.value
            self.job = nil
            current = nil
        }
        UIApplication.shared.isIdleTimerDisabled = false
        runner = nil
    }

    private func recognize(_ document: LibraryDocument) async {
        let pending = (0..<document.pageCount).filter { !library.hasSavedText(of: document, page: $0) }
        current = Progress(documentID: document.id, done: document.pageCount - pending.count, total: document.pageCount)
        let renderer = switch document.kind {
        case .pdf: PageRenderer(pdfURL: library.pdfURL(of: document), pagesFolder: nil)
        case .images: PageRenderer(pdfURL: nil, pagesFolder: library.imageURL(of: document, page: 0).deletingLastPathComponent())
        }
        let ocr = self.ocr

        for page in pending {
            if Task.isCancelled { return }
            // The reader may have recognized it in the meantime.
            if !library.hasSavedText(of: document, page: page) {
                // Vision fails when the app leaves the foreground mid-page: wait and retry once.
                for _ in 1...2 {
                    await waitUntilActive()
                    if Task.isCancelled { return }
                    do {
                        let text = try await Task.detached(priority: .utility) {
                            guard let image = await renderer.image(at: page) else { return PageText(lines: []) }
                            return try await ocr.recognize(image)
                        }.value
                        // Gone if the book was deleted meanwhile.
                        guard library.document(withID: document.id) != nil else { return }
                        if !library.hasSavedText(of: document, page: page) {
                            library.saveText(text, of: document, page: page)
                        }
                        break
                    } catch {
                        // After the second failure the page is left for the next run.
                    }
                }
            }
            current?.done += 1
        }
    }

    private func waitUntilActive() async {
        while UIApplication.shared.applicationState != .active, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
        }
    }
}

/// Renders page bitmaps off the main thread with its own PDFDocument.
private actor PageRenderer {
    private let pdf: PDFDocument?
    private let pagesFolder: URL?

    init(pdfURL: URL?, pagesFolder: URL?) {
        pdf = pdfURL.flatMap(PDFDocument.init(url:))
        self.pagesFolder = pagesFolder
    }

    func image(at index: Int) -> CGImage? {
        autoreleasepool {
            if let pdf {
                return pdf.page(at: index).flatMap { PageImages.render($0).cgImage }
            }
            guard let pagesFolder else { return nil }
            let url = pagesFolder.appending(path: String(format: "%04d.jpg", index))
            return UIImage(contentsOfFile: url.path(percentEncoded: false))?.cgImage
        }
    }
}
