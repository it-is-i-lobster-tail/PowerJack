//
//  BuildPlannerTests.swift
//  PowerJackTests
//
//  Build programs running on the Build engine through SwiftData: weeks, blocks, seeds and breaks.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct BuildPlannerTests {
    /// Held by the suite instance so models stay valid for the whole test.
    private let container = PowerJackSeed.makeInMemoryContainer()

    @Test("A Build program's week 1 is block week 1, aiming for 3 reps left while it finds each weight")
    func firstWeek() throws {
        let program = try makeProgram(weeks: 2)
        let week = try #require(program.programWeeks.first)
        let exercise = try #require(week.workouts.first?.workoutExercises.first)

        #expect(week.weekKind == .build)
        #expect(week.blockWeek == 1)
        #expect(exercise.rirTarget == 3)
        #expect(exercise.progressionCode == BuildReason.Code.calibrate.rawValue)
        #expect(exercise.progressionNote?.isEmpty == false)
        #expect(exercise.workingSets.allSatisfy { $0.weightTenthsPlannedPounds == nil })
    }

    @Test("BLK-02: in a 10-week program, four logged build weeks are followed by a deload, then a new block")
    func blockOfFive() throws {
        let program = try makeProgram(weeks: 10)
        for _ in 0..<5 {
            try finishWeek(of: program, reps: 10, weightTenthsPounds: 1000, repsLeft: .two)
        }
        let weeks = program.programWeeks
        #expect(weeks.prefix(6).map(\.weekKind) == [.build, .build, .build, .build, .deload, .build])
        #expect(weeks.prefix(6).map(\.blockWeek) == [1, 2, 3, 4, 5, 1])

        let deload = try #require(weeks[4].workouts.first?.workoutExercises.first)
        #expect(deload.progressionCode == BuildReason.Code.deloadPlanned.rawValue)
        #expect(deload.rirTarget == 3)
        let lastBuild = try #require(weeks[3].workouts.first?.workoutExercises.first)
        #expect(deload.workingSets.count <= lastBuild.workingSets.count)
        let deloadLoad = try #require(deload.workingSets.first?.weightTenthsPlannedPounds)
        #expect(deloadLoad < (lastBuild.workingSets.first?.weightTenthsPlannedPounds ?? 0))
    }

    @Test("Blocks fit the program's length, so every length but 2 weeks ends on a deload", arguments: [
        (2, "BB"), (4, "BBBD"), (6, "BBBBBD"), (8, "BBBDBBBD"), (10, "BBBBDBBBBD"), (12, "BBBBBDBBBBBD"),
    ])
    func blocksFitTheLength(weeks: Int, layout: String) throws {
        let program = try makeProgram(weeks: weeks)
        for _ in 0..<weeks {
            try finishWeek(of: program, reps: 10, weightTenthsPounds: 1000, repsLeft: .two)
        }
        let kinds = program.programWeeks.map { $0.weekKind == .deload ? "D" : "B" }.joined()
        #expect(kinds == layout)
    }

    @Test("EFF-01: reps left ramp 3, 2, then 1 in the last build week, however long the block")
    func aimsStretchToTheBlock() throws {
        let program = try makeProgram(weeks: 6)
        for _ in 0..<5 {
            try finishWeek(of: program, reps: 10, weightTenthsPounds: 1000, repsLeft: .two)
        }
        let aims = program.programWeeks.compactMap { $0.workouts.first?.workoutExercises.first?.rirTarget }
        #expect(aims == [3, 2, 2, 2, 1, 3])
    }

    @Test("START-04: an exercise lifted in an earlier program starts from those sets")
    func seededFromHistory() throws {
        let first = try makeProgram(weeks: 1)
        try finishWeek(of: first, reps: 10, weightTenthsPounds: 1000, repsLeft: .three)
        #expect(first.status == .complete)

        let bench = try #require(try benchExercise())
        let second = try makeProgram(weeks: 1, exercise: bench)
        let exercise = try #require(second.programWeeks.first?.workouts.first?.workoutExercises.first)
        #expect(exercise.progressionCode == BuildReason.Code.startHistory.rawValue)
        #expect(exercise.workingSets.map(\.weightTenthsPlannedPounds) == [1000, 1000])
        #expect(exercise.workingSets.map(\.repsPlanned) == [10, 10])
    }

    @Test("BLK-07: the first workout after 4 weeks off becomes a lighter return week with half the sets")
    func breakStartsReturnWeek() throws {
        let program = try makeProgram(weeks: 3)
        try finishWeek(of: program, reps: 10, weightTenthsPounds: 1000, repsLeft: .three)
        let weekTwo = try #require(program.nextWorkout)
        let planned = try #require(weekTwo.workoutExercises.first)
        let plannedLoad = try #require(planned.workingSets.first?.weightTenthsPlannedPounds)
        let plannedSets = planned.workingSets.count

        program.prepareToStart(weekTwo, at: .now.addingTimeInterval(30 * 86_400))

        let week = try #require(program.programWeek(containing: weekTwo))
        #expect(week.weekKind == .return)
        #expect(week.returnBand == 2)
        let exercise = try #require(weekTwo.workoutExercises.first)
        #expect(exercise.progressionCode == BuildReason.Code.returnWeek.rawValue)
        #expect(exercise.workingSets.count == (plannedSets + 1) / 2)
        #expect(exercise.workingSets.first?.weightTenthsPlannedPounds == BuildEngine.floorToStep(Double(plannedLoad) * 0.9))
        #expect(exercise.warmupSets.count == WorkoutExercise.initialWarmupSets)

        // It runs once a week.
        program.prepareToStart(weekTwo, at: .now.addingTimeInterval(31 * 86_400))
        #expect(exercise.workingSets.count == (plannedSets + 1) / 2)
    }

    @Test("CLOCK 0: a break in the second return week is caught, and the return starts from the return weeks' loads")
    func breakDuringSecondReturnWeek() throws {
        let program = try makeProgram(weeks: 4)
        let start = Date.now
        try finishWeek(of: program, reps: 10, weightTenthsPounds: 1000, repsLeft: .three, at: start)
        // 90 days off: return week 1 at 80%, then return week 2 with full sets.
        let returnStart = start.addingTimeInterval(90 * 86_400)
        program.prepareToStart(try #require(program.nextWorkout), at: returnStart)
        try finishWeek(of: program, reps: 10, weightTenthsPounds: 1000, repsLeft: .three, at: returnStart)
        let weekThree = try #require(program.nextWorkout)
        #expect(program.programWeek(containing: weekThree)?.weekKind == .return)
        #expect(program.programWeek(containing: weekThree)?.blockWeek == 2)

        // Five more weeks off before it: a band 2 return from the return weeks' 80 lb, not the 100 lb before.
        program.prepareToStart(weekThree, at: returnStart.addingTimeInterval(35 * 86_400))
        let week = try #require(program.programWeek(containing: weekThree))
        #expect(week.weekKind == .return)
        #expect(week.blockWeek == 1)
        #expect(week.returnBand == 2)
        let exercise = try #require(weekThree.workoutExercises.first)
        #expect(exercise.workingSets.count == 1)
        #expect(exercise.workingSets.first?.weightTenthsPlannedPounds == 700)
    }

    @Test("START-04: a seed from history never passes the heaviest load a set can log")
    func seedWithinLimit() throws {
        let first = try makeProgram(weeks: 1)
        try finishWeek(of: first, reps: 20, weightTenthsPounds: 10_000, repsLeft: .four)
        let bench = try #require(try benchExercise())
        let second = try makeProgram(weeks: 1, exercise: bench)
        let exercise = try #require(second.programWeeks.first?.workouts.first?.workoutExercises.first)
        #expect(exercise.progressionCode == BuildReason.Code.startHistory.rawValue)
        #expect(exercise.workingSets.map(\.weightTenthsPlannedPounds) == [10_000, 10_000])
    }

    @Test("A short gap leaves the week alone")
    func shortGapKeepsWeek() throws {
        let program = try makeProgram(weeks: 2)
        try finishWeek(of: program, reps: 10, weightTenthsPounds: 1000, repsLeft: .three)
        let weekTwo = try #require(program.nextWorkout)
        let before = weekTwo.workoutExercises.first?.workingSets.map(\.weightTenthsPlannedPounds)

        program.prepareToStart(weekTwo, at: .now.addingTimeInterval(10 * 86_400))

        #expect(program.programWeek(containing: weekTwo)?.weekKind == .build)
        #expect(weekTwo.workoutExercises.first?.workingSets.map(\.weightTenthsPlannedPounds) == before)
    }

    @Test("RIR-01: Build feedback asks for reps left and saves them on the version 2 scale")
    func feedbackDraft() throws {
        let program = try makeProgram(weeks: 1)
        let exercise = try #require(program.programWeeks.first?.workouts.first?.workoutExercises.first)
        #expect(exercise.templateType?.ratesRepsInReserve == true)

        var draft = FeedbackDraft(ratesRepsInReserve: true)
        draft.levelOfPain = .mild
        #expect(!draft.canSave)
        draft.repsInReserve = .fiveOrMore
        let feedback = try #require(draft.makeFeedback())
        #expect(feedback.repsInReserve == .fiveOrMore)
        #expect(feedback.effortScaleVersion == RepsInReserve.scaleVersion)
    }

    // MARK: Helpers

    private func benchExercise() throws -> Exercise? {
        try container.mainContext.fetch(FetchDescriptor<Exercise>()).first { $0.exerciseName == "Bench" }
    }

    private func makeProgram(weeks: Int, exercise: Exercise? = nil) throws -> Program {
        let context = container.mainContext
        let bench = exercise ?? Exercise(
            exerciseName: "Bench",
            exerciseEquipment: .barbell,
            primaryMuscleFocus: .chest,
            minReps: 6,
            maxReps: 12,
            fatigueLevel: .high
        )
        if exercise == nil {
            context.insert(bench)
        }
        let template = TemplateProgram(templateName: "Build", workoutsPerWeek: 1, templateMuscleFocus: [.chest])
        template.addTemplateWorkout().addTemplateExercise(exercise: bench)
        context.insert(template)
        let program = Program(programLengthWeeks: weeks, templateProgram: template)
        try context.insertAndSave(program)
        program.start()
        return program
    }

    /// Logs every working set as given with reps-left feedback and finishes the week's workout.
    private func finishWeek(
        of program: Program,
        reps: Int,
        weightTenthsPounds: Int,
        repsLeft: RepsInReserve,
        at date: Date = .now
    ) throws {
        let workout = try #require(program.nextWorkout)
        if workout.status == .planned { workout.startAndCascade() }
        for exercise in workout.workoutExercises {
            exercise.skipWarmups()
            for set in exercise.workingSets {
                set.reps = set.repsPlanned ?? reps
                set.weightTenthsPounds = set.weightTenthsPlannedPounds ?? weightTenthsPounds
                set.complete(at: date)
            }
            exercise.addFeedback(feedback: ExerciseFeedback(repsInReserve: repsLeft, levelOfPain: .none))
            exercise.completeAndCascade()
        }
        program.finishWorkout(workout)
    }
}
