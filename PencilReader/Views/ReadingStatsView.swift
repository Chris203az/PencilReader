import Charts
import ReaderCore
import SwiftUI

/// Reading time of the last 7 days, for all books or one, and the books read the most.
struct ReadingStatsView: View {
    /// Called when a book in the list is tapped, to open it.
    let open: (LibraryDocument) -> Void

    @Environment(ReadingStats.self) private var stats
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    /// Nil: every book.
    @State private var bookID: UUID?

    private var week: [ReadingLog.Day] { stats.log.lastDays(7, endingOn: .now, of: bookID) }
    private var books: [ReadingLog.BookTotal] { stats.log.bookTotals(lastDays: 7, endingOn: .now) }

    var body: some View {
        let week = week
        NavigationStack {
            List {
                Section {
                    Picker("Libro", selection: $bookID) {
                        Text("Tutti i libri").tag(UUID?.none)
                        ForEach(library.documents) { document in
                            Text(document.title).tag(UUID?.some(document.id))
                        }
                    }
                    summary(week)
                    chart(week)
                        .frame(height: 200)
                        .padding(.vertical, 8)
                } footer: {
                    Text("Il tempo si conta solo mentre un libro è aperto e l'app è in primo piano.")
                }

                Section("Ultimi 7 giorni per libro") {
                    if books.isEmpty {
                        Text("Ancora niente: apri un libro e inizia a leggere.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(books) { total in
                        if let document = library.document(withID: total.bookID) {
                            Button {
                                dismiss()
                                open(document)
                            } label: {
                                bookRow(document, total)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Statistiche di lettura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
    }

    private func summary(_ week: [ReadingLog.Day]) -> some View {
        let today = week.last
        let total = week.map(\.seconds).reduce(0, +)
        let readDays = week.filter { $0.seconds >= 60 }.count
        return Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                tile("Oggi", ReadingLog.duration(today?.seconds ?? 0))
                tile("7 giorni", ReadingLog.duration(total))
            }
            GridRow {
                tile("Pagine viste oggi", "\(today?.pages ?? 0)")
                if bookID == nil {
                    tile("Blocchi di studio oggi", "\(today?.focusBlocks ?? 0)")
                } else {
                    tile("Giorni di lettura", "\(readDays) su 7")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func chart(_ week: [ReadingLog.Day]) -> some View {
        Chart(week) { day in
            BarMark(x: .value("Giorno", day.date, unit: .day),
                    y: .value("Minuti", day.seconds / 60))
                .foregroundStyle(Calendar.current.isDateInToday(day.date) ? Color.accentColor : Color.accentColor.opacity(0.45))
                .cornerRadius(4)
                .annotation(position: .top) {
                    if day.seconds >= 60 {
                        Text("\(Int(day.seconds / 60))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let minutes = value.as(Double.self) { Text("\(Int(minutes)) min") }
                }
            }
        }
        .environment(\.locale, Locale(identifier: "it_IT"))
    }

    private func bookRow(_ document: LibraryDocument, _ total: ReadingLog.BookTotal) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .lineLimit(1)
                Text("\(total.pages) \(total.pages == 1 ? "pagina vista" : "pagine viste") · in tutto \(ReadingLog.duration(stats.log.totalSeconds(of: document.id)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(ReadingLog.duration(total.seconds))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}
