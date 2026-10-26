import ReaderCore
import SwiftUI

/// The study timer in the reader's bar: an icon when unused, the time left once started.
/// Tapping it opens the controls.
struct StudyTimerButton: View {
    let bookID: UUID
    @Environment(StudyTimer.self) private var timer
    @State private var showPanel = false

    var body: some View {
        Button { showPanel = true } label: { label }
            .accessibilityLabel("Timer di studio")
            .popover(isPresented: $showPanel) {
                StudyTimerPanel(bookID: bookID)
                    .frame(width: 340)
                    .presentationCompactAdaptation(.popover)
            }
    }

    @ViewBuilder private var label: some View {
        if timer.isIdle {
            Image(systemName: "timer")
        } else {
            HStack(spacing: 4) {
                Image(systemName: timer.phase.isBreak ? "cup.and.saucer.fill" : "timer")
                    .font(.caption)
                StudyTimerTime(timer: timer)
                    .font(.callout)
            }
            .foregroundStyle(timer.phase.tint.opacity(timer.isRunning ? 1 : 0.6))
        }
    }
}

/// Minutes and seconds left, counting down by itself while the timer runs.
private struct StudyTimerTime: View {
    let timer: StudyTimer

    var body: some View {
        Group {
            if let end = timer.endDate, end > .now {
                Text(timerInterval: Date.now...end, countsDown: true, showsHours: false)
            } else {
                Text(Self.clock(timer.remaining()))
            }
        }
        .monospacedDigit()
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct StudyTimerPanel: View {
    let bookID: UUID
    @Environment(StudyTimer.self) private var timer
    @Environment(ReadingStats.self) private var stats

    var body: some View {
        @Bindable var timer = timer
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text(timer.phaseName)
                    .font(.headline)
                    .foregroundStyle(timer.phase.tint)
                StudyTimerTime(timer: timer)
                    .font(.system(size: 54, weight: .light))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if timer.isRunning {
                    Button("Pausa", systemImage: "pause.fill") { timer.pause() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(timer.timer.isWaiting ? "Avvia" : "Riprendi", systemImage: "play.fill") { timer.start() }
                        .buttonStyle(.borderedProminent)
                }
                Button(timer.phase.isBreak ? "Salta la pausa" : "Salta", systemImage: "forward.end.fill") {
                    timer.skip()
                }
                .buttonStyle(.bordered)
                Menu {
                    Button("Ricomincia questo blocco", systemImage: "arrow.counterclockwise") { timer.restartPhase() }
                    Button("Azzera il ciclo", systemImage: "arrow.uturn.backward", role: .destructive) { timer.reset() }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(minHeight: 22)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Altro")
            }
            .tint(timer.phase.tint)

            if timer.notificationsDenied {
                Label("Le notifiche sono disattivate: la fine del blocco si vede solo nell'app. Puoi attivarle in Impostazioni › Notifiche › PencilReader.",
                      systemImage: "bell.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Oggi su questo libro").foregroundStyle(.secondary)
                        Text(ReadingLog.duration(stats.secondsToday(of: bookID)))
                    }
                    GridRow {
                        Text("Pagine viste oggi").foregroundStyle(.secondary)
                        Text("\(stats.log.pages(on: .now, of: bookID))")
                    }
                    GridRow {
                        Text("Blocchi completati oggi").foregroundStyle(.secondary)
                        Text("\(stats.log.focusBlocks(on: .now))")
                    }
                }
                .font(.subheadline)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            DisclosureGroup("Durate") {
                VStack(spacing: 4) {
                    Stepper("Studio: \(timer.settings.focusMinutes) min",
                            value: $timer.settings.focusMinutes, in: PomodoroSettings.focusRange, step: 5)
                    Stepper("Pausa breve: \(timer.settings.shortBreakMinutes) min",
                            value: $timer.settings.shortBreakMinutes, in: PomodoroSettings.shortBreakRange)
                    Stepper("Pausa lunga: \(timer.settings.longBreakMinutes) min",
                            value: $timer.settings.longBreakMinutes, in: PomodoroSettings.longBreakRange, step: 5)
                    Stepper("Pausa lunga ogni \(timer.settings.blocksBeforeLongBreak) blocchi",
                            value: $timer.settings.blocksBeforeLongBreak, in: PomodoroSettings.blocksRange)
                    Button("Ripristina 25 / 5") { timer.settings = PomodoroSettings() }
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 4)
                }
                .font(.subheadline)
                .padding(.top, 6)
            }
        }
        .padding(20)
        .onAppear { timer.refresh() }
    }

    private var subtitle: String {
        let blocks = timer.settings.blocksBeforeLongBreak
        switch timer.phase {
        case .focus:
            return "Blocco \(min(timer.blockNumber, blocks)) di \(blocks) · poi \(StudyTimer.name(of: timer.timer.nextPhase(settings: timer.settings)).lowercased())"
        case .shortBreak, .longBreak:
            return "Alzati, bevi qualcosa, guarda lontano dallo schermo"
        }
    }
}

extension PomodoroPhase {
    var tint: Color {
        switch self {
        case .focus: .red
        case .shortBreak: .green
        case .longBreak: .teal
        }
    }
}
