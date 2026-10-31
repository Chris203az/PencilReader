import SwiftUI

/// The PDF's chapters and sections: tapping one opens its page.
struct OutlineView: View {
    let entries: [OutlineEntry]
    let currentPage: Int
    let select: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    /// The chapter the open page belongs to: the last one starting at or before it.
    private var currentEntry: OutlineEntry? {
        entries.last { $0.page <= currentPage }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(entries) { entry in
                    Button {
                        select(entry.page)
                        dismiss()
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.title)
                                .font(entry.level == 0 ? .body.weight(.semibold) : .body)
                                .foregroundStyle(entry.level == 0 ? .primary : .secondary)
                                .padding(.leading, CGFloat(min(entry.level, 4)) * 18)
                            Spacer()
                            Text("\(entry.page + 1)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(entry == currentEntry ? Color.accentColor.opacity(0.12) : nil)
                    .id(entry.id)
                }
                .tint(.primary)
                .onAppear { if let currentEntry { proxy.scrollTo(currentEntry.id, anchor: .center) } }
            }
            .navigationTitle("Indice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
    }
}
