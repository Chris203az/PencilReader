import ReaderCore
import SwiftUI
import UIKit

/// Floating card next to the lasso: the translated sentence, with the
/// translation of the circled words highlighted.
struct TranslationPanel: View {
    let selection: ReaderModel.Selection
    let onClose: () -> Void
    /// Called when the AI is asked about the term.
    var onAskAI: () -> Void = {}
    @State private var showDictionary = false
    @State private var ai = AIState.idle
    /// Set to start a request; changing it cancels the running one.
    @State private var askID: UUID?
    @State private var showAISettings = false
    @State private var slowAnswer = false

    private enum AIState: Equatable {
        case idle, loading
        case done(WordExplanation)
        case failed(ExplanationError)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Chiudi")
            }

            if selection.translation != nil {
                HStack {
                    Button("Ascolta", systemImage: "speaker.wave.2") { Pronouncer.speak(selection.text) }
                        .accessibilityLabel("Ascolta la pronuncia inglese")
                    if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: selection.text) {
                        Button("Dizionario", systemImage: "character.book.closed") { showDictionary = true }
                    }
                    Button("Chiedi all'IA", systemImage: "sparkles", action: askAI)
                        .disabled(ai == .loading)
                    Spacer()
                    Button("Copia", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = selection.translation
                    }
                }
                .font(.footnote)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            aiContent
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
        .sheet(isPresented: $showDictionary) {
            DictionaryView(term: selection.text).ignoresSafeArea()
        }
        .sheet(isPresented: $showAISettings, onDismiss: {
            // A key was just added: ask right away.
            if case .failed(let error) = ai, error == .missingKey || error == .invalidKey, AIClient.hasKey(for: .ask) {
                askAI()
            }
        }) {
            AISettingsView().presentationSizing(.form)
        }
        .task(id: askID) {
            guard askID != nil else { return }
            ai = .loading
            slowAnswer = false
            do {
                ai = .done(try await AIClient.explain(term: selection.text, context: selection.context?.text))
            } catch {
                guard !Task.isCancelled else { return }
                ai = .failed(error as? ExplanationError ?? .unavailable)
            }
        }
        .onChange(of: selection.id) {
            ai = .idle
            askID = nil
        }
    }

    private func askAI() {
        guard AIClient.hasKey(for: .ask) else {
            ai = .failed(.missingKey)
            return
        }
        askID = UUID()
        onAskAI()
    }

    /// Only the explanation itself: no model name or other details.
    @ViewBuilder private var aiContent: some View {
        switch ai {
        case .idle:
            EmptyView()
        case .loading:
            Divider()
            HStack(spacing: 8) {
                ProgressView()
                Text(slowAnswer ? String(localized: "Ci sta mettendo un po', attendi…") : String(localized: "Sto chiedendo all'IA…")).foregroundStyle(.secondary)
            }
            .task {
                // Reassures when the free tier is slow.
                guard (try? await Task.sleep(for: .seconds(8))) != nil else { return }
                slowAnswer = true
            }
        case .done(let explanation):
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                aiSection(String(localized: "Significato"), explanation.meaning)
                aiSection(selection.context == nil ? String(localized: "Uso tipico") : String(localized: "In questo contesto"), explanation.inContext)
            }
        case .failed(let error):
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
                Group {
                    if error == .missingKey || error == .invalidKey {
                        Button("Impostazioni IA", systemImage: "key") { showAISettings = true }
                    } else {
                        Button("Riprova", systemImage: "arrow.clockwise", action: askAI)
                    }
                }
                .font(.footnote)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func aiSection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(Color(uiColor: .label))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let context = selection.context {
                Text(highlighted(context.text, range: context.selection, font: .callout,
                                 color: Color(uiColor: .secondaryLabel)))
                    .font(.callout)
                    .textSelection(.enabled)
                Divider()
            }
            translationContent
        }
    }

    @ViewBuilder private var translationContent: some View {
        if let translation = selection.translation {
            VStack(alignment: .leading, spacing: 8) {
                Text(highlighted(translation, range: selection.highlight, font: .body,
                                 color: Color(uiColor: .label)))
                    .font(.body)
                    .textSelection(.enabled)
                if let term = selection.termTranslation {
                    // The term couldn't be located in the sentence: show it on its own.
                    Text(term)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.yellow.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
                }
            }
        } else if let error = selection.error {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.red)
        } else {
            HStack(spacing: 8) {
                ProgressView()
                Text("Traduzione…").foregroundStyle(.secondary)
            }
        }
    }

    /// Colors are set on the text itself: a hierarchical `.foregroundStyle(.secondary)`
    /// on selectable text is drawn invisible in dark mode.
    private func highlighted(_ text: String, range: Range<String.Index>?, font: Font, color: Color) -> AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = color
        guard let range else { return result }
        let chars = result.characters
        let lower = chars.index(chars.startIndex, offsetBy: text.distance(from: text.startIndex, to: range.lowerBound))
        let upper = chars.index(lower, offsetBy: text.distance(from: range.lowerBound, to: range.upperBound))
        result[lower..<upper].backgroundColor = .yellow.opacity(0.45)
        result[lower..<upper].font = font.weight(.semibold)
        result[lower..<upper].foregroundColor = Color(uiColor: .label)
        return result
    }
}

/// The system dictionary (download "Italiano–Inglese" in Settings > General > Dictionary).
struct DictionaryView: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}
