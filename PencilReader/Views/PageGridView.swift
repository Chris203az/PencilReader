import ImageIO
import PDFKit
import SwiftUI

/// Thumbnails of every page, to jump quickly to one of them.
struct PageGridView: View {
    let pageCount: Int
    let currentPage: Int
    let thumbnails: PageThumbnails
    /// Pages that have a handwritten note, marked on their thumbnail.
    var notedPages: Set<Int> = []
    /// Pages with study marks, marked differently from the notes.
    var markedPages: Set<Int> = []
    let select: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 170), spacing: 20)]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(0..<pageCount, id: \.self) { index in
                            Button {
                                select(index)
                                dismiss()
                            } label: {
                                PageThumbnailCell(index: index, isCurrent: index == currentPage,
                                                  hasNote: notedPages.contains(index),
                                                  hasMarks: markedPages.contains(index), thumbnails: thumbnails)
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                    .padding(24)
                }
                .onAppear { proxy.scrollTo(currentPage, anchor: .center) }
            }
            .navigationTitle("Pagine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
    }
}

private struct PageThumbnailCell: View {
    let index: Int
    let isCurrent: Bool
    let hasNote: Bool
    let hasMarks: Bool
    let thumbnails: PageThumbnails

    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(height: 190)
            .frame(maxWidth: .infinity)
            .overlay {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: 3)
                }
            }
            .overlay(alignment: .topTrailing) {
                if hasNote {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange, .white)
                        .padding(6)
                        .accessibilityLabel("Ha una nota")
                }
            }
            .overlay(alignment: .topLeading) {
                if hasMarks {
                    Image(systemName: "highlighter")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(width: 26, height: 26)
                        .background(Color(uiColor: StudyColor.key.uiColor), in: Circle())
                        .padding(6)
                        .accessibilityLabel("Ha segni di studio")
                }
            }
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)

            Text("\(index + 1)")
                .font(.caption.weight(isCurrent ? .bold : .regular))
                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .task(id: index) { image = await thumbnails.thumbnail(at: index) }
    }
}

/// Small page images, rendered off the main thread. Kept in memory while the
/// book is open and on disk in Caches/Thumbnails/<book id>/, so the grid
/// opens instantly the second time.
actor PageThumbnails {
    /// The size of a grid cell: PDFKit renders it at the screen scale.
    private static let cellSize = CGSize(width: 170, height: 190)
    /// Pixel cap for page images, the cell height at 2×.
    private static let maxPixels: CGFloat = 380

    private let pdfURL: URL?
    private let pagesFolder: URL?
    private let pageCount: Int
    private let diskFolder: URL
    /// Opened on first use, off the main thread. Own instance: PDFDocument is not
    /// thread-safe, so it must not be shared with the page view or the OCR.
    private var pdf: PDFDocument?
    private let memory = NSCache<NSNumber, UIImage>()

    init(bookID: UUID, pageCount: Int, pdfURL: URL?, pagesFolder: URL?) {
        self.pdfURL = pdfURL
        self.pagesFolder = pagesFolder
        self.pageCount = pageCount
        diskFolder = Self.cacheFolder(of: bookID)
        try? FileManager.default.createDirectory(at: diskFolder, withIntermediateDirectories: true)
        memory.totalCostLimit = 50 * 1024 * 1024
    }

    static func cacheFolder(of bookID: UUID) -> URL {
        URL.cachesDirectory.appending(path: "Thumbnails/\(bookID.uuidString)", directoryHint: .isDirectory)
    }

    static func deleteCache(of bookID: UUID) {
        try? FileManager.default.removeItem(at: cacheFolder(of: bookID))
    }

    func thumbnail(at index: Int) -> UIImage? {
        if let cached = memory.object(forKey: index as NSNumber) { return cached }
        // Cells scrolled past before their turn don't need rendering.
        if Task.isCancelled { return nil }
        let image = autoreleasepool { fromDisk(index) ?? renderAndSave(index) }
        if let image { memory.setObject(image, forKey: index as NSNumber, cost: Self.cost(of: image)) }
        return image
    }

    /// Saves to disk, at low priority, the pages not cached yet: first the ones
    /// after `page`, then the ones before. Stops as soon as the task is cancelled.
    func prefetch(from page: Int) async {
        let start = min(max(page, 0), pageCount)
        for index in Array(start..<pageCount) + Array(0..<start).reversed() {
            if Task.isCancelled { return }
            if !FileManager.default.fileExists(atPath: diskURL(index).path(percentEncoded: false)) {
                autoreleasepool { _ = renderAndSave(index) }
            }
            // Lets the grid cells, at higher priority, go first.
            await Task.yield()
        }
    }

    private func diskURL(_ index: Int) -> URL {
        diskFolder.appending(path: String(format: "%04d.jpg", index))
    }

    private func fromDisk(_ index: Int) -> UIImage? {
        guard let data = try? Data(contentsOf: diskURL(index)), let image = UIImage(data: data) else { return nil }
        // Decoded here rather than on the main thread while scrolling.
        return image.preparingForDisplay() ?? image
    }

    private func renderAndSave(_ index: Int) -> UIImage? {
        guard let image = render(index) else { return nil }
        try? image.jpegData(compressionQuality: 0.7)?.write(to: diskURL(index), options: .atomic)
        return image
    }

    private func render(_ index: Int) -> UIImage? {
        if let pdfURL {
            if pdf == nil { pdf = PDFDocument(url: pdfURL) }
            return pdf?.page(at: index)?.thumbnail(of: Self.cellSize, for: .cropBox)
        }
        guard let pagesFolder else { return nil }
        let url = pagesFolder.appending(path: String(format: "%04d.jpg", index))
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: Self.maxPixels] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
