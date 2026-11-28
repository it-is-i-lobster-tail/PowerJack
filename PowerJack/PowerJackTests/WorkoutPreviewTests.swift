import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct WorkoutPreviewTests {
    @Test("Five of six prior occurrences earn a reminder, with one vote per day")
    func learnsFromDistinctOccurrences() throws {
        let calendar = try calendar()
        let today = date("2026-11-24T12:00:00Z")
        let weeks = [1, 2, 3, 4, 6]
        let starts = try weeks.enumerated().map { index, week in
            try start(weeksAgo: week, hour: 17, minute: index * 10, before: today, calendar: calendar)
        }
        let fewer = Array(starts.dropLast()) + [starts[0], starts[1]]
        #expect(predict(fewer, now: today, calendar: calendar) == nil)

        let prediction = try #require(predict(starts, now: today, calendar: calendar))
        #expect(prediction.workout == date("2026-11-24T17:20:00Z"))
        #expect(prediction.send == date("2026-11-24T14:20:00Z"))
        #expect(prediction.title(calendar: calendar) == "Tonight’s lift")
    }

    @Test("Morning reminders use the chosen evening time and skip elapsed send times")
    func morningLead() throws {
        let calendar = try calendar()
        let morning = date("2026-11-25T06:00:00Z")
        let now = date("2026-11-24T18:00:00Z")
        let starts = try (1...6).map { week in
            try start(weeksAgo: week, hour: 6, before: morning, calendar: calendar)
        }

        let prediction = try #require(predict(starts, now: now, calendar: calendar, eveningMinute: 19 * 60 + 30))
        #expect(prediction.workout == morning)
        #expect(prediction.send == date("2026-11-24T19:30:00Z"))
        #expect(prediction.nightBefore)
        let later = predict(starts, now: date("2026-11-24T21:00:00Z"), calendar: calendar)
        #expect(later.map { $0.workout > morning } ?? true)
    }

    @Test("Historical replay ignores future starts and skips a day the lifter already trained")
    func historicalReplay() throws {
        let calendar = try calendar()
        let now = date("2026-11-24T12:00:00Z")
        let history = try (1...6).map { week in
            try start(weeksAgo: week, hour: 18, before: now, calendar: calendar)
        }
        let future = date("2026-11-24T18:00:00Z")
        #expect(predict(Array(history.prefix(4)) + [future], now: now, calendar: calendar) == nil)
        #expect(predict(history + [future], now: now, calendar: calendar)?.workout == future)
        let earlierToday = date("2026-11-24T10:00:00Z")
        #expect(predict(history + [earlierToday], now: now, calendar: calendar)?.workout != future)
    }

    @Test("Prediction uses the selected local calendar across the end of daylight saving time")
    func localTime() throws {
        let calendar = try calendar(zone: "America/Los_Angeles")
        let now = date("2026-11-03T19:00:00Z")
        let starts = try (1...6).map { week in
            try start(weeksAgo: week, hour: 18, before: now, calendar: calendar)
        }
        let prediction = try #require(predict(starts, now: now, calendar: calendar))
        #expect(prediction.workout == date("2026-11-04T02:00:00Z"))
        #expect(prediction.send == date("2026-11-03T23:00:00Z"))
    }

    @Test("Archived session sets count once and only real bench work can set the record")
    func realBenchHistory() throws {
        let start = date("2026-11-10T18:00:00Z")
        let end = start.addingTimeInterval(1800)
        let bench = HistoryRow(
            week: 1, day: 1, workoutStatus: "Complete", workoutStarted: start, workoutEnded: end,
            exerciseKey: WorkoutPreviewHistory.benchKey, equipment: "Barbell", setType: "Working",
            setStatus: Status.complete.rawValue.capitalized, reps: 5, weightTenthsPounds: 2250,
            setLogged: start.addingTimeInterval(600)
        )
        var warmup = bench
        warmup.setType = "Warmup"
        warmup.weightTenthsPounds = 4000
        var automatic = bench
        automatic.setLogged = end
        automatic.weightTenthsPounds = 5000
        var incline = bench
        incline.exerciseKey = "catalog:incline-barbell-bench-press"
        incline.weightTenthsPounds = 3000

        let history = WorkoutPreviewHistory(rows: [bench, bench, warmup, automatic, incline], now: end)
        #expect(history.starts == [start])
        let logged = try #require(history.sessions.first).logged
        let benchSets = logged.filter { $0.exerciseKey == WorkoutPreviewHistory.benchKey }
        #expect(benchSets.map(\.weightTenthsPounds).compactMap { $0 }.max() == 2250)
        #expect(WorkoutPreviewHistory(rows: [automatic], now: end).starts.isEmpty)
    }

    @Test("A bench opportunity requires a prior record and a gain of at least two percent")
    func benchThreshold() throws {
        let container = PowerJackSeed.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(exerciseName: "Bench Press", exerciseEquipment: .barbell, primaryMuscleFocus: .chest)
        exercise.catalogID = StrengthLifts.benchID
        let template = TemplateProgram(templateName: "Bench Day", workoutsPerWeek: 1, templateMuscleFocus: [.chest],
                                       templateType: .hypertrophy)
        template.addTemplateWorkout().addTemplateExercise(exercise: exercise)
        context.insert(template)
        let program = Program(programLengthWeeks: 2, templateProgram: template)
        try context.insertAndSave(program)
        program.start()
        let workout = try #require(program.nextWorkout)
        let bench = try #require(workout.workoutExercises.first)
        let now = Date()
        let previous = HistoryRow(workoutStatus: "Complete", workoutStarted: now.addingTimeInterval(-3600),
                                  workoutEnded: now.addingTimeInterval(-1800), exerciseKey: WorkoutPreviewHistory.benchKey,
                                  equipment: Equipment.barbell.displayName, setType: "Working", setStatus: "Complete",
                                  reps: 5, weightTenthsPounds: 2250, setLogged: now.addingTimeInterval(-2400))
        func selected(_ rows: [HistoryRow]) -> WorkoutAchievement? {
            WorkoutAchievement.selected(preview: WorkoutPreview(program: program, workout: workout),
                                        program: program, workout: workout, history: WorkoutPreviewHistory(rows: rows, now: now), at: now)
        }
        bench.replacePlannedWorkingSets([(5, 2290), (12, 2500)])
        #expect(selected([])?.kind != .strengthPR)
        #expect(selected([previous])?.kind != .strengthPR)
        bench.replacePlannedWorkingSets([(5, 2300)])
        let record = try #require(selected([previous]))
        #expect(record.kind == .strengthPR)
        #expect(record.weight == 2300)
        #expect(record.detail(unit: .pounds).contains("230 lb"))
        #expect(record.detail(unit: .kilograms).contains("104.3 kg"))
    }

    @Test("All program types show their planned working sets and usable fallback copy", arguments: TemplateType.allCases)
    func plannedWorkoutPreview(type: TemplateType) throws {
        let container = PowerJackSeed.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(exerciseName: "Bench Press", exerciseEquipment: .barbell, primaryMuscleFocus: .chest)
        exercise.catalogID = StrengthLifts.benchID
        let template = TemplateProgram(
            templateName: "Bench Day", workoutsPerWeek: 1, templateMuscleFocus: [.chest], templateType: type
        )
        template.addTemplateWorkout().addTemplateExercise(exercise: exercise)
        context.insert(template)
        let program = Program(programLengthWeeks: 2, templateProgram: template)
        try context.insertAndSave(program)
        program.start()
        let workout = try #require(program.nextWorkout)
        let entry = try #require(workout.workoutExercises.first)
        entry.replacePlannedWorkingSets([(5, 2250), (5, 2250), (8, 1850)])
        let preview = WorkoutPreview(program: program, workout: workout)
        let bench = try #require(preview.lifts.first)

        #expect(preview.type == type)
        let facts = WorkoutReminderCopy.Facts(preview: preview, program: program, workout: workout,
                                             timingTitle: "Tonight’s lift", achievement: nil, unit: .pounds)
        #expect(facts.program == "Bench Day")
        #expect(facts.exercises.first?.exercise == "Bench Press")
        #expect(facts.prompt.contains("225 lb"))
        #expect(facts.trainingStyle == type.name)
        #expect(facts.exercises.first?.lastLoggedWork == nil)
        #expect(facts.achievementContext == nil)
        #expect(WorkoutReminderCopy.validSummary("Bench pressing leads tonight’s work.", for: facts))
        #expect(!WorkoutReminderCopy.validSummary("Explain the main lift in one short sentence.", for: facts))
        let sets = bench.sets.map { $0.text(unit: .pounds) }
        if type == .hypertrophy {
            #expect(sets == ["2 × 5 at 225 lb", "1 × 8 at 185 lb"])
        } else {
            #expect(sets == ["1 × 5 at 225 lb", "1 × 5 at 225 lb", "1 × 8 at 185 lb"])
            #expect(bench.sets.map(\.role) == [.top, .backOff, .backOff])
        }
        #expect(WorkoutPreviewCopy.fallback(for: preview, variation: 0).focus.contains("Bench Press"))
        #expect(WorkoutPreviewCopy.fallback(for: preview, variation: 0).tagline !=
                WorkoutPreviewCopy.fallback(for: preview, variation: 1).tagline)
    }

    @Test("Trainer copy receives a volume increase only for a matching hypertrophy slot")
    func increasedLegPressVolume() throws {
        let container = PowerJackSeed.makeInMemoryContainer()
        let exercise = Exercise(exerciseName: "Leg Press", exerciseEquipment: .machine, primaryMuscleFocus: .quads)
        exercise.catalogID = "leg-press"
        let template = TemplateProgram(templateName: "Leg Day", workoutsPerWeek: 1,
                                       templateMuscleFocus: [.quads], templateType: .hypertrophy)
        template.addTemplateWorkout().addTemplateExercise(exercise: exercise)
        container.mainContext.insert(template)
        let program = Program(programLengthWeeks: 2, templateProgram: template)
        try container.mainContext.insertAndSave(program)
        let prior = try #require(program.programWeeks.first?.workouts.first)
        let priorEntry = try #require(prior.workoutExercises.first)
        priorEntry.replacePlannedWorkingSets([(10, 1000), (10, 1000)])
        prior.startAndCascade()
        prior.completeAndCascade()
        let next = try #require(program.programWeeks.last?.addWorkout())
        let entry = try #require(next.addWorkoutExercise(exercise: exercise))
        func facts() -> WorkoutReminderCopy.Facts {
            WorkoutReminderCopy.Facts(preview: WorkoutPreview(program: program, workout: next),
                                      program: program, workout: next, timingTitle: "Tomorrow morning’s lift",
                                      achievement: nil, unit: .pounds)
        }
        entry.replacePlannedWorkingSets([(10, 1000), (10, 1000)])
        #expect(facts().exercises.first?.workingSetCountChange == 0)
        entry.replacePlannedWorkingSets([(10, 1000), (10, 1000), (10, 1000)])
        let increased = facts()
        #expect(increased.exercises.first?.workingSetCountChange == 1)
        #expect(increased.exercises.first?.lastPlannedWork == ["10 reps at 100 lb", "10 reps at 100 lb"])
        #expect(increased.prompt.contains("Leg Press goes from 2 to 3 working sets."))
    }

    @Test("All milestone types work in a starter and a custom template for every training style",
          arguments: TemplateType.allCases, [false, true])
    func achievementMatrix(type: TemplateType, starter: Bool) throws {
        for kind in WorkoutAchievement.Kind.allCases {
            let store = PowerJackStore(inMemory: true)
            let context = store.container!.mainContext
            let now = Date.now
            let program = try WorkoutReminderDemo.seed(kind, type: type, starter: starter, context: context, now: now)
            let planned = try #require(program.nextWorkout)
            let preview = WorkoutPreview(program: program, workout: planned)
            let history = try WorkoutPreviewHistory(programs: [program], in: context, now: .now)
            let result = WorkoutAchievement.selected(preview: preview, program: program, workout: planned, history: history, at: .now)
            #expect(result?.kind == kind, "Expected \(kind) in \(type) (starter: \(starter)); got \(String(describing: result))")
            guard let result else { continue }
            let base = WorkoutReminderCopy.Facts(preview: preview, program: program, workout: planned,
                                                timingTitle: "Tonight’s lift", achievement: nil, history: history)
            let facts = WorkoutReminderCopy.Facts(preview: preview, program: program, workout: planned,
                                                 timingTitle: "Tonight’s lift", achievement: result, history: history)
            #expect(facts.fingerprint != base.fingerprint)
            #expect(facts.achievementContext != nil)
            #expect(!WorkoutReminderCopy.validCheer("Congratulations, you already crushed it!", for: result, unit: .pounds))
            if kind == .extraSet {
                #expect(WorkoutReminderCopy.validCheer("Go get that extra set!", for: result, unit: .pounds))
                #expect(!WorkoutReminderCopy.validCheer("Go set a new bench PR!", for: result, unit: .pounds))
            }
            if kind == .repPR, let name = result.exerciseName {
                #expect(WorkoutReminderCopy.validCheer("Go get that \(name) rep PR!", for: result, unit: .pounds))
                #expect(!WorkoutReminderCopy.validCheer("Go for a \(name) rep PR for eight reps!", for: result, unit: .pounds))
            }
            if kind == .strengthPR {
                #expect(!WorkoutReminderCopy.validCheer("Go for the PR at 99999 lb for eight reps!", for: result, unit: .pounds))
            }
        }
    }

    @Test("Bodyweight rep records compare the same exercise across programs, ignoring unlogged or mismatched history")
    func bodyweightRepOpportunity() throws {
        let store = PowerJackStore(inMemory: true)
        let context = store.container!.mainContext
        let lift = Exercise(exerciseName: "Ring Push Up", exerciseEquipment: .bodyweight, primaryMuscleFocus: .chest)
        lift.assignSyncID()
        let template = TemplateProgram(templateName: "Rings", workoutsPerWeek: 1, templateMuscleFocus: [.chest], templateType: .hypertrophy)
        template.addTemplateWorkout().addTemplateExercise(exercise: lift)
        context.insert(template)
        let program = Program(programLengthWeeks: 3, templateProgram: template)
        context.insert(program)
        program.start()
        let workout = try #require(program.nextWorkout)
        let entry = try #require(workout.workoutExercises.first)
        entry.replacePlannedWorkingSets([(13, nil)])
        let preview = WorkoutPreview(program: program, workout: workout)
        let now = Date()
        let start = now.addingTimeInterval(-7 * 86_400)
        let row = HistoryRow(programID: UUID(), programName: "Previous program", programWeeks: 1, daysPerWeek: 1,
                             programStatus: .completed, week: 1, day: 1, workoutStatus: "Complete", workoutStarted: start,
                             workoutEnded: start.addingTimeInterval(1800), exerciseNumber: 1, exerciseName: lift.exerciseName,
                             exerciseKey: try #require(lift.syncKey), equipment: lift.equipment.displayName,
                             exerciseStatus: "Complete", setType: "Working", setNumber: 1, setStatus: "Complete",
                             targetReps: 12, reps: 12, setLogged: start.addingTimeInterval(600))
        func winner(_ rows: [HistoryRow]) -> WorkoutAchievement.Kind? {
            WorkoutAchievement.selected(preview: preview, program: program, workout: workout,
                                        history: WorkoutPreviewHistory(rows: rows, now: now), at: now)?.kind
        }
        #expect(winner([row]) == .repPR)
        var tie = row
        tie.reps = 13
        #expect(winner([tie]) != .repPR)
        var different = row
        different.exerciseKey = "own:\(UUID().uuidString)"
        #expect(winner([different]) != .repPR)
        var equipment = row
        equipment.equipment = Equipment.loadableBodyweight.displayName
        #expect(winner([equipment]) != .repPR)
        var skipped = row
        skipped.setStatus = "Skipped"
        #expect(winner([skipped]) != .repPR)
        var cascade = row
        cascade.setLogged = cascade.workoutEnded
        #expect(winner([cascade]) != .repPR)
        var warmup = row
        warmup.setType = "Warmup"
        #expect(winner([warmup]) != .repPR)
        var future = row
        future.workoutEnded = now.addingTimeInterval(3600)
        #expect(winner([future]) != .repPR)
    }

    @Test("A comeback needs an intervening lower session and thirty days since the last matched best")
    func comebackBoundaries() throws {
        let store = PowerJackStore(inMemory: true)
        let now = Date()
        let p = try WorkoutReminderDemo.seed(.returnToBest, type: .hypertrophy, starter: false,
                                             context: store.container!.mainContext, now: now)
        let w = try #require(p.nextWorkout)
        let preview = WorkoutPreview(program: p, workout: w)
        let source = try WorkoutPreviewHistory(programs: [p], in: store.container!.mainContext, now: now)
        let best = try #require(source.sessions.first?.logged.first)
        let lower = try #require(source.sessions.last?.logged.first)
        func dated(_ row: HistoryRow, daysAgo: Int) throws -> HistoryRow {
            var copy = row
            let end = try #require(Calendar.current.date(byAdding: .day, value: -daysAgo, to: now))
            copy.workoutStarted = end.addingTimeInterval(-1800)
            copy.setLogged = end.addingTimeInterval(-30)
            copy.workoutEnded = end
            return copy
        }
        func kind(_ rows: [HistoryRow]) -> WorkoutAchievement.Kind? {
            WorkoutAchievement.selected(preview: preview, program: p, workout: w,
                                        history: WorkoutPreviewHistory(rows: rows, now: now), at: now)?.kind
        }
        #expect(try kind([dated(best, daysAgo: 30), dated(lower, daysAgo: 2)]) == .returnToBest)
        #expect(try kind([dated(best, daysAgo: 29), dated(lower, daysAgo: 2)]) != .returnToBest)
        #expect(try kind([dated(lower, daysAgo: 45), dated(best, daysAgo: 30)]) != .returnToBest)
        #expect(try kind([dated(best, daysAgo: 45), dated(lower, daysAgo: 20), dated(best, daysAgo: 14)]) != .returnToBest)
        #expect(try kind([dated(best, daysAgo: 45), dated(lower, daysAgo: 45)]) != .returnToBest)
    }

    @Test("A missed set is still part of the previous prescription")
    func skippedPreviousSet() throws {
        let store = PowerJackStore(inMemory: true)
        let now = Date()
        let p = try WorkoutReminderDemo.seed(.extraSet, type: .hypertrophy, starter: false,
                                             context: store.container!.mainContext, now: now)
        let w = try #require(p.nextWorkout)
        let preview = WorkoutPreview(program: p, workout: w)
        let source = try WorkoutPreviewHistory(programs: [p], in: store.container!.mainContext, now: now)
        var skipped = try #require(source.sessions.last?.rows.first)
        skipped.setNumber = 3
        skipped.setStatus = Status.skipped.rawValue.capitalized
        skipped.setLogged = nil
        skipped.reps = nil
        let history = WorkoutPreviewHistory(rows: source.sessions.flatMap(\.rows) + [skipped], now: now)
        let result = WorkoutAchievement.selected(preview: preview, program: p, workout: w, history: history, at: now)
        #expect(result?.kind != .extraSet)
    }

    @Test("The program finish wins over a simultaneous four-week streak; an earlier skipped session breaks both")
    func simultaneousAttendance() throws {
        for skipFirst in [false, true] {
            let store = PowerJackStore(inMemory: true)
            let context = store.container!.mainContext
            let lift = Exercise(exerciseName: "Calf Raise", exerciseEquipment: .machine, primaryMuscleFocus: .calves)
            let template = TemplateProgram(templateName: "Calf block", workoutsPerWeek: 1, templateMuscleFocus: [.calves], templateType: .hypertrophy)
            template.addTemplateWorkout().addTemplateExercise(exercise: lift)
            context.insert(template)
            let program = Program(programLengthWeeks: 4, templateProgram: template)
            context.insert(program)
            program.start()
            for week in 1...3 {
                let previous = try #require(program.nextWorkout)
                if week == 1 && skipFirst {
                    program.skipWorkout(previous)
                } else {
                    previous.startAndCascade(at: Date().addingTimeInterval(-3600))
                    for entry in previous.workoutExercises {
                        for set in entry.workingSets {
                            set.reps = 8
                            set.weightTenthsPounds = 350
                            entry.completeSet(set, at: Date().addingTimeInterval(-60))
                        }
                    }
                    program.finishWorkout(previous)
                }
            }
            let last = try #require(program.nextWorkout)
            let history = try WorkoutPreviewHistory(programs: [program], in: context, now: .now)
            let winner = WorkoutAchievement.selected(preview: WorkoutPreview(program: program, workout: last),
                                                     program: program, workout: last, history: history, at: .now)
            if skipFirst {
                #expect(winner?.kind != .firstProgram && winner?.kind != .fourWeekStreak)
            } else {
                #expect(winner?.kind == .firstProgram)
            }
        }
    }

    @Test("Verified achievements stand alone, while vague, unrelated and contradictory claims are rejected")
    func coverageOfLegPressIncrease() throws {
        let store = PowerJackStore(inMemory: true)
        let now = Date()
        let program = try WorkoutReminderDemo.seed(.extraSet, type: .hypertrophy, starter: false,
                                                    context: store.container!.mainContext, now: now)
        let workout = try #require(program.nextWorkout)
        let preview = WorkoutPreview(program: program, workout: workout)
        let history = try WorkoutPreviewHistory(programs: [program], in: store.container!.mainContext, now: now)
        let award = try #require(WorkoutAchievement.selected(preview: preview, program: program, workout: workout,
                                                              history: history, at: now))
        let facts = WorkoutReminderCopy.Facts(preview: preview, program: program, workout: workout,
                                              timingTitle: "Tonight’s lift", achievement: award, history: history, unit: .pounds)
        let full = "Leg press goes from 2 to 3 working sets tonight."
        #expect(WorkoutReminderCopy.validSummary(full, for: facts))
        #expect(!WorkoutReminderCopy.validSummary("Leg Press goes from 2 to 3 planned working sets.", for: facts))
        for text in [full, "We've got one more set on leg press tonight.", "Leg press gets an extra working set tonight.",
                     "You’ll add one extra set to Leg Press, shifting to 3 planned working sets.",
                     "Leg press gains a third working set."] {
            #expect(WorkoutReminderCopy.coversAchievement(text, for: award, unit: .pounds))
        }
        for text in ["Go get that extra set!", "Squats go from 2 to 3 sets tonight.",
                     "Leg press goes from 3 to 2 sets tonight.", "Leg press goes from 2 to 4 sets tonight.",
                     "Leg press gains a fourth working set.", "Add one extra set to Leg Press for 4 working sets."] {
            #expect(!WorkoutReminderCopy.coversAchievement(text, for: award, unit: .pounds))
        }
        #expect(!WorkoutReminderCopy.validSummary("Leg press works your quads.", for: facts))
        #expect(!WorkoutReminderCopy.validSummary("This session is worth previewing because leg press gets one extra set.", for: facts))

        let finish = WorkoutAchievement(kind: .firstProgram)
        let finishFacts = WorkoutReminderCopy.Facts(preview: preview, program: program, workout: workout,
                                                    timingTitle: "Tonight’s lift", achievement: finish)
        #expect(!WorkoutReminderCopy.validSummary("Finishing Leg Press marks completion of the first program session.", for: finishFacts))
        let singleSetFinish = "Finish this set to complete every session in your first program."
        #expect(!WorkoutReminderCopy.validSummary(singleSetFinish, for: finishFacts))
        #expect(!WorkoutReminderCopy.validCheer(singleSetFinish, for: finish, unit: .pounds))
        #expect(!WorkoutReminderCopy.validSummary("Your training partner has Leg Press on the schedule too.", for: facts))
        #expect(!WorkoutReminderCopy.validSummary("Leg Press gets one extra set—let’s go!", for: facts))
        let streak = WorkoutAchievement(kind: .fourWeekStreak)
        #expect(WorkoutReminderCopy.coversAchievement("Finish tonight to make it four consecutive program weeks.",
                                                      for: streak, unit: .pounds))
        let streakFacts = WorkoutReminderCopy.Facts(preview: preview, program: program, workout: workout,
                                                    timingTitle: "Tonight’s lift", achievement: streak)
        #expect(!WorkoutReminderCopy.validSummary("Finish Leg Press with 2 working sets to complete four consecutive program weeks with every scheduled session logged.", for: streakFacts))
        let bench = WorkoutAchievement(kind: .strengthPR, exerciseName: "Barbell Bench Press", weight: 1000)
        #expect(WorkoutReminderCopy.validCheer("Go get that bench PR!", for: bench, unit: .pounds))
        for cheer in ["Go get that bench PR, let’s make it count!", "Go get that bench PR—we’ve got this!",
                      "Your training partner has a bench PR up next!", "Go get that bench PR, let’s go, crush it!"] {
            #expect(!WorkoutReminderCopy.validCheer(cheer, for: bench, unit: .pounds))
        }
        let strengthBest = "Barbell Bench Press at 100 lb could beat the previous strength best tomorrow morning."
        #expect(WorkoutReminderCopy.coversAchievement(strengthBest, for: bench, unit: .pounds))
        #expect(!WorkoutReminderCopy.coversAchievement(strengthBest.replacingOccurrences(of: "100", with: "105"),
                                                       for: bench, unit: .pounds))
        let comeback = WorkoutAchievement(kind: .returnToBest, exerciseName: "Barbell Back Squat", weight: 1000, reps: 5)
        #expect(!WorkoutReminderCopy.validCheer("Barbell Back Squat: 5 reps at 100 lb—one more set.", for: comeback, unit: .pounds))
        #expect(WorkoutReminderCopy.coversAchievement("Barbell Back Squat could bring you back to your strongest recent effort.",
                                                      for: comeback, unit: .pounds))
        let dumbbell = WorkoutAchievement(kind: .heavierDumbbells, exerciseName: "Dumbbell Curl", weight: 250)
        #expect(WorkoutReminderCopy.coversAchievement("Dumbbell Curl shifts to 25 lb, a heavier load than your prior max.",
                                                      for: dumbbell, unit: .pounds))
    }

    private func calendar(zone: String = "UTC") throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func start(
        weeksAgo: Int, hour: Int, minute: Int = 0, before date: Date, calendar: Calendar
    ) throws -> Date {
        let day = try #require(calendar.date(byAdding: .day, value: -7 * weeksAgo, to: date))
        return try #require(calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day))
    }

    private func predict(
        _ starts: [Date], now: Date, calendar: Calendar, eveningMinute: Int = WorkoutReminderTiming.defaultEveningMinute
    ) -> WorkoutReminderTiming.Prediction? {
        WorkoutReminderTiming.next(starts: starts, now: now, calendar: calendar, eveningMinute: eveningMinute)
    }
}
