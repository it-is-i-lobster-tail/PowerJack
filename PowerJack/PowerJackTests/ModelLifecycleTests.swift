//
//  ModelLifecycleTests.swift
//  PowerJackTests
//
//  Guarded status transitions and value rules on the program-side models.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct ModelLifecycleTests {
    /// Held by the suite instance so models stay valid for the whole test.
    private let container = PowerJackSeed.makeInMemoryContainer()

    // MARK: WorkoutSet

    @Test("Planned reps outside 1...30 are dropped when a set is created")
    func setInitDropsInvalidPlannedReps() {
        #expect(WorkoutSet(order: 0, plannedReps: 0, plannedWeightTenthsPounds: nil).repsPlanned == nil)
        #expect(WorkoutSet(order: 0, plannedReps: 31, plannedWeightTenthsPounds: nil).repsPlanned == nil)
        #expect(WorkoutSet(order: 0, plannedReps: 30, plannedWeightTenthsPounds: nil).repsPlanned == 30)
    }

    @Test("Logged values only change while a set is active")
    func setLoggedValuesNeedActiveSet() {
        let set = WorkoutSet(order: 0, plannedReps: 8, plannedWeightTenthsPounds: 1000)

        set.reps = 10
        set.repsPlanned = 9
        set.weightTenthsPounds = 500
        set.weightInPounds = 50
        #expect(set.reps == nil)
        #expect(set.repsPlanned == 8)
        #expect(set.weightTenthsPounds == nil)

        set.start()
        set.reps = 10
        set.repsPlanned = 9
        set.weightTenthsPounds = 500
        #expect(set.reps == 10)
        #expect(set.repsPlanned == 9)
        #expect(set.weightTenthsPounds == 500)

        // Invalid values clear the field instead of being stored.
        set.reps = 0
        set.repsPlanned = 99
        set.weightTenthsPounds = 0
        #expect(set.reps == nil)
        #expect(set.repsPlanned == nil)
        #expect(set.weightTenthsPounds == nil)
    }

    @Test("Weight in pounds round-trips through tenths of a pound")
    func setWeightInPounds() {
        let set = WorkoutSet(order: 0, plannedReps: nil, plannedWeightTenthsPounds: 1355)
        set.start()

        #expect(set.weightInPounds == nil)
        #expect(set.weightInPoundsPlanned == 135.5)

        set.weightInPounds = 102.46
        #expect(set.weightTenthsPounds == 1025)
        #expect(set.weightInPounds == 102.5)

        set.weightInPounds = 0
        #expect(set.weightTenthsPounds == nil)
        set.weightInPounds = 45
        set.weightInPounds = nil
        #expect(set.weightTenthsPounds == nil)

        set.complete()
        set.weightInPounds = 60
        #expect(set.weightTenthsPounds == nil)
    }

    @Test("Planned weight only changes while a set is planned")
    func setPlannedWeight() {
        let set = WorkoutSet(order: 0, plannedReps: nil, plannedWeightTenthsPounds: nil)
        set.weightTenthsPlannedPounds = 1000
        #expect(set.weightTenthsPlannedPounds == 1000)
        set.weightTenthsPlannedPounds = -5
        #expect(set.weightTenthsPlannedPounds == nil)

        set.start()
        set.weightTenthsPlannedPounds = 1200
        #expect(set.weightTenthsPlannedPounds == nil)
    }

    @Test("Planned weight in pounds rounds to tenths and only changes while planned")
    func setPlannedWeightInPounds() {
        let set = WorkoutSet(order: 0, plannedReps: nil, plannedWeightTenthsPounds: nil)
        set.weightInPoundsPlanned = 102.46
        #expect(set.weightTenthsPlannedPounds == 1025)
        #expect(set.weightInPoundsPlanned == 102.5)

        set.weightInPoundsPlanned = 0
        #expect(set.weightInPoundsPlanned == nil)
        set.weightInPoundsPlanned = 100
        set.weightInPoundsPlanned = nil
        #expect(set.weightInPoundsPlanned == nil)

        set.weightInPoundsPlanned = 100
        set.start()
        set.weightInPoundsPlanned = 200
        #expect(set.weightInPoundsPlanned == 100)
    }

    @Test("Completing, locking, skipping and reopening follow the set's guards")
    func setTransitions() {
        let first = Date(timeIntervalSince1970: 1_000)
        let later = Date(timeIntervalSince1970: 2_000)
        let set = WorkoutSet(order: 0, plannedReps: nil, plannedWeightTenthsPounds: nil)

        // A planned set can't be completed.
        set.complete(at: first)
        set.completeAndLock(at: first)
        #expect(set.status == .planned)
        #expect(!set.isDone)

        set.start()
        set.complete(at: first)
        #expect(set.status == .complete)
        #expect(set.isDone)

        // Locking a completed set keeps the time it was really done.
        set.completeAndLock(at: later)
        #expect(set.locked)
        #expect(set.completedAt == first)

        // Locked sets refuse every change.
        set.start()
        set.skip()
        set.complete(at: later)
        #expect(set.status == .complete)
        #expect(set.completedAt == first)
    }

    @Test("Locking an active set completes it now")
    func setCompleteAndLockFromActive() {
        let date = Date(timeIntervalSince1970: 5_000)
        let set = WorkoutSet(order: 0, plannedReps: nil, plannedWeightTenthsPounds: nil)
        set.start()
        set.completeAndLock(at: date)
        #expect(set.status == .complete)
        #expect(set.completedAt == date)
    }

    @Test("Stopping a set skips and locks it")
    func setStop() {
        let set = WorkoutSet(order: 0, plannedReps: nil, plannedWeightTenthsPounds: nil)
        set.stop()
        #expect(set.status == .skipped)
        #expect(set.locked)
        #expect(set.isDone)

        set.skip()
        set.completeAndLock()
        #expect(set.status == .skipped)
    }

    // MARK: WorkoutExercise

    @Test("Set counts reflect each status")
    func exerciseSetCounts() {
        let workoutExercise = makeWorkoutExercise()
        workoutExercise.start()
        let sets = (0..<4).compactMap { _ in workoutExercise.addSet() }
        sets[0].complete()
        sets[1].skip()

        #expect(workoutExercise.totalSets == 4)
        #expect(workoutExercise.getCountCompletedSets() == 1)
        #expect(workoutExercise.getCountSkippedSets() == 1)
        #expect(workoutExercise.getCountActiveSets() == 2)
        #expect(workoutExercise.getCountPlannedSets() == 0)
        #expect(!workoutExercise.allSetsDone())
    }

    @Test("Adding sets copies the last weight and stops at the max")
    func exerciseAddSet() {
        let workoutExercise = makeWorkoutExercise()
        let first = workoutExercise.addSet()
        first?.weightTenthsPounds = 1350
        let second = workoutExercise.addSet()

        #expect(second?.weightTenthsPlannedPounds == 1350)
        #expect(second?.status == .active)
        #expect(second?.order == 1)

        while workoutExercise.addSet() != nil {}
        #expect(workoutExercise.totalSets == WorkoutExercise.maxSets)
        #expect(workoutExercise.addPlannedSet(plannedReps: 8, plannedWeightTenthsPounds: nil) == nil)
    }

    @Test("Planned sets can only be added before the exercise starts")
    func exerciseAddPlannedSet() {
        let workoutExercise = makeWorkoutExercise()
        let planned = workoutExercise.addPlannedSet(plannedReps: 8, plannedWeightTenthsPounds: 900)
        #expect(planned?.status == .planned)
        #expect(planned?.weightTenthsPlannedPounds == 900)

        workoutExercise.start()
        #expect(workoutExercise.addPlannedSet(plannedReps: 8, plannedWeightTenthsPounds: 900) == nil)
    }

    @Test("Exercise transitions refuse invalid states")
    func exerciseTransitions() {
        let workoutExercise = makeWorkoutExercise()

        // Planned can't complete.
        workoutExercise.complete()
        #expect(workoutExercise.status == .planned)

        workoutExercise.start()
        workoutExercise.start()
        #expect(workoutExercise.status == .active)

        workoutExercise.complete()
        #expect(workoutExercise.status == .complete)
        #expect(workoutExercise.locked)

        workoutExercise.stop()
        workoutExercise.skip()
        #expect(workoutExercise.status == .complete)
        #expect(workoutExercise.addSet() == nil)
    }

    @Test("Stopping an exercise stops all of its sets")
    func exerciseStopCascade() {
        let workoutExercise = makeWorkoutExercise()
        _ = workoutExercise.addSet()
        _ = workoutExercise.addSet()
        workoutExercise.start()
        workoutExercise.stopAndCascade()

        #expect(workoutExercise.status == .stopped)
        #expect(workoutExercise.isFinished)
        #expect(workoutExercise.workoutSets.allSatisfy { $0.status == .skipped && $0.locked })
    }

    @Test("Removing the last set deletes it, and locked exercises refuse")
    func exerciseRemoveLastSet() throws {
        let workoutExercise = makeWorkoutExercise()
        try container.mainContext.save()
        let first = try #require(workoutExercise.addSet())
        _ = workoutExercise.addSet()

        workoutExercise.removeLastSet()
        #expect(workoutExercise.workoutSets.map(\.order) == [first.order])

        workoutExercise.start()
        workoutExercise.complete()
        workoutExercise.removeLastSet()
        #expect(workoutExercise.totalSets == 1)

        let empty = makeWorkoutExercise()
        empty.removeLastSet()
        #expect(empty.totalSets == 0)
    }

    @Test("Changing an exercise resets it to fresh sets, but not once locked")
    func exerciseChangeExercise() throws {
        let workoutExercise = makeWorkoutExercise()
        let replacement = makeExercise(name: "Row", primary: .back)
        for _ in 0..<4 { _ = workoutExercise.addSet() }

        workoutExercise.changeExercise(newExercise: replacement)
        #expect(workoutExercise.exercise === replacement)
        #expect(workoutExercise.totalSets == WorkoutExercise.initialSets)
        #expect(workoutExercise.workoutSets.map(\.order) == [0, 1])

        workoutExercise.start()
        workoutExercise.complete()
        workoutExercise.changeExercise(newExercise: makeExercise(name: "Curl", primary: .biceps))
        #expect(workoutExercise.exercise === replacement)
    }

    @Test("Check-ins only apply to planned exercises and resolve once")
    func exerciseCheckInGuards() {
        let started = makeWorkoutExercise()
        started.start()
        started.requireCheckIn(sourcePain: .severe)
        #expect(started.checkIn == ManualCheckIn.none)

        let notPending = makeWorkoutExercise()
        notPending.resolveCheckIn(.continue)
        #expect(notPending.checkIn == ManualCheckIn.none)
        #expect(notPending.status == .planned)
    }

    @Test("Resolving a check-in with skip skips the exercise and its sets")
    func exerciseCheckInSkip() {
        let workoutExercise = makeWorkoutExercise()
        workoutExercise.addPlannedSet(plannedReps: 8, plannedWeightTenthsPounds: 1000)
        workoutExercise.requireCheckIn(sourcePain: .extreme)
        #expect(workoutExercise.locked)

        workoutExercise.resolveCheckIn(.skip)
        #expect(workoutExercise.checkIn == .resolved)
        #expect(workoutExercise.status == .skipped)
        #expect(workoutExercise.workoutSets.allSatisfy { $0.status == .skipped })
        #expect(!workoutExercise.needsFeedback)
    }

    @Test("Feedback waits until every set is done, then is no longer needed")
    func exerciseFeedback() throws {
        let workoutExercise = makeWorkoutExercise()
        workoutExercise.start()
        let set = try #require(workoutExercise.addSet())
        let feedback = ExerciseFeedback(levelOfEffort: .easy, levelOfPain: .mild)

        workoutExercise.addFeedback(feedback: feedback)
        #expect(workoutExercise.feedback == nil)
        #expect(!workoutExercise.needsFeedback)

        set.complete()
        #expect(workoutExercise.needsFeedback)
        workoutExercise.addFeedback(feedback: feedback)
        #expect(workoutExercise.feedback === feedback)
        #expect(!workoutExercise.needsFeedback)

        feedback.levelOfEffort = .brutal
        feedback.levelOfPain = .moderate
        #expect(workoutExercise.feedback?.levelOfEffort == .brutal)
        #expect(workoutExercise.feedback?.levelOfPain == .moderate)
    }

    @Test("A nil weight is never copied to later sets")
    func exerciseApplyNilWeight() throws {
        let workoutExercise = makeWorkoutExercise()
        let first = try #require(workoutExercise.addSet())
        let second = try #require(workoutExercise.addSet())
        second.weightTenthsPounds = 800

        workoutExercise.applyWeight(nil, after: first)
        #expect(second.weightTenthsPounds == 800)
    }

    // MARK: Workout

    @Test("Workout set totals add up every exercise")
    func workoutCounts() throws {
        let workout = Workout(order: 0)
        container.mainContext.insert(workout)
        let bench = try #require(workout.addWorkoutExercise(exercise: makeExercise(name: "Bench", primary: .chest)))
        let row = try #require(workout.addWorkoutExercise(exercise: makeExercise(name: "Row", primary: .back)))
        bench.addPlannedSet(plannedReps: 8, plannedWeightTenthsPounds: nil)
        row.addPlannedSet(plannedReps: 8, plannedWeightTenthsPounds: nil)
        row.addPlannedSet(plannedReps: 8, plannedWeightTenthsPounds: nil)

        #expect(workout.totalSets == 3)
        #expect(workout.getCountPlannedSets() == 3)

        workout.startAndCascade()
        #expect(workout.getCountActiveSets() == 3)
        row.workoutSets[0].complete()
        row.workoutSets[1].skip()
        #expect(workout.getCountCompletedSets() == 1)
        #expect(workout.getCountSkippedSets() == 1)
    }

    @Test("Exercises can only be added to a planned workout")
    func workoutAddExerciseNeedsPlanned() {
        let workout = Workout(order: 0)
        container.mainContext.insert(workout)
        workout.start()
        #expect(workout.addWorkoutExercise(exercise: makeExercise(name: "Bench", primary: .chest)) == nil)
    }

    @Test("Removing and moving exercises keeps the order")
    func workoutRemoveAndMove() throws {
        let workout = Workout(order: 0)
        container.mainContext.insert(workout)
        let names = ["A", "B", "C"]
        for name in names {
            _ = workout.addWorkoutExercise(exercise: makeExercise(name: name, primary: .chest))
        }

        workout.moveWorkoutExercises(from: IndexSet(integer: 2), to: 0)
        #expect(workout.workoutExercises.compactMap(\.exercise?.exerciseName) == ["C", "A", "B"])
        #expect(workout.workoutExercises.map(\.order) == [0, 1, 2])

        workout.removeWorkoutExercise(index: 9)
        #expect(workout.workoutExercises.count == 3)
        workout.removeWorkoutExercise(index: 1)
        #expect(workout.workoutExercises.compactMap(\.exercise?.exerciseName) == ["C", "B"])
    }

    @Test("Workout transitions refuse invalid states")
    func workoutTransitions() {
        let workout = Workout(order: 0)
        #expect(workout.locked)

        // Planned workouts are locked, so only start works.
        workout.complete()
        workout.stop()
        workout.skip()
        #expect(workout.status == .planned)
        #expect(!workout.isFinished)

        workout.start()
        #expect(workout.status == .active)
        #expect(!workout.locked)
        workout.start()
        #expect(workout.status == .active)

        workout.stop()
        #expect(workout.status == .stopped)
        #expect(workout.isFinished)
        workout.complete()
        #expect(workout.status == .stopped)
    }

    @Test("Stopping a workout stops every exercise")
    func workoutStopCascade() throws {
        let workout = Workout(order: 0)
        container.mainContext.insert(workout)
        let workoutExercise = try #require(workout.addWorkoutExercise(exercise: makeExercise(name: "Bench", primary: .chest)))
        workoutExercise.addPlannedSet(plannedReps: 8, plannedWeightTenthsPounds: nil)
        workout.startAndCascade()

        workout.stopAndCascade()
        #expect(workout.status == .stopped)
        #expect(workoutExercise.status == .stopped)
        #expect(workout.allExercisesFinished)
    }

    @Test("An empty workout points at its first exercise slot")
    func workoutEmptyCurrentIndex() {
        let workout = Workout(order: 0)
        #expect(workout.currentExerciseIndex == 0)
        #expect(workout.allExercisesFinished)
        #expect(workout.currentSet == nil)
        #expect(workout.activityState() == nil)
    }

    // MARK: ProgramWeek

    @Test("Week transitions lock the week and refuse further changes")
    func weekTransitions() {
        let week = ProgramWeek(order: 0)
        week.start()
        #expect(week.status == .active)
        week.start()
        #expect(week.status == .active)

        week.skip()
        #expect(week.status == .skipped)
        #expect(week.locked)
        #expect(week.addWorkout() == nil)

        week.complete()
        week.stop()
        week.skip()
        #expect(week.status == .skipped)

        let stopped = ProgramWeek(order: 1)
        stopped.stop()
        #expect(stopped.status == .stopped)
        stopped.start()
        #expect(stopped.status == .stopped)
    }

    @Test("Week cascades reach every workout")
    func weekCascades() throws {
        let skipped = ProgramWeek(order: 0)
        container.mainContext.insert(skipped)
        let first = try #require(skipped.addWorkout())
        let second = try #require(skipped.addWorkout())
        #expect(skipped.workouts.map(\.order) == [0, 1])

        skipped.startAndCascade()
        #expect(skipped.workouts.allSatisfy { $0.status == .active })
        skipped.skipAndCascade()
        #expect(first.status == .skipped)
        #expect(second.status == .skipped)

        let stopped = ProgramWeek(order: 1)
        container.mainContext.insert(stopped)
        let workout = try #require(stopped.addWorkout())
        workout.start()
        stopped.stopAndCascade()
        #expect(stopped.status == .stopped)
        #expect(workout.status == .stopped)
    }

    // MARK: Program

    @Test("Program totals and template fallbacks")
    func programDerivedValues() throws {
        let program = try makeProgram(weeks: 4, workouts: 3)
        #expect(program.totalWorkouts == 12)
        #expect(program.percentFinished == 0)
        #expect(program.templateName == "Test")
        #expect(program.workoutsPerWeek == 3)
        #expect(program.templateMuscleFocus == [.chest])
        #expect(program.nextWorkout == nil)

        // A synced program can arrive before its template.
        program.templateProgramValue = nil
        #expect(program.templateName == "Program")
        #expect(program.workoutsPerWeek == 0)
        #expect(program.totalWorkouts == 0)
        #expect(program.percentFinished == 0)
        #expect(program.templateMuscleFocus.isEmpty)
    }

    @Test("Percent finished counts completed and skipped workouts")
    func programPercentFinished() throws {
        let program = try makeProgram(weeks: 1, workouts: 3)
        program.start()
        let workouts = program.programWeeks[0].workouts
        program.skipWorkout(workouts[0])
        #expect(program.workoutsFinished == 1)
        #expect(program.percentFinished == 33)
    }

    @Test("Program transitions refuse invalid states")
    func programTransitions() throws {
        let program = try makeProgram(weeks: 1, workouts: 1)
        let workout = program.programWeeks[0].workouts[0]

        program.complete()
        #expect(program.status == .planned)
        #expect(program.finishWorkout(workout) == nil)
        #expect(program.skipWorkout(workout) == nil)
        #expect(workout.status == .planned)

        program.start()
        #expect(program.status == .active)
        #expect(program.programWeeks[0].status == .active)
        program.start()
        #expect(program.status == .active)

        program.stop()
        #expect(program.status == .stopped)
        program.start()
        program.complete()
        #expect(program.status == .stopped)
    }

    @Test("Cascades only run after the program reached that status")
    func programCascadeGuards() throws {
        let program = try makeProgram(weeks: 2, workouts: 1)
        program.completeAndCascade()
        program.stopAndCascade()
        #expect(program.programWeeks.allSatisfy { $0.status == .planned })

        program.start()
        program.stop()
        program.stopAndCascade()
        #expect(program.programWeeks.allSatisfy { $0.status == .stopped })
    }

    @Test("Weeks can be added up to 12 and removed until the program is locked")
    func programWeeks() throws {
        let program = try makeProgram(weeks: 11, workouts: 1)
        #expect(program.addProgramWeek()?.order == 11)
        #expect(program.addProgramWeek() == nil)

        program.removeLastProgramWeek()
        #expect(program.programWeeks.count == 11)

        program.start()
        program.stop()
        program.removeLastProgramWeek()
        #expect(program.addProgramWeek() == nil)
        #expect(program.programWeeks.count == 11)
    }

    @Test("Finishing an already finished workout still advances")
    func programFinishFinishedWorkout() throws {
        let program = try makeProgram(weeks: 1, workouts: 2)
        program.start()
        let workouts = program.programWeeks[0].workouts
        workouts[0].start()
        workouts[0].stop()

        let next = program.finishWorkout(workouts[0])
        #expect(next === workouts[1])
        #expect(workouts[0].status == .stopped)
    }

    @Test("Week lookups and activity titles")
    func programWeekLookup() throws {
        let program = try makeProgram(weeks: 2, workouts: 2)
        let workout = program.programWeeks[0].workouts[1]
        #expect(program.weekNumber(containing: workout) == 1)
        #expect(program.programWeek(containing: workout) === program.programWeeks[0])
        #expect(program.activityTitle(for: workout) == "Day 2 · Week 1")

        let stray = Workout(order: 0)
        #expect(program.weekNumber(containing: stray) == nil)
        #expect(program.activityTitle(for: stray) == "Day 1")
    }

    // MARK: Templates

    @Test("Template focus ignores more than four muscles")
    func templateFocusLimit() {
        let template = TemplateProgram(templateName: "T", workoutsPerWeek: -3, templateMuscleFocus: [.quads, .back])
        #expect(template.workoutsPerWeek == 0)
        #expect(template.templateMuscleFocus == [.back, .quads])

        template.templateMuscleFocus = [.chest, .back, .biceps, .triceps, .abs]
        #expect(template.templateMuscleFocus == [.back, .quads])
        template.templateMuscleFocus = [.chest]
        #expect(template.templateMuscleFocus == [.chest])
    }

    @Test("Template exercises move and keep a gapless order")
    func templateMoveExercises() {
        let template = TemplateProgram(templateName: "T", workoutsPerWeek: 1, templateMuscleFocus: [])
        container.mainContext.insert(template)
        let workout = template.addTemplateWorkout()
        for name in ["A", "B", "C"] {
            workout.addTemplateExercise(exercise: makeExercise(name: name, primary: .chest))
        }

        workout.moveTemplateExercises(from: IndexSet(integer: 0), to: 3)
        #expect(workout.templateExercises.compactMap(\.exercise?.exerciseName) == ["B", "C", "A"])
        #expect(workout.templateExercises.map(\.order) == [0, 1, 2])

        // Out-of-range moves are ignored.
        workout.moveTemplateExercises(from: IndexSet(integer: 5), to: 0)
        workout.moveTemplateExercises(from: IndexSet(integer: 0), to: 9)
        #expect(workout.templateExercises.compactMap(\.exercise?.exerciseName) == ["B", "C", "A"])

        template.clearAllTemplateWorkoutsValue()
        #expect(template.templateWorkouts.isEmpty)
    }

    // MARK: Exercise

    @Test("Exercise accessors normalize what the forms and engine read")
    func exerciseAccessors() {
        let exercise = makeExercise(name: "Push Up", primary: .chest)
        exercise.exerciseEquipment = .bodyweight
        exercise.secondaryMuscles = [.triceps, .abs]
        exercise.minReps = 12
        exercise.maxReps = 10
        exercise.fatigueLevel = .low

        #expect(exercise.secondaryMuscles == [.abs, .triceps])
        #expect(exercise.repRange == 12...12)
        #expect(exercise.repsOnly)
        #expect(exercise.restDuration == FatigueLevel.low.restLength.duration)
    }

    // MARK: Helpers

    private func makeExercise(name: String, primary: Muscle) -> Exercise {
        let exercise = Exercise(exerciseName: name, exerciseEquipment: .barbell, primaryMuscleFocus: primary)
        container.mainContext.insert(exercise)
        return exercise
    }

    private func makeWorkoutExercise() -> WorkoutExercise {
        let workoutExercise = WorkoutExercise(exercise: makeExercise(name: "Bench", primary: .chest), order: 0)
        container.mainContext.insert(workoutExercise)
        return workoutExercise
    }

    private func makeProgram(weeks: Int, workouts: Int) throws -> Program {
        let exercise = makeExercise(name: "Bench", primary: .chest)
        let template = TemplateProgram(templateName: "Test", workoutsPerWeek: workouts, templateMuscleFocus: [.chest])
        for _ in 0..<workouts {
            template.addTemplateWorkout().addTemplateExercise(exercise: exercise)
        }
        container.mainContext.insert(template)
        let program = Program(programLengthWeeks: weeks, templateProgram: template)
        try container.mainContext.insertAndSave(program)
        return program
    }
}
