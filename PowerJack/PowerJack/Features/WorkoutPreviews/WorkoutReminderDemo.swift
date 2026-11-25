#if DEBUG
import Foundation
import SwiftData

/// Run with -demoWorkoutReminder [-demoAchievement kind] [-demoStyle type] [-demoStarter].
/// The launch path supplies an in-memory store. Nothing here writes to the lifter's history.
struct WorkoutReminderDemo {
    static let enabled = ProcessInfo.processInfo.arguments.contains("-demoWorkoutReminder")
    let eveningMinute: Int
    let deadline: Date

    enum FixtureError: Error { case invalidOption, missingFixture }

    init(now: Date, calendar: Calendar, context: ModelContext) throws {
        let args = ProcessInfo.processInfo.arguments
        func option(_ name: String, default value: String) throws -> String {
            guard let index = args.firstIndex(of: name) else { return value }
            guard args.indices.contains(index + 1) else { throw FixtureError.invalidOption }
            return args[index + 1]
        }
        let kindName = try option("-demoAchievement", default: args.contains("-demoLegPress") ? "extraSet" : "strengthPR")
        guard let kind = WorkoutAchievement.Kind(rawValue: kindName),
              let type = TemplateType(rawValue: try option("-demoStyle", default: "hypertrophy")) else {
            throw FixtureError.invalidOption
        }
        deadline = now.addingTimeInterval(120)
        eveningMinute = calendar.component(.hour, from: deadline) * 60 + calendar.component(.minute, from: deadline)
        _ = try Self.seed(kind, type: type, starter: args.contains("-demoStarter"), context: context, now: now)
        // Prior visits establish the timing pattern independently of the achievement case.
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: deadline) else { throw FixtureError.invalidOption }
        let batch = UUID()
        for week in 1...6 {
            guard let day = calendar.date(byAdding: .day, value: -7 * week, to: tomorrow),
                  let start = WorkoutReminderTiming.time(on: day, minute: 390 + week, calendar: calendar) else { continue }
            let row = HistoryRow(week: 7 - week, day: 1, workoutStarted: start, workoutEnded: start.addingTimeInterval(1800),
                                 exerciseKey: "catalog:crunch", equipment: "Bodyweight", setType: "Working",
                                 setStatus: Status.complete.rawValue.capitalized, reps: 10,
                                 setLogged: start.addingTimeInterval(600))
            context.insert(HistoryRecord(row, batchID: batch, savedAt: now, programStarted: nil, order: week))
        }
        try context.save()
    }

    @discardableResult
    static func seed(_ kind: WorkoutAchievement.Kind, type: TemplateType, starter: Bool,
                     context: ModelContext, now: Date) throws -> Program {
        let template = try makeTemplate(kind, type: type, starter: starter, context: context)
        let weeks = kind == .firstProgram ? 1 : 5
        let program = Program(programLengthWeeks: weeks, templateProgram: template)
        context.insert(program)
        program.start()
        let days = template.workoutsPerWeek
        if kind == .firstProgram || kind == .fourWeekStreak {
            let completed = (kind == .firstProgram ? days : 4 * days) - 1
            for index in 0..<completed {
                guard let prior = program.nextWorkout else { throw FixtureError.missingFixture }
                let start = now.addingTimeInterval(-Double(completed - index) * 86_400)
                complete(prior, in: program, at: start)
            }
            try context.save()
            return program
        }

        // Strength recalculates a new slot on start. Repeated slots in its second week have
        // stable archived prescriptions. Set up that week before installing the scenario.
        if type == .strength {
            for _ in 0..<days {
                guard let workout = program.nextWorkout else { throw FixtureError.missingFixture }
                program.skipWorkout(workout)
            }
        }
        let accessory = [.repPR, .extraSet, .heavierDumbbells].contains(kind)
        var target: WorkoutExercise?
        for _ in 0..<days {
            guard let upcoming = program.nextWorkout else { throw FixtureError.missingFixture }
            target = upcoming.workoutExercises.first {
                guard let ex = $0.shownExercise else { return false }
                if !starter { return true }
                if accessory { return ex.equipment == .dumbbell && [.shoulders, .biceps].contains(ex.primaryMuscleFocus) }
                return ex.equipment == .barbell || ex.equipment == .legPress
            }
            if target != nil { break }
            complete(upcoming, in: program, at: now.addingTimeInterval(-7 * 86_400))
        }
        guard let upcoming = program.nextWorkout, let target, let ex = target.shownExercise,
              let key = ex.syncKey else { throw FixtureError.missingFixture }
        for entry in upcoming.workoutExercises {
            let weight: Int? = entry.shownExercise?.repsOnly == true ? nil : 100
            entry.replacePlannedWorkingSets([(5, weight)])
        }

        var recorded: [(days: Int, reps: Int, weight: Int, count: Int)]
        var plan = [(5, 1000)]
        switch kind {
        case .returnToBest:
            recorded = [(45, 5, 1000, 2), (6, 5, 850, 2)]
        case .strengthPR:
            recorded = [(7, 5, 950, 2)]
        case .sessionVolume:
            recorded = [(7, 5, 1000, 1)]
            plan = [(5, 1000), (5, 1000)]
        case .heavierDumbbells:
            recorded = [(7, 12, 200, 4)]
            plan = [(4, 250)]
        case .repPR:
            recorded = [(7, 12, 200, 4)]
            plan = [(13, 200)]
        case .extraSet:
            recorded = [(21, 8, 1000, 4), (7, 8, 1000, 2)]
            plan = [(8, 1000), (8, 1000), (8, 1000)]
        default:
            throw FixtureError.invalidOption
        }
        target.replacePlannedWorkingSets(plan.map { ($0.0, $0.1) })
        let programID = UUID()
        let batch = UUID()
        var order = 0
        for (index, session) in recorded.enumerated() {
            let start = now.addingTimeInterval(-Double(session.days) * 86_400)
            for set in 1...session.count {
                let row = HistoryRow(programID: programID, programName: "Prior training", programWeeks: recorded.count,
                                     daysPerWeek: 1, programStatus: .completed, week: index + 1, day: 1,
                                     workoutStatus: Status.complete.rawValue.capitalized,
                                     workoutStarted: start, workoutEnded: start.addingTimeInterval(1800),
                                     exerciseNumber: 1, exerciseName: ex.exerciseName, exerciseKey: key,
                                     equipment: ex.equipment.displayName, exerciseStatus: Status.complete.rawValue.capitalized,
                                     setType: "Working", setNumber: set,
                                     setStatus: Status.complete.rawValue.capitalized, targetReps: session.reps,
                                     reps: session.reps, targetWeightTenthsPounds: session.weight,
                                     weightTenthsPounds: session.weight, setLogged: start.addingTimeInterval(Double(60 * set)))
                context.insert(HistoryRecord(row, batchID: batch, savedAt: now, programStarted: nil, order: order))
                order += 1
            }
        }
        try context.save()
        return program
    }

    private static func complete(_ workout: Workout, in program: Program, at start: Date) {
        program.prepareToStart(workout, at: start)
        workout.startAndCascade(at: start)
        for entry in workout.workoutExercises {
            for set in entry.workingSets {
                set.reps = set.repsPlanned ?? 5
                if entry.shownExercise?.repsOnly == false {
                    set.weightTenthsPounds = set.weightTenthsPlannedPounds ?? 100
                }
                entry.completeSet(set, at: start.addingTimeInterval(300))
                if entry.needsTopSetRating && entry.isLastTopSet(set) { entry.rateTopSets(.three) }
            }
        }
        program.finishWorkout(workout)
    }

    private static func makeTemplate(_ kind: WorkoutAchievement.Kind, type: TemplateType, starter: Bool,
                                     context: ModelContext) throws -> TemplateProgram {
        if starter {
            let id: String = switch type {
            case .powerJack: "powerjack-power-full-body-3x"
            case .strength: "strength-bigger-total-5x"
            case .hypertrophy: "build-full-body-3x"
            }
            guard let template = try context.fetch(FetchDescriptor<TemplateProgram>()).first(where: { $0.catalogID == id })
            else { throw FixtureError.missingFixture }
            return template
        }
        let id: String = switch kind {
        case .strengthPR: type == .strength ? "barbell-back-squat" : "barbell-bench-press"
        case .returnToBest: "barbell-back-squat"
        case .heavierDumbbells, .repPR: "dumbbell-curl"
        default: "leg-press"
        }
        guard let ex = try context.fetch(FetchDescriptor<Exercise>()).first(where: { $0.catalogID == id })
        else { throw FixtureError.missingFixture }
        let template = TemplateProgram(templateName: "\(ex.exerciseName) demo", workoutsPerWeek: 1,
                                       templateMuscleFocus: [ex.primaryMuscleFocus], templateType: type)
        template.addTemplateWorkout().addTemplateExercise(exercise: ex)
        context.insert(template)
        return template
    }
}
#endif
