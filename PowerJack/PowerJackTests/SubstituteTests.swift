//
//  SubstituteTests.swift
//  PowerJackTests
//
//  One-Time Substitute: swapping an exercise for one workout, the substitute's weights, Undo, what later
//  weeks and the watch see, and every engine progressing the planned exercise as if it was done to plan.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct SubstituteTests {
    private let container = PowerJackSeed.makeInMemoryContainer()
    private var context: ModelContext { container.mainContext }

    init() throws {
        UserDefaults.standard.set(WeightUnit.pounds.rawValue, forKey: AppSettings.Key.weightUnit)
        try ExerciseCatalog.seed(in: container.mainContext)
    }

    // MARK: Swapping

    @Test("A substitute shows in place of the planned exercise, which stays the row's exercise")
    func substituteIsShown() throws {
        let bench = try startedBench(plannedPounds: 185)
        let dumbbell = try exercise("dumbbell-bench-press")

        bench.substitute(with: dumbbell)

        #expect(bench.exercise?.catalogID == "barbell-bench-press")
        #expect(bench.substitute === dumbbell)
        #expect(bench.shownExercise === dumbbell)
        // No history for dumbbell press: its weights start blank, reps keep the plan.
        #expect(bench.workingSets.map(\.weightTenthsPounds) == [nil, nil])
        #expect(bench.workingSets.map(\.weightTenthsPlannedPounds) == [nil, nil])
        #expect(bench.workingSets.map(\.reps) == [8, 8])
        #expect(bench.workingSets.map(\.originalPlannedWeightTenthsPounds) == [1850, 1850])
    }

    @Test("Undo Substitute brings back the planned exercise and its planned weights")
    func undoRestoresPlan() throws {
        let bench = try startedBench(plannedPounds: 185)
        bench.substitute(with: try exercise("dumbbell-bench-press"))
        bench.workingSets[0].weightTenthsPounds = 600

        bench.undoSubstitute()

        #expect(bench.substitute == nil)
        #expect(bench.shownExercise === bench.exercise)
        #expect(bench.workingSets.map(\.weightTenthsPounds) == [1850, 1850])
        #expect(bench.workingSets.map(\.weightTenthsPlannedPounds) == [1850, 1850])
        #expect(bench.workingSets.map(\.originalPlannedWeightTenthsPounds) == [nil, nil])
    }

    @Test("Picking a second substitute still keeps the planned exercise's weights for Undo")
    func repickKeepsPlan() throws {
        let bench = try startedBench(plannedPounds: 185)
        bench.substitute(with: try exercise("dumbbell-bench-press"))
        bench.substitute(with: try exercise("cable-chest-fly"))

        #expect(bench.substitute?.catalogID == "cable-chest-fly")
        #expect(bench.workingSets.map(\.originalPlannedWeightTenthsPounds) == [1850, 1850])
        bench.undoSubstitute()
        #expect(bench.workingSets.map(\.weightTenthsPounds) == [1850, 1850])
    }

    @Test("A cross-muscle substitute can be selected and undone")
    func crossMuscleSubstitute() throws {
        let bench = try startedBench(plannedPounds: 185)
        let squat = try exercise("smith-machine-squat")
        bench.substitute(with: squat)
        #expect(bench.shownExercise === squat)
        bench.undoSubstitute()
        #expect(bench.shownExercise === bench.exercise)
        #expect(bench.workingSets.map(\.weightTenthsPounds) == [1850, 1850])
    }

    @Test("Substitute and Undo are offered only until a working set is logged")
    func availability() throws {
        let bench = try startedBench(plannedPounds: 185)
        #expect(bench.canSubstitute)

        // A logged warmup still allows it.
        let warmup = bench.addWarmupSet()
        if let warmup { bench.completeSet(warmup) }
        #expect(bench.canSubstitute)

        bench.substitute(with: try exercise("dumbbell-bench-press"))
        bench.completeSet(bench.workingSets[0])
        #expect(!bench.canSubstitute)
        bench.undoSubstitute()
        #expect(bench.substitute != nil)
    }

    @Test("A skipped or upcoming exercise can't be substituted")
    func notOfferedWhenSkippedOrPlanned() throws {
        let program = try makeProgram(type: .hypertrophy)
        let planned = try #require(program.nextWorkout?.workoutExercises.first)
        #expect(!planned.canSubstitute)

        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        planned.skipRemainingSets()
        #expect(!planned.canSubstitute)
    }

    // MARK: Prefill

    @Test("The substitute's weights come from the last time it was done, as itself or as a substitute")
    func prefillFromHistory() throws {
        let dumbbell = try exercise("dumbbell-bench-press")
        // Done as itself a week ago: 50, 55.
        try logRow(of: dumbbell, weights: [500, 550], daysAgo: 7)

        let bench = try startedBench(plannedPounds: 185, sets: 3)
        bench.substitute(with: dumbbell)
        // Matched set by set, the last weight repeating.
        #expect(bench.workingSets.map(\.weightTenthsPounds) == [500, 550, 550])
        #expect(bench.workingSets.map(\.weightTenthsPlannedPounds) == [500, 550, 550])

        // Logged at 60 as the substitute, which is now the most recent.
        bench.workingSets.forEach { $0.weightTenthsPounds = 600; bench.completeSet($0) }
        let nextBench = try startedBench(plannedPounds: 185)
        nextBench.substitute(with: dumbbell)
        #expect(nextBench.workingSets.map(\.weightTenthsPounds) == [600, 600])
    }

    @Test("A loadable bodyweight substitute with no history starts at bodyweight")
    func loadableBodyweightStartsAtZero() throws {
        let bench = try startedBench(plannedPounds: 185)
        bench.substitute(with: try exercise("weighted-dip"))
        #expect(bench.workingSets.map(\.weightTenthsPounds) == [0, 0])
        #expect(bench.workingSets.map(\.weightTenthsPlannedPounds) == [nil, nil])
    }

    @Test("A set added to a substitute reads as the planned exercise's weight, like the set before it")
    func addedSetKeepsPlannedWeight() throws {
        let bench = try startedBench(plannedPounds: 185)
        bench.substitute(with: try exercise("dumbbell-bench-press"))
        let added = try #require(bench.addSet())
        #expect(added.originalPlannedWeightTenthsPounds == 1850)
        bench.undoSubstitute()
        #expect(added.weightTenthsPounds == 1850)
    }

    @Test("Rest follows the substitute's own rest")
    func restUsesSubstitute() throws {
        let bench = try startedBench(plannedPounds: 185)
        let fly = try exercise("cable-chest-fly")
        fly.customRestTime = 45
        bench.substitute(with: fly)
        bench.completeSet(bench.workingSets[0])
        #expect(bench.restDuration == .seconds(45))
    }

    // MARK: Later weeks

    @Test("Next week plans the planned exercise again, with no substitute")
    func nextWeekKeepsOriginal() throws {
        let program = try makeProgram(type: .hypertrophy, workoutsPerWeek: 1)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let bench = try #require(workout.workoutExercises.first)
        bench.substitute(with: try exercise("dumbbell-bench-press"))
        logToPlan(workout, substituteWeight: 500)
        program.finishWorkout(workout)

        let nextBench = try #require(program.nextWorkout?.workoutExercises.first)
        #expect(nextBench.exercise?.catalogID == "barbell-bench-press")
        #expect(nextBench.substitute == nil)
        #expect(nextBench.workingSets.allSatisfy { $0.originalPlannedWeightTenthsPounds == nil })
    }

    @Test("Volume counts what was actually done; the history export names the substitute")
    func displaysShowSubstitute() throws {
        let bench = try startedBench(plannedPounds: 185)
        let fly = try exercise("cable-chest-fly")
        bench.substitute(with: fly)
        bench.workingSets.forEach { $0.weightTenthsPounds = 300; bench.completeSet($0) }
        let workout = try #require(bench.workoutValue)

        // The fly works chest and shoulders only, while bench press would add triceps.
        #expect(workout.loggedSetsByMuscle[.triceps] == nil)
        #expect(workout.loggedSetsByMuscle[.shoulders] == 1)
        #expect(workout.activityState()?.exerciseName == nil || workout.activityState()?.exerciseName == fly.exerciseName)
    }

    // MARK: Progression

    /// Week 2 done to plan, and week 2 done as a substitute at weights and reps nothing like the plan,
    /// give the planned exercise the same week 3.
    @Test("Each engine progresses the planned exercise from its plan and the feedback", arguments: TemplateType.allCases)
    func progressionReadsPlan(type: TemplateType) throws {
        let toPlan = try SubstituteRun(type: type, substitutes: false).weekThreeBench()
        let substituted = try SubstituteRun(type: type, substitutes: true).weekThreeBench()
        #expect(substituted == toPlan)
    }

    @Test("Strengthen's in-workout step leaves a substitute's weights alone (6.2)")
    func strengthMissKeepsSubstituteWeights() throws {
        let program = try makeProgram(type: .strength, workoutsPerWeek: 1)
        let workout = try #require(program.nextWorkout)
        program.prepareToStart(workout)
        workout.startAndCascade()
        let bench = try #require(workout.workoutExercises.first)
        bench.substitute(with: try exercise("dumbbell-bench-press"))
        for set in bench.workingSets { set.weightTenthsPounds = 600 }
        let back = try #require(bench.workingSets.dropFirst(max(1, bench.topSets)).first)
        back.reps = 1
        bench.completeSet(back)
        #expect(bench.workingSets.filter { $0.status == .active }.allSatisfy { $0.weightTenthsPounds == 600 })
    }

    // MARK: Sync

    @Test("The watch gets the substitute and the planned weights it holds")
    func syncRoundTrip() throws {
        let devices = try TwoDevices()
        let workout = try #require(try devices.phoneProgram.nextWorkout)
        workout.startAndCascade()
        let phoneRow = workout.workoutExercises[0]
        let original = try #require(phoneRow.exercise)
        let substitute = try #require(try devices.phoneContext.fetch(FetchDescriptor<Exercise>()).first { $0 !== original })
        phoneRow.substitute(with: substitute)
        try devices.phoneContext.save()

        try devices.sendProgram()

        let watchRow = try #require(try devices.watchProgram.nextWorkout?.workoutExercises.first)
        #expect(watchRow.exercise?.syncKey == original.syncKey)
        #expect(watchRow.substitute?.syncKey == substitute.syncKey)
        #expect(watchRow.shownExercise?.exerciseName == substitute.exerciseName)
        #expect(watchRow.workoutSets.map(\.originalPlannedWeightTenthsPounds) == phoneRow.workoutSets.map(\.originalPlannedWeightTenthsPounds))

        // Undo reaches the watch too.
        phoneRow.undoSubstitute()
        try devices.phoneContext.save()
        try devices.sendProgram()
        #expect(watchRow.substitute == nil)
    }

    @Test("State from a version without substitutes still decodes")
    func oldStateDecodes() throws {
        let bench = try startedBench(plannedPounds: 185)
        bench.assignSyncIDs()
        bench.substitute(with: try exercise("dumbbell-bench-press"))
        let state = try #require(bench.syncState)
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        #expect(json["substituteKey"] as? String == "catalog:dumbbell-bench-press")

        json["substituteKey"] = nil
        json["sets"] = (json["sets"] as? [[String: Any]])?.map { $0.filter { $0.key != "originalWeightTenthsPoundsPlanned" } }
        let old = try JSONDecoder().decode(WorkoutExerciseState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.substituteKey == nil)
        #expect(old.sets.allSatisfy { $0.originalWeightTenthsPoundsPlanned == nil })
    }

    // MARK: Helpers

    private func exercise(_ id: String) throws -> Exercise {
        try #require(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.catalogID == id })).first)
    }

    /// A bench press row in a started workout, its working sets planned at `plannedPounds` × 8.
    private func startedBench(plannedPounds: Int, sets: Int = 2) throws -> WorkoutExercise {
        let workout = Workout(order: 0)
        context.insert(workout)
        let bench = try #require(workout.addWorkoutExercise(exercise: try exercise("barbell-bench-press")))
        for _ in 0..<sets {
            bench.addPlannedSet(plannedReps: 8, plannedWeightTenthsPounds: plannedPounds * 10)
        }
        workout.startAndCascade()
        try context.save()
        return bench
    }

    /// A finished row of `exercise` logged at `weights` `daysAgo` days ago.
    private func logRow(of exercise: Exercise, weights: [Int], daysAgo: Double) throws {
        let workout = Workout(order: 0)
        context.insert(workout)
        let row = try #require(workout.addWorkoutExercise(exercise: exercise))
        for _ in weights { row.addPlannedSet(plannedReps: 10, plannedWeightTenthsPounds: nil) }
        workout.startAndCascade()
        for (set, weight) in zip(row.workingSets, weights) {
            set.weightTenthsPounds = weight
            row.completeSet(set, at: .now.addingTimeInterval(-daysAgo * 86_400))
        }
        try context.save()
    }

    private func makeProgram(type: TemplateType, workoutsPerWeek: Int = 1) throws -> Program {
        try SubstituteRun.makeProgram(type: type, in: context, workoutsPerWeek: workoutsPerWeek)
    }

    /// Logs every working set to plan, or at `substituteWeight` on a substitute, with easy, pain-free feedback.
    private func logToPlan(_ workout: Workout, substituteWeight: Int) {
        for row in workout.workoutExercises {
            for set in row.workingSets {
                set.weightTenthsPounds = row.substitute == nil ? set.weightTenthsPlannedPounds ?? 1000 : substituteWeight
                set.reps = set.repsPlanned ?? 8
                row.completeSet(set)
            }
            row.addFeedback(feedback: ExerciseFeedback(repsInReserve: .two, levelOfPain: .none))
        }
    }
}

/// A program of one type in its own store, run for two weeks: week 1 at set weights, week 2 to plan,
/// or week 2's bench press done as a dumbbell press at weights and reps nothing like the plan.
@MainActor
private struct SubstituteRun {
    let container = PowerJackSeed.makeInMemoryContainer()
    let program: Program
    let substitutes: Bool

    init(type: TemplateType, substitutes: Bool) throws {
        UserDefaults.standard.set(WeightUnit.pounds.rawValue, forKey: AppSettings.Key.weightUnit)
        try ExerciseCatalog.seed(in: container.mainContext)
        program = try Self.makeProgram(type: type, in: container.mainContext)
        self.substitutes = substitutes
    }

    /// One workout a week: bench press, then squat.
    static func makeProgram(type: TemplateType, in context: ModelContext, workoutsPerWeek: Int = 1) throws -> Program {
        let template = TemplateProgram(templateName: "Sub", workoutsPerWeek: workoutsPerWeek, templateMuscleFocus: [.chest], templateType: type)
        for _ in 0..<workoutsPerWeek {
            let day = template.addTemplateWorkout()
            for id in ["barbell-bench-press", "barbell-back-squat"] {
                let exercise = try #require(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.catalogID == id })).first)
                day.addTemplateExercise(exercise: exercise)
            }
        }
        context.insert(template)
        let program = Program(programLengthWeeks: 8, templateProgram: template)
        try context.insertAndSave(program)
        program.start()
        return program
    }

    /// Week 3's bench press: each set's planned reps and weight, its aim, its plan code and its lift record.
    func weekThreeBench() throws -> [String] {
        let context = container.mainContext
        // Week 1 has no plan for some engines, so it's logged at fixed weights.
        try finishWorkout { row, set in
            set.weightTenthsPounds = row.exercise?.catalogID == "barbell-bench-press" ? 1350 : 1850
            set.reps = set.repsPlanned ?? 8
        }
        let weekTwo = try #require(program.nextWorkout)
        let plannedBench = try #require(weekTwo.workoutExercises.first)
        try #require(plannedBench.workingSets.allSatisfy { $0.weightTenthsPlannedPounds != nil }, "Week 2 needs a plan to compare against")
        try finishWorkout(substitute: substitutes) { row, set in
            if row.substitute != nil {
                // Short of every plan's reps, so an engine reading them would see a miss.
                set.weightTenthsPounds = 400
                set.reps = 1
            } else {
                set.weightTenthsPounds = set.weightTenthsPlannedPounds
                set.reps = set.repsPlanned
            }
        }
        try context.save()
        let bench = try #require(program.nextWorkout?.workoutExercises.first)
        #expect(program.programWeek(containing: try #require(program.nextWorkout))?.order == 2)
        let plan = bench.workoutSets.map { "\($0.setType.rawValue) \($0.repsPlanned ?? -1)×\($0.weightTenthsPlannedPounds ?? -1)" }
            + ["aim \(bench.rirTarget ?? -1)", "code \(bench.progressionCode ?? "")"]
        // Strengthen also keeps lift records, which hold back a one-week drop before the plan shows it.
        guard let exercise = bench.exercise, let record = StrengthLog.latestState(in: context).lifts[StrengthLifts.key(for: exercise)] else {
            return plan
        }
        return plan + [
            "e1rm \(record.e1rmKg ?? -1)", "suspect \(record.suspectKg ?? -1)", "flagged \(record.flagged)",
            "drop \(record.dropWeeks)", "marks \(record.marks.map(\.bad))",
        ]
    }

    private func finishWorkout(substitute: Bool = false, log: (WorkoutExercise, WorkoutSet) -> Void) throws {
        let workout = try #require(program.nextWorkout)
        program.prepareToStart(workout)
        workout.startAndCascade()
        if substitute, let bench = workout.workoutExercises.first {
            let dumbbell = try #require(try container.mainContext.fetch(
                FetchDescriptor<Exercise>(predicate: #Predicate { $0.catalogID == "dumbbell-bench-press" })
            ).first)
            bench.substitute(with: dumbbell)
        }
        for row in workout.workoutExercises {
            for set in row.workoutSets {
                log(row, set)
                row.completeSet(set)
            }
            if row.topSets > 0 {
                row.rateTopSets(.two)
            }
            row.addFeedback(feedback: ExerciseFeedback(repsInReserve: .two, levelOfPain: .none))
        }
        program.finishWorkout(workout)
    }
}
