import SwiftUI

/// Where the Google AI Studio key for "Chiedi all'IA" is added or removed.
struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var keys = APIKeyStore.shared
    @State private var draft = ""
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let key = keys.googleKey {
                        LabeledContent("Chiave salvata", value: "••••" + String(key.suffix(4)))
                        Button("Cancella chiave", systemImage: "trash", role: .destructive) {
                            keys.deleteGoogleKey()
                        }
                    } else {
                        SecureField("Incolla qui la chiave", text: $draft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit(save)
                        Button("Salva", action: save)
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    Text("Chiave API di Google AI Studio")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Serve per \"Chiedi all'IA\" nel riquadro della traduzione. Resta solo su questo iPad, nel Portachiavi.")
                        Link("Crea una chiave gratuita su Google AI Studio",
                             destination: URL(string: "https://aistudio.google.com/apikey")!)
                    }
                }
                if saveFailed {
                    Label("Non è stato possibile salvare la chiave. Riprova.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
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

    private func save() {
        saveFailed = !keys.saveGoogleKey(draft)
        if !saveFailed { draft = "" }
    }
}
