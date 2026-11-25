#if DEBUG
import Foundation
import SwiftData

extension PowerJackSeed {
    private struct SampleLift {
        let catalogID: String
        let reps: Int
        let load: Int?

        init(_ catalogID: String, reps: Int, load: Int?) {
            self.catalogID = catalogID
            self.reps = reps
            self.load = load
        }
    }

    /// Fictional workouts for the Data previews and chart tests.
    private static let sampleWeek: [[SampleLift]] = [
        [
            SampleLift("dumbbell-bench-press", reps: 7, load: 550),
            SampleLift("barbell-row", reps: 8, load: 1_250),
            SampleLift("cable-triceps-pushdown", reps: 8, load: 350),
        ],
        [
            SampleLift("smith-machine-squat", reps: 6, load: 1_650),
            SampleLift("dumbbell-romanian-deadlift", reps: 8, load: 650),
            SampleLift("leg-extension", reps: 8, load: 950),
        ],
        [
            SampleLift("pull-up", reps: 6, load: nil),
            SampleLift("dumbbell-curl", reps: 7, load: 250),
            SampleLift("cable-lateral-raise", reps: 8, load: 125),
        ],
    ]

    static func trainingHistory() -> ModelContainer {
        let container = makeInMemoryContainer()
        let context = container.mainContext
        let template = TemplateProgram(templateName: "Sample Physique", workoutsPerWeek: sampleWeek.count,
                                       templateMuscleFocus: [], templateType: .hypertrophy)
        context.insert(template)
        let program = Program(programLengthWeeks: 6, templateProgram: template)
        program.statusValue = .active
        program.programWeeksValue = (0..<6).map { ProgramWeek(order: $0) }
        context.insert(program)

        let catalog = Dictionary(uniqueKeysWithValues: ExerciseCatalog.entries.map { ($0.id, $0) })
        var exercisesByID: [String: Exercise] = [:]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let repChanges = [0, 1, -1, 0]
        let loadChanges = [0, 25, 0, -25]
        for week in 0..<4 {
            for (day, lifts) in sampleWeek.enumerated() {
                let start = calendar.date(byAdding: .day, value: week * 7 + day * 2 - 30, to: today) ?? today
                let end = start.addingTimeInterval(45 * 60)
                let exercises = lifts.map { lift in
                    if let exercise = exercisesByID[lift.catalogID] { return exercise }
                    guard let entry = catalog[lift.catalogID] else { preconditionFailure("Unknown sample exercise: \(lift.catalogID)") }
                    let exercise = entry.makeExercise()
                    context.insert(exercise)
                    exercisesByID[lift.catalogID] = exercise
                    return exercise
                }
                let sets = lifts.enumerated().map { liftIndex, lift in
                    (0..<3).map { set in
                        let variation = (week + day + liftIndex + set) % repChanges.count
                        return SeedSet(plannedReps: week == 0 ? nil : lift.reps,
                                       plannedWeightTenthsPounds: week == 0 ? nil : lift.load,
                                       actualReps: lift.reps + repChanges[variation],
                                       actualWeightTenthsPounds: lift.load.map { $0 + loadChanges[variation] },
                                       status: .complete)
                    }
                }
                let workout = makeWorkout(order: day, exercises: exercises, sets: sets)
                workout.start(at: start)
                for (index, slot) in workout.workoutExercises.enumerated() {
                    slot.start()
                    if let reserve = RepsInReserve(rawValue: (week + index) % 3),
                       let pain = LevelOfPain(rawValue: 0) {
                        slot.addFeedback(feedback: ExerciseFeedback(repsInReserve: reserve, levelOfPain: pain))
                    }
                    slot.complete()
                }
                workout.complete()
                workout.assignSyncIDs()
                if var state = workout.syncState {
                    state.createdAt = start
                    state.endedAt = end
                    workout.apply(state, exercises: [:])
                }
                let programWeek = program.programWeeks[week]
                programWeek.workoutsValue = programWeek.workouts + [workout]
                context.insert(WorkoutLog(date: end, setsByMuscle: workout.loggedSetsByMuscle, sessionID: workout.syncID))
            }
        }
        do {
            try MovementCatalog.reconcile(Array(exercisesByID.values), in: context)
            try context.save()
        } catch {
            fatalError("Invalid Data preview fixture: \(error)")
        }
        return container
    }
}
#endif
