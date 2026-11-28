//
//  OwnedWeightsTests.swift
//  PowerJackTests
//
//  Only These Weights: the load grid as a list of owned weights, the saved setting, the Hypertrophy
//  big-jump rule, planners snapping onto the list, and the watch's Digital Crown stepping through it.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct OwnedWeightsTests {
    private let container = PowerJackSeed.makeInMemoryContainer()
    private let kettlebells = LoadGrid(unit: .kilograms, owned: [32, 16, 24])

    // MARK: Load grid

    @Test("A list of kettlebells rounds to the nearest one, ties down, and never off the list")
    func listNearestAndDown() {
        #expect(kettlebells.minimumKilograms == 16)
        #expect(kettlebells.maximumKilograms == 32)
        #expect(kettlebells.nearest(20) == 16)
        #expect(kettlebells.nearest(20.1) == 24)
        #expect(kettlebells.nearest(4) == 16)
        #expect(kettlebells.nearest(50) == 32)
        #expect(kettlebells.down(23.9) == 16)
        #expect(kettlebells.down(24) == 24)
        // Nothing lighter is owned, so the lightest.
        #expect(kettlebells.down(10) == 16)
        #expect(kettlebells.share(30) == 24)
        #expect(kettlebells.up(16.5) == 24)
        #expect(kettlebells.up(33) == nil)
    }

    @Test("A step on a list is the next weight on it, and stops at both ends")
    func listMoved() {
        #expect(kettlebells.moved(24, bySteps: 1) == 32)
        #expect(kettlebells.moved(23, bySteps: -1) == 16)
        #expect(kettlebells.moved(32, bySteps: 1) == 32)
        #expect(kettlebells.moved(16, bySteps: -2) == 16)
        #expect(kettlebells.stepKilograms(above: 16) == 8)
        #expect(kettlebells.stepKilograms(above: 32) == 0)
    }

    @Test("A list is coarse where the next weight is over 7.5% heavier, and on the heaviest weight")
    func listCoarse() {
        #expect(kettlebells.isCoarse(at: 16))
        #expect(kettlebells.isCoarse(at: 32))

        let plates = LoadGrid(unit: .pounds, owned: [200, 205, 225])
        #expect(!plates.isCoarse(at: pounds(200)))
        #expect(plates.isCoarse(at: pounds(205)))
        #expect(abs(plates.nearest(pounds(202.5)) - pounds(200)) < 0.001)
        #expect(abs(plates.down(pounds(224)) - pounds(205)) < 0.001)
    }

    @Test("Owned weights are cleaned up: sorted, no repeats, nothing at or under 0 or past what a set can log")
    func listCleanup() {
        let grid = LoadGrid(unit: .pounds, owned: [50, 0, -5, 25, 25, 1_200])
        #expect(grid.owned?.map { ($0 / WeightUnit.kilogramsPerPound).rounded() } == [25, 50])
        #expect(OwnedLoads.decode("35, 20,abc,20,0", in: .kilograms) == [20, 35])
    }

    @Test("Loadable bodyweight on a list can still go back to no added weight")
    func listStartsAtZero() {
        let belt = LoadGrid(unit: .pounds, owned: [10, 25], startsAtZero: true)
        #expect(belt.minimumKilograms == 0)
        #expect(belt.down(pounds(5)) == 0)
        #expect(belt.moved(0, bySteps: 1) == pounds(10))
    }

    @Test("The equipment's grid is the owned list when one is picked, else its even steps")
    func gridFromSettings() throws {
        OwnedLoads.$pinned.withValue([.kettlebell: [24, 16]]) {
            let bells = LoadGrid(equipment: .kettlebell, unit: .kilograms)
            #expect(bells?.owned == [16, 24])
            #expect(LoadGrid(equipment: .barbell, unit: .kilograms)?.owned == nil)
            #expect(LoadGrid(equipment: .bodyweight, unit: .kilograms) == nil)
        }
        // Only These Weights with nothing listed yet stays on even steps.
        OwnedLoads.$pinned.withValue([.kettlebell: []]) {
            #expect(LoadGrid(equipment: .kettlebell, unit: .kilograms)?.owned == nil)
            #expect(LoadGrid(equipment: .kettlebell, unit: .kilograms)?.step == 4)
        }
    }

    @Test("The setting saves per equipment and unit, reads back sorted, and goes back to even steps")
    func settingsRoundTrip() {
        let defaults = UserDefaults.standard
        let keys = [
            OwnedLoads.modeKey(for: .kettlebell, in: .kilograms),
            OwnedLoads.weightsKey(for: .kettlebell, in: .kilograms),
            OwnedLoads.modeKey(for: .kettlebell, in: .pounds),
        ]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        for key in keys { defaults.removeObject(forKey: key) }

        // Stored under the settings prefix, so the watch gets it, as plain strings.
        #expect(keys[0] == "settings.strength.loadMode.kg.kettlebell")
        #expect(keys[1] == "settings.strength.ownedLoads.kg.kettlebell")
        #expect(OwnedLoads.mode(for: .kettlebell, in: .kilograms) == .evenSteps)

        defaults.set(LoadMode.ownedWeights.rawValue, forKey: keys[0])
        defaults.set(OwnedLoads.encode([32, 16, 24]), forKey: keys[1])
        #expect(OwnedLoads.mode(for: .kettlebell, in: .kilograms) == .ownedWeights)
        #expect(OwnedLoads.active(for: .kettlebell, in: .kilograms) == [16, 24, 32])
        #expect(LoadGrid(equipment: .kettlebell, unit: .kilograms)?.owned == [16, 24, 32])
        // Pounds keep their own choice.
        #expect(OwnedLoads.active(for: .kettlebell, in: .pounds) == nil)

        defaults.set(LoadMode.evenSteps.rawValue, forKey: keys[0])
        #expect(OwnedLoads.active(for: .kettlebell, in: .kilograms) == nil)
        // The list is kept for when Only These Weights is picked again.
        #expect(OwnedLoads.weights(for: .kettlebell, in: .kilograms) == [16, 24, 32])
    }

    // MARK: Hypertrophy

    /// 45s and 25s on the bar: past 225 lb the smallest jump is a 25 on each side, 50 lb.
    private let plates = LoadGrid(unit: .pounds, owned: [135, 185, 225, 275, 315])

    @Test("225 × 15 with 25 lb plates jumps to 275 at the reps that match its estimated max")
    func bigJumpMatchesReps() {
        let result = next([(15, 2250), (15, 2250)], range: 5...15, grid: plates)
        #expect(result.gate == .load)
        #expect(result.sets == [set(7, 2750), set(7, 2750)])

        // Even steps of 25 lb go to 250 instead, still more than 7.5%: 225 × 15 matches about 250 × 11.
        let even = next([(15, 2250)], range: 5...15, grid: LoadGrid(unit: .pounds, step: 25, isBarbell: false))
        #expect(even.sets == [set(11, 2500)])
    }

    @Test("When the matched reps fall under the range, reps keep rising, then the jump plans the bottom of the range")
    func bigJumpWaitsForTopOfRange() {
        let waiting = next([(12, 2250), (12, 2250)], range: 8...15, grid: plates)
        #expect(waiting.gate == .reps)
        #expect(waiting.sets.allSatisfy { $0.plannedWeightTenthsPounds == 2250 })
        #expect(waiting.sets.map(\.plannedReps) == [13, 12])

        let jump = next([(15, 2250), (15, 2250)], range: 8...15, grid: plates)
        #expect(jump.gate == .load)
        #expect(jump.sets == [set(8, 2750), set(8, 2750)])
    }

    @Test("A jump of 7.5% or less keeps the reps, as before")
    func smallJumpKeepsReps() {
        let bar = LoadGrid(unit: .pounds, step: 5, isBarbell: true)
        let result = next([(11, 1350), (11, 1350)], range: 6...12, grid: bar)
        #expect(result.gate == .load)
        #expect(result.sets == [set(11, 1400), set(11, 1400)])
        // Without a grid, exactly 5 lb, as before.
        #expect(next([(11, 1350), (11, 1350)], range: 6...12, grid: nil).sets == result.sets)
        // A weight typed off the grid moves onto it.
        #expect(next([(11, 1375)], range: 6...12, grid: bar).sets == [set(11, 1450)])
    }

    @Test("Owned 16, 24 and 32 kg kettlebells: wait at 16, jump at the top of the range, then reps at 32")
    func ownedKettlebells() {
        let bells = LoadGrid(unit: .kilograms, owned: [16, 24, 32])
        let sixteen = WeightUnit.tenthsPounds(fromKilograms: 16)
        let twentyFour = WeightUnit.tenthsPounds(fromKilograms: 24)
        let thirtyTwo = WeightUnit.tenthsPounds(fromKilograms: 32)

        let waiting = next([(12, sixteen)], range: 8...15, grid: bells)
        #expect(waiting.sets == [set(13, sixteen)])

        let jump = next([(15, sixteen)], range: 8...15, grid: bells)
        #expect(jump.sets == [set(8, twentyFour)])

        // The heaviest kettlebell can only add reps, up to the top of the range.
        #expect(next([(12, thirtyTwo)], range: 8...15, grid: bells).sets == [set(13, thirtyTwo)])
        let top = next([(15, thirtyTwo)], range: 8...15, grid: bells)
        #expect(top.gate == .reps)
        #expect(top.sets == [set(15, thirtyTwo)])
    }

    @Test("Loadable bodyweight at 0 takes its first step at the same reps")
    func loadableBodyweightFromZero() {
        let belt = LoadGrid(unit: .pounds, step: 5, isBarbell: false, startsAtZero: true)
        let result = next([(11, 0)], range: 6...12, grid: belt, addsToBodyweight: true)
        #expect(result.sets == [set(11, 50)])
    }

    // MARK: Strength and PowerJack

    @Test("Strengthen plans the next week onto owned barbells: top set to the nearest, back-offs and warm-ups down")
    func strengthSnapsToOwnedBarbells() throws {
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        try WeightUnit.$pinned.withValue(.pounds) {
            try OwnedLoads.$pinned.withValue([.barbell: [135, 185, 225, 275, 315, 365]]) {
                let program = try makeStrengthProgram(in: context)
                let week = try #require(program.nextWorkout.flatMap { program.programWeek(containing: $0) })
                while let workout = program.nextWorkout, program.programWeek(containing: workout) === week {
                    program.prepareToStart(workout)
                    workout.startAndCascade()
                    for workoutExercise in workout.workoutExercises {
                        for set in workoutExercise.workingSets {
                            set.weightTenthsPounds = 3000
                            set.reps = set.repsPlanned ?? 5
                            workoutExercise.completeSet(set)
                        }
                        workoutExercise.addFeedback(feedback: ExerciseFeedback(repsInReserve: .three, levelOfPain: LevelOfPain.none))
                    }
                    program.finishWorkout(workout)
                    try context.save()
                }

                let owned: Set<Int> = [1350, 1850, 2250, 2750, 3150, 3650]
                let workout = try #require(program.programWeeks[1].workouts.first { $0.order == 0 })
                let squat = try #require(workout.workoutExercises.first { $0.exercise?.catalogID == "barbell-back-squat" })
                let working = squat.workingSets.compactMap(\.weightTenthsPlannedPounds)
                let warmups = squat.warmupSets.compactMap(\.weightTenthsPlannedPounds)
                #expect(!working.isEmpty)
                #expect(Set(working + warmups).isSubset(of: owned), "\(working) \(warmups)")
                // 333.9 lb planned goes to 315, back-offs at 90% (283.5) down to 275, and warm-ups at
                // 50/70/85% down to 135, 185 and 225.
                #expect(working == [3150, 2750, 2750, 2750])
                #expect(warmups == [1350, 1850, 2250])
            }
        }
    }

    @Test("PowerJack loads move onto owned weights; duplicate warm-ups are dropped")
    func powerJackSnaps() {
        let exercise = PowerJackExercise(id: "bells", multiJoint: true, repsOnly: false, fatigue: .moderate, primary: .shoulders)
        var entry = PowerJackEntryPlan(
            exercise: exercise,
            role: PowerJackSlotRole(role: .accessory),
            sets: [PowerJackSetPlan(reps: 8, load: 44), PowerJackSetPlan(reps: 8, load: 44)]
        )
        entry.warmups = [PowerJackSetPlan(reps: 5, load: 22), PowerJackSetPlan(reps: 3, load: 30), PowerJackSetPlan(reps: 1, load: 40)]
        let snapped = WeightUnit.$pinned.withValue(.pounds) {
            OwnedLoads.$pinned.withValue([.kettlebell: [20, 35, 45, 55]]) {
                PowerJackPlanner.snappedToOwnedWeights(entry, deload: false, equipment: .kettlebell)
            }
        }
        #expect(snapped.sets.map(\.load) == [45, 45])
        // 22 and 30 both round down to 20, and 40 to 35.
        #expect(snapped.warmups.map(\.load) == [20, 35])

        let even = WeightUnit.$pinned.withValue(.pounds) {
            PowerJackPlanner.snappedToOwnedWeights(entry, deload: false, equipment: .kettlebell)
        }
        #expect(even == entry)
    }

    // MARK: Watch

    @Test("With owned weights, each click of the Digital Crown is the next owned weight")
    func crownStepsThroughOwnedWeights() throws {
        try OwnedLoads.$pinned.withValue([.dumbbell: [20, 25, 35, 50]]) {
            let workoutExercise = try makeStartedExercise(equipment: .dumbbell)
            let workoutSet = try #require(workoutExercise.workingSets.first)
            workoutSet.weightTenthsPounds = 250
            var entry = SetEntry(for: workoutSet, unit: .pounds)
            #expect(entry.maxWeightSteps == 4)
            #expect(entry.weightSteps == 2)

            entry.weightSteps += 1
            #expect(entry.weight == 35)
            entry.weightSteps += 1
            #expect(entry.weight == 50)
            entry.weightSteps -= 3
            #expect(entry.weight == 20)

            // A weight typed off the list steps to its neighbours.
            workoutSet.weightTenthsPounds = 300
            entry = SetEntry(for: workoutSet, unit: .pounds)
            entry.weightSteps += 1
            #expect(entry.weight == 35)
        }
    }

    // MARK: Helpers

    private func next(
        _ sets: [(reps: Int, weight: Int)],
        range: ClosedRange<Int>,
        grid: LoadGrid?,
        addsToBodyweight: Bool = false
    ) -> Prescription {
        let exercise = ProgressionExerciseInfo(
            minReps: range.lowerBound,
            maxReps: range.upperBound,
            primaryMuscle: .chest,
            secondaryMuscles: [],
            repsOnly: false,
            addsToBodyweight: addsToBodyweight,
            loadGrid: grid
        )
        let history = ProgressionHistory(
            programWeek: 1,
            status: .complete,
            pain: LevelOfPain.none,
            // Hard enough that no set is added on top.
            effort: .veryHard,
            sets: sets.map {
                ProgressionSet(plannedReps: nil, plannedWeightTenthsPounds: nil, actualReps: $0.reps, actualWeightTenthsPounds: $0.weight, status: .complete)
            }
        )
        return ProgressionEngine.nextPrescription(ProgressionInput(
            current: history,
            previous: nil,
            exercise: exercise,
            focusMuscles: [],
            currentWeekMuscleSetCredits: [:]
        ))
    }

    private func set(_ reps: Int, _ weight: Int) -> SetPrescription {
        SetPrescription(plannedReps: reps, plannedWeightTenthsPounds: weight)
    }

    private func pounds(_ value: Double) -> Double { value * WeightUnit.kilogramsPerPound }

    /// Day 1: squat, bench. Day 2: squat, front squat, curl.
    private func makeStrengthProgram(in context: ModelContext) throws -> Program {
        func exercise(_ id: String) throws -> Exercise {
            try #require(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.catalogID == id })).first)
        }
        let template = TemplateProgram(templateName: "Strong", workoutsPerWeek: 2, templateMuscleFocus: [.quads], templateType: .strength)
        let dayOne = template.addTemplateWorkout()
        for id in ["barbell-back-squat", "barbell-bench-press"] {
            dayOne.addTemplateExercise(exercise: try exercise(id))
        }
        let dayTwo = template.addTemplateWorkout()
        for id in ["barbell-back-squat", "barbell-front-squat", "dumbbell-curl"] {
            dayTwo.addTemplateExercise(exercise: try exercise(id))
        }
        context.insert(template)
        let program = Program(programLengthWeeks: 4, templateProgram: template)
        try context.insertAndSave(program)
        program.start()
        return program
    }

    private func makeStartedExercise(equipment: Equipment) throws -> WorkoutExercise {
        let exercise = Exercise(exerciseName: "Lift", exerciseEquipment: equipment, primaryMuscleFocus: .chest, minReps: 6, maxReps: 12)
        let workout = Workout(order: 0)
        container.mainContext.insert(exercise)
        container.mainContext.insert(workout)
        let workoutExercise = try #require(workout.addWorkoutExercise(exercise: exercise))
        _ = workoutExercise.addSet()
        workout.startAndCascade()
        return workoutExercise
    }
}
