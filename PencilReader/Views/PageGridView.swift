import ImageIO
import PDFKit
import SwiftUI

/// Thumbnails of every page, to jump quickly to one of them.
struct PageGridView: View {
    let pageCount: Int
    let currentPage: Int
    let thumbnails: PageThumbnails
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
                                PageThumbnailCell(index: index, isCurrent: index == currentPage, thumbnails: thumbnails)
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

/// Small page images, rendered off the main thread and kept in memory while
/// the document is open.
actor PageThumbnails {
    private static let maxPixels: CGFloat = 400

    private let pdf: PDFDocument?
    private let pagesFolder: URL?
    private let cache = NSCache<NSNumber, UIImage>()

    init(pdfURL: URL?, pagesFolder: URL?) {
        pdf = pdfURL.flatMap(PDFDocument.init(url:))
        self.pagesFolder = pagesFolder
        cache.countLimit = 200
    }

    func thumbnail(at index: Int) -> UIImage? {
        if let cached = cache.object(forKey: index as NSNumber) { return cached }
        // Cells scrolled past before their turn don't need rendering.
        if Task.isCancelled { return nil }
        let image = autoreleasepool { render(index) }
        if let image { cache.setObject(image, forKey: index as NSNumber) }
        return image
    }

    private func render(_ index: Int) -> UIImage? {
        if let pdf {
            return pdf.page(at: index).map { PageImages.render($0, maxDimension: Self.maxPixels) }
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
}
