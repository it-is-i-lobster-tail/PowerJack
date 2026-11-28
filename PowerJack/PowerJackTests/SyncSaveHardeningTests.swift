//
//  SyncSaveHardeningTests.swift
//  PowerJackTests
//
//  Screens whose models syncing deleted, and the warning when saves keep failing.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct SyncSaveHardeningTests {
    @Test("A route whose workout syncing deleted is dropped, with every screen after it")
    func removedWorkoutRouteIsDropped() throws {
        let scenario = PowerJackSeed.weekOneProgress()
        let context = scenario.container.mainContext
        let program = scenario.program
        let workout = try #require(scenario.weekOneWorkouts.first)
        let router = ProgramsRouter()
        router.path = [.detail(program), .preview(program, workout, nil), .editDays(program)]
        #expect(router.path.allSatisfy { !$0.showsRemovedModel })

        context.delete(workout)
        #expect(ProgramRoute.preview(program, workout, nil).showsRemovedModel)
        try context.save()
        #expect(ProgramRoute.preview(program, workout, nil).showsRemovedModel)
        #expect(!ProgramRoute.detail(program).showsRemovedModel)

        router.dropRemovedRoutes()
        #expect(router.path == [.detail(program)])
    }

    @Test("Routes that all still exist are left alone")
    func liveRoutesStay() {
        let scenario = PowerJackSeed.weekOneProgress()
        let router = ProgramsRouter()
        router.path = [.newProgram, .detail(scenario.program)]

        router.dropRemovedRoutes()

        #expect(router.path == [.newProgram, .detail(scenario.program)])
    }

    @Test("Two failed saves in a row show the warning, and a save that works clears it")
    func unsavedWarning() async throws {
        let container = PowerJackSeed.makeInMemoryContainer()
        let context = container.mainContext
        let health = SaveHealth.shared

        health.recordFailure(in: context)
        #expect(!health.changesAreUnsaved)
        health.recordFailure(in: context)
        #expect(health.changesAreUnsaved)

        // A save of another store says nothing about this one.
        let other = PowerJackSeed.makeInMemoryContainer().mainContext
        other.insert(Exercise(exerciseName: "Other Store Lift", exerciseEquipment: .barbell, primaryMuscleFocus: .back))
        try other.save()
        try await Task.sleep(for: .milliseconds(100))
        #expect(health.changesAreUnsaved)

        context.insert(Exercise(exerciseName: "Saved Lift", exerciseEquipment: .barbell, primaryMuscleFocus: .back))
        try context.save()
        for _ in 0..<50 where health.changesAreUnsaved {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!health.changesAreUnsaved)
    }
}
