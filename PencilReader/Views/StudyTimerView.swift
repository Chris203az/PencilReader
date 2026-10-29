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
        } else if timer.isSessionOver {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
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
    @State private var showReadingTime = false

    var body: some View {
        @Bindable var timer = timer
        VStack(spacing: 18) {
            if timer.isSessionOver {
                sessionOver
            } else {
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
                controls
            }

            if timer.notificationsDenied {
                Label("Le notifiche sono disattivate: la fine del blocco si vede solo nell'app. Puoi attivarle in Impostazioni › Notifiche › PencilReader.",
                      systemImage: "bell.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            readingTime

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
                    if timer.session != nil {
                        Text("Durante la sessione valgono le durate adattate al tempo scelto; queste tornano dopo.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
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

    private var controls: some View {
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
                if timer.session != nil {
                    Button("Ricomincia la sessione", systemImage: "arrow.uturn.backward") { timer.reset() }
                    Button("Termina la sessione", systemImage: "xmark", role: .destructive) { timer.endSession() }
                } else {
                    Button("Azzera il ciclo", systemImage: "arrow.uturn.backward", role: .destructive) { timer.reset() }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(minHeight: 22)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Altro")
        }
        .tint(timer.phase.tint)
    }

    /// The session's time is used up: start another one or go on with single blocks.
    private var sessionOver: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text(timer.phaseName)
                .font(.headline)
            if let plan = timer.session?.plan {
                Text("Hai finito la sessione da \(ReadingTimePicker.duration(plan.totalMinutes)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("Nuova sessione", systemImage: "hourglass") {
                    timer.endSession()
                    showReadingTime = true
                }
                .buttonStyle(.borderedProminent)
                Button("Continua a blocchi", systemImage: "timer") { timer.endSession() }
                    .buttonStyle(.bordered)
            }
        }
    }

    /// Reading for a chosen time: the session under way, or the form to start one.
    @ViewBuilder private var readingTime: some View {
        if let session = timer.session {
            if !session.isOver {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Sessione da \(ReadingTimePicker.duration(session.plan.totalMinutes))",
                              systemImage: "hourglass")
                        if let end = timer.sessionEnd(from: context.date) {
                            Text(sessionEndText(end, now: context.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            DisclosureGroup("Leggi per un tempo preciso", isExpanded: $showReadingTime) {
                ReadingTimePicker { minutes in
                    timer.startSession(minutes: minutes)
                    showReadingTime = false
                }
                .padding(.top, 6)
            }
        }
    }

    private func sessionEndText(_ end: Date, now: Date) -> String {
        if timer.isRunning {
            return "Finisce verso le \(end.formatted(date: .omitted, time: .shortened))"
        }
        let minutes = Int((end.timeIntervalSince(now) / 60).rounded(.up))
        return "Mancano \(ReadingTimePicker.duration(minutes)), timer fermo"
    }

    private var subtitle: String {
        let settings = timer.activeSettings
        let next = timer.timer.isLastBlock
            ? "ultimo blocco"
            : "poi \(StudyTimer.name(of: timer.timer.nextPhase(settings: timer.settings)).lowercased())"
        switch timer.phase {
        case .focus:
            if let session = timer.session {
                return "Blocco \(session.blocksDone + 1) di \(session.plan.blocks) · \(next)"
            }
            let blocks = settings.blocksBeforeLongBreak
            return "Blocco \(min(timer.blockNumber, blocks)) di \(blocks) · \(next)"
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
