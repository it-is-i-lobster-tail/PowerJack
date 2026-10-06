import SwiftData

enum ExerciseCatalog {
    struct Entry {
        let id: String
        let name: String
        let equipment: Equipment
        let primaryMuscle: Muscle
        let fatigueLevel: FatigueLevel
        let secondaryMuscles: [Muscle]

        init(
            _ id: String,
            _ name: String,
            _ equipment: Equipment,
            _ primaryMuscle: Muscle,
            _ fatigueLevel: FatigueLevel,
            _ secondaryMuscles: [Muscle] = []
        ) {
            self.id = id
            self.name = name
            self.equipment = equipment
            self.primaryMuscle = primaryMuscle
            self.fatigueLevel = fatigueLevel
            self.secondaryMuscles = secondaryMuscles
        }

        var minReps: Int { Exercise.defaultMinReps }
        var maxReps: Int { fatigueLevel.defaultMaxReps }

        func makeExercise() -> Exercise {
            let exercise = Exercise(
                exerciseName: name,
                exerciseEquipment: equipment,
                primaryMuscleFocus: primaryMuscle,
                secondaryMuscles: secondaryMuscles,
                userCreated: false,
                fatigueLevel: fatigueLevel
            )
            exercise.catalogID = id
            return exercise
        }

        /// Refreshes secondary muscles on an already-seeded catalog exercise.
        /// Display fields are left alone so renamed rows stay renamed, and rep range
        /// and fatigue are left alone because the user can edit them.
        func backfill(_ exercise: Exercise) -> Bool {
            guard exercise.secondaryMusclesValue != secondaryMuscles else { return false }
            exercise.secondaryMuscles = secondaryMuscles
            return true
        }
    }

    // IDs are permanent: changing a display name must not create another exercise.
    // Secondary muscles come from the original PowerJack reference catalog.
    // Rep ranges are the defaults: 5 reps up to the fatigue level's max.
    // Borderline fatigue levels round up: too much rest beats too little.
    static let entries: [Entry] = [
        Entry("barbell-bench-press", "Barbell Bench Press", .barbell, .chest, .high, [.triceps, .shoulders]),
        Entry("incline-barbell-bench-press", "Incline Barbell Bench Press", .barbell, .chest, .high, [.triceps, .shoulders]),
        Entry("dumbbell-bench-press", "Dumbbell Bench Press", .dumbbell, .chest, .moderate, [.triceps, .shoulders]),
        Entry("incline-dumbbell-bench-press", "Incline Dumbbell Bench Press", .dumbbell, .chest, .moderate, [.triceps, .shoulders]),
        Entry("cable-chest-fly", "Cable Chest Fly", .cable, .chest, .low, [.shoulders]),
        Entry("push-up", "Push Up", .bodyweight, .chest, .moderate, [.triceps, .shoulders, .abs]),
        Entry("pull-up", "Pull Up", .bodyweight, .back, .moderate, [.biceps, .forearms, .abs]),
        Entry("chin-up", "Chin Up", .bodyweight, .back, .moderate, [.biceps, .forearms, .abs]),
        Entry("lat-pulldown", "Lat Pulldown", .cable, .back, .moderate, [.biceps, .forearms]),
        Entry("seated-cable-row", "Seated Cable Row", .cable, .back, .moderate, [.biceps, .forearms]),
        Entry("barbell-row", "Barbell Row", .barbell, .back, .high, [.biceps, .forearms, .abs]),
        Entry("one-arm-dumbbell-row", "One Arm Dumbbell Row", .dumbbell, .back, .moderate, [.biceps, .forearms, .abs]),
        Entry("barbell-deadlift", "Barbell Deadlift", .barbell, .back, .high, [.glutes, .hamstrings, .quads, .forearms]),
        Entry("barbell-overhead-press", "Barbell Overhead Press", .barbell, .shoulders, .high, [.triceps, .abs]),
        Entry("dumbbell-shoulder-press", "Dumbbell Shoulder Press", .dumbbell, .shoulders, .moderate, [.triceps, .abs]),
        Entry("dumbbell-lateral-raise", "Dumbbell Lateral Raise", .dumbbell, .shoulders, .low),
        Entry("cable-lateral-raise", "Cable Lateral Raise", .cable, .shoulders, .low),
        Entry("dumbbell-reverse-fly", "Dumbbell Reverse Fly", .dumbbell, .shoulders, .low, [.back]),
        Entry("cable-face-pull", "Cable Face Pull", .cable, .shoulders, .low, [.back]),
        Entry("barbell-curl", "Barbell Curl", .barbell, .biceps, .low, [.forearms]),
        Entry("dumbbell-curl", "Dumbbell Curl", .dumbbell, .biceps, .low, [.forearms]),
        Entry("dumbbell-hammer-curl", "Dumbbell Hammer Curl", .dumbbell, .biceps, .low, [.forearms]),
        Entry("cable-curl", "Cable Curl", .cable, .biceps, .low, [.forearms]),
        Entry("cable-triceps-pushdown", "Cable Triceps Pushdown", .cable, .triceps, .low),
        Entry("cable-overhead-extension", "Cable Overhead Extension", .cable, .triceps, .low, [.shoulders]),
        Entry("dumbbell-triceps-extension", "Dumbbell Triceps Extension", .dumbbell, .triceps, .low, [.shoulders]),
        Entry("barbell-skull-crusher", "Barbell Skull Crusher", .barbell, .triceps, .low, [.shoulders]),
        Entry("barbell-back-squat", "Barbell Back Squat", .barbell, .quads, .high, [.glutes, .hamstrings, .abs]),
        Entry("barbell-front-squat", "Barbell Front Squat", .barbell, .quads, .high, [.glutes, .abs]),
        Entry("goblet-squat", "Goblet Squat", .kettlebell, .quads, .moderate, [.glutes, .abs]),
        Entry("leg-press", "Leg Press", .legPress, .quads, .high, [.glutes, .hamstrings]),
        Entry("leg-extension", "Leg Extension", .machine, .quads, .low),
        Entry("barbell-romanian-deadlift", "Barbell Romanian Deadlift", .barbell, .hamstrings, .high, [.glutes, .back, .forearms]),
        Entry("dumbbell-romanian-deadlift", "Dumbbell Romanian Deadlift", .dumbbell, .hamstrings, .moderate, [.glutes, .back, .forearms]),
        Entry("seated-leg-curl", "Seated Leg Curl", .machine, .hamstrings, .low),
        Entry("lying-leg-curl", "Lying Leg Curl", .machine, .hamstrings, .low),
        Entry("barbell-hip-thrust", "Barbell Hip Thrust", .barbell, .glutes, .high, [.hamstrings, .abs]),
        Entry("glute-bridge", "Glute Bridge", .bodyweight, .glutes, .low, [.hamstrings]),
        Entry("cable-glute-kickback", "Cable Glute Kickback", .cable, .glutes, .low, [.hamstrings]),
        Entry("standing-calf-raise", "Standing Calf Raise", .machine, .calves, .low),
        Entry("seated-calf-raise", "Seated Calf Raise", .machine, .calves, .low),
        Entry("crunch", "Crunch", .bodyweight, .abs, .low),
        Entry("hanging-knee-raise", "Hanging Knee Raise", .bodyweight, .abs, .low, [.forearms]),
        Entry("cable-crunch", "Cable Crunch", .cable, .abs, .low),
        Entry("cable-woodchop", "Cable Woodchop", .cable, .obliques, .low, [.abs]),
        Entry("side-plank", "Side Plank", .bodyweight, .obliques, .low, [.abs]),
        Entry("dumbbell-wrist-curl", "Dumbbell Wrist Curl", .dumbbell, .forearms, .low),
        Entry("dumbbell-reverse-wrist-curl", "Dumbbell Reverse Wrist Curl", .dumbbell, .forearms, .low),
    ]

    @MainActor
    static func seed(in context: ModelContext) throws {
        var changed = try removeDuplicates(in: context)
        let existing = try context.fetch(FetchDescriptor<Exercise>())
        let existingByID = Dictionary(
            existing.compactMap { exercise in exercise.catalogID.map { ($0, exercise) } },
            uniquingKeysWith: { first, _ in first }
        )

        for entry in entries {
            if let exercise = existingByID[entry.id] {
                changed = entry.backfill(exercise) || changed
            } else {
                context.insert(entry.makeExercise())
                changed = true
            }
        }

        guard changed else { return }
        try context.save()
    }

    /// Merges copies of the same catalog exercise. A new device seeds the catalog before its
    /// synced data arrives, so both copies can end up stored. The oldest copy survives on every
    /// device, and rows that used a duplicate are pointed at it.
    /// - Returns: Whether anything changed. The caller saves.
    @MainActor
    static func removeDuplicates(in context: ModelContext) throws -> Bool {
        let catalogExercises = try context.fetch(FetchDescriptor<Exercise>()).filter { $0.catalogID != nil }
        var changed = false

        for copies in Dictionary(grouping: catalogExercises, by: \.catalogID).values where copies.count > 1 {
            let oldestFirst = copies.sorted { $0.createdAtValue < $1.createdAtValue }
            let survivor = oldestFirst[0]
            for duplicate in oldestFirst.dropFirst() {
                for row in duplicate.templateExercisesValue ?? [] {
                    row.exercise = survivor
                }
                for row in duplicate.workoutExercisesValue ?? [] {
                    row.replaceDuplicateExercise(with: survivor)
                }
                context.delete(duplicate)
            }
            changed = true
        }
        return changed
    }
}
