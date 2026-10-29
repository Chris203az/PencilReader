import Foundation

/// A reading session that fits the time the user has: how many study blocks, and how long the
/// blocks and the breaks between them are. Blocks stay close to the classic 25 minutes; the breaks
/// grow with them (a fifth of a block, a long one every four) and none comes after the last block.
public struct ReadingPlan: Codable, Sendable, Equatable {
    /// The time the user asked for, breaks included.
    public let totalMinutes: Int
    public let blocks: Int
    /// The lengths the timer uses during the session.
    public let settings: PomodoroSettings

    public static let totalRange = 10...480
    static let idealFocusMinutes = 25.0
    /// Shorter blocks than this aren't worth a break: below it the whole time is one block.
    static let shortestSplitBlock = 20.0
    static let shortBreakShare = 0.2
    static let longBreakShare = 0.6
    static let longBreakEvery = 4

    public init(totalMinutes: Int) {
        let total = min(max(totalMinutes, Self.totalRange.lowerBound), Self.totalRange.upperBound)
        self.totalMinutes = total

        // The number of blocks whose length comes closest to the ideal one.
        var best = (blocks: 1, focus: Double(total))
        var count = 2
        while true {
            let focus = Self.focusEstimate(total: total, blocks: count)
            if focus < Self.shortestSplitBlock { break }
            if abs(focus - Self.idealFocusMinutes) < abs(best.focus - Self.idealFocusMinutes) {
                best = (count, focus)
            }
            count += 1
        }
        blocks = best.blocks

        var settings = PomodoroSettings()
        settings.blocksBeforeLongBreak = Self.longBreakEvery
        let (short, long) = Self.breaks(blocks: blocks)
        if blocks > 1 {
            settings.shortBreakMinutes = Self.clamp(Int((best.focus * Self.shortBreakShare).rounded()),
                                                    to: 3...15)
            settings.longBreakMinutes = Self.clamp(Int((best.focus * Self.longBreakShare).rounded()),
                                                   to: 10...30)
        }
        let breakMinutes = short * settings.shortBreakMinutes + long * settings.longBreakMinutes
        settings.focusMinutes = Self.clamp((total - breakMinutes) / blocks, to: PomodoroSettings.focusRange)
        self.settings = settings
    }

    /// Minutes actually planned: the blocks and the breaks between them. It can fall short of the
    /// time asked for by less than a minute per block, since lengths are whole minutes.
    public var plannedMinutes: Int {
        let (short, long) = Self.breaks(blocks: blocks)
        return blocks * settings.focusMinutes + short * settings.shortBreakMinutes + long * settings.longBreakMinutes
    }

    /// Breaks between the blocks: a long one after every fourth block, short ones otherwise.
    public static func breaks(blocks: Int) -> (short: Int, long: Int) {
        let gaps = max(0, blocks - 1)
        let long = gaps / longBreakEvery
        return (gaps - long, long)
    }

    private static func focusEstimate(total: Int, blocks: Int) -> Double {
        let (short, long) = breaks(blocks: blocks)
        return Double(total) / (Double(blocks) + Double(short) * shortBreakShare + Double(long) * longBreakShare)
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// A reading session under way: the plan and the study blocks already behind.
public struct ReadingSession: Codable, Sendable, Equatable {
    public let plan: ReadingPlan
    /// Study blocks finished or skipped.
    public internal(set) var blocksDone = 0

    public init(plan: ReadingPlan) {
        self.plan = plan
    }

    public var isOver: Bool { blocksDone >= plan.blocks }
}
