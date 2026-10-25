import ReaderCore
import SwiftUI

/// The bookmarked pages of the book, in page order: tap to jump, swipe to rename or remove.
struct BookmarksListView: View {
    let bookmarks: BookmarkStore
    let thumbnails: PageThumbnails?
    let currentPage: Int
    let select: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var renaming: Bookmark?

    var body: some View {
        NavigationStack {
            Group {
                if bookmarks.bookmarks.isEmpty {
                    ContentUnavailableView("Nessun segnalibro", systemImage: "bookmark",
                                           description: Text("Tocca il segnalibro nella barra per segnare la pagina che stai leggendo."))
                } else {
                    List(bookmarks.bookmarks) { mark in
                        Button {
                            select(mark.page)
                            dismiss()
                        } label: {
                            row(mark)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button("Rimuovi", systemImage: "bookmark.slash", role: .destructive) {
                                bookmarks.remove(mark.page)
                            }
                            Button("Rinomina", systemImage: "pencil") { renaming = mark }
                                .tint(.blue)
                        }
                        .contextMenu {
                            Button("Rinomina", systemImage: "pencil") { renaming = mark }
                            Button("Rimuovi", systemImage: "bookmark.slash", role: .destructive) {
                                bookmarks.remove(mark.page)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Segnalibri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
            .bookmarkTitleAlert(item: $renaming) { mark, title in bookmarks.add(mark.page, title: title) }
        }
    }

    private func row(_ mark: Bookmark) -> some View {
        HStack(spacing: 16) {
            if let thumbnails { BookmarkThumbnail(page: mark.page, thumbnails: thumbnails) }
            VStack(alignment: .leading, spacing: 2) {
                Text(mark.title)
                    .font(.headline)
                if mark.customTitle != nil {
                    Text(Bookmark.defaultTitle(page: mark.page))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer()
            if mark.page == currentPage {
                Text("Qui")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

private struct BookmarkThumbnail: View {
    let page: Int
    let thumbnails: PageThumbnails

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
        .overlay(alignment: .topTrailing) { BookmarkRibbon(height: 18).padding(.trailing, 6) }
        .task(id: page) { image = await thumbnails.thumbnail(at: page) }
    }
}

/// The red ribbon hanging from the top edge of a bookmarked page.
struct BookmarkRibbon: View {
    var height: CGFloat = 30

    static let color = Color(red: 0.86, green: 0.16, blue: 0.2)

    var body: some View {
        RibbonShape()
            .fill(Self.color)
            .frame(width: height * 0.55, height: height)
            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            .accessibilityLabel("Segnalibro")
    }
}

private struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.width * 0.45))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

extension View {
    /// Asks for a bookmark's name; an empty name keeps "Pagina N".
    func bookmarkTitleAlert(item: Binding<Bookmark?>, save: @escaping (Bookmark, String) -> Void) -> some View {
        modifier(BookmarkTitleAlert(item: item, save: save))
    }
}

private struct BookmarkTitleAlert: ViewModifier {
    @Binding var item: Bookmark?
    let save: (Bookmark, String) -> Void
    @State private var text = ""

    func body(content: Content) -> some View {
        content
            .alert("Nome del segnalibro", isPresented: Binding(get: { item != nil },
                                                               set: { if !$0 { item = nil } })) {
                TextField(item.map { Bookmark.defaultTitle(page: $0.page) } ?? "", text: $text)
                Button("Annulla", role: .cancel) {}
                Button("Salva") { if let item { save(item, text) } }
            } message: {
                Text("Lascia vuoto per chiamarlo \"\(item.map { Bookmark.defaultTitle(page: $0.page) } ?? "")\".")
            }
            .onChange(of: item) { _, mark in text = mark?.customTitle ?? "" }
    }
}
