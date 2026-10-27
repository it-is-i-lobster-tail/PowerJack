//
//  ProgramBlocks.swift
//  PowerJack
//
//  Lays a program's weeks out in blocks of build weeks that each end in a deload, sized so the program
//  ends on a deload (PowerJack R5.2). Every style uses it, so blocks fit whatever length the lifter picks.
//

import Foundation

enum ProgramBlocks {
    static let buildWeeks = 4
    static let minBuildWeeks = 3
    static let maxBuildWeeks = 6

    /// Labels the remaining `weeks` build or deload so blocks run 4-7 weeks, after `carry` build weeks of the
    /// current block. Too few weeks for a block are all build weeks.
    static func layout(weeks: Int, carry: Int) -> [WeekKind] {
        guard weeks > 0 else { return [] }
        if carry >= buildWeeks {
            return [.deload] + layout(weeks: weeks - 1, carry: 0)
        }
        let total = weeks + carry
        if total < minBuildWeeks + 1 {
            return Array(repeating: .build, count: weeks)
        }
        var blocks = Int((Double(total) / Double(buildWeeks + 1)).rounded())
        blocks = max(blocks, Int((Double(total) / Double(maxBuildWeeks + 1)).rounded(.up)))
        blocks = min(blocks, total / (minBuildWeeks + 1))
        let lengths = (0..<blocks).map { total / blocks + ($0 < total % blocks ? 1 : 0) }
        let all = lengths.flatMap { Array(repeating: WeekKind.build, count: $0 - 1) + [.deload] }
        return Array(all.dropFirst(carry))
    }

    /// The planned build weeks of a block whose block week 1 falls on program week `start` (0-based). A block
    /// carried over from an earlier program starts before week 0. A block the program ends inside runs at
    /// least 4 build weeks, so it carries on into the next program.
    static func buildWeeks(blockStart start: Int, programWeeks: Int) -> Int {
        let carry = max(0, -start)
        let plan = layout(weeks: programWeeks - max(0, start), carry: carry)
        let leading = plan.prefix { $0 == .build }.count
        return leading < plan.count ? carry + leading : max(buildWeeks, carry + leading)
    }

    /// The planned build weeks of the block that program week `index` (0-based) is block week `blockWeek` of.
    /// A week that didn't count toward its block, like a repeated or calibration week, moves the block's
    /// start later, so the rest of the program is laid out again from there.
    static func buildWeeks(blockWeek: Int, at index: Int, programWeeks: Int) -> Int {
        buildWeeks(blockStart: index - (max(blockWeek, 1) - 1), programWeeks: programWeeks)
    }
}
