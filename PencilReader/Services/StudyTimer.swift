import Foundation
import Observation
import ReaderCore
import UserNotifications

/// The Pomodoro study timer. It keeps running when the book or the app is closed: the end of a
/// block is announced by a local notification, and the state is saved so it is picked up again.
@MainActor
@Observable
final class StudyTimer {
    private(set) var timer: PomodoroTimer {
        didSet { Self.store(timer, forKey: Self.timerKey) }
    }
    var settings: PomodoroSettings {
        didSet { Self.store(settings, forKey: Self.settingsKey) }
    }
    /// The user turned notifications off for the app: the end of a block shows only in the app.
    private(set) var notificationsDenied = false

    private let stats: ReadingStats
    private var finishTask: Task<Void, Never>?
    private static let timerKey = "studyTimer.state"
    private static let settingsKey = "studyTimer.settings"
    private static let notificationID = "studyTimer.end"

    init(stats: ReadingStats) {
        self.stats = stats
        timer = Self.load(PomodoroTimer.self, forKey: Self.timerKey) ?? PomodoroTimer()
        settings = Self.load(PomodoroSettings.self, forKey: Self.settingsKey) ?? PomodoroSettings()
        refresh()
    }

    var phase: PomodoroPhase { timer.phase }
    var isRunning: Bool { timer.isRunning }
    /// Untouched since the last reset: the reader shows just an icon.
    var isIdle: Bool { timer.isWaiting && timer.phase == .focus && timer.blocksInCycle == 0 }
    var endDate: Date? { timer.endDate }

    func remaining(at now: Date = .now) -> TimeInterval { timer.remaining(at: now, settings: settings) }

    /// Study block number in the cycle, counted from 1.
    var blockNumber: Int { timer.blocksInCycle + (timer.phase == .focus ? 1 : 0) }

    var phaseName: String { Self.name(of: timer.phase) }

    static func name(of phase: PomodoroPhase) -> String {
        switch phase {
        case .focus: "Studio"
        case .shortBreak: "Pausa breve"
        case .longBreak: "Pausa lunga"
        }
    }

    // MARK: Controls

    func start() {
        timer.start(at: .now, settings: settings)
        scheduleEnd()
    }

    func pause() {
        timer.pause(at: .now)
        cancelEnd()
    }

    func skip() {
        cancelEnd()
        timer.skip(settings: settings)
    }

    func restartPhase() {
        cancelEnd()
        timer.restartPhase()
    }

    func reset() {
        cancelEnd()
        timer.reset()
    }

    /// Catches up with a block that ended while the app was in the background or closed.
    func refresh() {
        if let ended = timer.finishIfDue(at: .now, settings: settings) {
            if ended.phase == .focus { stats.focusBlockFinished(at: ended.end) }
        }
        armFinishTask()
    }

    // MARK: End of a block

    private func scheduleEnd() {
        armFinishTask()
        guard let endDate = timer.endDate else { return }
        let ending = timer.phase
        let next = timer.nextPhase(settings: settings)
        let minutes = settings.minutes(of: next)
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            notificationsDenied = !granted
            guard granted, timer.endDate == endDate else { return }
            let content = UNMutableNotificationContent()
            if ending == .focus {
                content.title = "Blocco di studio finito"
                content.body = next == .longBreak
                    ? "Ottimo lavoro: concediti una pausa lunga di \(minutes) minuti."
                    : "Fai una pausa di \(minutes) minuti."
            } else {
                content.title = "Pausa finita"
                content.body = "Pronto per un altro blocco da \(minutes) minuti?"
            }
            content.sound = .default
            let interval = max(1, endDate.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: Self.notificationID, content: content,
                                                        trigger: trigger))
        }
    }

    private func cancelEnd() {
        finishTask?.cancel()
        finishTask = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }

    /// While the app is open, moves to the next phase as soon as the block ends.
    private func armFinishTask() {
        finishTask?.cancel()
        finishTask = nil
        guard let endDate = timer.endDate else { return }
        finishTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, endDate.timeIntervalSinceNow) + 0.2)) } catch { return }
            self?.refresh()
        }
    }

    // MARK: Storage

    private static func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func store<T: Encodable>(_ value: T, forKey key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }
}

/// Shows the end-of-block notification as a banner also while the app is in front.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
