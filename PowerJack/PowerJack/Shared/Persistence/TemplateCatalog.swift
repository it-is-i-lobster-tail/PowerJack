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
    // Lifts stick to barbells, dumbbells, cables and bodyweight so a small gym can run every template.
    // Programs start each exercise at 2 sets, so most muscles get 3 to 5 exercises a week to grow into.
    static let entries: [Entry] = [
        Entry(
            id: "full-body-2x",
            name: "Full Body",
            muscleFocus: [.chest, .back, .quads, .hamstrings],
            workouts: [
                ["barbell-back-squat", "barbell-bench-press", "barbell-row", "dumbbell-romanian-deadlift", "dumbbell-lateral-raise", "dumbbell-curl", "cable-triceps-pushdown"],
                ["barbell-romanian-deadlift", "dumbbell-bulgarian-split-squat", "incline-dumbbell-bench-press", "lat-pulldown", "dumbbell-shoulder-press", "dumbbell-hammer-curl", "cable-overhead-extension"],
            ]
        ),
        Entry(
            id: "upper-lower-upper",
            name: "Upper Lower Upper",
            muscleFocus: [.chest, .back, .shoulders, .biceps],
            workouts: [
                // Upper
                ["barbell-bench-press", "barbell-row", "dumbbell-shoulder-press", "lat-pulldown", "cable-lateral-raise", "barbell-curl", "cable-triceps-pushdown"],
                // Lower
                ["barbell-back-squat", "barbell-romanian-deadlift", "dumbbell-walking-lunge", "cable-pull-through", "dumbbell-calf-raise", "cable-crunch"],
                // Upper
                ["incline-dumbbell-bench-press", "pull-up", "one-arm-dumbbell-row", "cable-chest-fly", "dumbbell-lateral-raise", "cable-face-pull", "dumbbell-curl"],
            ]
        ),
        Entry(
            id: "push-pull-legs-3x",
            name: "Push Pull Legs",
            muscleFocus: [.chest, .back, .hamstrings, .triceps],
            workouts: [
                // Push
                ["barbell-bench-press", "incline-dumbbell-bench-press", "dumbbell-shoulder-press", "cable-chest-fly", "cable-lateral-raise", "cable-triceps-pushdown", "cable-overhead-extension"],
                // Pull
                ["barbell-row", "lat-pulldown", "seated-cable-row", "cable-face-pull", "barbell-curl", "dumbbell-hammer-curl"],
                // Legs
                ["barbell-romanian-deadlift", "barbell-back-squat", "dumbbell-bulgarian-split-squat", "cable-pull-through", "dumbbell-calf-raise", "hanging-knee-raise"],
            ]
        ),
        Entry(
            id: "upper-lower-4x",
            name: "Upper Lower",
            muscleFocus: [.back, .shoulders, .quads, .glutes],
            workouts: [
                // Upper
                ["barbell-bench-press", "barbell-row", "dumbbell-shoulder-press", "lat-pulldown", "cable-lateral-raise", "barbell-curl", "cable-triceps-pushdown"],
                // Lower
                ["barbell-back-squat", "barbell-romanian-deadlift", "dumbbell-walking-lunge", "cable-glute-kickback", "dumbbell-calf-raise", "cable-crunch"],
                // Upper
                ["pull-up", "incline-dumbbell-bench-press", "one-arm-dumbbell-row", "dumbbell-lateral-raise", "cable-face-pull", "dumbbell-curl", "dumbbell-triceps-extension"],
                // Lower
                ["barbell-hip-thrust", "dumbbell-bulgarian-split-squat", "dumbbell-romanian-deadlift", "goblet-squat", "cable-pull-through", "dumbbell-calf-raise"],
            ]
        ),
        Entry(
            id: "lower-upper-lower",
            name: "Lower Upper Lower",
            muscleFocus: [.quads, .glutes, .hamstrings, .abs],
            workouts: [
                // Lower
                ["barbell-back-squat", "barbell-romanian-deadlift", "dumbbell-walking-lunge", "cable-pull-through", "dumbbell-calf-raise", "cable-crunch", "cable-woodchop"],
                // Upper
                ["barbell-bench-press", "barbell-row", "dumbbell-shoulder-press", "lat-pulldown", "dumbbell-lateral-raise", "dumbbell-curl", "cable-triceps-pushdown"],
                // Lower
                ["barbell-hip-thrust", "dumbbell-bulgarian-split-squat", "dumbbell-romanian-deadlift", "goblet-squat", "dumbbell-calf-raise", "hanging-knee-raise", "side-plank"],
            ]
        ),
        Entry(
            id: "upper-lower-5x",
            name: "Upper Lower Plus",
            muscleFocus: [.chest, .back, .biceps, .triceps],
            workouts: [
                // Upper
                ["barbell-bench-press", "barbell-row", "dumbbell-shoulder-press", "lat-pulldown", "cable-lateral-raise", "barbell-curl", "cable-triceps-pushdown"],
                // Lower
                ["barbell-back-squat", "barbell-romanian-deadlift", "dumbbell-walking-lunge", "cable-pull-through", "dumbbell-calf-raise", "cable-crunch"],
                // Upper
                ["incline-dumbbell-bench-press", "pull-up", "seated-cable-row", "cable-chest-fly", "dumbbell-lateral-raise", "dumbbell-hammer-curl", "cable-overhead-extension"],
                // Lower
                ["barbell-hip-thrust", "dumbbell-bulgarian-split-squat", "dumbbell-romanian-deadlift", "goblet-squat", "dumbbell-calf-raise", "hanging-knee-raise"],
                // Upper
                ["dumbbell-bench-press", "chin-up", "one-arm-dumbbell-row", "cable-face-pull", "dumbbell-curl", "barbell-skull-crusher", "dumbbell-triceps-extension"],
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
