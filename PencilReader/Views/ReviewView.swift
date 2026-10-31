import ReaderCore
import SwiftUI

/// Flashcards of the saved words due today: the English word with its sentence, tap to turn
/// it and see the Italian, then say how well it was known. Forgotten cards come back at the end.
struct ReviewView: View {
    /// The words this review draws from: all of them, or those of one book.
    let words: [SavedWord]
    /// Called when the book and page of a card are tapped, to go there.
    let select: (SavedWord) -> Void

    @Environment(ReviewStore.self) private var reviews
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var session: ReviewSession?
    @State private var turned = false

    private var current: SavedWord? {
        session?.current.flatMap { id in words.first { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let session, let word = current {
                    VStack(spacing: 28) {
                        ProgressView(value: Double(session.done), total: Double(max(session.total, 1))) {
                            Text("\(session.done) di \(session.total)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Color(uiColor: .secondaryLabel))
                        }
                        FlashCard(word: word, turned: turned,
                                  canOpen: library.document(withID: word.documentID) != nil) {
                            select(word)
                            dismiss()
                        }
                        .onTapGesture { withAnimation(.snappy) { turned.toggle() } }
                        .id(word.id)
                        grades(for: word)
                    }
                    .padding(32)
                    .frame(maxWidth: 700)
                } else if let session, session.total > 0 {
                    ContentUnavailableView {
                        Label("Ripasso finito", systemImage: "checkmark.seal")
                    } description: {
                        Text(session.forgotten == 0
                             ? "\(cards(session.total)) ripassate, tutte al primo colpo."
                             : "\(cards(session.total)) ripassate; \(session.forgotten) volte “Non la sapevo”.")
                    } actions: {
                        Button("Fine") { dismiss() }.buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView {
                        Label("Niente da ripassare oggi", systemImage: "rectangle.on.rectangle.angled")
                    } description: {
                        Text(nextReviewText)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Ripasso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
        .onAppear {
            if session == nil { session = ReviewSession(cards: reviews.dueWords(in: words).map(\.id)) }
        }
    }

    /// The three answers, once the card is turned, each with when the word comes back.
    private func grades(for word: SavedWord) -> some View {
        HStack(spacing: 16) {
            gradeButton("Non la sapevo", .again, color: .red, word: word)
            gradeButton("Difficile", .hard, color: .orange, word: word)
            gradeButton("La sapevo", .good, color: .green, word: word)
        }
        .opacity(turned ? 1 : 0)
        .disabled(!turned)
        .overlay {
            if !turned {
                Text("Tocca la carta per vedere la traduzione")
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
        }
    }

    private func gradeButton(_ title: String, _ grade: ReviewGrade, color: Color, word: SavedWord) -> some View {
        Button {
            reviews.record(grade, for: word)
            turned = false
            withAnimation(.snappy) { session?.answer(grade) }
        } label: {
            VStack(spacing: 2) {
                Text(title).font(.headline)
                Text(comesBack(word, after: grade)).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .tint(color)
    }

    private func comesBack(_ word: SavedWord, after grade: ReviewGrade) -> String {
        let state = reviews.states[word.id] ?? .new(on: .now)
        switch state.answered(grade, on: .now).intervalDays {
        case 0: return "di nuovo ora"
        case 1: return "domani"
        case let days: return "tra \(days) giorni"
        }
    }

    private var nextReviewText: String {
        let next = words.compactMap { reviews.states[$0.id]?.due }.min()
        guard let next else { return "Le parole che cerchi con la Pencil compaiono qui da ripassare." }
        let day = next.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "it_IT")))
        return "Le prossime parole tornano \(day)."
    }

    private func cards(_ n: Int) -> String { n == 1 ? "1 parola" : "\(n) parole" }
}

/// One card: the English side, or the Italian side once turned.
private struct FlashCard: View {
    let word: SavedWord
    let turned: Bool
    let canOpen: Bool
    let open: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            if turned {
                Text(word.translation)
                    .font(.system(size: 40, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text(word.term)
                    .font(.title3)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                if let sentence = word.sentenceTranslation {
                    Text(sentence)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            } else {
                Text(word.term)
                    .font(.system(size: 40, weight: .semibold))
                    .multilineTextAlignment(.center)
                if let sentence = word.sentence {
                    Text(highlighted(sentence))
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }
            Spacer(minLength: 0)
            Button(action: open) {
                Label("\(word.documentTitle) · pagina \(word.page + 1)", systemImage: "book")
                    .font(.footnote)
                    .lineLimit(1)
            }
            .buttonStyle(.borderless)
            .disabled(!canOpen)
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 320)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24))
        // Turned around its vertical axis; the content is mirrored back so it reads the right way.
        .rotation3DEffect(.degrees(turned ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .scaleEffect(x: turned ? -1 : 1)
    }

    /// The sentence with the word in bold, wherever it appears in it.
    private func highlighted(_ sentence: String) -> AttributedString {
        var text = AttributedString(sentence)
        if let range = text.range(of: word.term, options: [.caseInsensitive, .diacriticInsensitive]) {
            text[range].inlinePresentationIntent = .stronglyEmphasized
            text[range].foregroundColor = Color(uiColor: .label)
        }
        return text
    }
}

/// Opens the review, with the number of words due today on a red badge.
struct ReviewButton: View {
    let count: Int
    /// "Ripasso" beside the symbol, where there is room for it.
    var showsTitle = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.on.rectangle.angled")
                if showsTitle { Text("Ripasso") }
            }
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text(count > 99 ? "99+" : "\(count)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.red, in: Capsule())
                            .fixedSize()
                            .offset(x: showsTitle ? 16 : 12, y: -10)
                    }
                }
        }
        .accessibilityLabel(count > 0 ? "Ripassa, \(count) parole da ripassare oggi" : "Ripassa")
    }
}
