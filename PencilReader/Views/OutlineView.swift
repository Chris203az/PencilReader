import SwiftUI

/// The PDF's chapters and sections, in a column left of the page: tapping one opens its page.
struct OutlineView: View {
    let entries: [OutlineEntry]
    let currentPage: Int
    let select: (Int) -> Void
    let close: () -> Void

    static let width: CGFloat = 300

    /// The chapter the open page belongs to: the last one starting at or before it.
    private var currentEntry: OutlineEntry? {
        entries.last { $0.page <= currentPage }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Indice").font(.headline)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Chiudi indice")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            ScrollViewReader { proxy in
                List(entries) { entry in
                    Button {
                        select(entry.page)
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.title)
                                .font(entry.level == 0 ? .subheadline.weight(.semibold) : .subheadline)
                                .foregroundStyle(entry.level == 0 ? .primary : .secondary)
                                .padding(.leading, CGFloat(min(entry.level, 4)) * 14)
                            Spacer()
                            Text("\(entry.page + 1)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(entry == currentEntry ? Color.accentColor.opacity(0.12) : nil)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .id(entry.id)
                }
                .listStyle(.plain)
                .tint(.primary)
                // A moment after opening: the list must have laid out its rows first.
                .task {
                    try? await Task.sleep(for: .milliseconds(150))
                    if let currentEntry { proxy.scrollTo(currentEntry.id, anchor: .center) }
                }
                // Follows the reading: the chapter of the open page stays in view.
                .onChange(of: currentEntry) { _, entry in
                    if let entry { withAnimation { proxy.scrollTo(entry.id, anchor: .center) } }
                }
            }
        }
        .frame(width: Self.width)
        .background(Color(.systemBackground))
    }
}
