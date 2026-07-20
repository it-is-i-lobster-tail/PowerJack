//
//  CreationFlowTests.swift
//  PowerJackTests
//
//  Created by Codex on 7/20/26.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct CreationFlowTests {
    @Test("Exercise drafts validate, trim, create, and update")
    func exerciseDraftLifecycle() throws {
        var draft = ExerciseDraft()
        draft.name = "  Row  "
        draft.equipment = .cable
        draft.primaryMuscle = .back
        draft.secondaryMuscles = [.biceps]

        #expect(draft.canSave)

        let exercise = try #require(draft.makeExercise())
        #expect(exercise.exerciseName == "Row")
        #expect(exercise.userCreated)
        #expect(exercise.secondaryMuscles == [.biceps])

        draft.name = String(repeating: "x", count: maxExerciseNameLengthInput + 1)
        #expect(!draft.canSave)

        draft.name = "Pulldown"
        draft.primaryMuscle = .shoulders
        let didApply = draft.apply(to: exercise)
        #expect(didApply)
        #expect(exercise.exerciseName == "Pulldown")
        #expect(exercise.primaryMuscleFocus == .shoulders)
    }

    @Test("Template workout counts stay ordered and protect configured trailing days")
    func templateWorkoutCountSynchronization() {
        var draft = TemplateProgramDraft()
        draft.setWorkoutsPerWeek(3)

        #expect(draft.templateWorkoutDrafts.count == 3)
        #expect(draft.templateWorkoutDrafts.compactMap(\.order) == [0, 1, 2])
        #expect(!draft.removingConfiguredWorkouts(for: 2))

        let exercise = makeExercise(name: "Row")
        _ = draft.templateWorkoutDraftsValue[2].addTemplateExerciseDraft(exercise: exercise)

        #expect(draft.removingConfiguredWorkouts(for: 2))

        draft.setWorkoutsPerWeek(2)
        #expect(draft.templateWorkoutDrafts.count == 2)
        #expect(draft.templateWorkoutDrafts.compactMap(\.order) == [0, 1])
    }

    @Test("Template workout exercises reject duplicates and preserve order")
    func templateExerciseOrdering() {
        let row = makeExercise(name: "Row")
        let press = makeExercise(name: "Press")
        var workout = TemplateWorkoutDraft(order: 0)

        let firstRow = workout.addTemplateExerciseDraft(exercise: row)
        let duplicateRow = workout.addTemplateExerciseDraft(exercise: row)
        let firstPress = workout.addTemplateExerciseDraft(exercise: press)
        #expect(firstRow != nil)
        #expect(duplicateRow == nil)
        #expect(firstPress != nil)

        workout.moveTemplateExercises(from: IndexSet(integer: 0), to: 2)

        #expect(workout.templateExerciseDrafts.compactMap(\.exercise).first === press)
        #expect(workout.templateExerciseDrafts.compactMap(\.order) == [0, 1])

        workout.removeTemplateExercises(at: IndexSet(integer: 0))
        #expect(workout.templateExerciseDrafts.count == 1)
        #expect(workout.templateExerciseDrafts.first?.order == 0)
    }

    @Test("A valid template draft creates an ordered persistent graph")
    func templateDraftFactoryAndPersistence() throws {
        let container = PowerJackSeed.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = makeExercise(name: "Row")
        context.insert(exercise)

        var draft = TemplateProgramDraft()
        draft.templateName = "  Pull Days  "
        draft.templateMuscleFocus = [.back, .biceps]
        draft.setWorkoutsPerWeek(2)
        _ = draft.templateWorkoutDraftsValue[0].addTemplateExerciseDraft(exercise: exercise)
        _ = draft.templateWorkoutDraftsValue[1].addTemplateExerciseDraft(exercise: exercise)

        #expect(draft.canSave)

        let templateProgram = try #require(draft.makeTemplateProgram())
        try context.insertAndSave(templateProgram)

        let storedTemplates = try context.fetch(FetchDescriptor<TemplateProgram>())
        let storedTemplate = try #require(storedTemplates.first)
        #expect(storedTemplate.templateName == "Pull Days")
        #expect(storedTemplate.templateWorkouts.map(\.order) == [0, 1])
        #expect(storedTemplate.templateWorkouts.allSatisfy { $0.templateExercises.count == 1 })
    }

    @Test("Programs build requested weeks and all first-week template workouts")
    func programFactoryBuildsRequestedShape() throws {
        for weekCount in [2, 8, 12] {
            for workoutCount in 2...6 {
                let templateProgram = makeTemplateProgram(workoutCount: workoutCount)
                let draft = ProgramDraft(
                    programLengthWeeks: weekCount,
                    templateProgram: templateProgram
                )

                let program = try #require(draft.makeProgram())
                #expect(program.programLengthWeeks == weekCount)
                #expect(program.programWeeks.count == weekCount)
                #expect(program.programWeeks.first?.workouts.count == workoutCount)
                #expect(program.programWeeks.dropFirst().allSatisfy { $0.workouts.isEmpty })
                #expect(program.programWeeks.first?.workouts.allSatisfy {
                    $0.workoutExercises.count == 1 &&
                    $0.workoutExercises[0].workoutSets.count == 2
                } == true)
                #expect(program.nextWorkout != nil)
            }
        }
    }

    @Test("Program lengths are clamped to the supported domain")
    func programLengthClamping() {
        let templateProgram = makeTemplateProgram(workoutCount: 2)

        #expect(Program(programLengthWeeks: 0, templateProgram: templateProgram).programLengthWeeks == 1)
        #expect(Program(programLengthWeeks: 20, templateProgram: templateProgram).programLengthWeeks == 12)
    }

    @Test("New exercise and program roots persist in SwiftData")
    func newRootPersistence() throws {
        let container = PowerJackSeed.makeInMemoryContainer()
        let context = container.mainContext

        let exercise = makeExercise(name: "Row")
        try context.insertAndSave(exercise)

        let templateProgram = makeTemplateProgram(
            workoutCount: 2,
            exercise: exercise
        )
        try context.insertAndSave(templateProgram)

        let program = Program(
            programLengthWeeks: 2,
            templateProgram: templateProgram
        )
        try context.insertAndSave(program)

        #expect(try context.fetch(FetchDescriptor<Exercise>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<TemplateProgram>()).count == 1)

        let storedPrograms = try context.fetch(FetchDescriptor<Program>())
        let storedProgram = try #require(storedPrograms.first)
        #expect(storedProgram.programWeeks.count == 2)
        #expect(storedProgram.programWeeks.first?.workouts.count == 2)
    }

    private func makeExercise(name: String) -> Exercise {
        Exercise(
            exerciseName: name,
            exerciseEquipment: .cable,
            primaryMuscleFocus: .back
        )
    }

    private func makeTemplateProgram(
        workoutCount: Int,
        exercise: Exercise? = nil
    ) -> TemplateProgram {
        let exercise = exercise ?? makeExercise(name: "Row")
        let templateProgram = TemplateProgram(
            templateName: "Test Template",
            workoutsPerWeek: workoutCount,
            templateMuscleFocus: [.back]
        )

        templateProgram.templateWorkoutsValue = (0..<workoutCount).map { order in
            let workout = TemplateWorkout(order: order)
            workout.templateExercisesValue = [
                TemplateExercise(exercise: exercise, order: 0),
            ]
            return workout
        }

        return templateProgram
    }
}
