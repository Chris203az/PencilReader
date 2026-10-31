import ReaderCore
import SwiftUI

/// UserDefaults keys of the settings that live only here.
enum AppSettings {
    static let wordBoxesKey = "reader.showWordBoxes"
    static let fingerDrawingKey = "reader.allowsFingerDrawing"
    static let progressBarKey = "reader.showsProgressBar"
    static let keepsScreenOnKey = "reader.keepsScreenOn"
    static let hintsKey = "app.showsHints"
    static let continueReadingKey = "library.showsContinueReading"
    static let appearanceKey = "app.appearance"

    static func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
}

/// Light or dark for the whole app, or as the iPad is set.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Sistema"
        case .light: "Chiaro"
        case .dark: "Scuro"
        }
    }

    /// `nil` follows the iPad.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Every setting of the app in one place: reading, notebook, study, export, AI.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StudyTimer.self) private var studyTimer

    @AppStorage(AppSettings.continueReadingKey) private var showsContinueReading = true
    @AppStorage(AppSettings.appearanceKey) private var appearance = AppAppearance.system
    @AppStorage(AppSettings.progressBarKey) private var showsProgressBar = true
    @AppStorage(AppSettings.keepsScreenOnKey) private var keepsScreenOn = false
    @AppStorage(AppSettings.wordBoxesKey) private var showsWordBoxes = false
    @AppStorage(AppSettings.fingerDrawingKey) private var allowsFingerDrawing = false
    @AppStorage(AppSettings.hintsKey) private var showsHints = true
    @AppStorage(ReadingTheme.lastKey) private var defaultTheme = ReadingTheme.normal

    @AppStorage(NotebookModel.paperKey) private var paper = PaperStyle.grid
    @AppStorage(NotebookModel.shapesKey) private var straightensShapes = true
    @AppStorage(NotebookModel.smoothKey) private var smoothsStrokes = true
    @AppStorage(NotebookModel.strengthKey) private var smoothingStrength = 3.0

    @AppStorage("summaryJoinsHighlights") private var joinsHighlights = true
    @AppStorage("studyTimer.readingMinutes") private var readingMinutes = 60
    @AppStorage("exportIncludesMarks") private var exportIncludesMarks = true
    @AppStorage("exportNoteLayout") private var exportNoteLayout = NoteLayout.beside

    @State private var showsGuide = false
    @State private var confirmsDeleteWords = false
    @State private var backup = BackupService.shared
    /// What the folder being picked is for; kept after the picker closes, since its answer comes after.
    @State private var pickMode = FolderPick.destination
    @State private var picksFolder = false
    @State private var restoring: URL?
    @State private var restored = false
    @State private var backupError: String?

    private enum FolderPick { case destination, restore }
    @Environment(WordList.self) private var wordList

    var body: some View {
        @Bindable var timer = studyTimer
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $appearance) {
                        ForEach(AppAppearance.allCases) { Text($0.label).tag($0) }
                    } label: {
                        SettingsRow("Aspetto", systemImage: "circle.lefthalf.filled", color: .indigo)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Aspetto dell'app")
                } footer: {
                    Text("«Sistema» segue l'iPad. Il tema della pagina del libro si sceglie a parte, qui sotto in Lettura.")
                }

                Section {
                    NavigationLink {
                        AISettingsForm()
                    } label: {
                        SettingsRow("Intelligenza artificiale", systemImage: "sparkles", color: .purple,
                                    detail: AISettingsForm.summary)
                    }
                }

                Section {
                    Toggle(isOn: $showsContinueReading) {
                        SettingsRow("«Continua a leggere» in alto", systemImage: "book", color: .accentColor)
                    }
                } header: {
                    Text("Libreria")
                }

                Section {
                    Picker(selection: $defaultTheme) {
                        ForEach(ReadingTheme.allCases) { theme in
                            Label(theme.label, systemImage: theme.systemImage).tag(theme)
                        }
                    } label: {
                        SettingsRow("Tema dei libri nuovi", systemImage: "circle.lefthalf.filled", color: .gray)
                    }
                    Toggle(isOn: $showsProgressBar) {
                        SettingsRow("Barra di avanzamento", systemImage: "chart.bar.fill", color: .accentColor)
                    }
                    Toggle(isOn: $keepsScreenOn) {
                        SettingsRow("Schermo sempre acceso", systemImage: "sun.max.fill", color: .yellow)
                    }
                    Toggle(isOn: $allowsFingerDrawing) {
                        SettingsRow("Cerchia le parole col dito", systemImage: "hand.draw", color: .teal)
                    }
                    Toggle(isOn: $showsWordBoxes) {
                        SettingsRow("Riquadri del testo riconosciuto", systemImage: "square.dashed", color: .gray)
                    }
                    Toggle(isOn: $showsHints) {
                        SettingsRow("Suggerimenti tenendo premuto", systemImage: "questionmark.bubble", color: .blue)
                    }
                } header: {
                    Text("Lettura")
                } footer: {
                    Text("Il tema si cambia anche per ogni libro, dal menu «Altro». Lo schermo sempre acceso vale solo con un libro aperto.")
                }

                Section {
                    Picker(selection: $paper) {
                        ForEach(PaperStyle.allCases, id: \.self) { style in
                            Text(style.label).tag(style)
                        }
                    } label: {
                        SettingsRow("Sfondo", systemImage: "squareshape.split.3x3", color: .orange)
                    }
                    Toggle(isOn: $straightensShapes) {
                        SettingsRow("Raddrizza le forme", systemImage: "square.on.circle", color: .orange)
                    }
                    Toggle(isOn: $smoothsStrokes) {
                        SettingsRow("Leviga i tratti", systemImage: "scribble", color: .orange)
                    }
                    if smoothsStrokes {
                        Picker(selection: $smoothingStrength) {
                            ForEach([1.0, 2.0, 3.0, 4.0], id: \.self) { points in
                                Text("\(Int(points)) pt").tag(points)
                            }
                        } label: {
                            SettingsRow("Intensità levigatura", systemImage: "dial.medium", color: .orange)
                        }
                    }
                } header: {
                    Text("Quaderno")
                } footer: {
                    Text("La barra degli strumenti del quaderno si personalizza dal quaderno stesso, con il pulsante delle opzioni.")
                }

                Section {
                    Stepper(value: $timer.settings.focusMinutes, in: PomodoroSettings.focusRange, step: 5) {
                        SettingsRow("Blocco di studio", systemImage: "timer", color: .red,
                                    detail: "\(timer.settings.focusMinutes) min")
                    }
                    Stepper(value: $timer.settings.shortBreakMinutes, in: PomodoroSettings.shortBreakRange) {
                        SettingsRow("Pausa breve", systemImage: "cup.and.saucer", color: .green,
                                    detail: "\(timer.settings.shortBreakMinutes) min")
                    }
                    Stepper(value: $timer.settings.longBreakMinutes, in: PomodoroSettings.longBreakRange, step: 5) {
                        SettingsRow("Pausa lunga", systemImage: "bed.double", color: .green,
                                    detail: "\(timer.settings.longBreakMinutes) min")
                    }
                    Stepper(value: $timer.settings.blocksBeforeLongBreak, in: PomodoroSettings.blocksRange) {
                        SettingsRow("Pausa lunga ogni", systemImage: "repeat", color: .green,
                                    detail: "\(timer.settings.blocksBeforeLongBreak) blocchi")
                    }
                    Stepper(value: $readingMinutes, in: 10...240, step: 10) {
                        SettingsRow("Lettura a tempo, proposta", systemImage: "hourglass", color: .red,
                                    detail: "\(readingMinutes) min")
                    }
                    Button("Ripristina 25 / 5") { timer.settings = PomodoroSettings() }
                } header: {
                    Text("Timer di studio")
                }

                Section {
                    Toggle(isOn: $joinsHighlights) {
                        SettingsRow("Unisci i concetti con l'IA", systemImage: "sparkles", color: .purple)
                    }
                    Button {
                        showsGuide = true
                    } label: {
                        SettingsRow("Come studiare con la modalità studio", systemImage: "highlighter", color: .orange)
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("Studio e riepilogo")
                } footer: {
                    Text("Nel riepilogo, l'IA raccoglie le evidenziazioni simili sotto un unico concetto.")
                }

                Section {
                    Toggle(isOn: $exportIncludesMarks) {
                        SettingsRow("Includi i segni di studio", systemImage: "highlighter", color: .indigo)
                    }
                    Picker(selection: $exportNoteLayout) {
                        ForEach(NoteLayout.allCases, id: \.self) { layout in
                            Text(layout.label).tag(layout)
                        }
                    } label: {
                        SettingsRow("Note del quaderno", systemImage: "rectangle.split.2x1", color: .indigo)
                    }
                } header: {
                    Text("Esporta PDF")
                }

                Section {
                    Button {
                        pickMode = .destination
                        picksFolder = true
                    } label: {
                        SettingsRow("Cartella dei backup", systemImage: "folder", color: .blue,
                                    detail: backup.folderName ?? "Scegli…")
                    }
                    .foregroundStyle(.primary)
                    Toggle(isOn: $backup.isAutomatic) {
                        SettingsRow("Backup automatico ogni giorno", systemImage: "clock.arrow.circlepath", color: .blue)
                    }
                    .disabled(!backup.hasFolder)
                    Button {
                        Task { await backup.backUp() }
                    } label: {
                        HStack {
                            SettingsRow("Fai un backup adesso", systemImage: "externaldrive.badge.icloud", color: .blue)
                            if backup.state == .running {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    .disabled(!backup.hasFolder || backup.state == .running)
                    Button {
                        pickMode = .restore
                        picksFolder = true
                    } label: {
                        SettingsRow("Ripristina da un backup…", systemImage: "arrow.counterclockwise", color: .gray)
                    }
                    .foregroundStyle(.primary)
                    .disabled(backup.state == .running)
                } header: {
                    Text("Backup")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if case .failed(let message) = backup.state {
                            Label("Ultimo backup non riuscito: \(message)", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        Text(backupFooter)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmsDeleteWords = true
                    } label: {
                        SettingsRow("Cancella tutte le parole cercate", systemImage: "trash", color: .red,
                                    detail: "\(wordList.words.count)")
                    }
                    .disabled(wordList.words.isEmpty)
                } header: {
                    Text("Dati")
                } footer: {
                    Text("Toglie le parole cercate di tutti i libri, con il loro ripasso. I libri, le note e i segni restano.")
                }

                Section {
                    LabeledContent("Versione", value: Self.version)
                } header: {
                    Text("Informazioni")
                }
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
            .confirmationDialog("Cancellare tutte le \(wordList.words.count) parole cercate?",
                                isPresented: $confirmsDeleteWords, titleVisibility: .visible) {
                Button("Cancella tutte", role: .destructive) { wordList.delete(Set(wordList.words.map(\.id))) }
            } message: {
                Text("Non si può annullare.")
            }
            .fileImporter(isPresented: $picksFolder, allowedContentTypes: [.folder]) { result in
                guard case .success(let url) = result else { return }
                switch pickMode {
                case .destination:
                    do { try backup.choose(url) } catch { backupError = error.localizedDescription }
                case .restore:
                    if BackupService.isBackup(url) {
                        restoring = url
                    } else {
                        backupError = "Questa cartella non è un backup di PencilReader: scegli una cartella «PencilReader …»."
                    }
                }
            }
            .confirmationDialog("Ripristinare questo backup?",
                                isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }),
                                titleVisibility: .visible) {
                Button("Sostituisci tutto con il backup", role: .destructive) {
                    guard let url = restoring else { return }
                    Task {
                        do {
                            try await backup.restore(from: url)
                            restored = true
                        } catch {
                            backupError = error.localizedDescription
                        }
                    }
                }
            } message: {
                Text("Libri, note, segni, parole e impostazioni di adesso vengono sostituiti da quelli di «\(restoring?.lastPathComponent ?? "")».")
            }
            .alert("Ripristino completato", isPresented: $restored) {
                Button("Chiudi l'app") { exit(0) }
            } message: {
                Text("Chiudi e riapri l'app per vedere i dati del backup.")
            }
            .alert("Backup", isPresented: Binding(get: { backupError != nil }, set: { if !$0 { backupError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(backupError ?? "")
            }
            .sheet(isPresented: $showsGuide) {
                StudyGuideView().presentationSizing(.form)
            }
        }
    }

    private var backupFooter: String {
        let last = backup.lastBackup.map { "Ultimo backup: \($0.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "it_IT"))))." }
            ?? "Nessun backup ancora."
        return "\(last) Copia libri, note, segni, parole, statistiche e impostazioni (non le chiavi IA) in una cartella di File: scegline una in iCloud Drive per averla anche fuori dall'iPad. Restano gli ultimi \(BackupService.kept) backup."
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }
}

/// A settings row: a white symbol on a small colored square, the title and an optional value.
struct SettingsRow: View {
    let title: String
    let systemImage: String
    let color: Color
    var detail: String?

    init(_ title: String, systemImage: String, color: Color, detail: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.detail = detail
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(title)
            if let detail {
                Spacer()
                Text(detail)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
