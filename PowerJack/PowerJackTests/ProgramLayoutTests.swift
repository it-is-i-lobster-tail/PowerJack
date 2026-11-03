//
//  ProgramLayoutTests.swift
//  PowerJackTests
//
//  A running program's days can be edited in the template builder. Workouts not started yet change now,
//  days already started change from next week, and later weeks follow the edit.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct ProgramLayoutTests {
    @Test("Every day opens with its exercises; days already started say their changes start next week")
    func startedDaysOpen() throws {
        let (container, template) = try makeTemplate("Full Body")
        let program = try startProgram(template, in: container)
        try finishNextWorkout(of: program)

        let draft = ProgramLayoutDraft(program: program)

        #expect(draft.lockedDays.isEmpty)
        #expect(draft.dayNotes == [0: "Day 1 is done for this week. Changes start next week."])
        let week = try #require(program.programWeeks.first)
        for (index, workout) in week.workouts.enumerated() {
            #expect(
                draft.days.templateWorkoutDraftsValue[index].templateExerciseDrafts.map(\.exercise.exerciseName)
                    == workout.workoutExercises.compactMap(\.exercise?.exerciseName)
            )
        }
        #expect(draft.days.workoutsPerWeek == template.workoutsPerWeek)
    }

    @Test("Editing a day already done leaves this week alone and changes it from next week on",
          arguments: TemplateCatalog.entries.map(\.name))
    func doneDayChangesNextWeek(templateName: String) throws {
        let (container, template) = try makeTemplate(templateName)
        let program = try startProgram(template, in: container)
        try finishNextWorkout(of: program)
        let dayOne = try #require(program.programWeeks.first?.workouts[0])
        let loggedThisWeek = dayOne.workoutExercises.compactMap(\.exercise?.exerciseName)
        let curl = try #require(try container.mainContext.fetch(FetchDescriptor<Exercise>()).first {
            $0.exerciseName == "Dumbbell Curl"
        })

        var draft = ProgramLayoutDraft(program: program)
        var day = draft.days.templateWorkoutDraftsValue[0]
        day.removeTemplateExercises(at: IndexSet(integer: 0))
        day.addTemplateExerciseDraft(exercise: curl)
        day.drop(day.blocks[1].exercises.map(\.id), on: day.blocks[0], at: .onto)
        draft.days.templateWorkoutDraftsValue[0] = day
        draft.apply()
        try container.mainContext.save()

        let expected = day.templateExerciseDrafts.map(\.exercise.exerciseName)
        #expect(dayOne.workoutExercises.compactMap(\.exercise?.exerciseName) == loggedThisWeek)
        #expect(dayOne.nextWeekLayout?.compactMap(\.exercise?.exerciseName) == expected)
        // Opening Edit Days again shows the saved edit.
        #expect(
            ProgramLayoutDraft(program: program).days.templateWorkoutDraftsValue[0].templateExerciseDrafts
                .map(\.exercise.exerciseName) == expected
        )

        // Every later week's day one has the edit, with its sets planned.
        while let workout = program.nextWorkout {
            try finishNextWorkout(of: program)
            guard let week = program.programWeek(containing: workout), week.order > 0, workout.order == 0 else { continue }
            #expect(workout.workoutExercises.compactMap(\.exercise?.exerciseName) == expected, "\(templateName) week \(week.order + 1)")
            #expect(workout.workoutExercises[0].supersetPartners.first === workout.workoutExercises[1])
            #expect(workout.workoutExercises.allSatisfy { !$0.workingSets.isEmpty }, "\(templateName) week \(week.order + 1)")
        }
        #expect(dayOne.nextWeekLayout == nil)
    }

    @Test("Undoing a done day's edit leaves nothing waiting for next week")
    func undoneEditClears() throws {
        let (container, template) = try makeTemplate("Full Body")
        let program = try startProgram(template, in: container)
        try finishNextWorkout(of: program)
        let dayOne = try #require(program.programWeeks.first?.workouts[0])

        var draft = ProgramLayoutDraft(program: program)
        let original = draft.days.templateWorkoutDraftsValue[0]
        draft.days.templateWorkoutDraftsValue[0].removeTemplateExercises(at: IndexSet(integer: 0))
        draft.apply()
        #expect(dayOne.nextWeekLayout != nil)

        draft.days.templateWorkoutDraftsValue[0] = original
        draft.apply()
        #expect(dayOne.nextWeekLayout == nil)
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
        day.drop(day.blocks[1].exercises.map(\.id), on: day.blocks[0], at: .onto)
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

    @Test("In the program's last week, a finished day is locked")
    func lockedMessages() throws {
        let (container, template) = try makeTemplate("Full Body")
        let program = try startProgram(template, in: container, weeks: 1)
        try finishNextWorkout(of: program)

        let draft = ProgramLayoutDraft(program: program)

        #expect(draft.lockedDays[0]?.title == "Day 1 is done for this week")
        #expect(draft.lockedDays[0]?.detail == nil)
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
