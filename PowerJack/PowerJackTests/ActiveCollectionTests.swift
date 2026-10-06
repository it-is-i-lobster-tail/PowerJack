//
//  ActiveCollectionTests.swift
//  PowerJackTests
//
//  Created by Codex on 7/17/26.
//

import Testing
@testable import PowerJack

@MainActor
struct ActiveCollectionTests {
    @Test("An empty collection has no active program")
    func emptyCollectionReturnsNil() {
        let programs: [Program] = []

        #expect(programs.active == nil)
    }

    @Test("A collection without an active program returns nil")
    func collectionWithoutActiveProgramReturnsNil() {
        let programs = [
            makeProgram(status: .planned),
            makeProgram(status: .complete),
        ]

        #expect(programs.active == nil)
    }

    @Test("A collection returns its active program")
    func collectionReturnsActiveProgram() {
        let activeProgram = makeProgram(status: .active)
        let programs = [
            makeProgram(status: .planned),
            activeProgram,
            makeProgram(status: .complete),
        ]

        #expect(programs.active === activeProgram)
    }

    @Test("The active lookup works with any matching Collection")
    func arraySliceReturnsActiveProgram() {
        let activeProgram = makeProgram(status: .active)
        let programs = [
            makeProgram(status: .planned),
            activeProgram,
            makeProgram(status: .complete),
        ]
        let programSlice = programs[1...]

        #expect(programSlice.active === activeProgram)
    }

    @Test("Two active programs, as sync can produce, return the first instead of crashing")
    func twoActiveProgramsReturnFirst() {
        let first = makeProgram(status: .active)
        let programs = [first, makeProgram(status: .active)]

        #expect(programs.active === first)
    }

    private func makeProgram(status: Status) -> Program {
        let templateProgram = TemplateProgram(
            templateName: "Test Program",
            workoutsPerWeek: 0,
            templateMuscleFocus: []
        )
        let program = Program(
            programLengthWeeks: 1,
            templateProgram: templateProgram
        )
        program.statusValue = status
        return program
    }
}
