import ReaderCore
import SwiftUI

/// Search in the whole book; tapping a result opens its page with the words highlighted.
struct SearchView: View {
    let document: LibraryDocument
    @Bindable var search: BookSearch
    let select: (_ page: Int, _ wordIDs: [Int]) -> Void

    @Environment(BookRecognizer.self) private var recognizer
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    private var matchCount: Int { search.results.reduce(0) { $0 + $1.matches.count } }

    var body: some View {
        NavigationStack {
            List {
                if search.missingPages > 0 {
                    Section {
                        missingPagesNote
                    }
                }
                if !search.results.isEmpty {
                    Section {
                        Text(matchCount == 1 ? "1 risultato" : "\(matchCount) risultati in \(search.results.count) pagine")
                            .font(.footnote)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .listRowBackground(Color.clear)
                    }
                }
                ForEach(search.results) { result in
                    Section("Pagina \(result.page + 1)") {
                        ForEach(Array(result.matches.enumerated()), id: \.offset) { _, match in
                            Button {
                                select(result.page, match.wordIDs)
                                dismiss()
                            } label: {
                                Text(highlighted(match))
                                    .font(.callout)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .overlay {
                if search.isSearching {
                    ProgressView()
                } else if search.results.isEmpty, !search.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView.search(text: search.query)
                }
            }
            .searchable(text: $search.query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Cerca nel libro")
            .searchFocused($focused)
            .onAppear {
                focused = search.query.isEmpty
                if !search.query.isEmpty { search.search() }
            }
            .navigationTitle("Cerca in “\(document.title)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder private var missingPagesNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(search.missingPages == 1
                  ? "1 pagina non è ancora stata riconosciuta: lì la ricerca non trova nulla."
                  : "\(search.missingPages) pagine non sono ancora state riconosciute: lì la ricerca non trova nulla.",
                  systemImage: "exclamationmark.triangle")
                .font(.footnote)
            if let progress = recognizer.progress(of: document) {
                Text("Riconoscimento in corso: \(progress.done)/\(progress.total)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            } else if recognizer.isQueued(document) {
                Text("In coda per il riconoscimento")
                    .font(.footnote)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            } else {
                Button("Riconosci tutto il libro", systemImage: "text.viewfinder") { recognizer.start(document) }
                    .font(.footnote)
            }
        }
    }

    private func highlighted(_ match: SearchMatch) -> AttributedString {
        var result = AttributedString(match.snippet)
        result.foregroundColor = Color(uiColor: .secondaryLabel)
        let snippet = match.snippet
        let chars = result.characters
        let lower = chars.index(chars.startIndex, offsetBy: snippet.distance(from: snippet.startIndex, to: match.highlight.lowerBound))
        let upper = chars.index(lower, offsetBy: snippet.distance(from: match.highlight.lowerBound, to: match.highlight.upperBound))
        result[lower..<upper].foregroundColor = Color(uiColor: .label)
        result[lower..<upper].backgroundColor = .orange.opacity(0.35)
        result[lower..<upper].font = .callout.weight(.semibold)
        return result
    }
}
