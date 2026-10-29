import ReaderCore
import SwiftUI

/// Which AI service each feature uses, and the key (and model) of each service.
struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AIFeature.ask.providerKey) private var askProvider = AIProvider.google
    @AppStorage(AIFeature.study.providerKey) private var studyProvider = AIProvider.google

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    providerPicker(AIFeature.ask, $askProvider)
                    providerPicker(AIFeature.study, $studyProvider)
                } header: {
                    Text("Servizio IA")
                } footer: {
                    Text("\(AIFeature.ask.title): \(AIFeature.ask.detail)\n\(AIFeature.study.title): \(AIFeature.study.detail)")
                }

                ForEach(AIProvider.allCases) { provider in
                    ProviderSection(provider: provider, usedBy: features(using: provider))
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

    private func providerPicker(_ feature: AIFeature, _ selection: Binding<AIProvider>) -> some View {
        Picker(feature.title, selection: selection) {
            ForEach(AIProvider.allCases) { provider in
                Text(provider.name).tag(provider)
            }
        }
    }

    private func features(using provider: AIProvider) -> [AIFeature] {
        [(AIFeature.ask, askProvider), (.study, studyProvider)].filter { $0.1 == provider }.map(\.0)
    }
}

/// The key and the model of one provider.
private struct ProviderSection: View {
    let provider: AIProvider
    let usedBy: [AIFeature]
    @State private var keys = APIKeyStore.shared
    @State private var draft = ""
    @State private var check = KeyCheck.idle
    @AppStorage private var preferredModel: String

    init(provider: AIProvider, usedBy: [AIFeature]) {
        self.provider = provider
        self.usedBy = usedBy
        _preferredModel = AppStorage(wrappedValue: provider.defaultModel, AIClient.modelKey(provider))
    }

    private enum KeyCheck: Equatable {
        case idle, checking
        case works(seconds: Double)
        /// The service refused the key (a new one isn't saved).
        case refused(ExplanationError, wasNew: Bool)
        /// The test failed for another reason (quota, network…): the key is saved anyway.
        case untested(ExplanationError)
        /// Re-testing the saved key failed.
        case failed(ExplanationError)
        case saveFailed
    }

    var body: some View {
        Section {
            if let key = keys.key(for: provider) {
                LabeledContent("Chiave salvata", value: "••••" + String(key.suffix(4)))
                Button("Prova la chiave", systemImage: "checkmark.seal") { test(key, saving: false) }
                    .disabled(check == .checking)
                Button("Cancella chiave", systemImage: "trash", role: .destructive) {
                    keys.delete(for: provider)
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
            if provider.choices.count > 1 {
                Picker("Modello", selection: $preferredModel) {
                    ForEach(provider.choices, id: \.id) { choice in
                        Text(choice.name).tag(choice.id)
                    }
                }
            } else {
                LabeledContent("Modello", value: provider.choices[0].name)
            }
        } header: {
            Text("\(provider.name) · \(provider.note)")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(footer)
                Link(provider.keyPage.title, destination: provider.keyPage.url)
            }
        }
    }

    private var footer: String {
        let use = usedBy.isEmpty
            ? "Non è usato da nessuna funzione."
            : "Usato per: " + usedBy.map { "\"\($0.title)\"" }.joined(separator: " e ") + "."
        let fallback = provider.choices.count > 1
            ? " Se il modello scelto è sovraccarico o non risponde in tempo, si passa da soli agli altri." : ""
        return "\(use) La chiave resta solo su questo iPad, nel Portachiavi; quando la salvi viene mandato un breve messaggio di prova.\(fallback)"
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

    /// Sends the test message; when `saving`, keeps the key unless the service refuses it.
    private func test(_ key: String, saving: Bool) {
        check = .checking
        Task {
            let start = Date()
            do {
                try await AIClient.test(provider, apiKey: key)
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
            if keys.save(key, for: provider) { draft = "" } else { check = .saveFailed }
        }
    }
}
