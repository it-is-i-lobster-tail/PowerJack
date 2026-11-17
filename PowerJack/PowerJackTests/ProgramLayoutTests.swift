//
//  ProgramLayoutTests.swift
//  PowerJackTests
//
//  A running program's days can be edited in the template builder. Workouts not started yet and the one in
//  progress change now (keeping anything logged), days already done change from next week, and later weeks
//  follow the edit.
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
        day.startSuperset(with: day.blocks[0])
        day.add(day.blocks[1], to: day.supersets[0])
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
        day.startSuperset(with: day.blocks[0])
        day.add(day.blocks[1], to: day.supersets[0])
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

    @Test("The day in progress changes now: logged exercises keep their sets, new ones are ready to log, and later weeks follow",
          arguments: TemplateCatalog.entries.map(\.name))
    func liveDayChangesNow(templateName: String) throws {
        let (container, template) = try makeTemplate(templateName)
        let program = try startProgram(template, in: container)
        let dayOne = try startNextWorkout(of: program)
        let logged = try #require(dayOne.workoutExercises.first)
        try logSets(of: logged)
        let loggedSets = logged.workoutSets.map { ($0.status, $0.reps, $0.weightTenthsPounds) }
        let untouched = try #require(dayOne.workoutExercises.last)
        let curl = try #require(try container.mainContext.fetch(FetchDescriptor<Exercise>()).first {
            $0.exerciseName == "Dumbbell Curl"
        })

        var draft = ProgramLayoutDraft(program: program)
        #expect(draft.lockedDays.isEmpty)
        #expect(draft.dayNotes == [0: "Day 1 is in progress. Changes start now, and logged exercises stay."])
        let loggedDraft = try #require(draft.days.templateWorkoutDraftsValue[0].templateExerciseDrafts.first)
        #expect(draft.loggedExercises == [loggedDraft.id])

        var day = draft.days.templateWorkoutDraftsValue[0]
        day.removeTemplateExercises(at: IndexSet(integer: day.templateExerciseDrafts.count - 1))
        day.addTemplateExerciseDraft(exercise: curl)
        day.moveTemplateExercises(from: IndexSet(integer: day.templateExerciseDrafts.count - 1), to: 1)
        draft.days.templateWorkoutDraftsValue[0] = day
        draft.apply()
        try container.mainContext.save()

        let expected = day.templateExerciseDrafts.map(\.exercise.exerciseName)
        #expect(dayOne.status == .active)
        #expect(dayOne.workoutExercises.compactMap(\.exercise?.exerciseName) == expected)
        #expect(!dayOne.workoutExercises.contains { $0 === untouched })
        #expect(dayOne.workoutExercises[0] === logged)
        #expect(logged.workoutSets.map { ($0.status, $0.reps, $0.weightTenthsPounds) }.elementsEqual(loggedSets) { $0 == $1 })
        let added = dayOne.workoutExercises[1]
        #expect(added.exercise === curl)
        #expect(added.status == .active)
        #expect(added.workingSets.count == WorkoutExercise.initialSets)
        #expect(added.workoutSets.allSatisfy { $0.status == .active })

        // Applying again changes nothing.
        let before = dayOne.workoutExercises.map(ObjectIdentifier.init)
        draft.apply()
        #expect(dayOne.workoutExercises.map(ObjectIdentifier.init) == before)

        // Finishing the day, then every later week's day one, keeps the edit.
        for workoutExercise in dayOne.workoutExercises {
            try logSets(of: workoutExercise)
        }
        program.finishWorkout(dayOne)
        try container.mainContext.save()
        #expect(dayOne.workoutExercises[0].workoutSets.map { ($0.status, $0.reps, $0.weightTenthsPounds) }
            .elementsEqual(loggedSets) { $0 == $1 })
        while let workout = program.nextWorkout {
            try finishNextWorkout(of: program)
            guard let week = program.programWeek(containing: workout), week.order > 0, workout.order == 0 else { continue }
            #expect(workout.workoutExercises.compactMap(\.exercise?.exerciseName) == expected, "\(templateName) week \(week.order + 1)")
            #expect(workout.workoutExercises.allSatisfy { !$0.workingSets.isEmpty }, "\(templateName) week \(week.order + 1)")
        }
        #expect(program.status == .complete)
    }

    @Test("An exercise with logged sets stays in the day in progress, even when an edit leaves it out")
    func loggedExerciseStays() throws {
        let (container, template) = try makeTemplate("Full Body")
        let program = try startProgram(template, in: container)
        let dayOne = try startNextWorkout(of: program)
        let logged = try #require(dayOne.workoutExercises.dropFirst().first)
        try logSets(of: logged)
        let names = dayOne.workoutExercises.compactMap(\.exercise?.exerciseName)
        let setCount = logged.workoutSets.count

        // Like copying an empty day over it with Replace.
        var draft = ProgramLayoutDraft(program: program)
        let all = IndexSet(draft.days.templateWorkoutDraftsValue[0].templateExerciseDrafts.indices)
        draft.days.templateWorkoutDraftsValue[0].removeTemplateExercises(at: all)
        draft.apply()
        try container.mainContext.save()

        #expect(dayOne.workoutExercises.count == 1)
        #expect(dayOne.workoutExercises.first === logged)
        #expect(logged.workoutSets.count == setCount)
        #expect(logged.completedWorkingSets == logged.workingSets.count)
        // The builder shows what the workout kept.
        let shown = draft.days.templateWorkoutDraftsValue[0].templateExerciseDrafts
        #expect(shown.map(\.exercise.exerciseName) == [names[1]])
        #expect(draft.loggedExercises == Set(shown.map(\.id)))
    }

    @Test("A skipped exercise in the day in progress stays too")
    func skippedExerciseStays() throws {
        let (container, template) = try makeTemplate("Full Body")
        let program = try startProgram(template, in: container)
        let dayOne = try startNextWorkout(of: program)
        let skipped = try #require(dayOne.workoutExercises.first)
        skipped.skipAndCascade()

        var draft = ProgramLayoutDraft(program: program)
        draft.days.templateWorkoutDraftsValue[0].removeTemplateExercises(at: IndexSet(integer: 0))
        draft.apply()

        #expect(dayOne.workoutExercises.first === skipped)
    }

    @Test("A stacked superset in the day in progress takes effect now")
    func liveDaySupersets() throws {
        let (container, template) = try makeTemplate("Full Body")
        let program = try startProgram(template, in: container)
        let dayOne = try startNextWorkout(of: program)

        var draft = ProgramLayoutDraft(program: program)
        var day = draft.days.templateWorkoutDraftsValue[0]
        day.startSuperset(with: day.blocks[0])
        day.add(day.blocks[1], to: day.supersets[0])
        draft.days.templateWorkoutDraftsValue[0] = day
        draft.apply()
        try container.mainContext.save()

        #expect(dayOne.workoutExercises[0].supersetPartners.first === dayOne.workoutExercises[1])
    }

    @Test("An edit to the day in progress replaces one saved for next week before it started")
    func liveEditClearsNextWeekEdit() throws {
        let (container, template) = try makeTemplate("Full Body")
        let program = try startProgram(template, in: container)
        let dayOne = try startNextWorkout(of: program)
        let first = try #require(dayOne.workoutExercises.first?.exercise)
        dayOne.setNextWeekLayout([(exercise: first, supersetID: nil)])

        var draft = ProgramLayoutDraft(program: program)
        draft.apply()
        #expect(dayOne.nextWeekLayout != nil, "Opening and saving without a change keeps it")

        draft.days.templateWorkoutDraftsValue[0].removeTemplateExercises(at: IndexSet(integer: 0))
        draft.apply()
        #expect(dayOne.nextWeekLayout == nil)
    }

    @Test("In the program's last week, the day in progress can still be edited")
    func lastWeekLiveDayOpens() throws {
        let (container, template) = try makeTemplate("Full Body")
        let program = try startProgram(template, in: container, weeks: 1)
        try finishNextWorkout(of: program)
        _ = try startNextWorkout(of: program)

        let draft = ProgramLayoutDraft(program: program)

        #expect(draft.lockedDays.keys.sorted() == [0])
        #expect(draft.dayNotes[1] == "Day 2 is in progress. Changes start now, and logged exercises stay.")
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

    /// Starts the next workout, as Start Workout does.
    private func startNextWorkout(of program: Program) throws -> Workout {
        let workout = try #require(program.nextWorkout)
        program.prepareToStart(workout)
        workout.startAndCascade()
        try program.modelContext?.save()
        return workout
    }

    /// Logs every set still to do at its target, and rates the exercise.
    private func logSets(of workoutExercise: WorkoutExercise) throws {
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
        if workoutExercise.feedback == nil {
            workoutExercise.addFeedback(feedback: ExerciseFeedback(levelOfEffort: .challenge, levelOfPain: .none))
        }
    }

    /// Logs every set of the next workout at its target, rates each exercise, and finishes it.
    private func finishNextWorkout(of program: Program) throws {
        let workout = try startNextWorkout(of: program)
        for workoutExercise in workout.workoutExercises {
            try logSets(of: workoutExercise)
        }
        program.finishWorkout(workout)
        try program.modelContext?.save()
    }
}
