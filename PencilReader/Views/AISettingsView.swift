import ReaderCore
import SwiftUI

/// Where the Google AI Studio key for "Chiedi all'IA" is added or removed.
struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var keys = APIKeyStore.shared
    @State private var draft = ""
    @State private var check = KeyCheck.idle
    @AppStorage(WordExplainer.preferredModelKey) private var preferredModel = GeminiExplainer.model

    private enum KeyCheck: Equatable {
        case idle, checking
        case works(seconds: Double)
        /// Google refused the key (a new one isn't saved).
        case refused(ExplanationError, wasNew: Bool)
        /// The test failed for another reason (quota, network…): the key is saved anyway.
        case untested(ExplanationError)
        /// Re-testing the saved key failed.
        case failed(ExplanationError)
        case saveFailed
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let key = keys.googleKey {
                        LabeledContent("Chiave salvata", value: "••••" + String(key.suffix(4)))
                        Button("Prova la chiave", systemImage: "checkmark.seal") { test(key, saving: false) }
                            .disabled(check == .checking)
                        Button("Cancella chiave", systemImage: "trash", role: .destructive) {
                            keys.deleteGoogleKey()
                            check = .idle
                        }
                    } else {
                        SecureField("Incolla qui la chiave", text: $draft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit(save)
                        Button("Salva e prova", action: save)
                            .disabled(trimmedDraft.isEmpty || check == .checking)
                    }
                    checkRow
                } header: {
                    Text("Chiave API di Google AI Studio")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Serve per \"Chiedi all'IA\" nel riquadro della traduzione. Resta solo su questo iPad, nel Portachiavi. Quando la salvi viene mandato un breve messaggio di prova.")
                        Link("Crea una chiave gratuita su Google AI Studio",
                             destination: URL(string: "https://aistudio.google.com/apikey")!)
                    }
                }

                Section {
                    Picker("Modello", selection: $preferredModel) {
                        ForEach(GeminiExplainer.choices, id: \.id) { choice in
                            Text(choice.name).tag(choice.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Modello")
                } footer: {
                    Text("Se il modello scelto è sovraccarico o non risponde entro 25 secondi, si passa da soli agli altri.")
                }
            }
            .navigationTitle("Impostazioni IA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder private var checkRow: some View {
        switch check {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                Text("Prova della chiave in corso…").foregroundStyle(.secondary)
            }
        case .works(let seconds):
            Label("La chiave funziona (risposta in \(seconds.formatted(.number.precision(.fractionLength(1)))) s).",
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .refused(let error, let wasNew):
            Label(wasNew ? "\(error.message) La chiave non è stata salvata." : error.message,
                  systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .untested(let error):
            Label("Chiave salvata, ma la prova non è riuscita: \(error.message)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .failed(let error):
            Label(error.message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .saveFailed:
            Label("Non è stato possibile salvare la chiave. Riprova.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        guard !trimmedDraft.isEmpty else { return }
        test(trimmedDraft, saving: true)
    }

    /// Sends the test message; when `saving`, keeps the key unless Google refuses it.
    private func test(_ key: String, saving: Bool) {
        check = .checking
        Task {
            let start = Date()
            do {
                try await WordExplainer.test(apiKey: key)
                check = .works(seconds: Date().timeIntervalSince(start))
            } catch {
                let failure = error as? ExplanationError ?? .unavailable
                guard saving else {
                    check = failure == .invalidKey ? .refused(failure, wasNew: false) : .failed(failure)
                    return
                }
                guard failure != .invalidKey else {
                    check = .refused(failure, wasNew: true)
                    return
                }
                check = .untested(failure)
            }
            guard saving else { return }
            if keys.saveGoogleKey(key) { draft = "" } else { check = .saveFailed }
        }
    }
}
