//
//  LoadableBodyweightTests.swift
//  PowerJackTests
//
//  Weighted pull-ups and dips: a weight of 0 is bodyweight alone, shown as "BW", and every
//  progression can add weight from there. The lifter's own copies move onto the built-in ones.
//

import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import PowerJack

@MainActor
@Suite(.serialized)
struct LoadableBodyweightTests {
    /// Held by the suite instance so models stay valid for the whole test.
    private let container = PowerJackSeed.makeInMemoryContainer()

    init() {
        UserDefaults.standard.set(WeightUnit.pounds.rawValue, forKey: AppSettings.Key.weightUnit)
    }

    // MARK: Equipment

    @Test("Weighted Pull-Ups and Weighted Dips are built in as Loadable Bodyweight")
    func catalogEntries() throws {
        let pullUp = try #require(ExerciseCatalog.entries.first { $0.id == "weighted-pull-up" })
        let dip = try #require(ExerciseCatalog.entries.first { $0.id == "weighted-dip" })
        #expect(pullUp.name == "Weighted Pull-Ups" && dip.name == "Weighted Dips")
        for entry in [pullUp, dip] {
            let exercise = entry.makeExercise()
            #expect(exercise.equipment == .loadableBodyweight)
            #expect(exercise.addsToBodyweight && !exercise.repsOnly)
        }
        #expect(Equipment.loadableBodyweight.displayName == "Loadable Bodyweight")
        #expect(Equipment.legPress.displayName == "Leg Press")
    }

    @Test("Loadable bodyweight is stored as bodyweight, so older versions and watches can still read it")
    func storedForOlderVersions() throws {
        let exercise = Exercise(exerciseName: "Own Dip", exerciseEquipment: .loadableBodyweight, primaryMuscleFocus: .chest, userCreated: true)
        exercise.assignSyncID()
        let state = try #require(exercise.syncState)
        #expect(state.equipment == .bodyweight && state.addsToBodyweight == true)
        #expect(Exercise(snapshot: state).equipment == .loadableBodyweight)

        // An older iPhone's snapshot has no flag: plain bodyweight.
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        old["addsToBodyweight"] = nil
        let oldState = try JSONDecoder().decode(ExerciseState.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(Exercise(snapshot: oldState).equipment == .bodyweight)

        // Changing the equipment clears the flag.
        exercise.equipment = .barbell
        #expect(exercise.equipment == .barbell && !exercise.addsToBodyweight)
        exercise.equipment = .bodyweight
        #expect(exercise.equipment == .bodyweight && exercise.repsOnly)
    }

    @Test("The equipment survives a save and a fresh read")
    func persists() throws {
        let exercise = Exercise(exerciseName: "Own Dip", exerciseEquipment: .loadableBodyweight, primaryMuscleFocus: .chest, userCreated: true)
        container.mainContext.insert(exercise)
        try container.mainContext.save()

        let fresh = ModelContext(container)
        let read = try #require(try fresh.fetch(FetchDescriptor<Exercise>()).first { $0.exerciseName == "Own Dip" })
        #expect(read.equipment == .loadableBodyweight)
    }

    // MARK: Logging 0

    @Test("A weight of 0 is kept only for loadable bodyweight, and a set with no target starts there")
    func zeroWeight() throws {
        let loadable = try makeWorkout(.loadableBodyweight, sets: [(8, nil), (8, 250)]).sets
        #expect(loadable[0].weightTenthsPounds == 0)
        #expect(loadable[1].weightTenthsPounds == 250)
        loadable[1].weightTenthsPounds = 0
        #expect(loadable[1].weightTenthsPounds == 0)

        let barbell = try makeWorkout(.barbell, sets: [(8, nil)]).sets
        #expect(barbell[0].weightTenthsPounds == nil)
        barbell[0].weightTenthsPounds = 0
        #expect(barbell[0].weightTenthsPounds == nil)
    }

    @Test("Typing 0 logs bodyweight, and a typed weight replaces the 0")
    func typedZero() async throws {
        let workoutSet = try makeWorkout(.loadableBodyweight, sets: [(8, 250)]).sets[0]
        let screen = try await HostedView(SetHost(workoutSet: workoutSet).modelContainer(container))
        defer { screen.close() }

        #expect(await screen.type("0", into: "Set 1 weight"))
        #expect(workoutSet.weightTenthsPounds == 0)
        await screen.tap("Set 1 complete")
        #expect(workoutSet.status == .complete)
        #expect(workoutSet.weightTenthsPounds == 0)

        #expect(WorkoutSetView.weightInput("02", previous: "0") == "2")
        #expect(WorkoutSetView.weightInput("0.5", previous: "0.") == "0.5")
        #expect(WorkoutSetView.weightInput("00", previous: "0") == "0")
    }

    @Test("The Live Activity and rest timer say BW for bodyweight alone, and the voice leaves it out")
    func shownAsBodyweight() throws {
        try WeightUnit.$pinned.withValue(.pounds) {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let (workout, sets, _) = try makeWorkout(.loadableBodyweight, sets: [(8, 0), (8, 0)])
            let state = try #require(workout.activityState())
            #expect(state.sets[0].weightText(repsOnly: state.repsOnly) == "BW")
            #expect(state.canCompleteAtTarget)

            #expect(sets[0].completeAsEntered(repsOnly: false, at: start))
            #expect(sets[0].weightTenthsPounds == 0)
            let rest = try #require(workout.currentRest)
            #expect(rest.prescriptionText == "8 reps × BW")
            #expect(workout.restCallout?.phrase.text == "Start set. 8 reps.")
        }
    }

    @Test("The watch logs bodyweight alone, and shows it as BW")
    func watchEntry() throws {
        let workoutExercise = try makeWorkout(.loadableBodyweight, sets: [(8, nil), (8, nil)]).workoutExercise
        let first = try #require(workoutExercise.workingSets.first)
        var entry = SetEntry(for: first, unit: .pounds)
        #expect(entry.weight == 0 && entry.weightText == "BW" && entry.weightTenthsPounds == 0)

        workoutExercise.log(entry, on: first)
        #expect(first.status == .complete && first.weightTenthsPounds == 0)

        let second = try #require(workoutExercise.workingSets.last)
        entry = SetEntry(for: second, unit: .pounds)
        entry.weight = 25
        #expect(entry.weightText == "25")
        workoutExercise.log(entry, on: second)
        #expect(second.weightTenthsPounds == 250)
    }

    // MARK: Progression

    @Test("Build adds weight once bodyweight sets reach the top of the range")
    func buildAddsWeight() {
        let atTop = ProgressionSet(plannedReps: 12, plannedWeightTenthsPounds: 0, actualReps: 12, actualWeightTenthsPounds: 0, status: .complete)
        let input = ProgressionInput(
            current: ProgressionHistory(programWeek: 3, status: .complete, pain: LevelOfPain.none, effort: .challenge, sets: [atTop, atTop]),
            previous: nil,
            twoWeeksAgo: nil,
            exercise: ProgressionExerciseInfo(minReps: 5, maxReps: 12, primaryMuscle: .back, secondaryMuscles: [], repsOnly: false, addsToBodyweight: true),
            focusMuscles: [],
            programLengthWeeks: 6,
            currentWeekMuscleSetCredits: [:]
        )
        let prescription = ProgressionEngine.nextPrescription(input)
        #expect(prescription.gate == .load)
        #expect(prescription.sets.map(\.plannedWeightTenthsPounds) == [50, 50])

        // Short of the top: one more rep, still at bodyweight.
        var short = input
        short.current.sets = Array(repeating: ProgressionSet(plannedReps: 8, plannedWeightTenthsPounds: 0, actualReps: 8, actualWeightTenthsPounds: 0, status: .complete), count: 2)
        let reps = ProgressionEngine.nextPrescription(short)
        #expect(reps.gate == .reps)
        #expect(reps.sets.map(\.plannedWeightTenthsPounds) == [0, 0])
        #expect(reps.sets.map(\.plannedReps) == [9, 9])
    }

    @Test("Strengthen's load steps start at no added weight")
    func strengthGrid() throws {
        let grid = try #require(LoadGrid(equipment: .loadableBodyweight, unit: .pounds))
        #expect(grid.nearest(0) == 0)
        #expect(abs(grid.moved(0, bySteps: 1) - 5 * WeightUnit.kilogramsPerPound) < 1e-9)
        #expect(grid.moved(0, bySteps: -1) == 0)
        #expect(StrengthLoadSteps.defaultStep(for: .loadableBodyweight, in: .kilograms) == 2.5)

        let exercise = Exercise(exerciseName: "Own Dip", exerciseEquipment: .loadableBodyweight, primaryMuscleFocus: .chest, secondaryMuscles: [.triceps, .shoulders])
        #expect(!StrengthLifts.isCompound(exercise))
    }

    @Test("PowerJack keeps loadable bodyweight off main lifts")
    func powerJackRoles() throws {
        let dip = try #require(ExerciseCatalog.entries.first { $0.id == "weighted-dip" }).makeExercise()
        let exercise = PowerJackPlanner.exercise(dip)
        #expect(exercise.addsToBodyweight && exercise.pattern == .verticalPush)
        #expect(!exercise.isMainLiftEligible)
    }

    // MARK: Moving the lifter's own copies

    @Test("The lifter's own Weighted Pull-ups becomes the built-in one, keeping its templates, programs and logs")
    func adoptsOwnCopy() throws {
        let context = container.mainContext
        let own = Exercise(exerciseName: "weighted pullups", exerciseEquipment: .bodyweight, primaryMuscleFocus: .biceps, userCreated: true, minReps: 6, maxReps: 10)
        own.customRestTime = 150
        own.assignSyncID()
        let notIt = Exercise(exerciseName: "Weighted Pull-Up Negatives", exerciseEquipment: .bodyweight, primaryMuscleFocus: .back, userCreated: true)
        context.insert(own)
        context.insert(notIt)
        let template = TemplateExercise(exercise: own, order: 0)
        context.insert(template)
        let (workout, sets) = try makeWorkout(own, sets: [(8, nil)])
        sets[0].reps = 8
        sets[0].complete()
        try context.save()
        let ownID = own.persistentModelID

        try ExerciseCatalog.seed(in: context)

        let pullUps = try context.fetch(FetchDescriptor<Exercise>()).filter { $0.catalogID == "weighted-pull-up" }
        #expect(pullUps.count == 1)
        #expect(pullUps.first?.persistentModelID == ownID)
        #expect(own.exerciseName == "Weighted Pull-Ups" && !own.userCreated)
        #expect(own.equipment == .loadableBodyweight && own.primaryMuscleFocus == .back)
        #expect(own.repRange == 6...10 && own.customRestTime == 150)
        #expect(template.exercise === own)
        #expect(workout.workoutExercises.first?.exercise === own)
        #expect(sets[0].status == .complete && sets[0].reps == 8)
        #expect(notIt.catalogID == nil && notIt.userCreated)

        // Seeding again changes nothing.
        try ExerciseCatalog.seed(in: context)
        #expect(try context.fetch(FetchDescriptor<Exercise>()).filter { $0.catalogID == "weighted-pull-up" }.count == 1)
    }

    @Test("An own copy iCloud brings in after the catalog was seeded merges into the built-in one")
    func adoptsLaterImport() throws {
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        #expect(try context.fetch(FetchDescriptor<Exercise>()).contains { $0.catalogID == "weighted-dip" })

        // An older device's own exercise, made long before, with a workout logged on it.
        let imported = Exercise(exerciseName: "Weighted Dips", exerciseEquipment: .dumbbell, primaryMuscleFocus: .triceps, userCreated: true)
        imported.createdAtValue = Date(timeIntervalSinceReferenceDate: 700_000_000)
        context.insert(imported)
        let (workout, sets) = try makeWorkout(imported, sets: [(10, 250)])
        sets[0].complete()
        try context.save()

        // What the store runs after every iCloud import.
        #expect(try ExerciseCatalog.removeDuplicates(in: context))
        try context.save()

        let dips = try context.fetch(FetchDescriptor<Exercise>()).filter { $0.catalogID == "weighted-dip" }
        #expect(dips.count == 1)
        #expect(dips.first === imported)
        #expect(imported.equipment == .loadableBodyweight && imported.exerciseName == "Weighted Dips")
        #expect(workout.workoutExercises.first?.exercise === imported)
        #expect(sets[0].weightTenthsPounds == 250)
    }

    @Test("Name variants the lifter might have typed are matched", arguments: [
        ("Weighted Pull-Ups", "weighted-pull-up"), ("Weighted Pull-ups", "weighted-pull-up"), ("weighted pullup", "weighted-pull-up"),
        ("Weight Pull-Ups", "weighted-pull-up"), ("WEIGHTED PULL UPS", "weighted-pull-up"),
        ("Weighted Dips", "weighted-dip"), ("weighted dip", "weighted-dip"), ("Weight Dips", "weighted-dip"),
    ])
    func nameVariants(name: String, id: String) {
        let match = ExerciseCatalog.replacedOwnNames.first { $0.value.contains(ExerciseCatalog.matchingName(name)) }?.key
        #expect(match == id)
    }

    // MARK: Helpers

    private func makeWorkout(
        _ equipment: Equipment,
        sets: [(reps: Int, weightTenthsPounds: Int?)]
    ) throws -> (workout: Workout, sets: [WorkoutSet], workoutExercise: WorkoutExercise) {
        let exercise = Exercise(exerciseName: "Lift", exerciseEquipment: equipment, primaryMuscleFocus: .back, minReps: 5, maxReps: 12)
        container.mainContext.insert(exercise)
        let (workout, workoutSets) = try makeWorkout(exercise, sets: sets)
        return (workout, workoutSets, try #require(workout.workoutExercises.first))
    }

    private func makeWorkout(
        _ exercise: Exercise,
        sets: [(reps: Int, weightTenthsPounds: Int?)]
    ) throws -> (Workout, [WorkoutSet]) {
        let workout = Workout(order: 0)
        let workoutExercise = try #require(workout.addWorkoutExercise(exercise: exercise))
        for set in sets {
            _ = workoutExercise.addSet(plannedReps: set.reps, plannedWeightTenthsPounds: set.weightTenthsPounds)
        }
        container.mainContext.insert(workout)
        workout.startAndCascade()
        return (workout, workoutExercise.workoutSets)
    }
}

private struct SetHost: View {
    let workoutSet: WorkoutSet
    @FocusState private var focusedSetField: FocusedSetField?

    var body: some View {
        WorkoutSetView(focusedSetField: $focusedSetField, workoutSet: workoutSet)
    }
}
