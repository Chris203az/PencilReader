import Observation
import QuickLook
import ReaderCore
import SwiftUI

/// Runs one export at a time in the background and tells the sheet how far it got.
@MainActor
@Observable
final class PDFExportModel {
    enum Phase {
        case options
        case exporting(done: Int, total: Int)
        case finished(PDFExportResult)
        case failed(String)
    }

    private(set) var phase: Phase = .options
    @ObservationIgnored private var work: Task<PDFExportResult, Error>?

    var isExporting: Bool {
        if case .exporting = phase { return true }
        return false
    }

    func start(_ job: PDFExportJob) {
        cancel()
        let total = job.pages.count
        phase = .exporting(done: 0, total: total)
        let work = Task.detached(priority: .userInitiated) {
            try PDFExporter.export(job) { done in
                Task { @MainActor [weak self] in self?.advance(to: done, of: total) }
            }
        }
        self.work = work
        Task {
            let result = await work.result
            // Cancelled, or replaced by a newer export.
            guard self.work == work else { return }
            self.work = nil
            switch result {
            case .success(let export): phase = .finished(export)
            case .failure(let error): phase = error is CancellationError ? .options : .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        work?.cancel()
        work = nil
        phase = .options
    }

    private func advance(to done: Int, of total: Int) {
        guard isExporting else { return }
        phase = .exporting(done: done, total: total)
    }
}

/// Options of the PDF export of a book, its progress, then the share sheet.
struct PDFExportView: View {
    let document: LibraryDocument
    let currentPage: Int
    /// Pages with a note or study marks.
    let annotatedPages: Set<Int>
    let paper: PaperStyle

    private enum PageChoice: Hashable {
        case all, range, annotated
    }

    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var model = PDFExportModel()
    @State private var pageChoice = PageChoice.all
    @State private var firstPage = 1
    @State private var lastPage = 1
    @State private var preview: URL?
    @AppStorage("exportIncludesMarks") private var includesMarks = true
    @AppStorage("exportNoteLayout") private var noteLayout = NoteLayout.beside

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .options: options
                case .exporting(let done, let total): progress(done: done, total: total)
                case .finished(let result): finished(result)
                case .failed(let message): failed(message)
                }
            }
            .navigationTitle("Esporta PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        .quickLookPreview($preview)
        .onAppear {
            firstPage = currentPage + 1
            lastPage = currentPage + 1
        }
        // Closing the sheet stops the export.
        .onDisappear { if model.isExporting { model.cancel() } }
    }

    private var pages: [Int] {
        let choice: ExportPages = switch pageChoice {
        case .all: .all
        case .range: .range((firstPage - 1)...(max(firstPage, lastPage) - 1))
        case .annotated: .annotated
        }
        return PDFExportPlan.pages(choice, pageCount: document.pageCount, annotated: annotatedPages)
    }

    // MARK: Options

    private var options: some View {
        Form {
            Section {
                Picker("Pagine", selection: $pageChoice) {
                    Text("Tutto il libro").tag(PageChoice.all)
                    Text("Intervallo").tag(PageChoice.range)
                    Text("Solo annotate").tag(PageChoice.annotated)
                }
                .pickerStyle(.segmented)
                if pageChoice == .range {
                    Stepper(value: $firstPage, in: 1...max(document.pageCount, 1)) {
                        Text("Da pagina \(firstPage)").monospacedDigit()
                    }
                    Stepper(value: $lastPage, in: 1...max(document.pageCount, 1)) {
                        Text("A pagina \(lastPage)").monospacedDigit()
                    }
                }
            } header: {
                Text("Pagine")
            } footer: {
                Text(pagesSummary)
            }
            .onChange(of: firstPage) { _, first in lastPage = max(lastPage, first) }
            .onChange(of: lastPage) { _, last in firstPage = min(firstPage, last) }

            Section {
                Toggle(isOn: $includesMarks) {
                    Label("Segni della modalità studio", systemImage: "highlighter")
                }
                Picker(selection: $noteLayout) {
                    ForEach(NoteLayout.allCases, id: \.self) { layout in
                        Text(layout.label).tag(layout)
                    }
                } label: {
                    Label("Note del quaderno", systemImage: "square.and.pencil")
                }
            } header: {
                Text("Contenuto")
            } footer: {
                Text(layoutSummary)
            }

            Section {
                Button {
                    model.start(job())
                } label: {
                    Label("Esporta \(pages.count) \(pages.count == 1 ? "pagina" : "pagine")",
                          systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .disabled(pages.isEmpty)
            }
        }
    }

    private var pagesSummary: String {
        switch pageChoice {
        case .all: "Tutte le \(document.pageCount) pagine del libro."
        case .range: "Dalla pagina \(firstPage) alla \(max(firstPage, lastPage))."
        case .annotated: annotatedPages.isEmpty
            ? "Nessuna pagina ha ancora segni o note."
            : "Le \(pages.count) pagine con segni della modalità studio o una nota."
        }
    }

    private var layoutSummary: String {
        switch noteLayout {
        case .none: "Solo le pagine del libro."
        case .beside: "Pagina del libro a sinistra e nota a destra, come sullo schermo. Una nota lunga continua sulla pagina dopo."
        case .after: "Ogni nota su una pagina sua, subito dopo la pagina del libro."
        }
    }

    private func job() -> PDFExportJob {
        let source: PDFExportJob.Source = switch document.kind {
        case .pdf: .pdf(library.pdfURL(of: document))
        case .images: .images(folder: library.imageURL(of: document, page: 0).deletingLastPathComponent())
        }
        return PDFExportJob(bookID: document.id, title: library.document(withID: document.id)?.title ?? document.title,
                            source: source, pages: pages, includesMarks: includesMarks, noteLayout: noteLayout,
                            split: NotebookSettings.split, paper: paper,
                            marksPageWidth: StudyCanvasView.pageWidth, paperStep: PaperView.step)
    }

    // MARK: Progress and result

    private func progress(done: Int, total: Int) -> some View {
        VStack(spacing: 20) {
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .frame(maxWidth: 360)
            Text("Pagina \(done) di \(total)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button("Annulla", role: .cancel) { model.cancel() }
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func finished(_ result: PDFExportResult) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text(result.url.lastPathComponent)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("\(result.pageCount) pagine · \(fileSize(of: result.url))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            ShareLink(item: result.url) {
                Label("Condividi PDF", systemImage: "square.and.arrow.up")
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            HStack {
                Button("Anteprima", systemImage: "eye") { preview = result.url }
                Button("Cambia opzioni", systemImage: "slider.horizontal.3") { model.cancel() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failed(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Esportazione non riuscita", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Riprova") { model.cancel() }
        }
    }

    private func fileSize(of url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
