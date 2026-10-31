import ReaderCore
import SwiftUI

/// Asks how long the user wants to read and shows how the time is split into study blocks and
/// breaks. The chosen time is remembered for next time.
struct ReadingTimePicker: View {
    var startTitle = String(localized: "Inizia a leggere")
    let onStart: (Int) -> Void
    @AppStorage("studyTimer.readingMinutes") private var minutes = 60

    var body: some View {
        let plan = ReadingPlan(totalMinutes: minutes)
        VStack(alignment: .leading, spacing: 8) {
            Stepper(value: $minutes, in: ReadingPlan.totalRange, step: minutes < 60 ? 5 : 15) {
                LabeledContent("Tempo di lettura", value: Self.duration(minutes))
            }
            Text(Self.description(of: plan))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(startTitle, systemImage: "play.fill") { onStart(minutes) }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 4)
        }
        .font(.subheadline)
    }

    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    static func description(of plan: ReadingPlan) -> String {
        let settings = plan.settings
        guard plan.blocks > 1 else { return String(localized: "Un blocco unico da \(settings.focusMinutes) min, senza pause.") }
        var text = String(localized: "\(plan.blocks) blocchi da \(settings.focusMinutes) min, pause da \(settings.shortBreakMinutes) min")
        if ReadingPlan.breaks(blocks: plan.blocks).long > 0 {
            text += String(localized: " e una pausa lunga da \(settings.longBreakMinutes) min ogni \(settings.blocksBeforeLongBreak) blocchi")
        }
        return text + "."
    }
}
