//
//  SupersetTests.swift
//  PowerJackTests
//
//  Exercises stacked in the template are done one set of each in turn, and rest once each round is done.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct SupersetTests {
    /// Held by the suite instance so models stay valid for the whole test.
    private let container = PowerJackSeed.makeInMemoryContainer()
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: Workout

    @Test("A superset takes one set of each exercise in turn, warmups first")
    func roundOrder() throws {
        let workout = try makeSupersetWorkout()
        let a = workout.workoutExercises[0]
        let b = workout.workoutExercises[1]

        var order: [String] = []
        var time = start
        // Up to C, which comes after the superset.
        while let current = workout.currentSet, current.workoutExercise !== workout.workoutExercises[2] {
            order.append(label(current.workoutSet, in: current.workoutExercise, a: a))
            current.workoutExercise.completeSet(current.workoutSet, at: time)
            time += 60
        }

        #expect(order == [
            "A W1", "B W1",
            "A W2", "B W2",
            "A W3",
            "A 1", "B 1",
            "A 2", "B 2",
            "B 3",
        ])
    }

    @Test("A superset rests once each round is done, for the longer of the two rests")
    func restAfterRound() throws {
        let workout = try makeSupersetWorkout()
        let a = workout.workoutExercises[0]
        let b = workout.workoutExercises[1]

        // A then B: no rest between them, then the longer rest (A's high fatigue, 3:00).
        a.completeSet(a.warmupSets[0], at: start)
        #expect(workout.currentRest == nil)
        #expect(workout.currentSet?.workoutExercise === b)

        b.completeSet(b.warmupSets[0], at: start + 30)
        let rest = try #require(workout.currentRest)
        #expect(rest.startedAt == start + 30)
        #expect(rest.duration == 180)
        #expect(rest.exerciseName == "A")
        #expect(rest.isWarmup)
        #expect(rest.setNumber == 2)

        // A's third warmup is a round on its own, so it rests for A's rest alone.
        a.completeSet(a.warmupSets[1], at: start + 300)
        b.completeSet(b.warmupSets[1], at: start + 330)
        a.completeSet(a.warmupSets[2], at: start + 600)
        #expect(workout.currentRest?.duration == 180)
        #expect(workout.currentSet?.workoutSet === a.workingSets[0])
    }

    @Test("A round of B alone rests for B's own rest, and the superset's last set starts no rest")
    func loneRoundUsesItsOwnRest() throws {
        let workout = try makeSupersetWorkout(bWorkingSets: 4)
        let a = workout.workoutExercises[0]
        let b = workout.workoutExercises[1]
        a.skipWarmups()
        b.skipWarmups()

        var time = start
        for workoutSet in [a.workingSets[0], b.workingSets[0], a.workingSets[1], b.workingSets[1], b.workingSets[2]] {
            let workoutExercise = workoutSet.workoutExerciseValue
            workoutExercise?.completeSet(workoutSet, at: time)
            time += 60
        }
        // B (low fatigue) rests 1:15 on its own.
        #expect(workout.currentRest?.duration == 75)

        b.completeSet(b.workingSets[3], at: time)
        #expect(workout.currentRest == nil)
        #expect(workout.currentSet?.workoutExercise === workout.workoutExercises[2])
    }

    @Test("Mid-round, the workout opens on the exercise whose turn it is")
    func currentExerciseFollowsTheRound() throws {
        let workout = try makeSupersetWorkout()
        let a = workout.workoutExercises[0]
        #expect(workout.currentExerciseIndex == 0)

        a.completeSet(a.warmupSets[0], at: start)

        #expect(workout.currentExerciseIndex == 1)
    }

    @Test("Exercises only form a superset next to each other")
    func groupsNeedNeighbors() throws {
        let workout = try makeSupersetWorkout()
        let a = workout.workoutExercises[0]
        let b = workout.workoutExercises[1]
        let c = workout.workoutExercises[2]
        #expect(a.supersetPartners.map(\.exercise?.exerciseName) == ["B"])
        #expect(c.supersetPartners.isEmpty)

        workout.moveWorkoutExercises(from: IndexSet(integer: 2), to: 1)

        #expect(a.supersetPartners.isEmpty)
        #expect(b.supersetPartners.isEmpty)
        #expect(workout.exerciseGroups.count == 3)
    }

    // MARK: Template builder

    @Test("Stacking pairs an exercise with the one below, or above for the last one")
    func stacking() throws {
        var day = makeDay(["A", "B", "C"])
        #expect(day.blocks.count == 3)

        day.stack(day.blocks[0])
        #expect(day.blocks.map { $0.exercises.map(\.exercise.exerciseName) } == [["A", "B"], ["C"]])
        // C's neighbor is already a superset, and supersets are pairs.
        #expect(!day.canStack(day.blocks[1]))
        #expect(!day.canStack(day.blocks[0]))

        day.unstack(day.blocks[0])
        day.stack(day.blocks[2])
        #expect(day.blocks.map { $0.exercises.map(\.exercise.exerciseName) } == [["A"], ["B", "C"]])
    }

    @Test("Moving a superset moves both exercises, and removing one's neighbor keeps it intact")
    func movingSupersets() throws {
        var day = makeDay(["A", "B", "C"])
        day.stack(day.blocks[0])

        day.moveBlocks(from: IndexSet(integer: 0), to: 2)
        #expect(day.templateExerciseDrafts.map(\.exercise.exerciseName) == ["C", "A", "B"])
        #expect(day.blocks.map(\.isSuperset) == [false, true])

        day.removeTemplateExercises(at: IndexSet(integer: 0))
        #expect(day.blocks.map(\.isSuperset) == [true])
    }

    @Test("Moving an exercise out of a superset splits it")
    func movingOneExerciseSplits() throws {
        var day = makeDay(["A", "B", "C"])
        day.stack(day.blocks[0])

        day.moveTemplateExercises(from: IndexSet(integer: 0), to: 3)

        #expect(day.templateExerciseDrafts.map(\.exercise.exerciseName) == ["B", "C", "A"])
        #expect(day.templateExerciseDrafts.allSatisfy { $0.supersetID == nil })
    }

    @Test("A saved superset reaches the program's first week", arguments: TemplateType.allCases)
    func supersetReachesProgram(templateType: TemplateType) throws {
        let program = try makeProgram(templateType: templateType, weeks: 1)
        let exercises = try #require(program.programWeeks.first?.workouts.first?.workoutExercises)

        #expect(exercises[0].supersetPartners.map { $0 === exercises[1] } == [true])
        #expect(exercises[2].supersetPartners.isEmpty)
    }

    @Test("Editing only the stacking still saves it")
    func applyingStackingSaves() throws {
        let program = try makeProgram(templateType: .hypertrophy, weeks: 1)
        let template = try #require(program.templateProgram)
        var draft = TemplateProgramDraft(templateProgram: template)
        // The draft reads the saved superset back in.
        #expect(draft.templateWorkoutDraftsValue[0].blocks.map(\.isSuperset) == [true, false])
        draft.templateWorkoutDraftsValue[0].unstack(draft.templateWorkoutDraftsValue[0].blocks[0])

        draft.apply(to: template)

        #expect(template.templateWorkouts[0].templateExercises.allSatisfy { $0.supersetID == nil })
    }

    @Test("Next week keeps the superset", arguments: TemplateType.allCases)
    func nextWeekKeepsSuperset(templateType: TemplateType) throws {
        let program = try makeProgram(templateType: templateType, weeks: 2)
        // Both days of week one.
        var next = try #require(program.nextWorkout)
        for _ in 0..<2 {
            next.startAndCascade()
            for workoutExercise in next.workoutExercises {
                for workoutSet in workoutExercise.workoutSets {
                    workoutSet.reps = workoutSet.repsPlanned ?? 10
                    workoutSet.weightTenthsPounds = workoutSet.weightTenthsPlannedPounds ?? 1000
                    workoutSet.complete()
                }
                workoutExercise.addFeedback(feedback: ExerciseFeedback(levelOfEffort: .challenge, levelOfPain: .none))
            }
            next = try #require(program.finishWorkout(next))
        }
        #expect(program.programWeeks[1].workouts.first === next)

        let exercises = next.workoutExercises
        #expect(exercises.count == 3)
        #expect(exercises[0].supersetPartners.map { $0 === exercises[1] } == [true])
        #expect(exercises[2].supersetPartners.isEmpty)
    }

    // MARK: Helpers

    /// A (high fatigue) with 3 warmups and 2 working sets, superset with B (low fatigue) with 2 warmups
    /// and 3 working sets, then C on its own.
    private func makeSupersetWorkout(bWorkingSets: Int = 3) throws -> Workout {
        let workout = Workout(order: 0)
        let supersetID = UUID()
        let plan: [(name: String, fatigue: FatigueLevel, warmups: Int, sets: Int, superset: UUID?)] = [
            ("A", .high, 3, 2, supersetID),
            ("B", .low, 2, bWorkingSets, supersetID),
            ("C", .moderate, 0, 2, nil),
        ]
        for entry in plan {
            let exercise = Exercise(
                exerciseName: entry.name,
                exerciseEquipment: .dumbbell,
                primaryMuscleFocus: .biceps,
                fatigueLevel: entry.fatigue
            )
            let workoutExercise = try #require(workout.addWorkoutExercise(exercise: exercise))
            workoutExercise.setSuperset(entry.superset)
            for _ in 0..<entry.warmups {
                _ = workoutExercise.addSet(type: .warmup, plannedReps: 8, plannedWeightTenthsPounds: 200)
            }
            for _ in 0..<entry.sets {
                _ = workoutExercise.addSet(plannedReps: 10, plannedWeightTenthsPounds: 300)
            }
        }
        container.mainContext.insert(workout)
        workout.startAndCascade()
        return workout
    }

    private func label(_ workoutSet: WorkoutSet, in workoutExercise: WorkoutExercise, a: WorkoutExercise) -> String {
        let name = workoutExercise === a ? "A" : "B"
        let number = workoutExercise.number(of: workoutSet)
        return workoutSet.isWarmup ? "\(name) W\(number)" : "\(name) \(number)"
    }

    private func makeDay(_ names: [String]) -> TemplateWorkoutDraft {
        var day = TemplateWorkoutDraft(enabled: true, order: 0, templateExercises: nil)
        for name in names {
            let exercise = Exercise(exerciseName: name, exerciseEquipment: .dumbbell, primaryMuscleFocus: .biceps)
            container.mainContext.insert(exercise)
            day.addTemplateExerciseDraft(exercise: exercise)
        }
        return day
    }

    /// One day: Bench and Row stacked into a superset, then Curl on its own.
    private func makeTemplate(_ templateType: TemplateType) throws -> TemplateProgram {
        var draft = TemplateProgramDraft(templateType: templateType)
        draft.templateName = "Superset"
        draft.workoutsPerWeek = 2
        draft.templateMuscleFocus = [.chest]
        let lifts: [(String, Muscle, FatigueLevel)] = [
            ("Superset Bench", .chest, .high),
            ("Superset Row", .back, .moderate),
            ("Superset Curl", .biceps, .low),
        ]
        for (name, muscle, fatigue) in lifts {
            let exercise = Exercise(
                exerciseName: name,
                exerciseEquipment: .barbell,
                primaryMuscleFocus: muscle,
                minReps: 6,
                maxReps: 12,
                fatigueLevel: fatigue
            )
            container.mainContext.insert(exercise)
            draft.templateWorkoutDraftsValue[0].addTemplateExerciseDraft(exercise: exercise)
            draft.templateWorkoutDraftsValue[1].addTemplateExerciseDraft(exercise: exercise)
        }
        draft.templateWorkoutDraftsValue[0].stack(draft.templateWorkoutDraftsValue[0].blocks[0])
        let template = try #require(draft.makeTemplate())
        container.mainContext.insert(template)
        return template
    }

    private func makeProgram(templateType: TemplateType, weeks: Int) throws -> Program {
        let program = Program(programLengthWeeks: weeks, templateProgram: try makeTemplate(templateType))
        try container.mainContext.insertAndSave(program)
        program.start()
        return program
    }
}
