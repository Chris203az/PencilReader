import Foundation

/// Lengths of the study timer's blocks, in minutes.
public struct PomodoroSettings: Codable, Sendable, Equatable {
    public var focusMinutes = 25
    public var shortBreakMinutes = 5
    public var longBreakMinutes = 15
    /// A long break comes after this many study blocks.
    public var blocksBeforeLongBreak = 4

    public static let focusRange = 5...90
    public static let shortBreakRange = 1...30
    public static let longBreakRange = 5...45
    public static let blocksRange = 2...8

    public init() {}

    public func minutes(of phase: PomodoroPhase) -> Int {
        switch phase {
        case .focus: focusMinutes
        case .shortBreak: shortBreakMinutes
        case .longBreak: longBreakMinutes
        }
    }

    public func duration(of phase: PomodoroPhase) -> TimeInterval { TimeInterval(minutes(of: phase) * 60) }
}

public enum PomodoroPhase: String, Codable, Sendable {
    case focus
    case shortBreak
    case longBreak

    public var isBreak: Bool { self != .focus }
}

/// The study timer: a study block, then a break, then the next block. It keeps the end time, not
/// a counter, so it stays right while the app is in the background or closed. When a block ends
/// the next one waits to be started. During a reading session the plan's lengths take the place of
/// the settings passed in, and the timer stops for good after the plan's last block.
public struct PomodoroTimer: Codable, Sendable, Equatable {
    public private(set) var phase: PomodoroPhase = .focus
    /// Study blocks finished since the last long break.
    public private(set) var blocksInCycle = 0
    /// Set while the timer runs.
    public private(set) var endDate: Date?
    /// Time left when paused; nil when the phase hasn't started.
    public private(set) var pausedRemaining: TimeInterval?
    /// Set while reading for a chosen time; nil for the open-ended cycle.
    public private(set) var session: ReadingSession?

    public init() {}

    /// The lengths in use: the session's while one is under way, otherwise `settings`.
    public func activeSettings(_ settings: PomodoroSettings) -> PomodoroSettings {
        session?.plan.settings ?? settings
    }

    /// The session's last block is over: nothing is left to start.
    public var isSessionOver: Bool { session?.isOver ?? false }

    /// The running phase is the session's last block: no break comes after it.
    public var isLastBlock: Bool {
        guard phase == .focus, let session else { return false }
        return session.blocksDone + 1 >= session.plan.blocks
    }

    /// Starts reading for the plan's time, from its first block.
    public mutating func startSession(_ plan: ReadingPlan, at now: Date) {
        self = PomodoroTimer()
        session = ReadingSession(plan: plan)
        start(at: now, settings: plan.settings)
    }

    /// Leaves the session for the open-ended cycle, waiting at a new study block.
    public mutating func endSession() {
        self = PomodoroTimer()
    }

    /// Time until the end of the session: what's left of this phase plus the phases still to come.
    /// Nil outside a session.
    public func sessionRemaining(at now: Date) -> TimeInterval? {
        guard let session else { return nil }
        if session.isOver { return 0 }
        let settings = session.plan.settings
        var total = remaining(at: now, settings: settings)
        var rest = self
        while true {
            rest.moveToNextPhase(countingBlock: true, settings: settings)
            if rest.isSessionOver { break }
            total += settings.duration(of: rest.phase)
        }
        return total
    }

    public var isRunning: Bool { endDate != nil }
    /// Neither running nor paused halfway: the phase is waiting to start from the full length.
    public var isWaiting: Bool { endDate == nil && pausedRemaining == nil }

    public func remaining(at now: Date, settings: PomodoroSettings) -> TimeInterval {
        let settings = activeSettings(settings)
        if let endDate { return max(0, endDate.timeIntervalSince(now)) }
        return pausedRemaining ?? settings.duration(of: phase)
    }

    public mutating func start(at now: Date, settings: PomodoroSettings) {
        guard endDate == nil, !isSessionOver else { return }
        let settings = activeSettings(settings)
        endDate = now.addingTimeInterval(pausedRemaining ?? settings.duration(of: phase))
        pausedRemaining = nil
    }

    public mutating func pause(at now: Date) {
        guard let endDate else { return }
        pausedRemaining = max(0, endDate.timeIntervalSince(now))
        self.endDate = nil
    }

    /// Back to the start of the current phase, stopped.
    public mutating func restartPhase() {
        endDate = nil
        pausedRemaining = nil
    }

    /// Back to the first study block of a new cycle, or of the session, stopped.
    public mutating func reset() {
        let plan = session?.plan
        self = PomodoroTimer()
        session = plan.map(ReadingSession.init(plan:))
    }

    /// Ends the phase now without counting it as done, and waits at the next one.
    public mutating func skip(settings: PomodoroSettings) {
        moveToNextPhase(countingBlock: false, settings: settings)
    }

    /// When the running phase is over by `now`, moves to the next one (stopped) and returns the
    /// phase that ended with its end time; nil while it's still running.
    public mutating func finishIfDue(at now: Date, settings: PomodoroSettings) -> (phase: PomodoroPhase, end: Date)? {
        guard let endDate, endDate <= now else { return nil }
        let ended = phase
        moveToNextPhase(countingBlock: true, settings: settings)
        return (ended, endDate)
    }

    /// The phase that follows the current one.
    public func nextPhase(settings: PomodoroSettings, countingBlock: Bool = true) -> PomodoroPhase {
        guard phase == .focus, !isLastBlock else { return .focus }
        let settings = activeSettings(settings)
        let blocks = blocksInCycle + (countingBlock ? 1 : 0)
        return blocks >= settings.blocksBeforeLongBreak ? .longBreak : .shortBreak
    }

    private mutating func moveToNextPhase(countingBlock: Bool, settings: PomodoroSettings) {
        let next = nextPhase(settings: settings, countingBlock: countingBlock)
        if phase == .focus, countingBlock { blocksInCycle += 1 }
        // A skipped block still uses up its slot of the session's time.
        if phase == .focus { session?.blocksDone += 1 }
        if next == .longBreak || isSessionOver { blocksInCycle = 0 }
        phase = next
        endDate = nil
        pausedRemaining = nil
    }
}
