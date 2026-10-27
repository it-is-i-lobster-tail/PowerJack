//
//  ProgramBlocksTests.swift
//  PowerJackTests
//
//  The block layout every style shares: blocks fit the program's length so it ends on a deload.
//

import Testing
@testable import PowerJack

struct ProgramBlocksTests {
    @Test("Every program length the lifter can pick ends on a deload, except 2 weeks, which is too short for a block")
    func layoutsFitEachLength() {
        let expected = [
            2: "BB",
            4: "BBBD",
            6: "BBBBBD",
            8: "BBBDBBBD",
            10: "BBBBDBBBBD",
            12: "BBBBBDBBBBBD",
        ]
        for (weeks, text) in expected {
            #expect(Self.text(ProgramBlocks.layout(weeks: weeks, carry: 0)) == text, "\(weeks) weeks")
        }
    }

    @Test("A block's planned build weeks come from where it starts in the program")
    func buildWeeksFromTheBlockStart() {
        #expect(ProgramBlocks.buildWeeks(blockStart: 0, programWeeks: 12) == 5)
        #expect(ProgramBlocks.buildWeeks(blockStart: 6, programWeeks: 12) == 5)
        #expect(ProgramBlocks.buildWeeks(blockStart: 0, programWeeks: 8) == 3)
        // A deload two weeks early lays the rest of a 12-week program out again: 4 build weeks, then 3.
        #expect(ProgramBlocks.buildWeeks(blockStart: 3, programWeeks: 12) == 4)
        #expect(ProgramBlocks.buildWeeks(blockStart: 8, programWeeks: 12) == 3)
        // Too few weeks left for a block: it runs 4 build weeks and carries on past the program.
        #expect(ProgramBlocks.buildWeeks(blockStart: 0, programWeeks: 2) == 4)
        #expect(ProgramBlocks.buildWeeks(blockStart: 12, programWeeks: 12) == 4)
        // A block carried in from a 2-week program finishes in a second one: 3 build weeks, then the deload.
        #expect(ProgramBlocks.buildWeeks(blockStart: -2, programWeeks: 2) == 3)
    }

    @Test("A week that didn't count toward its block moves the block's start, so it still ends on the program's last week")
    func uncountedWeekMovesTheStart() {
        // Week 3 of a 6-week program repeated block week 2, so block week 3 falls on week 4.
        #expect(ProgramBlocks.buildWeeks(blockWeek: 3, at: 3, programWeeks: 6) == 4)
        #expect(ProgramBlocks.buildWeeks(blockWeek: 3, at: 2, programWeeks: 6) == 5)
    }

    private static func text(_ kinds: [WeekKind]) -> String {
        kinds.map { $0 == .deload ? "D" : "B" }.joined()
    }
}
