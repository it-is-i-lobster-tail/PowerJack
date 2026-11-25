#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftData

/// An opt-in simulator history. The Data tab reads these rows through its usual workout models.
@MainActor
enum SimulatorTrainingHistory {
    private static let selectionKey = "simulator.sampleTrainingHistory"

    /// Once selected, tapping the app icon reopens the same editable sample database.
    static var isSelected: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-regularTrainingHistory") {
            UserDefaults.standard.removeObject(forKey: selectionKey)
        } else if arguments.contains("-sampleTrainingHistory") {
            UserDefaults.standard.set(true, forKey: selectionKey)
        }
        return UserDefaults.standard.bool(forKey: selectionKey)
    }

    static func openStore(in directory: URL = URL.applicationSupportDirectory.appending(path: "SimulatorTrainingHistory")) throws -> PowerJackStore {
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "Workouts.store")
        let marker = directory.appending(path: "Seeded")
        let needsSeed = !files.fileExists(atPath: url.path) || !files.fileExists(atPath: marker.path)
        let schema = PowerJackSchema.schema
        let configuration = ModelConfiguration("SimulatorTrainingHistory", schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        try TemplateCatalog.seed(in: context)
        if needsSeed {
            // A previous launch might have saved the workouts immediately before the marker write.
            if try context.fetchCount(FetchDescriptor<Program>()) == 0 { try populate(in: context) }
            try Data().write(to: marker, options: .atomic)
        }
        try HistoryArchive.saveEndedPrograms(in: context)
        return PowerJackStore(simulatorTrainingContainer: container)
    }

    private static let squat = "barbell-back-squat"
    private static let bench = "barbell-bench-press"
    private static let lunge = "reverse-lunge-per-leg"
    private static let curl = "cable-curl"

    private struct Lift {
        var id: String
        var sets: Int
        var reps: Int
        /// Total barbell load, stack weight, or weight per dumbbell, in pounds.
        var pounds: Int?

        init(_ id: String, _ sets: Int, _ reps: Int, _ pounds: Int? = nil) {
            self.id = id
            self.sets = sets
            self.reps = reps
            self.pounds = pounds
        }
    }

    static func populate(in context: ModelContext, now: Date = .now) throws {
        let catalog = try context.fetch(FetchDescriptor<Exercise>())
        var exercises = Dictionary(catalog.compactMap { exercise in
            exercise.catalogID.map { ($0, exercise) }
        }, uniquingKeysWith: { first, _ in first })
        let reverseLunge = Exercise(exerciseName: "Barbell Reverse Lunge (reps per leg)", exerciseEquipment: .barbell,
                                    primaryMuscleFocus: .quads, secondaryMuscles: [.glutes, .hamstrings],
                                    userCreated: true, fatigueLevel: .high)
        reverseLunge.assignSyncID()
        context.insert(reverseLunge)
        exercises[lunge] = reverseLunge

        // All completed days precede this local Monday. A three-week gap separates the second and third programs.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        let monday = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let names = ["Winter Strength Base", "Upper / Lower Build", "Strength & Accessories", "Autumn Strength"]
        for (cycle, name) in names.enumerated() {
            let template = TemplateProgram(templateName: name, workoutsPerWeek: 3,
                                           templateMuscleFocus: [.quads, .chest, .back], templateType: .strength)
            context.insert(template)
            let program = Program(programLengthWeeks: 12, templateProgram: template)
            context.insert(program)
            program.start()
            for week in program.programWeeks {
                let number = cycle * 12 + week.order
                let currentWeek = number == 47
                let blockWeek = week.order % 6 + 1
                week.setBlock(kind: blockWeek == 6 ? .deload : .build, blockWeek: blockWeek)
                if week.status == .planned { week.start() }
                for day in 0..<3 {
                    let layout = lifts(week: number, day: day)
                    let workout = week.addWorkout()!
                    let daysBeforeMonday = (number - 47 - (cycle < 2 ? 3 : 0)) * 7
                    // A lower day, an upper day and a mixed day with a little variability in workout time.
                    let date = calendar.date(byAdding: .day, value: daysBeforeMonday + [0, 2, 5][day], to: monday)!
                    let start = calendar.date(bySettingHour: day == 2 ? 9 : 17, minute: (number % 4) * 10,
                                              second: 0, of: date)!
                    if currentWeek {
                        for lift in layout {
                            let slot = workout.addWorkoutExercise(exercise: exercises[lift.id]!)!
                            for _ in 0..<lift.sets {
                                _ = slot.addPlannedSet(plannedReps: lift.reps, plannedWeightTenthsPounds: lift.pounds.map { $0 * 10 })
                            }
                        }
                    } else {
                        let end = record(workout, layout: layout, exercises: exercises, week: number, day: day, start: start)
                        context.insert(WorkoutLog(date: end, setsByMuscle: workout.loggedSetsByMuscle,
                                                  sessionID: workout.syncID, programType: template.templateType))
                    }
                }
                if !currentWeek { week.complete() }
            }
            if cycle < names.count - 1 { program.complete() }
            for day in 0..<3 {
                let workout = TemplateWorkout(order: day)
                workout.templateExercisesValue = lifts(week: cycle * 12, day: day).enumerated().map {
                    TemplateExercise(exercise: exercises[$0.element.id]!, order: $0.offset)
                }
                template.templateWorkoutsValue = template.templateWorkouts + [workout]
            }
        }
        try context.save()
    }

    private static func lifts(week: Int, day: Int) -> [Lift] {
        let phase = week % 6
        let step = week / 6
        let deload = phase == 5
        let highRepWeek = week == 11 || week == 37
        let squatLoad = 190 + 5 * step + [0, 5, 0, 10, 5, -15][phase]
        switch day {
        case 0:
            return [
                Lift(squat, 3, highRepWeek ? 15 : (deload ? 8 : 5), highRepWeek ? 155 : (deload ? 185 : squatLoad)),
                Lift(lunge, deload ? 2 : 3, 6, 65 + 5 * (step / 2) + [0, 5, 0, 5, 10, -5][phase]),
                Lift("seated-leg-curl", 3, 10, 60 + 5 * step),
                Lift("standing-calf-raise", 3, 12, 90 + 5 * step),
                Lift("barbell-hip-thrust", 2, 8, 115 + 5 * step)
            ]
        case 1:
            let curls = Lift(curl, 3, 10, 30)
            var upper = [
                Lift(bench, 3, 5, deload ? 165 : 165 + min(4, step) * 5 + [0, 5, 0, 5, 10, 0][phase]),
                Lift("seated-cable-row", 3, 8, 80 + 5 * step),
                Lift("cable-triceps-pushdown", deload ? 2 : 3, 12, 35 + 5 * (step / 2)),
                Lift("dumbbell-wrist-curl", 2, 12, 15)
            ]
            upper.insert(curls, at: week.isMultiple(of: 3) ? 0 : 2)
            return upper
        default:
            // The fixed-load exposures complement the heavier squat and bench days.
            return [
                Lift(squat, 3, highRepWeek ? 15 : (week.isMultiple(of: 4) ? 5 : 8), highRepWeek ? 155 : 185),
                Lift(bench, 4, week.isMultiple(of: 3) ? 10 : 8, 135),
                Lift("dumbbell-hammer-curl", deload ? 2 : 3, 10, 25 + 5 * (step / 3)),
                Lift("push-up", 3, 10 + step),
                Lift("dumbbell-romanian-deadlift", 2, 8, 50 + 5 * (step / 2))
            ]
        }
    }

    private static func record(_ workout: Workout, layout: [Lift], exercises: [String: Exercise],
                               week: Int, day: Int, start: Date) -> Date {
        var cursor = start
        for (position, lift) in layout.enumerated() {
            let slot = workout.addWorkoutExercise(exercise: exercises[lift.id]!)!
            let targetRIR = week % 6 == 5 ? 3 : 2
            slot.setProgression(rirTarget: targetRIR, code: nil, note: nil)
            slot.start()
            let swappedSquat = lift.id == squat && day == 0 && week % 13 == 6
            if swappedSquat { slot.substituteValue = exercises["goblet-squat"] }
            let workingPounds = swappedSquat ? 65 : lift.pounds
            if position == 0, let workingPounds {
                let warmup = slot.addSet(type: .warmup, plannedReps: 8,
                                         plannedWeightTenthsPounds: max(10, workingPounds / 10 * 5) * 10)!
                let end = cursor.addingTimeInterval(190)
                warmup.complete(at: end, startedAt: cursor)
                warmup.completeAndLock(at: end)
                cursor = end
            }
            for index in 0..<lift.sets {
                let set = slot.addSet(plannedReps: lift.reps, plannedWeightTenthsPounds: workingPounds.map { $0 * 10 })!
                if index == lift.sets - 1 && (week + day * 3 + position * 5) % 31 == 12 {
                    set.skip()
                    continue
                }
                let variation = [0, 1, 0, -1, 2, 0, -2][(week + day + position) % 7]
                set.reps = max(1, lift.reps + variation - index / 2)
                set.weightTenthsPounds = workingPounds.map { $0 * 10 }
                let seconds = 100 + (position < 2 ? 65 : 0) + (week * 11 + index * 13) % 70
                let end = cursor.addingTimeInterval(TimeInterval(seconds))
                set.complete(at: end, startedAt: cursor)
                set.completeAndLock(at: end)
                cursor = end
            }
            if (week + position) % 11 != 4 {
                let actualRIR = max(0, min(4, targetRIR + [0, -1, 0, 1, -2][(week + position) % 5]))
                slot.addFeedback(feedback: ExerciseFeedback(repsInReserve: RepsInReserve(rawValue: actualRIR)!,
                                                            levelOfPain: .none))
            }
            slot.complete()
        }
        let end = cursor.addingTimeInterval(60)
        // Workout.complete() uses the live clock. Apply the same persisted timestamps a finished phone workout carries.
        var state = workout.syncState!
        state.status = .complete
        state.locked = true
        state.createdAt = start
        state.startedAt = start
        state.startedOn = SyncDevice.iPhone
        state.endedAt = end
        workout.apply(state, exercises: [:])
        return end
    }
}
#endif
