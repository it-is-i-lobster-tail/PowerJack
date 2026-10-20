//
//  WatchWorkoutTests.swift
//  PowerJackTests
//
//  The shared logic behind the watch app: dialing in a set, logging it with one tap,
//  following the iPhone's settings, and planning the next week on its own.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct WatchWorkoutTests {
    /// Held by the suite instance so models stay valid for the whole test.
    private let container = PowerJackSeed.makeInMemoryContainer()

    @Test("A set starts on its target weight and reps")
    func entryStartsOnTarget() throws {
        let workoutExercise = try makeStartedExercise(equipment: .dumbbell)
        let workoutSet = try #require(workoutExercise.workingSets.first)
        workoutSet.reps = 8
        workoutSet.weightTenthsPounds = 505

        let entry = SetEntry(for: workoutSet, unit: .pounds)

        #expect(entry.weight == 50.5)
        #expect(entry.reps == 8)
        #expect(entry.weightTenthsPounds == 505)
    }

    @Test("A barbell set with nothing entered starts at the empty bar")
    func entryStartsAtBar() throws {
        let workoutExercise = try makeStartedExercise(equipment: .barbell)
        let workoutSet = try #require(workoutExercise.workingSets.first)

        #expect(SetEntry(for: workoutSet, unit: .pounds).weight == LoadGrid.barPounds)
        #expect(SetEntry(for: workoutSet, unit: .kilograms).weight == LoadGrid.barKilograms)
        #expect(SetEntry(for: workoutSet, unit: .pounds).reps == 6)
    }

    @Test("Each click of the Digital Crown is one load step")
    func crownClicksAreLoadSteps() throws {
        let workoutExercise = try makeStartedExercise(equipment: .dumbbell)
        let workoutSet = try #require(workoutExercise.workingSets.first)
        var entry = SetEntry(for: workoutSet, unit: .pounds)
        #expect(entry.weightStep == 5)

        entry.weightSteps = 9
        #expect(entry.weight == 45)
        entry.weightSteps += 1
        #expect(entry.weight == 50)
        #expect(entry.maxWeightSteps == 200)
    }

    @Test("Logging a set completes it and carries its weight to the later sets")
    func logCarriesWeight() throws {
        let workoutExercise = try makeStartedExercise(equipment: .dumbbell)
        let first = try #require(workoutExercise.workingSets.first)
        var entry = SetEntry(for: first, unit: .pounds)
        entry.weight = 60
        entry.reps = 10

        workoutExercise.log(entry, on: first)

        #expect(first.status == .complete)
        #expect(first.reps == 10)
        #expect(first.weightTenthsPounds == 600)
        #expect(workoutExercise.workingSets.dropFirst().allSatisfy { $0.weightTenthsPounds == 600 })
        #expect(workoutExercise.nextSet === workoutExercise.workingSets[1])
    }

    @Test("A TOP set's weight stays off the BACK sets after it")
    func topSetWeightStaysPut() throws {
        let workoutExercise = try makeStartedExercise(equipment: .barbell)
        workoutExercise.powerJackTopSetsValue = 1
        let top = try #require(workoutExercise.workingSets.first)
        var entry = SetEntry(for: top, unit: .pounds)
        entry.weight = 225

        workoutExercise.log(entry, on: top)

        #expect(top.weightTenthsPounds == 2250)
        #expect(workoutExercise.workingSets[1].weightTenthsPounds == nil)
    }

    @Test("A set needs a weight to be logged, unless it's bodyweight")
    func logNeedsWeight() throws {
        let dumbbell = try makeStartedExercise(equipment: .dumbbell)
        let weighted = try #require(dumbbell.workingSets.first)
        dumbbell.log(SetEntry(for: weighted, unit: .pounds), on: weighted)
        #expect(weighted.status == .active)

        let bodyweight = try makeStartedExercise(equipment: .bodyweight)
        let unweighted = try #require(bodyweight.workingSets.first)
        bodyweight.log(SetEntry(for: unweighted, unit: .pounds), on: unweighted)
        #expect(unweighted.status == .complete)
        #expect(unweighted.weightTenthsPounds == nil)
    }

    @Test("Logging the first working set skips the warmups still to do")
    func firstWorkingSetSkipsWarmups() throws {
        let workoutExercise = try makeStartedExercise(equipment: .dumbbell, warmups: true)
        #expect(workoutExercise.nextSet?.isWarmup == true)
        let first = try #require(workoutExercise.workingSets.first)
        var entry = SetEntry(for: first, unit: .pounds)
        entry.weight = 40

        workoutExercise.log(entry, on: first)

        #expect(workoutExercise.warmupSets.allSatisfy { $0.status == .skipped })
        #expect(workoutExercise.nextSet === workoutExercise.workingSets[1])
    }

    @Test("Each program type plans next week from a week logged on the watch", arguments: TemplateType.allCases)
    func plansNextWeek(type: TemplateType) throws {
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        try TemplateCatalog.seed(in: context)
        let template = try #require(
            try context.fetch(FetchDescriptor<TemplateProgram>())
                .filter { $0.templateType == type }
                .min { $0.templateName < $1.templateName }
        )
        let program = Program(programLengthWeeks: 4, templateProgram: template)
        try context.insertAndSave(program)
        program.start()
        let weekOne = program.programWeeks[0]

        // What the watch does: start, dial in and log every set, answer feedback, finish.
        while let workout = program.nextWorkout, workout.programWeekValue === weekOne {
            program.prepareToStart(workout)
            workout.startAndCascade()
            for workoutExercise in workout.workoutExercises {
                logEverySet(of: workoutExercise)
            }
            workout.skipRemainingSets()
            program.finishWorkout(workout)
        }

        #expect(weekOne.status == .complete)
        let weekTwo = program.programWeeks[1]
        #expect(weekTwo.status == .active)
        #expect(weekTwo.workouts.count == weekOne.workouts.count)
        let exercises = weekTwo.workouts.flatMap(\.workoutExercises)
        #expect(!exercises.isEmpty)
        #expect(exercises.allSatisfy { !$0.workingSets.isEmpty })
        // Next week's weights come from what was logged.
        #expect(exercises.contains { $0.workingSets.contains { $0.weightTenthsPlannedPounds != nil } })
    }

    @Test("The watch takes the iPhone's settings, and drops ones the iPhone no longer has")
    func settingsFollowIPhone() throws {
        let defaults = try #require(UserDefaults(suiteName: "WatchWorkoutTests.\(UUID().uuidString)"))
        defaults.set("stale", forKey: "settings.old")
        defaults.set("kept", forKey: "templates.selectedType")
        let sync = SettingsSync(defaults: defaults)

        sync.apply([
            AppSettings.Key.weightUnit: WeightUnit.kilograms.rawValue,
            RestLength.long.secondsKey: 240,
        ])

        #expect(defaults.string(forKey: AppSettings.Key.weightUnit) == "kg")
        #expect(defaults.integer(forKey: RestLength.long.secondsKey) == 240)
        #expect(defaults.object(forKey: "settings.old") == nil)
        // Only settings are synced; other saved state stays.
        #expect(defaults.string(forKey: "templates.selectedType") == "kept")
        #expect(Set(sync.settings.keys) == [AppSettings.Key.weightUnit, RestLength.long.secondsKey])
    }

    // MARK: Helpers

    /// An exercise in a started workout, with two working sets and no targets yet.
    private func makeStartedExercise(equipment: Equipment, warmups: Bool = false) throws -> WorkoutExercise {
        let exercise = Exercise(exerciseName: "Lift", exerciseEquipment: equipment, primaryMuscleFocus: .chest, minReps: 6, maxReps: 12)
        let workout = Workout(order: 0)
        container.mainContext.insert(exercise)
        container.mainContext.insert(workout)
        let workoutExercise = try #require(workout.addWorkoutExercise(exercise: exercise))
        if warmups {
            workoutExercise.addWarmupSets()
        }
        _ = workoutExercise.addSet()
        _ = workoutExercise.addSet()
        workout.startAndCascade()
        return workoutExercise
    }

    private func logEverySet(of workoutExercise: WorkoutExercise) {
        if workoutExercise.checkInPending {
            workoutExercise.resolveCheckIn(.continue)
        }
        var logged = 0
        while let workoutSet = workoutExercise.nextSet, logged < 20 {
            var entry = SetEntry(for: workoutSet, unit: .pounds)
            if entry.weightTenthsPounds == nil {
                entry.weight = 100
            }
            workoutExercise.log(entry, on: workoutSet)
            logged += 1
        }
        if workoutExercise.needsFeedback {
            if workoutExercise.topSetsNeedRating {
                workoutExercise.rateTopSets(.two)
            }
            workoutExercise.addFeedback(feedback: ExerciseFeedback(repsInReserve: .two, levelOfPain: .none))
        }
        #expect(workoutExercise.isDone)
    }
}
