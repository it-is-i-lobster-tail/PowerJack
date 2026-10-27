//
//  PowerJackCalendar.swift
//  PowerJack
//
//  Blocks of BUILD weeks and a deload laid out inside the program (R5.1, R5.2), the next week's
//  type (R6.1 to R6.4) and its target RIR column (R4.3).
//

import Foundation

enum PowerJackCalendar {
    /// R5.2: labels the remaining weeks BUILD or DELOAD so blocks run 4-7 weeks.
    static func layout(weeks: Int, carry: Int) -> [PowerJackWeekType] {
        ProgramBlocks.layout(weeks: weeks, carry: carry).map { $0 == .deload ? .deload : .build }
    }

    /// R4.3: the target column of BUILD week `week` of `buildWeeks`, never below `lastColumn`.
    static func column(week: Int, of buildWeeks: Int, lastColumn: Int) -> Int {
        let column = week > buildWeeks || buildWeeks <= 1
            ? 4
            : 1 + (3 * Double(week - 1) / Double(buildWeeks - 1)).roundedHalfUp
        return max(column, lastColumn)
    }
}

/// Where the program stands when a week closes, and what the next week is.
struct PowerJackWeekPlanHeader: Equatable {
    var type: PowerJackWeekType
    var blockNumber: Int
    var blockWeek: Int
    var column: Int
    var isBlockStart: Bool
    /// One strained week makes the next one cautious: no added sets, no extra easy step (R6.4).
    var caution = false
    /// Two strained weeks before the block can deload: flagged exercises hold (R6.4).
    var holdFlagged = false
    /// Every BUILD week of the block so far but the last can take an added set (R3.5).
    var isLastBuildWeek = false
}

extension PowerJackCalendar {
    /// The first week of a program.
    static func firstWeek(programWeeks: Int) -> PowerJackWeekPlanHeader {
        let plan = layout(weeks: programWeeks, carry: 0)
        let buildWeeks = blockBuildWeeks(counted: 0, plan: plan)
        return PowerJackWeekPlanHeader(
            type: plan.first ?? .build,
            blockNumber: 1,
            blockWeek: 1,
            column: 1,
            isBlockStart: true,
            isLastBuildWeek: buildWeeks == 1
        )
    }

    /// Decides the week after `weeks`, with `strained` telling which BUILD weeks showed strain (R6.4)
    /// and `hardDeload` whether a deload just closed with hard taps (R6.3).
    static func nextWeek(
        after weeks: [PowerJackWeekLog],
        programWeeks: Int,
        strained: (PowerJackWeekLog) -> Bool,
        anyStrainSign: (PowerJackWeekLog) -> Bool,
        hardDeload: Bool
    ) -> PowerJackWeekPlanHeader {
        guard let last = weeks.last else { return firstWeek(programWeeks: programWeeks) }
        let plan = Replay(weeks, programWeeks: programWeeks).plan(from: weeks.count)

        if last.type == .deload {
            let previous = weeks.dropLast().last
            if hardDeload, previous?.type != .deload {
                return PowerJackWeekPlanHeader(
                    type: .deload, blockNumber: last.blockNumber, blockWeek: 0, column: 0, isBlockStart: false
                )
            }
            return PowerJackWeekPlanHeader(
                type: .build,
                blockNumber: last.blockNumber + 1,
                blockWeek: 1,
                column: 1,
                isBlockStart: true,
                isLastBuildWeek: blockBuildWeeks(counted: 0, plan: plan) <= 1
            )
        }

        let block = weeks.filter { $0.blockNumber == last.blockNumber && $0.type == .build }
        let counted = block.filter { !$0.isPartial }
        let lastColumn = counted.map(\.column).max() ?? 0

        // Strained BUILD weeks in a row, partial weeks skipped (R6.4).
        var run = 0
        for week in counted.reversed() {
            guard strained(week) else { break }
            run += 1
        }
        let deload = PowerJackWeekPlanHeader(
            type: .deload, blockNumber: last.blockNumber, blockWeek: 0, column: 0, isBlockStart: false
        )
        if run >= 3 || (run >= PowerJackRules.strainWeeks && counted.count >= PowerJackRules.minBuildWeeks) {
            return deload
        }

        let nextWeek = counted.count + 1
        var buildWeeks = blockBuildWeeks(counted: counted.count, plan: plan)
        if plan.first == .deload {
            // R6.2: once a block, one more BUILD week when the last 2 showed no strain.
            let postponed = counted.filter { $0.column == 4 }.count >= 2
            let calm = !counted.suffix(PowerJackRules.strainWeeks).contains(where: anyStrainSign)
            let lastPlanned = lastColumn == 4
            guard !postponed, calm, lastPlanned, counted.count + 1 <= PowerJackRules.maxBuildWeeks else {
                return deload
            }
            buildWeeks = counted.count
        }

        return PowerJackWeekPlanHeader(
            type: .build,
            blockNumber: last.blockNumber,
            blockWeek: nextWeek,
            column: column(week: nextWeek, of: buildWeeks, lastColumn: lastColumn),
            isBlockStart: false,
            caution: run >= 1,
            holdFlagged: run >= PowerJackRules.strainWeeks,
            isLastBuildWeek: nextWeek >= buildWeeks
        )
    }

    /// Block number, block week and target column of each built week, replayed from their types,
    /// so the program only stores each week's type (R5.1).
    static func replay(_ weeks: [PowerJackWeekLog], programWeeks: Int) -> [(block: Int, week: Int, column: Int)] {
        Replay(weeks, programWeeks: programWeeks).weeks
    }

    /// The program's weeks replayed from their types: R5.2's layout from week 1, laid out again the way
    /// R5.4 does when a BUILD week doesn't count, a deload comes early or twice, or the engine postpones
    /// one, and each week's block, block week and column (R5.1).
    struct Replay {
        let programWeeks: Int
        /// One type per program week, as laid out by the end of the weeks replayed.
        private(set) var types: [PowerJackWeekType]
        private(set) var weeks: [(block: Int, week: Int, column: Int)] = []

        init(_ logs: [PowerJackWeekLog], programWeeks: Int) {
            self.programWeeks = programWeeks
            types = PowerJackCalendar.layout(weeks: programWeeks, carry: 0)
            var block = 1
            var counted = 0
            var lastColumn = 0
            var afterDeload = false
            for (index, week) in logs.enumerated() {
                let laidOut = types.indices.contains(index) ? types[index] : week.type
                if week.type == .deload {
                    // An early or second deload, in place of a BUILD week.
                    if laidOut != .deload {
                        relayout(from: index, [.deload] + PowerJackCalendar.layout(weeks: programWeeks - index - 1, carry: 0))
                    }
                    weeks.append((block, 0, 0))
                    afterDeload = true
                    continue
                }
                if afterDeload {
                    block += 1
                    counted = 0
                    lastColumn = 0
                    afterDeload = false
                }
                let buildWeeks: Int
                if laidOut == .deload {
                    // The engine postponed the deload by one BUILD week (R6.2), which k leaves out.
                    relayout(from: index, [.build, .deload] + PowerJackCalendar.layout(weeks: programWeeks - index - 2, carry: 0))
                    buildWeeks = counted
                } else {
                    buildWeeks = PowerJackCalendar.blockBuildWeeks(counted: counted, plan: plan(from: index))
                }
                let weekColumn = PowerJackCalendar.column(week: counted + 1, of: buildWeeks, lastColumn: lastColumn)
                weeks.append((block, counted + 1, weekColumn))
                if week.isPartial {
                    relayout(from: index + 1, PowerJackCalendar.layout(weeks: programWeeks - index - 1, carry: counted))
                } else {
                    counted += 1
                    lastColumn = weekColumn
                }
            }
        }

        /// The laid-out types from program week `index` (0-based) on.
        func plan(from index: Int) -> [PowerJackWeekType] {
            Array(types.dropFirst(index))
        }

        private mutating func relayout(from index: Int, _ tail: [PowerJackWeekType]) {
            types = Array(types.prefix(index)) + Array(tail.prefix(max(0, programWeeks - index)))
        }
    }

    /// k: the block's planned BUILD weeks, counted ones included (R5.1).
    fileprivate static func blockBuildWeeks(counted: Int, plan: [PowerJackWeekType]) -> Int {
        let leading = plan.prefix { $0 == .build }.count
        guard leading < plan.count else {
            // The block is left open at the program's end.
            return max(PowerJackRules.buildWeeks, counted + leading)
        }
        return counted + leading
    }
}
