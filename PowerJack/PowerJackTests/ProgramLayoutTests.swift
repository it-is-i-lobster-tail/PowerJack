//
//  ProgramLayoutTests.swift
//  PowerJackTests
//
//  A running program's days can be edited in the template builder. Only workouts not started yet change,
//  and later weeks follow the edit.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct ProgramLayoutTests {
    @Test("Days already started this week are locked; the rest open with their exercises and supersets")
    func lockedDays() throws {
        let (container, template) = try makeTemplate("Full Body")
        let program = try startProgram(template, in: container)
        try finishNextWorkout(of: program)

        let draft = ProgramLayoutDraft(program: program)

        #expect(draft.lockedDays.keys.sorted() == [0])
        #expect(draft.days.templateWorkoutDraftsValue[0].templateExerciseDrafts.isEmpty)
        let dayTwo = try #require(program.programWeeks.first?.workouts[1])
        #expect(
            draft.days.templateWorkoutDraftsValue[1].templateExerciseDrafts.map(\.exercise.exerciseName)
                == dayTwo.workoutExercises.compactMap(\.exercise?.exerciseName)
        )
        #expect(draft.days.workoutsPerWeek == template.workoutsPerWeek)
    }

    @Test("Removing, moving, adding and stacking change the open day and every later week",
          arguments: TemplateCatalog.entries.map(\.name))
    func editsCarryForward(templateName: String) throws {
        let (container, template) = try makeTemplate(templateName)
        let program = try startProgram(template, in: container)
        try finishNextWorkout(of: program)
        let dayTwo = try #require(program.programWeeks.first?.workouts[1])
        let curl = try #require(try container.mainContext.fetch(FetchDescriptor<Exercise>()).first {
            $0.exerciseName == "Dumbbell Curl"
        })

        var draft = ProgramLayoutDraft(program: program)
        var day = draft.days.templateWorkoutDraftsValue[1]
        day.removeTemplateExercises(at: IndexSet(integer: 0))
        day.moveTemplateExercises(from: IndexSet(integer: day.templateExerciseDrafts.count - 1), to: 0)
        day.addTemplateExerciseDraft(exercise: curl)
        day.stack(day.blocks[0])
        draft.days.templateWorkoutDraftsValue[1] = day
        draft.apply()
        try container.mainContext.save()

        let expected = day.templateExerciseDrafts.map(\.exercise.exerciseName)
        #expect(dayTwo.workoutExercises.compactMap(\.exercise?.exerciseName) == expected)
        #expect(dayTwo.workoutExercises[0].supersetPartners.first === dayTwo.workoutExercises[1])
        let added = try #require(dayTwo.workoutExercises.last)
        #expect(added.exercise === curl)
        #expect(added.workingSets.count == WorkoutExercise.initialSets)

        // Applying again changes nothing.
        let before = dayTwo.workoutExercises.map(ObjectIdentifier.init)
        draft.apply()
        #expect(dayTwo.workoutExercises.map(ObjectIdentifier.init) == before)

        // Every later week keeps the edit, and its engine plans every exercise.
        while let workout = program.nextWorkout {
            try finishNextWorkout(of: program)
            guard let week = program.programWeek(containing: workout), week.order > 0, workout.order == 1 else { continue }
            #expect(workout.workoutExercises.compactMap(\.exercise?.exerciseName) == expected, "\(templateName) week \(week.order + 1)")
            #expect(workout.workoutExercises[0].supersetPartners.first === workout.workoutExercises[1])
            #expect(workout.workoutExercises.allSatisfy { !$0.workingSets.isEmpty }, "\(templateName) week \(week.order + 1)")
        }
        #expect(program.status == .complete)
    }

    @Test("A finished day's message says when it can change, except in the last week")
    func lockedMessages() throws {
        let (container, template) = try makeTemplate("Full Body")
        let program = try startProgram(template, in: container, weeks: 1)
        try finishNextWorkout(of: program)

        let draft = ProgramLayoutDraft(program: program)

        #expect(draft.lockedDays[0] == "Day 1 is done for this week.")
    }

    // MARK: Helpers

    private func makeTemplate(_ name: String) throws -> (ModelContainer, TemplateProgram) {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        try ExerciseCatalog.seed(in: container.mainContext)
        try TemplateCatalog.seed(in: container.mainContext)
        let template = try #require(try container.mainContext.fetch(FetchDescriptor<TemplateProgram>()).first {
            $0.templateName == name
        })
        return (container, template)
    }

    private func startProgram(_ template: TemplateProgram, in container: ModelContainer, weeks: Int = 3) throws -> Program {
        let program = Program(programLengthWeeks: weeks, templateProgram: template)
        try container.mainContext.insertAndSave(program)
        program.start()
        return program
    }

    /// Logs every set of the next workout at its target, rates each exercise, and finishes it.
    private func finishNextWorkout(of program: Program) throws {
        let workout = try #require(program.nextWorkout)
        program.prepareToStart(workout)
        workout.startAndCascade()
        for workoutExercise in workout.workoutExercises {
            if workoutExercise.checkInPending {
                workoutExercise.resolveCheckIn(.continue)
            }
            for workoutSet in workoutExercise.workoutSets where workoutSet.status == .active {
                workoutSet.reps = workoutSet.repsPlanned ?? 8
                if workoutExercise.exercise?.repsOnly == false {
                    workoutSet.weightTenthsPounds = workoutSet.weightTenthsPlannedPounds ?? 1000
                }
                workoutExercise.completeSet(workoutSet)
            }
            workoutExercise.addFeedback(feedback: ExerciseFeedback(levelOfEffort: .challenge, levelOfPain: .none))
        }
        program.finishWorkout(workout)
        try program.modelContext?.save()
    }
}
