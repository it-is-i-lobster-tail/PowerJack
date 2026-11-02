import OSLog
import SwiftData

/// Built-in templates for experienced lifters, listed under their type's section.
/// Exercises reference `ExerciseCatalog` IDs, so seed the exercise catalog first.
enum TemplateCatalog {
    struct Entry {
        let id: String
        let name: String
        var type: TemplateType = .hypertrophy
        let muscleFocus: [Muscle]
        /// One list of exercise catalog IDs per workout, in order.
        let workouts: [[String]]

        func makeTemplate(exercisesByID: [String: Exercise]) -> TemplateProgram? {
            let template = TemplateProgram(
                templateName: name,
                workoutsPerWeek: workouts.count,
                templateMuscleFocus: muscleFocus,
                templateType: type
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
    // Names are the split or the lifts; the list already shows the days and focus muscles.
    // Workouts are in order, one per day. Programs start each exercise at 2 sets.
    static let entries: [Entry] = [
        // Build: every muscle trained at least twice a week (START-01). Full gym unless named Home.
        Entry(
            id: "build-full-body-3x",
            name: "Full Body",
            muscleFocus: [.chest, .back, .quads, .shoulders],
            workouts: [
                ["barbell-back-squat", "dumbbell-bench-press", "chest-supported-dumbbell-row", "seated-leg-curl", "dumbbell-lateral-raise", "cable-overhead-extension", "standing-calf-raise"],
                ["barbell-romanian-deadlift", "incline-dumbbell-bench-press", "lat-pulldown", "leg-extension", "dumbbell-curl", "seated-calf-raise", "cable-crunch"],
                ["hack-squat", "seated-cable-row", "cable-chest-fly", "cable-lateral-raise", "incline-dumbbell-curl", "cable-triceps-pushdown", "hanging-leg-raise"],
            ]
        ),
        Entry(
            id: "build-upper-lower-4x",
            name: "Upper Lower",
            muscleFocus: [.chest, .back, .quads, .hamstrings],
            workouts: [
                ["barbell-bench-press", "chest-supported-dumbbell-row", "incline-dumbbell-bench-press", "lat-pulldown", "dumbbell-lateral-raise", "cable-triceps-pushdown", "dumbbell-curl"],
                ["barbell-back-squat", "barbell-romanian-deadlift", "leg-extension", "seated-leg-curl", "standing-calf-raise", "cable-crunch"],
                ["dumbbell-shoulder-press", "pull-up", "cable-chest-fly", "seated-cable-row", "cable-lateral-raise", "cable-overhead-extension", "incline-dumbbell-curl"],
                ["hack-squat", "dumbbell-bulgarian-split-squat", "lying-leg-curl", "seated-calf-raise", "hanging-leg-raise"],
            ]
        ),
        Entry(
            id: "build-physique-5x",
            name: "Physique",
            muscleFocus: [.shoulders, .chest, .back, .biceps],
            workouts: [
                // Push, pull, legs, upper, lower.
                ["barbell-bench-press", "incline-dumbbell-bench-press", "dumbbell-shoulder-press", "dumbbell-lateral-raise", "cable-triceps-pushdown", "cable-overhead-extension"],
                ["pull-up", "chest-supported-dumbbell-row", "seated-cable-row", "cable-face-pull", "dumbbell-curl", "dumbbell-hammer-curl"],
                ["barbell-back-squat", "barbell-romanian-deadlift", "leg-extension", "seated-leg-curl", "standing-calf-raise", "cable-crunch"],
                ["dumbbell-bench-press", "lat-pulldown", "cable-chest-fly", "cable-lateral-raise", "incline-dumbbell-curl", "barbell-skull-crusher"],
                ["hack-squat", "lying-leg-curl", "dumbbell-bulgarian-split-squat", "seated-calf-raise", "hanging-leg-raise"],
            ]
        ),
        Entry(
            // Dumbbells, a bench and a pull-up bar.
            id: "build-home-full-body-3x",
            name: "Home Full Body",
            muscleFocus: [.chest, .back, .quads, .glutes],
            workouts: [
                ["dumbbell-bulgarian-split-squat", "dumbbell-bench-press", "pull-up", "dumbbell-romanian-deadlift", "dumbbell-lateral-raise", "dumbbell-triceps-extension", "crunch"],
                ["dumbbell-goblet-squat", "incline-dumbbell-bench-press", "chest-supported-dumbbell-row", "sliding-leg-curl", "dumbbell-curl", "dumbbell-calf-raise", "hanging-leg-raise"],
                ["dumbbell-walking-lunge", "dumbbell-shoulder-press", "push-up", "one-arm-dumbbell-row", "incline-dumbbell-curl", "dumbbell-triceps-extension", "dumbbell-calf-raise"],
            ]
        ),
        // Strengthen: a barbell, rack, bench, dumbbells and a pull-up bar. Each day opens with a priority
        // lift; one trained twice a week gets a heavy day, then a moderate one (rule 5.3).
        Entry(
            id: "strength-big-three-3x",
            name: "Big Three",
            type: .strength,
            muscleFocus: [.quads, .glutes, .chest, .back],
            workouts: [
                ["barbell-back-squat", "barbell-bench-press", "barbell-row", "hanging-leg-raise"],
                ["barbell-deadlift", "barbell-overhead-press", "chin-up", "dip"],
                ["barbell-back-squat", "barbell-bench-press", "barbell-romanian-deadlift", "one-arm-dumbbell-row"],
            ]
        ),
        Entry(
            id: "strength-big-four-4x",
            name: "Big Four",
            type: .strength,
            muscleFocus: [.quads, .chest, .back, .shoulders],
            workouts: [
                ["barbell-back-squat", "barbell-romanian-deadlift", "dumbbell-bulgarian-split-squat", "hanging-leg-raise"],
                ["barbell-bench-press", "barbell-row", "dip", "barbell-curl"],
                ["barbell-deadlift", "barbell-front-squat", "one-arm-dumbbell-row", "hanging-leg-raise"],
                ["barbell-overhead-press", "barbell-bench-press", "chin-up", "dumbbell-lateral-raise"],
            ]
        ),
        Entry(
            id: "strength-bigger-total-5x",
            name: "Bigger Total",
            type: .strength,
            muscleFocus: [.quads, .chest, .back, .triceps],
            workouts: [
                ["barbell-back-squat", "barbell-bench-press", "barbell-row", "hanging-leg-raise"],
                ["barbell-deadlift", "barbell-overhead-press", "chin-up", "barbell-curl"],
                ["barbell-bench-press", "barbell-front-squat", "one-arm-dumbbell-row", "dip"],
                ["barbell-back-squat", "barbell-romanian-deadlift", "dumbbell-bulgarian-split-squat", "hanging-leg-raise"],
                ["barbell-bench-press", "close-grip-bench-press", "chest-supported-dumbbell-row", "dumbbell-lateral-raise"],
            ]
        ),
        // PowerJack: the squat, deadlift, bench and overhead press come before any other lift of their
        // pattern, so they are the main lifts (R1.1).
        Entry(
            // The same setup as Strengthen.
            id: "powerjack-power-full-body-3x",
            name: "Power Full Body",
            type: .powerJack,
            muscleFocus: [.quads, .chest, .back, .shoulders],
            workouts: [
                ["barbell-back-squat", "barbell-bench-press", "barbell-row", "sliding-leg-curl", "dumbbell-lateral-raise", "barbell-curl"],
                ["barbell-deadlift", "barbell-overhead-press", "pull-up", "dumbbell-bulgarian-split-squat", "barbell-skull-crusher", "hanging-leg-raise"],
                ["barbell-back-squat", "barbell-bench-press", "dumbbell-romanian-deadlift", "chest-supported-dumbbell-row", "dumbbell-hammer-curl", "dumbbell-calf-raise"],
            ]
        ),
        Entry(
            id: "powerjack-power-upper-lower-4x",
            name: "Power Upper Lower",
            type: .powerJack,
            muscleFocus: [.chest, .back, .quads, .hamstrings],
            workouts: [
                ["barbell-bench-press", "barbell-row", "barbell-overhead-press", "lat-pulldown", "dumbbell-lateral-raise", "cable-triceps-pushdown", "barbell-curl"],
                ["barbell-back-squat", "barbell-deadlift", "leg-press", "seated-leg-curl", "standing-calf-raise", "cable-crunch"],
                ["barbell-bench-press", "chin-up", "incline-dumbbell-bench-press", "seated-cable-row", "dumbbell-lateral-raise", "dumbbell-hammer-curl"],
                ["barbell-back-squat", "barbell-romanian-deadlift", "dumbbell-walking-lunge", "leg-extension", "seated-calf-raise", "hanging-leg-raise"],
            ]
        ),
        Entry(
            id: "powerjack-power-and-pump-5x",
            name: "Power & Pump",
            type: .powerJack,
            muscleFocus: [.chest, .back, .shoulders, .quads],
            workouts: [
                // Heavy upper and lower days, then back and shoulders, legs, and chest and arms.
                ["barbell-bench-press", "barbell-row", "barbell-overhead-press", "pull-up", "barbell-skull-crusher", "barbell-curl"],
                ["barbell-back-squat", "barbell-deadlift", "seated-leg-curl", "standing-calf-raise", "hanging-leg-raise"],
                ["chest-supported-dumbbell-row", "lat-pulldown", "dumbbell-shoulder-press", "dumbbell-lateral-raise", "cable-face-pull", "dumbbell-curl"],
                ["barbell-back-squat", "barbell-romanian-deadlift", "hack-squat", "leg-extension", "lying-leg-curl", "seated-calf-raise"],
                ["barbell-bench-press", "incline-dumbbell-bench-press", "cable-chest-fly", "cable-triceps-pushdown", "incline-dumbbell-curl", "cable-crunch"],
            ]
        ),
    ]

    /// Built-in templates the app no longer ships. Seeding hides them the way deleting a built-in
    /// template does: programs started from one keep it, and an older app version won't seed it again.
    static let retiredIDs: Set<String> = [
        "home-whole-body-essentials-2x",
        "small-gym-whole-body-essentials-2x",
        "full-gym-legs-core-focus-2x",
        "home-whole-body-muscle-builder-3x",
        "small-gym-whole-body-muscle-builder-3x",
        "full-gym-arms-focus-3x",
        "full-gym-chest-back-core-focus-3x",
        "full-gym-whole-body-muscle-builder-4x",
        "small-gym-glutes-shoulders-focus-4x",
        "full-gym-upper-body-specialization-5x",
        "full-gym-glute-specialization-5x",
        "full-gym-strength-foundations-3x",
        "full-gym-upper-lower-strength-4x",
        "powerjack-whole-body-3x",
        "powerjack-upper-lower-4x",
    ]

    /// Inserts any built-in template that isn't stored yet and hides retired ones. Existing ones are left
    /// alone so user edits stick.
    @MainActor
    static func seed(in context: ModelContext) throws {
        var changed = try removeDuplicates(in: context)
        let stored = try context.fetch(FetchDescriptor<TemplateProgram>())
        changed = hideRetired(stored) || changed
        let existingIDs = Set(stored.compactMap(\.catalogID))
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

    /// Hides retired built-in templates that are still listed.
    /// - Returns: Whether any were. The caller saves.
    @MainActor
    private static func hideRetired(_ templates: [TemplateProgram]) -> Bool {
        let showing = templates.filter { retiredIDs.contains($0.catalogID ?? "") && !$0.hiddenValue }
        for template in showing {
            // Only hides it: `delete()` never removes a built-in template.
            template.delete()
        }
        return !showing.isEmpty
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
