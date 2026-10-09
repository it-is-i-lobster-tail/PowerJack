import OSLog
import SwiftData

/// Built-in templates for experienced lifters chasing hypertrophy.
/// Exercises reference `ExerciseCatalog` IDs, so seed the exercise catalog first.
enum TemplateCatalog {
    struct Entry {
        let id: String
        let name: String
        let muscleFocus: [Muscle]
        /// One list of exercise catalog IDs per workout, in order.
        let workouts: [[String]]

        func makeTemplate(exercisesByID: [String: Exercise]) -> TemplateProgram? {
            let template = TemplateProgram(
                templateName: name,
                workoutsPerWeek: workouts.count,
                templateMuscleFocus: muscleFocus
            )
            template.catalogID = id

            for exerciseIDs in workouts {
                let workout = template.addTemplateWorkout()
                for exerciseID in exerciseIDs {
                    guard let exercise = exercisesByID[exerciseID] else {
                        Logger.persistence.error("Template \(id) needs missing catalog exercise \(exerciseID).")
                        return nil
                    }
                    workout.addTemplateExercise(exercise: exercise)
                }
            }
            return template
        }
    }

    // IDs are permanent: changing a display name must not create another template.
    // Each name says the gym it needs: Home (dumbbells, or a barbell and rack), Small Gym
    // (Smith machine, dumbbells and cables) or Full Gym. Workouts are in order, one per day.
    // Programs start each exercise at 2 sets, so most muscles get 3 to 5 exercises a week to grow into.
    static let entries: [Entry] = [
        Entry(
            id: "home-whole-body-essentials-2x",
            name: "Home Whole Body Essentials",
            muscleFocus: [.chest, .back, .quads, .hamstrings],
            workouts: [
                ["dumbbell-goblet-squat", "dumbbell-bench-press", "one-arm-dumbbell-row", "dumbbell-romanian-deadlift", "dumbbell-calf-raise"],
                ["dumbbell-goblet-squat", "push-up", "one-arm-dumbbell-row", "sliding-leg-curl", "crunch"],
            ]
        ),
        Entry(
            id: "small-gym-whole-body-essentials-2x",
            name: "Small Gym Whole Body Essentials",
            muscleFocus: [.chest, .back, .quads, .hamstrings],
            workouts: [
                ["smith-machine-squat", "dumbbell-bench-press", "seated-cable-row", "sliding-leg-curl", "dumbbell-calf-raise"],
                ["smith-machine-squat", "dumbbell-romanian-deadlift", "incline-dumbbell-bench-press", "lat-pulldown", "cable-crunch"],
            ]
        ),
        Entry(
            id: "full-gym-legs-core-focus-2x",
            name: "Full Gym Legs & Core Focus",
            muscleFocus: [.quads, .hamstrings, .abs, .obliques],
            workouts: [
                ["leg-press", "seated-leg-curl", "standing-calf-raise", "dumbbell-bench-press", "seated-cable-row", "cable-crunch"],
                ["dumbbell-romanian-deadlift", "leg-extension", "standing-calf-raise", "incline-dumbbell-bench-press", "lat-pulldown", "cable-woodchop"],
            ]
        ),
        Entry(
            id: "home-whole-body-muscle-builder-3x",
            name: "Home Whole Body Muscle Builder",
            muscleFocus: [.chest, .back, .quads, .hamstrings],
            workouts: [
                ["barbell-back-squat", "barbell-bench-press", "one-arm-dumbbell-row", "sliding-leg-curl", "dumbbell-lateral-raise"],
                ["barbell-romanian-deadlift", "dumbbell-shoulder-press", "pull-up", "dumbbell-goblet-squat", "dumbbell-calf-raise", "crunch"],
                ["dumbbell-goblet-squat", "incline-dumbbell-bench-press", "one-arm-dumbbell-row", "sliding-leg-curl", "dumbbell-curl", "dumbbell-triceps-extension"],
            ]
        ),
        Entry(
            id: "small-gym-whole-body-muscle-builder-3x",
            name: "Small Gym Whole Body Muscle Builder",
            muscleFocus: [.chest, .back, .quads, .hamstrings],
            workouts: [
                ["smith-machine-squat", "dumbbell-bench-press", "seated-cable-row", "sliding-leg-curl", "dumbbell-lateral-raise"],
                ["dumbbell-romanian-deadlift", "lat-pulldown", "dumbbell-shoulder-press", "dumbbell-curl", "cable-crunch", "dumbbell-calf-raise"],
                ["smith-machine-squat", "incline-dumbbell-bench-press", "seated-cable-row", "sliding-leg-curl", "cable-overhead-extension", "dumbbell-calf-raise"],
            ]
        ),
        Entry(
            id: "full-gym-arms-focus-3x",
            name: "Full Gym Arms Focus",
            muscleFocus: [.biceps, .triceps],
            workouts: [
                ["dumbbell-curl", "cable-overhead-extension", "dumbbell-bench-press", "seated-cable-row", "seated-leg-curl", "dumbbell-lateral-raise"],
                ["leg-press", "dumbbell-romanian-deadlift", "dumbbell-shoulder-press", "standing-calf-raise", "cable-crunch"],
                ["dumbbell-hammer-curl", "cable-triceps-pushdown", "incline-dumbbell-bench-press", "lat-pulldown", "leg-press", "dumbbell-reverse-fly"],
            ]
        ),
        Entry(
            id: "full-gym-chest-back-core-focus-3x",
            name: "Full Gym Chest, Back & Core Focus",
            muscleFocus: [.chest, .back, .abs, .obliques],
            workouts: [
                ["dumbbell-bench-press", "seated-cable-row", "leg-press", "standing-calf-raise", "cable-crunch"],
                ["lat-pulldown", "incline-dumbbell-bench-press", "dumbbell-romanian-deadlift", "dumbbell-lateral-raise", "cable-woodchop"],
                ["seated-cable-row", "cable-chest-fly", "leg-extension", "seated-leg-curl", "hanging-knee-raise"],
            ]
        ),
        Entry(
            id: "full-gym-whole-body-muscle-builder-4x",
            name: "Full Gym Whole Body Muscle Builder",
            muscleFocus: [.chest, .back, .quads, .hamstrings],
            workouts: [
                ["dumbbell-bench-press", "seated-cable-row", "lat-pulldown", "dumbbell-lateral-raise", "dumbbell-curl", "cable-triceps-pushdown"],
                ["barbell-back-squat", "dumbbell-romanian-deadlift", "seated-leg-curl", "standing-calf-raise", "cable-crunch"],
                ["incline-dumbbell-bench-press", "lat-pulldown", "dumbbell-shoulder-press", "dumbbell-reverse-fly", "dumbbell-curl", "cable-overhead-extension"],
                ["leg-press", "barbell-hip-thrust", "leg-extension", "seated-leg-curl", "standing-calf-raise", "cable-woodchop"],
            ]
        ),
        Entry(
            id: "small-gym-glutes-shoulders-focus-4x",
            name: "Small Gym Glutes & Shoulders Focus",
            muscleFocus: [.glutes, .shoulders],
            workouts: [
                ["smith-machine-squat", "dumbbell-romanian-deadlift", "smith-machine-hip-thrust", "dumbbell-calf-raise", "cable-crunch"],
                ["incline-dumbbell-bench-press", "seated-cable-row", "dumbbell-shoulder-press", "dumbbell-lateral-raise", "dumbbell-curl", "cable-overhead-extension"],
                ["smith-machine-hip-thrust", "dumbbell-bulgarian-split-squat", "sliding-leg-curl", "cable-hip-abduction", "dumbbell-calf-raise"],
                ["lat-pulldown", "dumbbell-bench-press", "dumbbell-reverse-fly", "cable-lateral-raise", "cable-triceps-pushdown", "cable-hip-abduction"],
            ]
        ),
        Entry(
            id: "full-gym-upper-body-specialization-5x",
            name: "Full Gym Upper Body Specialization",
            muscleFocus: [.chest, .back, .biceps, .triceps],
            workouts: [
                ["dumbbell-bench-press", "seated-cable-row", "lat-pulldown", "dumbbell-lateral-raise", "dumbbell-curl", "cable-triceps-pushdown"],
                ["barbell-back-squat", "dumbbell-romanian-deadlift", "seated-leg-curl", "standing-calf-raise", "cable-crunch"],
                ["incline-dumbbell-bench-press", "lat-pulldown", "dumbbell-shoulder-press", "dumbbell-reverse-fly", "dumbbell-curl", "cable-overhead-extension"],
                ["leg-press", "barbell-hip-thrust", "leg-extension", "seated-leg-curl", "standing-calf-raise", "cable-woodchop"],
                ["cable-chest-fly", "seated-cable-row", "dumbbell-lateral-raise", "dumbbell-curl", "cable-overhead-extension"],
            ]
        ),
        Entry(
            id: "full-gym-glute-specialization-5x",
            name: "Full Gym Glute Specialization",
            muscleFocus: [.glutes],
            workouts: [
                ["barbell-back-squat", "dumbbell-romanian-deadlift", "seated-leg-curl", "standing-calf-raise", "cable-crunch"],
                ["dumbbell-bench-press", "seated-cable-row", "lat-pulldown", "dumbbell-lateral-raise", "dumbbell-curl", "cable-triceps-pushdown"],
                ["barbell-hip-thrust", "cable-glute-kickback", "cable-hip-abduction", "dumbbell-lateral-raise", "cable-crunch"],
                ["leg-press", "barbell-hip-thrust", "leg-extension", "seated-leg-curl", "standing-calf-raise", "cable-woodchop"],
                ["incline-dumbbell-bench-press", "lat-pulldown", "dumbbell-shoulder-press", "dumbbell-reverse-fly", "dumbbell-curl", "cable-overhead-extension"],
            ]
        ),
    ]

    /// Inserts any built-in template that isn't stored yet. Existing ones are left alone so user edits stick.
    @MainActor
    static func seed(in context: ModelContext) throws {
        var changed = try removeDuplicates(in: context)
        let existingIDs = Set(try context.fetch(FetchDescriptor<TemplateProgram>()).compactMap(\.catalogID))
        let missing = entries.filter { !existingIDs.contains($0.id) }

        if !missing.isEmpty {
            let exercisesByID = Dictionary(
                try context.fetch(FetchDescriptor<Exercise>()).compactMap { exercise in exercise.catalogID.map { ($0, exercise) } },
                uniquingKeysWith: { first, _ in first }
            )
            for entry in missing {
                guard let template = entry.makeTemplate(exercisesByID: exercisesByID) else { continue }
                context.insert(template)
                changed = true
            }
        }

        guard changed else { return }
        try context.save()
    }

    /// Merges copies of the same built-in template, the same way `ExerciseCatalog.removeDuplicates`
    /// does. The oldest copy keeps the user's edits; programs that used a duplicate are pointed at it.
    /// - Returns: Whether anything changed. The caller saves.
    @MainActor
    static func removeDuplicates(in context: ModelContext) throws -> Bool {
        let catalogTemplates = try context.fetch(FetchDescriptor<TemplateProgram>()).filter { $0.catalogID != nil }
        var changed = false

        for copies in Dictionary(grouping: catalogTemplates, by: \.catalogID).values where copies.count > 1 {
            let oldestFirst = copies.sorted { $0.createdAtValue < $1.createdAtValue }
            let survivor = oldestFirst[0]
            for duplicate in oldestFirst.dropFirst() {
                for program in duplicate.programsValue ?? [] {
                    program.templateProgramValue = survivor
                }
                // Cascades to the duplicate's workouts and their exercises.
                context.delete(duplicate)
            }
            changed = true
        }
        return changed
    }
}
