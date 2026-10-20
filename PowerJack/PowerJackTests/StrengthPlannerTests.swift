//
//  StrengthPlannerTests.swift
//  PowerJackTests
//
//  Strengthen programs end to end: week 1, logging, the week's close and the next week's plan,
//  lift records carrying over, breaks, pain and the miss rule. Weights are in pounds: 5 lb steps on a 45 lb bar.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct StrengthPlannerTests {
    private let container = PowerJackSeed.makeInMemoryContainer()
    private var context: ModelContext { container.mainContext }

    init() throws {
        // Every suite that sets the unit sets pounds, so tests running side by side agree.
        UserDefaults.standard.set(WeightUnit.pounds.rawValue, forKey: AppSettings.Key.weightUnit)
        try ExerciseCatalog.seed(in: container.mainContext)
    }

    @Test("Week 1 plans priority lifts by feel: 3 sets at the slot's reps, with the reps-left aim")
    func firstWeekByFeel() throws {
        let program = try makeProgram()
        let squat = try slot("barbell-back-squat", day: 0, in: program)
        #expect(squat.workingSets.count == 3)
        #expect(squat.workingSets.allSatisfy { $0.repsPlanned == 4 && $0.weightTenthsPlannedPounds == nil })
        #expect(squat.rirTarget == 3)
        #expect(squat.progressionNote == "Pick a weight you could lift 7 times. Do 4.")

        // The squat's second slot of the week is the moderate one; curls stay a double progression.
        let moderate = try slot("barbell-back-squat", day: 1, in: program)
        #expect(moderate.workingSets.first?.repsPlanned == 6)
        #expect(moderate.rirTarget == 2)
        let curl = try slot("dumbbell-curl", day: 1, in: program)
        #expect(curl.workingSets.count == 2)
        #expect(curl.rirTarget == nil)
    }

    @Test("Finishing a week logs the lift records and plans the next on the lb grid")
    func weekTwoFromWeekOne() throws {
        let program = try makeProgram()
        try finishWeek(of: program) { id in id == "dumbbell-curl" ? (25, 10) : (300, nil) }

        let logs = try context.fetch(FetchDescriptor<StrengthLog>())
        #expect(logs.count == 1)
        let squatRecord = try #require(logs.first?.state?.lifts["barbell-back-squat"])
        #expect(squatRecord.e1rmKg != nil)
        #expect(squatRecord.calibrationWeeksLeft == 1)

        let squat = try slot("barbell-back-squat", day: 0, in: program, week: 1)
        // 300 lb on target nudges 1.25% to 303.75, so 305 on the 5 lb grid.
        #expect(squat.workingSets.map { $0.weightTenthsPlannedPounds?.pounds } == [305, 305, 305])
        #expect(squat.progressionCode?.hasPrefix("calibration") == true)
        // Planned warmups stay as logged while a lift calibrates (5.7).
        #expect(squat.warmupSets.count == WorkoutExercise.initialWarmupSets)

        // Curls hit 10 reps: a rep more next week.
        let curl = try slot("dumbbell-curl", day: 1, in: program, week: 1)
        #expect(curl.workingSets.map(\.repsPlanned) == [11, 11])
    }

    @Test("A new program loads week 1 from the lift records when its workouts start, with % warmups (2.6, 5.7)")
    func recordsCarryOver() throws {
        var record = StrengthLiftRecord(e1rmKg: 400 * WeightUnit.kilogramsPerPound, calibrationWeeksLeft: 0)
        record.ratedDates = [.now, .now, .now]
        record.lastTrained = .now.addingTimeInterval(-2 * 86_400)
        var state = StrengthState()
        state["barbell-back-squat"] = record
        context.insert(StrengthLog(date: .now, state: state))

        let program = try makeProgram()
        let workout = try #require(program.nextWorkout)
        program.prepareToStart(workout)

        // 400 × pct(4 + 3) = 341.2, rounded down for a first week.
        let squat = try slot("barbell-back-squat", day: 0, in: program)
        #expect(squat.workingSets.map { $0.weightTenthsPlannedPounds?.pounds } == [340, 340, 340])
        #expect(squat.progressionCode?.hasPrefix("normal") == true)
        #expect(squat.progressionNote == nil)
        #expect(squat.warmupSets.map(\.repsPlanned) == [5, 3, 1])
        #expect(squat.warmupSets.map { $0.weightTenthsPlannedPounds?.pounds } == [170, 240, 290])
    }

    @Test("Five weeks off restarts a lift 10% lighter with a set fewer when its workout starts (12.1, 12.2)")
    func breakReturn() throws {
        var record = StrengthLiftRecord(e1rmKg: 400 * WeightUnit.kilogramsPerPound, calibrationWeeksLeft: 0)
        record.ratedDates = [.now, .now, .now]
        record.lastTrained = .now.addingTimeInterval(-35 * 86_400)
        var state = StrengthState()
        state["barbell-back-squat"] = record
        context.insert(StrengthLog(date: .now, state: state))

        let program = try makeProgram()
        let workout = try #require(program.nextWorkout)
        program.prepareToStart(workout)

        // 341.2 × 0.9 = 307.08, so 305 lb, 2 sets and a rep more in reserve.
        let squat = try slot("barbell-back-squat", day: 0, in: program)
        #expect(squat.progressionCode?.hasPrefix("returnWeek1.2") == true)
        #expect(squat.workingSets.count == 2)
        #expect(squat.workingSets.first?.weightTenthsPlannedPounds?.pounds == 305)
        #expect(squat.rirTarget == 4)
    }

    @Test("Severe pain puts the lift's next session behind a check-in with the Lighter plan (15.4)")
    func severePainCheckIn() throws {
        let program = try makeProgram()
        let dayOne = try #require(program.nextWorkout)
        try log(dayOne, in: program, pain: { $0 == "barbell-back-squat" ? .severe : LevelOfPain.none }) { id in
            id == "dumbbell-curl" ? (25, 10) : (300, nil)
        }

        let dayTwo = try #require(program.nextWorkout)
        program.prepareToStart(dayTwo)
        dayTwo.startAndCascade()
        let squat = try slot("barbell-back-squat", day: 1, in: program)
        #expect(squat.checkInPending)
        #expect(squat.workingSets.count == 2)
        #expect((squat.rirTarget ?? 0) >= 3)
        #expect(squat.progressionCode?.hasPrefix("painLighter") == true)
    }

    @Test("A short set lowers the prefilled weight of the sets still to do (6.2)")
    func missRule() throws {
        let program = try makeProgram()
        let workout = try #require(program.nextWorkout)
        program.prepareToStart(workout)
        workout.startAndCascade()
        let squat = try slot("barbell-back-squat", day: 0, in: program)
        for set in squat.workingSets {
            set.weightTenthsPounds = 3000
        }
        let first = try #require(squat.workingSets.first)
        first.reps = 2
        squat.completeSet(first)

        // Two reps short: 300 × 0.92 = 276, so 275 lb for the rest.
        #expect(squat.workingSets.dropFirst().map { $0.weightTenthsPounds?.pounds } == [275, 275])
    }

    @Test("A program's last week still moves the lift records, so the next program starts from it (the weekly loop)")
    func lastWeekCloses() throws {
        let program = try makeProgram(weeks: 1)
        try finishWeek(of: program) { id in id == "dumbbell-curl" ? (25, 10) : (300, nil) }
        #expect(program.status == .complete)

        let logs = try context.fetch(FetchDescriptor<StrengthLog>())
        #expect(logs.count == 1)
        let state = try #require(logs.first?.state)
        #expect(state["barbell-back-squat"].e1rmKg != nil)
        #expect(state.clock.trainedWeeks == 1)
    }

    @Test("Stopping a program partway through a week keeps what was trained, so pain still opens a check-in next program (15.4)")
    func stoppedWeekCloses() throws {
        let program = try makeProgram()
        let dayOne = try #require(program.nextWorkout)
        try log(dayOne, in: program, pain: { $0 == "barbell-back-squat" ? .severe : LevelOfPain.none }) { id in
            id == "dumbbell-curl" ? (25, 10) : (300, nil)
        }
        program.stop()
        program.stopAndCascade()
        let logs = try context.fetch(FetchDescriptor<StrengthLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.state?["barbell-back-squat"].pain.pending == .lighter)

        let next = try makeProgram()
        let workout = try #require(next.nextWorkout)
        next.prepareToStart(workout)
        #expect(try slot("barbell-back-squat", day: 0, in: next).checkInPending)

        // A week stopped before anything in it was trained logs nothing.
        next.stop()
        next.stopAndCascade()
        #expect(try context.fetchCount(FetchDescriptor<StrengthLog>()) == 1)
    }

    @Test("A lift whose first week was skipped before it started still loads from its e1RM (2.6)")
    func skippedFirstWeekLoadsFromRecords() throws {
        var record = StrengthLiftRecord(e1rmKg: 400 * WeightUnit.kilogramsPerPound, calibrationWeeksLeft: 0)
        record.ratedDates = [.now, .now, .now]
        record.lastTrained = .now.addingTimeInterval(-2 * 86_400)
        var state = StrengthState()
        state["barbell-back-squat"] = record
        context.insert(StrengthLog(date: .now.addingTimeInterval(-86_400), state: state))

        let program = try makeProgram()
        for _ in 0..<2 {
            program.skipWorkout(try #require(program.nextWorkout))
        }
        let squat = try slot("barbell-back-squat", day: 0, in: program, week: 1)
        #expect(squat.progressionCode?.hasPrefix("normal") == true)
        #expect(squat.workingSets.allSatisfy { $0.weightTenthsPlannedPounds != nil })
    }

    @Test("Warm-ups follow the working weight down when pain lightens it at the start of a workout (5.7, 15.4)")
    func warmupsFollowPain() throws {
        var record = StrengthLiftRecord(e1rmKg: 400 * WeightUnit.kilogramsPerPound, calibrationWeeksLeft: 0)
        record.ratedDates = [.now, .now, .now]
        record.lastTrained = .now.addingTimeInterval(-2 * 86_400)
        var state = StrengthState()
        state["barbell-back-squat"] = record
        context.insert(StrengthLog(date: .now.addingTimeInterval(-86_400), state: state))

        let program = try makeProgram()
        let dayOne = try #require(program.nextWorkout)
        try log(dayOne, in: program, pain: { $0 == "barbell-back-squat" ? .severe : LevelOfPain.none }) { id in
            id == "dumbbell-curl" ? (25, 10) : (340, nil)
        }
        let dayTwo = try #require(program.nextWorkout)
        program.prepareToStart(dayTwo)

        // The pain floor makes it 6 @ 3, so 400 × pct(9) = 325.2, and Lighter takes 80%: 260 lb, not the 275 lb
        // top warm-up the unlightened 325 lb would have had.
        let squat = try slot("barbell-back-squat", day: 1, in: program)
        #expect(squat.progressionCode?.hasPrefix("painLighter") == true)
        #expect(squat.workingSets.first?.weightTenthsPlannedPounds?.pounds == 260)
        #expect(squat.warmupSets.map { $0.weightTenthsPlannedPounds?.pounds } == [130, 180])
    }

    @Test("A new program takes the deload that is due even when its first workout is skipped before it starts (10.5)")
    func firstWeekTakesTheClock() throws {
        var record = StrengthLiftRecord(e1rmKg: 400 * WeightUnit.kilogramsPerPound, calibrationWeeksLeft: 0)
        record.ratedDates = [.now, .now, .now]
        record.lastTrained = .now.addingTimeInterval(-2 * 86_400)
        var state = StrengthState()
        state["barbell-back-squat"] = record
        state.clock.upcoming = .deload
        state.clock.weeksSinceDeload = 8
        context.insert(StrengthLog(date: .now.addingTimeInterval(-86_400), state: state))

        let program = try makeProgram()
        program.skipWorkout(try #require(program.nextWorkout))
        let dayTwo = try #require(program.nextWorkout)
        program.prepareToStart(dayTwo)
        #expect(program.programWeeks.first?.weekKind == .deload)
        #expect(try slot("barbell-back-squat", day: 1, in: program).progressionCode?.hasPrefix("deload") == true)

        // Skipped whole, the first week still counts as the deload.
        let skipped = try makeProgram()
        for _ in 0..<2 {
            skipped.skipWorkout(try #require(skipped.nextWorkout))
        }
        #expect(StrengthLog.latestState(in: context).clock.weeksSinceDeload == 0)
    }

    @Test("Lighter on an accessory with no logged reps plans the bottom of its range, not 3 reps (15.4)")
    func accessoryLighterReps() throws {
        let curl = try exercise("dumbbell-curl")
        let template = TemplateProgram(templateName: "Curls", workoutsPerWeek: 2, templateMuscleFocus: [.biceps], templateType: .strength)
        for _ in 0..<2 {
            template.addTemplateWorkout().addTemplateExercise(exercise: curl)
        }
        context.insert(template)
        let program = Program(programLengthWeeks: 3, templateProgram: template)
        try context.insertAndSave(program)
        program.start()

        // Week 1: day 2 is skipped, so its curls carry their by-feel plan into week 2.
        try log(try #require(program.nextWorkout), in: program) { _ in (25, 10) }
        program.skipWorkout(try #require(program.nextWorkout))
        // Week 2: Severe pain on day 1 puts day 2's curls behind a check-in.
        try log(try #require(program.nextWorkout), in: program, pain: { _ in .severe }) { _ in (25, 10) }
        let dayTwo = try #require(program.nextWorkout)
        program.prepareToStart(dayTwo)

        let curls = try slot("dumbbell-curl", day: 1, in: program, week: 1)
        #expect(curls.checkInPending)
        #expect(curls.workingSets.map(\.repsPlanned) == [curl.minReps, curl.minReps])
    }

    @Test("Another break during week 2 back starts the return over (12.1)")
    func breakDuringReturn() throws {
        var record = StrengthLiftRecord(e1rmKg: 400 * WeightUnit.kilogramsPerPound, calibrationWeeksLeft: 0)
        record.ratedDates = [.now, .now, .now]
        record.lastTrained = .now.addingTimeInterval(-35 * 86_400)
        var state = StrengthState()
        state["barbell-back-squat"] = record
        context.insert(StrengthLog(date: .now.addingTimeInterval(-86_400), state: state))

        let program = try makeProgram()
        try finishWeek(of: program) { id in id == "dumbbell-curl" ? (25, 10) : (305, nil) }
        #expect(try slot("barbell-back-squat", day: 0, in: program, week: 1).progressionCode?.hasPrefix("returnWeek2") == true)

        let workout = try #require(program.nextWorkout)
        program.prepareToStart(workout, at: .now.addingTimeInterval(20 * 86_400))
        #expect(try slot("barbell-back-squat", day: 0, in: program, week: 1).progressionCode?.hasPrefix("returnWeek1.1") == true)
    }

    @Test("A short set in kilograms lowers the sets still to do by at least a step (6.2)")
    func missRuleInKilograms() throws {
        let program = try makeProgram()
        let workout = try #require(program.nextWorkout)
        try WeightUnit.$pinned.withValue(.kilograms) {
            try StrengthLoadSteps.$pinned.withValue([.barbell: 5]) {
                program.prepareToStart(workout)
                workout.startAndCascade()
                let squat = try slot("barbell-back-squat", day: 0, in: program)
                for set in squat.workingSets {
                    set.weightTenthsPounds = WeightUnit.tenthsPounds(fromKilograms: 60)
                }
                let first = try #require(squat.workingSets.first)
                first.reps = 3
                squat.completeSet(first)
                // 4% off 60 kg is 57.6, which rounds back to 60 on a 5 kg grid, so the cut takes a whole step to 55.
                #expect(squat.workingSets.dropFirst().map { $0.weightTenthsPounds } == Array(repeating: WeightUnit.tenthsPounds(fromKilograms: 55), count: 2))
            }
        }
    }

    @Test("Priority lifts rest 3:00 and their close variants 2:15; other exercises keep their own rest (5.6)")
    func restDefaults() throws {
        let program = try makeProgram()
        #expect(try slot("barbell-back-squat", day: 0, in: program).restDuration == .seconds(180))
        #expect(try slot("barbell-front-squat", day: 1, in: program).restDuration == .seconds(135))
        let curl = try slot("dumbbell-curl", day: 1, in: program)
        #expect(curl.restDuration == curl.exercise?.restDuration)
    }

    // MARK: Helpers

    /// Day 1: squat, bench. Day 2: squat, front squat, curl.
    private func makeProgram(weeks: Int = 4) throws -> Program {
        let template = TemplateProgram(templateName: "Strong", workoutsPerWeek: 2, templateMuscleFocus: [.quads], templateType: .strength)
        let dayOne = template.addTemplateWorkout()
        for id in ["barbell-back-squat", "barbell-bench-press"] {
            dayOne.addTemplateExercise(exercise: try exercise(id))
        }
        let dayTwo = template.addTemplateWorkout()
        for id in ["barbell-back-squat", "barbell-front-squat", "dumbbell-curl"] {
            dayTwo.addTemplateExercise(exercise: try exercise(id))
        }
        context.insert(template)
        let program = Program(programLengthWeeks: weeks, templateProgram: template)
        try context.insertAndSave(program)
        program.start()
        return program
    }

    private func exercise(_ id: String) throws -> Exercise {
        try #require(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.catalogID == id })).first)
    }

    private func slot(_ id: String, day: Int, in program: Program, week: Int = 0) throws -> WorkoutExercise {
        let workout = try #require(program.programWeeks[week].workouts.first { $0.order == day })
        return try #require(workout.workoutExercises.first { $0.exercise?.catalogID == id })
    }

    /// Logs every workout of the current week with `load(catalogID)`: pounds, and reps or the plan's.
    private func finishWeek(of program: Program, load: (String) -> (pounds: Double, reps: Int?)) throws {
        let week = try #require(program.nextWorkout.flatMap { program.programWeek(containing: $0) })
        while let workout = program.nextWorkout, program.programWeek(containing: workout) === week {
            try log(workout, in: program, load: load)
        }
    }

    private func log(
        _ workout: Workout,
        in program: Program,
        pain: (String) -> LevelOfPain = { _ in .none },
        load: (String) -> (pounds: Double, reps: Int?)
    ) throws {
        program.prepareToStart(workout)
        workout.startAndCascade()
        for workoutExercise in workout.workoutExercises {
            let id = workoutExercise.exercise?.catalogID ?? ""
            let (pounds, reps) = load(id)
            for set in workoutExercise.workingSets {
                set.weightTenthsPounds = Int(pounds * 10)
                set.reps = reps ?? set.repsPlanned
                workoutExercise.completeSet(set)
            }
            workoutExercise.addFeedback(feedback: ExerciseFeedback(repsInReserve: .three, levelOfPain: pain(id)))
        }
        program.finishWorkout(workout)
        try context.save()
    }
}

private extension Int {
    var pounds: Double { Double(self) / 10 }
}
