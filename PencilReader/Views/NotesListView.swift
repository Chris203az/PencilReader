import PencilKit
import SwiftUI

/// Every page of the book that has a handwritten note, to jump straight to one of them.
struct NotesListView: View {
    let bookID: UUID
    let pages: [Int]
    let select: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if pages.isEmpty {
                    ContentUnavailableView("Nessuna nota", systemImage: "square.and.pencil",
                                           description: Text("Le note scritte sulle pagine del libro compaiono qui."))
                } else {
                    List(pages, id: \.self) { page in
                        Button {
                            select(page)
                            dismiss()
                        } label: {
                            HStack(spacing: 16) {
                                NoteThumbnail(bookID: bookID, page: page)
                                Text("Pagina \(page + 1)")
                                    .font(.headline)
                                    .monospacedDigit()
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Note del libro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
    }
}

/// The handwriting of one page, scaled down, on the paper's white.
private struct NoteThumbnail: View {
    let bookID: UUID
    let page: Int

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .frame(width: 56, height: 76)
        .background(Color(.systemBackground))
        .overlay(Rectangle().stroke(.quaternary, lineWidth: 1))
        .task(id: page) { image = Self.thumbnail(of: bookID, page: page) }
    }

    private static func thumbnail(of bookID: UUID, page: Int) -> UIImage? {
        guard let drawing = NoteStore.drawing(of: bookID, page: page), !drawing.bounds.isEmpty else { return nil }
        return drawing.image(from: drawing.bounds, scale: 0.5)
    }
}
