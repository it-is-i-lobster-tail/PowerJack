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
        draft.name = "  Cable Row  "
        draft.equipment = .cable
        draft.primaryMuscle = .back
        draft.secondaryMuscles = [.biceps]

        #expect(draft.canSave)
        #expect(draft.fatigue == Exercise.defaultFatigue)
        draft.fatigue = .heavy

        let exercise = try #require(draft.makeExercise())
        #expect(exercise.exerciseName == "Cable Row")
        #expect(exercise.userCreated)
        #expect(exercise.secondaryMuscles == [.biceps])
        #expect(exercise.fatigue == .heavy)
        #expect(ExerciseDraft(exercise: exercise).fatigue == .heavy)

        draft.name = String(repeating: "x", count: maxExerciseNameLengthInput + 1)
        #expect(!draft.canSave)

        draft.name = "Pulldown"
        draft.primaryMuscle = .shoulders
        draft.fatigue = .light
        let didApply = draft.apply(to: exercise)
        #expect(didApply)
        #expect(exercise.exerciseName == "Pulldown")
        #expect(exercise.primaryMuscleFocus == .shoulders)
        #expect(exercise.fatigue == .light)
        #expect(exercise.restDuration == .seconds(75))
    }

    @Test("Exercise drafts cap rep ranges at 30 and keep min at or below max")
    func exerciseDraftRepRange() throws {
        var draft = ExerciseDraft()
        draft.name = "Cable Row"
        draft.equipment = .cable
        draft.primaryMuscle = .back
        #expect(draft.canSave)
        #expect(draft.minReps == Exercise.defaultMinReps && draft.maxReps == Exercise.defaultMaxReps)

        draft.maxReps = 31
        #expect(!draft.canSave)
        draft.maxReps = 30
        #expect(draft.canSave)
        draft.minReps = 0
        #expect(!draft.canSave)
        draft.minReps = 20
        draft.maxReps = 15
        #expect(!draft.canSave)
        draft.maxReps = 25

        let exercise = try #require(draft.makeExercise())
        #expect(exercise.repRange == 20...25)

        draft.minReps = 6
        draft.maxReps = 10
        #expect(draft.apply(to: exercise))
        #expect(exercise.repRange == 6...10)
    }

    @Test("Template workout counts stay ordered and retain disabled days")
    func templateWorkoutCountSynchronization() {
        var draft = TemplateProgramDraft()
        draft.workoutsPerWeek = 3

        #expect(draft.templateWorkoutDrafts.count == 3)
        #expect(draft.templateWorkoutDrafts.compactMap(\.order) == [0, 1, 2])

        let exercise = makeExercise(name: "Row")
        _ = draft.templateWorkoutDraftsValue[2].addTemplateExerciseDraft(exercise: exercise)


        draft.workoutsPerWeek = 2
        #expect(draft.templateWorkoutDrafts.count == 2)
        #expect(draft.templateWorkoutDrafts.map(\.order) == [0, 1])
        draft.workoutsPerWeek = 3
        #expect(draft.templateWorkoutDrafts[2].templateExerciseDrafts.first?.exercise === exercise)
    }

    @Test("Template workout exercises preserve order")
    func templateExerciseOrdering() {
        let row = makeExercise(name: "Row")
        let press = makeExercise(name: "Press")
        var workout = TemplateWorkoutDraft(enabled: true, order: 0, templateExercises: nil)

        let firstRow = workout.addTemplateExerciseDraft(exercise: row)
        let firstPress = workout.addTemplateExerciseDraft(exercise: press)
        #expect(firstRow != nil)
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
        draft.workoutsPerWeek = 2
        _ = draft.templateWorkoutDraftsValue[0].addTemplateExerciseDraft(exercise: exercise)
        _ = draft.templateWorkoutDraftsValue[1].addTemplateExerciseDraft(exercise: exercise)

        #expect(draft.canSave)

        let templateProgram = try #require(draft.makeTemplate())
        try context.insertAndSave(templateProgram)

        let storedTemplates = try context.fetch(FetchDescriptor<TemplateProgram>())
        let storedTemplate = try #require(storedTemplates.first)
        #expect(storedTemplate.templateName == "Pull Days")
        #expect(storedTemplate.templateWorkouts.map(\.order) == [0, 1])
        #expect(storedTemplate.templateWorkouts.allSatisfy { $0.templateExercises.count == 1 })
    }

    @Test("Applying template edits rebuilds workouts only when exercises change, without orphans")
    func templateDraftApplyRebuildsOnlyOnLayoutChange() throws {
        let container = PowerJackSeed.makeInMemoryContainer()
        let context = container.mainContext
        let row = makeExercise(name: "Row")
        let curl = makeExercise(name: "Curl")
        context.insert(row)
        context.insert(curl)
        let template = makeTemplateProgram(workoutCount: 2, exercise: row)
        try context.insertAndSave(template)
        let originalWorkouts = template.templateWorkouts.map(\.persistentModelID)

        // A rename keeps the same workout rows.
        var draft = TemplateProgramDraft(templateProgram: template)
        draft.templateName = "Renamed"
        #expect(draft.apply(to: template))
        try context.save()
        #expect(template.templateName == "Renamed")
        #expect(template.templateWorkouts.map(\.persistentModelID) == originalWorkouts)

        // Adding an exercise rebuilds the workouts and deletes the old rows.
        _ = draft.templateWorkoutDraftsValue[0].addTemplateExerciseDraft(exercise: curl)
        #expect(draft.apply(to: template))
        try context.save()
        #expect(template.templateWorkouts[0].templateExercises.map(\.exercise.exerciseName) == ["Row", "Curl"])
        #expect(try context.fetchCount(FetchDescriptor<TemplateWorkout>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<TemplateExercise>()) == 3)
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
                #expect(program.nextWorkout == nil)
                program.start()
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
