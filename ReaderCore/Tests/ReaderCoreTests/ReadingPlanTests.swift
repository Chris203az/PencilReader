import Foundation
import Testing
@testable import ReaderCore

struct ReadingPlanTests {
    let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func anHourIsTwoBlocksWithABreak() {
        let plan = ReadingPlan(totalMinutes: 60)
        #expect(plan.blocks == 2)
        #expect(plan.settings.focusMinutes == 27)
        #expect(plan.settings.shortBreakMinutes == 5)
        #expect(plan.plannedMinutes == 59)
    }

    @Test func shortTimeIsASingleBlock() {
        let plan = ReadingPlan(totalMinutes: 35)
        #expect(plan.blocks == 1)
        #expect(plan.settings.focusMinutes == 35)
        #expect(plan.plannedMinutes == 35)
    }

    @Test func blocksStayNearTwentyFiveMinutesAndFitTheTime() {
        for total in stride(from: 10, through: 480, by: 5) {
            let plan = ReadingPlan(totalMinutes: total)
            #expect(plan.plannedMinutes <= total, "\(total) min")
            #expect(total - plan.plannedMinutes < plan.blocks, "\(total) min")
            if plan.blocks > 1 {
                #expect((20...32).contains(plan.settings.focusMinutes), "\(total) min")
            }
        }
    }

    @Test func longSessionsGetALongBreakEveryFourBlocks() {
        let plan = ReadingPlan(totalMinutes: 180)
        #expect(plan.blocks == 6)
        let breaks = ReadingPlan.breaks(blocks: plan.blocks)
        #expect(breaks.short == 4 && breaks.long == 1)
        #expect(plan.settings.longBreakMinutes > plan.settings.shortBreakMinutes)
        #expect(plan.settings.blocksBeforeLongBreak == 4)
    }

    @Test func timeOutsideTheRangeIsClamped() {
        #expect(ReadingPlan(totalMinutes: 2).totalMinutes == ReadingPlan.totalRange.lowerBound)
        #expect(ReadingPlan(totalMinutes: 2000).totalMinutes == ReadingPlan.totalRange.upperBound)
    }

    @Test func sessionRunsThePlanAndStopsAfterTheLastBlock() {
        let plan = ReadingPlan(totalMinutes: 180)
        var timer = PomodoroTimer()
        timer.startSession(plan, at: start)
        #expect(timer.isRunning)
        #expect(timer.sessionRemaining(at: start) == TimeInterval(plan.plannedMinutes * 60))

        let ignored = PomodoroSettings()  // the user's own lengths don't count during a session
        var phases: [PomodoroPhase] = []
        var now = start
        while !timer.isSessionOver {
            timer.start(at: now, settings: ignored)
            now = timer.endDate!
            phases.append(timer.finishIfDue(at: now, settings: ignored)!.phase)
        }
        #expect(phases == [.focus, .shortBreak, .focus, .shortBreak, .focus, .shortBreak, .focus, .longBreak,
                           .focus, .shortBreak, .focus])
        #expect(now == start.addingTimeInterval(TimeInterval(plan.plannedMinutes * 60)))
        #expect(timer.sessionRemaining(at: now) == 0)

        timer.start(at: now, settings: ignored)
        #expect(!timer.isRunning)
    }

    @Test func lastBlockHasNoBreakAfterIt() {
        var timer = PomodoroTimer()
        timer.startSession(ReadingPlan(totalMinutes: 30), at: start)
        #expect(timer.isLastBlock)
        #expect(timer.nextPhase(settings: PomodoroSettings()) == .focus)
        _ = timer.finishIfDue(at: start.addingTimeInterval(3600), settings: PomodoroSettings())
        #expect(timer.isSessionOver)
    }

    @Test func skippingABlockUsesUpItsSlot() {
        var timer = PomodoroTimer()
        timer.startSession(ReadingPlan(totalMinutes: 60), at: start)
        timer.skip(settings: PomodoroSettings())
        #expect(timer.phase == .shortBreak)
        #expect(timer.session?.blocksDone == 1)
        timer.skip(settings: PomodoroSettings())
        #expect(timer.isLastBlock)
    }

    @Test func endingTheSessionGoesBackToTheUsersLengths() {
        var timer = PomodoroTimer()
        timer.startSession(ReadingPlan(totalMinutes: 60), at: start)
        #expect(timer.remaining(at: start, settings: PomodoroSettings()) == 27 * 60)
        timer.endSession()
        #expect(timer.session == nil)
        #expect(timer.isWaiting)
        #expect(timer.remaining(at: start, settings: PomodoroSettings()) == 25 * 60)
    }

    @Test func resetRestartsTheSessionStopped() {
        var timer = PomodoroTimer()
        timer.startSession(ReadingPlan(totalMinutes: 60), at: start)
        timer.skip(settings: PomodoroSettings())
        timer.reset()
        #expect(timer.session?.blocksDone == 0)
        #expect(timer.phase == .focus)
        #expect(timer.isWaiting)
    }

    @Test func savedTimersWithoutASessionStillLoad() throws {
        let old = #"{"phase":"shortBreak","blocksInCycle":2}"#
        let timer = try JSONDecoder().decode(PomodoroTimer.self, from: Data(old.utf8))
        #expect(timer.phase == .shortBreak)
        #expect(timer.session == nil)
    }
}
