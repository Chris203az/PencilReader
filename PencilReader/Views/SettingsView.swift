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
        case .system: String(localized: "Sistema")
        case .light: String(localized: "Chiaro")
        case .dark: String(localized: "Scuro")
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

/// The language of the interface: as the iPad is set, or one of the app's own.
/// iOS reads it only at launch, so a change applies the next time the app opens.
enum AppLanguage {
    static let languagesKey = "AppleLanguages"

    /// The languages the app is translated into, Italian first.
    static var available: [String] {
        Bundle.main.localizations.filter { $0 != "Base" }.sorted { $0 == "it" || ($1 != "it" && $0 < $1) }
    }

    /// The language chosen in the app, `nil` when it follows the iPad.
    static var chosen: String? {
        get { UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[languagesKey]
                .flatMap { ($0 as? [String])?.first } }
        set {
            if let newValue {
                UserDefaults.standard.set([newValue], forKey: languagesKey)
            } else {
                UserDefaults.standard.removeObject(forKey: languagesKey)
            }
        }
    }

    /// The language the app is showing now.
    static var current: String { Bundle.main.preferredLocalizations.first ?? "it" }

    /// "English", "Italiano": each language in its own words.
    static func name(of code: String) -> String {
        Locale(identifier: code).localizedString(forLanguageCode: code)?.capitalized(with: Locale(identifier: code)) ?? code
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
    @State private var language = AppLanguage.chosen
    @State private var languageChanged = false
    @AppStorage(TranslationLanguages.sourceKey) private var sourceLanguage = LanguagePair.default.source
    @AppStorage(TranslationLanguages.targetKey) private var targetLanguage = LanguagePair.default.target
    @State private var translationLanguages: [String] = []
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
                        SettingsRow(String(localized: "Aspetto"), systemImage: "circle.lefthalf.filled", color: .indigo)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Aspetto dell'app")
                } footer: {
                    Text("«Sistema» segue l'iPad. Il tema della pagina del libro si sceglie a parte, qui sotto in Lettura.")
                }

                Section {
                    Picker(selection: $language) {
                        Text("Sistema").tag(String?.none)
                        ForEach(AppLanguage.available, id: \.self) { code in
                            Text(AppLanguage.name(of: code)).tag(Optional(code))
                        }
                    } label: {
                        SettingsRow(String(localized: "Lingua"), systemImage: "globe", color: .blue)
                    }
                    .onChange(of: language) { _, newValue in
                        AppLanguage.chosen = newValue
                        languageChanged = true
                    }
                } footer: {
                    Text("«Sistema» segue la lingua dell'iPad. La nuova lingua si vede alla prossima apertura dell'app.")
                }

                Section {
                    Picker(selection: $sourceLanguage) {
                        languageOptions(including: sourceLanguage)
                    } label: {
                        SettingsRow(String(localized: "Lingua dei libri"), systemImage: "book.closed", color: .teal)
                    }
                    Picker(selection: $targetLanguage) {
                        languageOptions(including: targetLanguage)
                    } label: {
                        SettingsRow(String(localized: "Traduci in"), systemImage: "character.bubble", color: .teal)
                    }
                    Button {
                        (sourceLanguage, targetLanguage) = (targetLanguage, sourceLanguage)
                    } label: {
                        SettingsRow(String(localized: "Inverti le lingue"), systemImage: "arrow.left.arrow.right", color: .gray)
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("Traduzione")
                } footer: {
                    Text("Traduce sull'iPad con i modelli di Apple: la prima volta che usi una lingua nuova, l'iPad chiede di scaricarla. Seguono queste lingue anche «Ascolta», le risposte dell'IA e la lettura del testo delle pagine non ancora riconosciute.")
                }
                .task { translationLanguages = await TranslationLanguages.supported() }

                Section {
                    NavigationLink {
                        AISettingsForm()
                    } label: {
                        SettingsRow(String(localized: "Intelligenza artificiale"), systemImage: "sparkles", color: .purple,
                                    detail: AISettingsForm.summary)
                    }
                }

                Section {
                    Toggle(isOn: $showsContinueReading) {
                        SettingsRow(String(localized: "«Continua a leggere» in alto"), systemImage: "book", color: .accentColor)
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
                        SettingsRow(String(localized: "Tema dei libri nuovi"), systemImage: "circle.lefthalf.filled", color: .gray)
                    }
                    Toggle(isOn: $showsProgressBar) {
                        SettingsRow(String(localized: "Barra di avanzamento"), systemImage: "chart.bar.fill", color: .accentColor)
                    }
                    Toggle(isOn: $keepsScreenOn) {
                        SettingsRow(String(localized: "Schermo sempre acceso"), systemImage: "sun.max.fill", color: .yellow)
                    }
                    Toggle(isOn: $allowsFingerDrawing) {
                        SettingsRow(String(localized: "Cerchia le parole col dito"), systemImage: "hand.draw", color: .teal)
                    }
                    Toggle(isOn: $showsWordBoxes) {
                        SettingsRow(String(localized: "Riquadri del testo riconosciuto"), systemImage: "square.dashed", color: .gray)
                    }
                    Toggle(isOn: $showsHints) {
                        SettingsRow(String(localized: "Suggerimenti tenendo premuto"), systemImage: "questionmark.bubble", color: .blue)
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
                        SettingsRow(String(localized: "Sfondo"), systemImage: "squareshape.split.3x3", color: .orange)
                    }
                    Toggle(isOn: $straightensShapes) {
                        SettingsRow(String(localized: "Raddrizza le forme"), systemImage: "square.on.circle", color: .orange)
                    }
                    Toggle(isOn: $smoothsStrokes) {
                        SettingsRow(String(localized: "Leviga i tratti"), systemImage: "scribble", color: .orange)
                    }
                    if smoothsStrokes {
                        Picker(selection: $smoothingStrength) {
                            ForEach([1.0, 2.0, 3.0, 4.0], id: \.self) { points in
                                Text("\(Int(points)) pt").tag(points)
                            }
                        } label: {
                            SettingsRow(String(localized: "Intensità levigatura"), systemImage: "dial.medium", color: .orange)
                        }
                    }
                } header: {
                    Text("Quaderno")
                } footer: {
                    Text("La barra degli strumenti del quaderno si personalizza dal quaderno stesso, con il pulsante delle opzioni.")
                }

                Section {
                    Stepper(value: $timer.settings.focusMinutes, in: PomodoroSettings.focusRange, step: 5) {
                        SettingsRow(String(localized: "Blocco di studio"), systemImage: "timer", color: .red,
                                    detail: "\(timer.settings.focusMinutes) min")
                    }
                    Stepper(value: $timer.settings.shortBreakMinutes, in: PomodoroSettings.shortBreakRange) {
                        SettingsRow(String(localized: "Pausa breve"), systemImage: "cup.and.saucer", color: .green,
                                    detail: "\(timer.settings.shortBreakMinutes) min")
                    }
                    Stepper(value: $timer.settings.longBreakMinutes, in: PomodoroSettings.longBreakRange, step: 5) {
                        SettingsRow(String(localized: "Pausa lunga"), systemImage: "bed.double", color: .green,
                                    detail: "\(timer.settings.longBreakMinutes) min")
                    }
                    Stepper(value: $timer.settings.blocksBeforeLongBreak, in: PomodoroSettings.blocksRange) {
                        SettingsRow(String(localized: "Pausa lunga ogni"), systemImage: "repeat", color: .green,
                                    detail: String(localized: "\(timer.settings.blocksBeforeLongBreak) blocchi"))
                    }
                    Stepper(value: $readingMinutes, in: 10...240, step: 10) {
                        SettingsRow(String(localized: "Lettura a tempo, proposta"), systemImage: "hourglass", color: .red,
                                    detail: "\(readingMinutes) min")
                    }
                    Button("Ripristina 25 / 5") { timer.settings = PomodoroSettings() }
                } header: {
                    Text("Timer di studio")
                }

                Section {
                    Toggle(isOn: $joinsHighlights) {
                        SettingsRow(String(localized: "Unisci i concetti con l'IA"), systemImage: "sparkles", color: .purple)
                    }
                    Button {
                        showsGuide = true
                    } label: {
                        SettingsRow(String(localized: "Come studiare con la modalità studio"), systemImage: "highlighter", color: .orange)
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("Studio e riepilogo")
                } footer: {
                    Text("Nel riepilogo, l'IA raccoglie le evidenziazioni simili sotto un unico concetto.")
                }

                Section {
                    Toggle(isOn: $exportIncludesMarks) {
                        SettingsRow(String(localized: "Includi i segni di studio"), systemImage: "highlighter", color: .indigo)
                    }
                    Picker(selection: $exportNoteLayout) {
                        ForEach(NoteLayout.allCases, id: \.self) { layout in
                            Text(layout.label).tag(layout)
                        }
                    } label: {
                        SettingsRow(String(localized: "Note del quaderno"), systemImage: "rectangle.split.2x1", color: .indigo)
                    }
                } header: {
                    Text("Esporta PDF")
                }

                Section {
                    Button {
                        pickMode = .destination
                        picksFolder = true
                    } label: {
                        SettingsRow(String(localized: "Cartella dei backup"), systemImage: "folder", color: .blue,
                                    detail: backup.folderName ?? String(localized: "Scegli…"))
                    }
                    .foregroundStyle(.primary)
                    Toggle(isOn: $backup.isAutomatic) {
                        SettingsRow(String(localized: "Backup automatico ogni giorno"), systemImage: "clock.arrow.circlepath", color: .blue)
                    }
                    .disabled(!backup.hasFolder)
                    Button {
                        Task { await backup.backUp() }
                    } label: {
                        HStack {
                            SettingsRow(String(localized: "Fai un backup adesso"), systemImage: "externaldrive.badge.icloud", color: .blue)
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
                        SettingsRow(String(localized: "Ripristina da un backup…"), systemImage: "arrow.counterclockwise", color: .gray)
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
                        SettingsRow(String(localized: "Cancella tutte le parole cercate"), systemImage: "trash", color: .red,
                                    detail: "\(wordList.words.count)")
                    }
                    .disabled(wordList.words.isEmpty)
                } header: {
                    Text("Dati")
                } footer: {
                    Text("Toglie le parole cercate di tutti i libri, con il loro ripasso. I libri, le note e i segni restano.")
                }

                Section {
                    NavigationLink {
                        GuideView()
                    } label: {
                        SettingsRow(String(localized: "Guida all'uso"), systemImage: "book.pages", color: .accentColor)
                    }
                    LabeledContent("Versione", value: Self.version)
                } header: {
                    Text("Informazioni")
                } footer: {
                    Text("Come funziona ogni parte dell'app, con tutti i gesti delle dita e della Pencil.")
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
                        backupError = String(localized: "Questa cartella non è un backup di PencilReader: scegli una cartella «PencilReader …».")
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
            .alert("Lingua cambiata", isPresented: $languageChanged) {
                Button("Chiudi l'app") { exit(0) }
                Button("Più tardi", role: .cancel) {}
            } message: {
                Text("Chiudi e riapri l'app per vederla nella nuova lingua.")
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

    /// The languages of the on-device translation, plus the chosen one while they load.
    @ViewBuilder
    private func languageOptions(including chosen: String) -> some View {
        let codes = translationLanguages.contains(chosen) ? translationLanguages : [chosen] + translationLanguages
        ForEach(codes, id: \.self) { code in
            Text(TranslationLanguages.name(of: code)).tag(code)
        }
    }

    private var backupFooter: String {
        let last = backup.lastBackup.map { date in String(localized: "Ultimo backup: \(date.formatted(date: .abbreviated, time: .shortened)).") }
            ?? String(localized: "Nessun backup ancora.")
        return String(localized: "\(last) Copia libri, note, segni, parole, statistiche e impostazioni (non le chiavi IA) in una cartella di File: scegline una in iCloud Drive per averla anche fuori dall'iPad. Restano gli ultimi \(BackupService.kept) backup.")
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
