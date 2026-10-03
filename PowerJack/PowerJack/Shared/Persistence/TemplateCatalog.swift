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
    static let entries: [Entry] = [
        Entry(
            id: "upper-body-builder",
            name: "Upper Body Builder",
            muscleFocus: [.chest, .back, .biceps, .triceps],
            workouts: [
                // Chest & back
                ["barbell-bench-press", "barbell-row", "incline-dumbbell-bench-press", "lat-pulldown", "cable-chest-fly", "cable-face-pull"],
                // Arms
                ["barbell-curl", "barbell-skull-crusher", "dumbbell-hammer-curl", "cable-triceps-pushdown", "cable-curl", "cable-overhead-extension"],
                // Back & chest
                ["pull-up", "incline-barbell-bench-press", "seated-cable-row", "dumbbell-bench-press", "one-arm-dumbbell-row", "dumbbell-lateral-raise"],
                // Arms & shoulders
                ["chin-up", "dumbbell-shoulder-press", "dumbbell-curl", "dumbbell-triceps-extension", "cable-lateral-raise", "dumbbell-reverse-fly"],
            ]
        ),
        Entry(
            id: "leg-blaster",
            name: "Leg Blaster",
            muscleFocus: [.quads, .hamstrings, .glutes, .calves],
            workouts: [
                // Quads
                ["barbell-back-squat", "leg-press", "leg-extension", "lying-leg-curl", "standing-calf-raise"],
                // Hamstrings & glutes
                ["barbell-romanian-deadlift", "barbell-hip-thrust", "seated-leg-curl", "leg-press", "seated-calf-raise"],
                // Quads
                ["barbell-front-squat", "goblet-squat", "leg-extension", "seated-leg-curl", "standing-calf-raise"],
                // Hamstrings & glutes
                ["barbell-deadlift", "dumbbell-romanian-deadlift", "lying-leg-curl", "cable-glute-kickback", "seated-calf-raise"],
            ]
        ),
        Entry(
            id: "full-body",
            name: "Full Body",
            muscleFocus: [.chest, .back, .quads, .hamstrings],
            workouts: [
                ["barbell-back-squat", "barbell-bench-press", "barbell-row", "barbell-romanian-deadlift", "dumbbell-lateral-raise", "barbell-curl", "cable-triceps-pushdown"],
                ["leg-press", "incline-dumbbell-bench-press", "pull-up", "lying-leg-curl", "dumbbell-shoulder-press", "dumbbell-hammer-curl", "cable-overhead-extension"],
            ]
        ),
        Entry(
            id: "push-pull-legs",
            name: "Push, Pull, Legs",
            muscleFocus: [.chest, .back, .quads, .shoulders],
            workouts: [
                // Push
                ["barbell-bench-press", "barbell-overhead-press", "incline-dumbbell-bench-press", "cable-lateral-raise", "cable-chest-fly", "cable-triceps-pushdown", "cable-overhead-extension"],
                // Pull
                ["pull-up", "barbell-row", "seated-cable-row", "cable-face-pull", "barbell-curl", "dumbbell-hammer-curl"],
                // Legs
                ["barbell-back-squat", "barbell-romanian-deadlift", "leg-press", "lying-leg-curl", "leg-extension", "standing-calf-raise"],
            ]
        ),
    ]

    /// Inserts any built-in template that isn't stored yet. Existing ones are left alone so user edits stick.
    @MainActor
    static func seed(in context: ModelContext) throws {
        let existingIDs = Set(try context.fetch(FetchDescriptor<TemplateProgram>()).compactMap(\.catalogID))
        let missing = entries.filter { !existingIDs.contains($0.id) }
        guard !missing.isEmpty else { return }

        let exercisesByID = Dictionary(
            try context.fetch(FetchDescriptor<Exercise>()).compactMap { exercise in exercise.catalogID.map { ($0, exercise) } },
            uniquingKeysWith: { first, _ in first }
        )
        var changed = false
        for entry in missing {
            guard let template = entry.makeTemplate(exercisesByID: exercisesByID) else { continue }
            context.insert(template)
            changed = true
        }

        guard changed else { return }
        try context.save()
    }
}
