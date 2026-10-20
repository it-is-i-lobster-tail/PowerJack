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
        guard weeks > 0 else { return [] }
        if carry >= PowerJackRules.buildWeeks {
            return [.deload] + layout(weeks: weeks - 1, carry: 0)
        }
        let total = weeks + carry
        if total < PowerJackRules.minBuildWeeks + 1 {
            return Array(repeating: .build, count: weeks)
        }
        var blocks = (Double(total) / Double(PowerJackRules.buildWeeks + 1)).roundedHalfUp
        blocks = max(blocks, Int((Double(total) / Double(PowerJackRules.maxBuildWeeks + 1)).rounded(.up)))
        blocks = min(blocks, total / (PowerJackRules.minBuildWeeks + 1))
        let lengths = (0..<blocks).map { total / blocks + ($0 < total % blocks ? 1 : 0) }
        let all = lengths.flatMap { Array(repeating: PowerJackWeekType.build, count: $0 - 1) + [.deload] }
        return Array(all.dropFirst(carry))
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
        let rest = programWeeks - weeks.count

        if last.type == .deload {
            let previous = weeks.dropLast().last
            if hardDeload, previous?.type != .deload {
                return PowerJackWeekPlanHeader(
                    type: .deload, blockNumber: last.blockNumber, blockWeek: 0, column: 0, isBlockStart: false
                )
            }
            return blockStart(number: last.blockNumber + 1, rest: rest)
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

        let plan = layout(weeks: rest, carry: counted.count)
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

    private static func blockStart(number: Int, rest: Int) -> PowerJackWeekPlanHeader {
        let plan = layout(weeks: rest, carry: 0)
        return PowerJackWeekPlanHeader(
            type: plan.first ?? .build,
            blockNumber: number,
            blockWeek: plan.first == .deload ? 0 : 1,
            column: plan.first == .deload ? 0 : 1,
            isBlockStart: true,
            isLastBuildWeek: blockBuildWeeks(counted: 0, plan: plan) <= 1
        )
    }

    /// Block number, block week and target column of each built week, replayed from their types,
    /// so the program only stores each week's type (R5.1).
    static func replay(_ weeks: [PowerJackWeekLog], programWeeks: Int) -> [(block: Int, week: Int, column: Int)] {
        var result: [(block: Int, week: Int, column: Int)] = []
        var block = 1
        var counted = 0
        var lastColumn = 0
        var afterDeload = false
        for (index, week) in weeks.enumerated() {
            if week.type == .deload {
                result.append((block, 0, 0))
                afterDeload = true
                continue
            }
            if afterDeload {
                block += 1
                counted = 0
                lastColumn = 0
                afterDeload = false
            }
            let plan = layout(weeks: programWeeks - index, carry: counted)
            // A planned deload here means the engine postponed it by one BUILD week (R6.2).
            let buildWeeks = plan.first == .deload ? counted : blockBuildWeeks(counted: counted, plan: plan)
            let column = column(week: counted + 1, of: buildWeeks, lastColumn: lastColumn)
            result.append((block, counted + 1, column))
            if !week.isPartial {
                counted += 1
                lastColumn = column
            }
        }
        return result
    }

    /// k: the block's planned BUILD weeks, counted ones included (R5.1).
    private static func blockBuildWeeks(counted: Int, plan: [PowerJackWeekType]) -> Int {
        let leading = plan.prefix { $0 == .build }.count
        guard leading < plan.count else {
            // The block is left open at the program's end.
            return max(PowerJackRules.buildWeeks, counted + leading)
        }
        return counted + leading
    }
}
