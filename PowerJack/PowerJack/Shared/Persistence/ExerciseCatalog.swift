import SwiftData

enum ExerciseCatalog {
    struct Entry {
        let id: String
        let name: String
        let equipment: Equipment
        let primaryMuscle: Muscle
        let minReps: Int
        let maxReps: Int
        let fatigueLevel: FatigueLevel
        let secondaryMuscles: [Muscle]

        init(
            _ id: String,
            _ name: String,
            _ equipment: Equipment,
            _ primaryMuscle: Muscle,
            _ minReps: Int,
            _ maxReps: Int,
            _ fatigueLevel: FatigueLevel,
            _ secondaryMuscles: [Muscle] = []
        ) {
            self.id = id
            self.name = name
            self.equipment = equipment
            self.primaryMuscle = primaryMuscle
            self.minReps = minReps
            self.maxReps = maxReps
            self.fatigueLevel = fatigueLevel
            self.secondaryMuscles = secondaryMuscles
        }

        func makeExercise() -> Exercise {
            let exercise = Exercise(
                exerciseName: name,
                exerciseEquipment: equipment,
                primaryMuscleFocus: primaryMuscle,
                secondaryMuscles: secondaryMuscles,
                userCreated: false,
                minReps: minReps,
                maxReps: maxReps,
                fatigueLevel: fatigueLevel
            )
            exercise.catalogID = id
            return exercise
        }

        /// Refreshes progression and rest data on an already-seeded catalog exercise.
        /// Display fields are left alone so renamed rows stay renamed.
        func backfill(_ exercise: Exercise) -> Bool {
            guard exercise.minReps != minReps ||
                    exercise.maxReps != maxReps ||
                    exercise.secondaryMusclesValue != secondaryMuscles ||
                    exercise.fatigueLevel != fatigueLevel
            else {
                return false
            }
            exercise.minReps = minReps
            exercise.maxReps = maxReps
            exercise.secondaryMuscles = secondaryMuscles
            exercise.fatigueLevel = fatigueLevel
            return true
        }
    }

    // IDs are permanent: changing a display name must not create another exercise.
    // Rep ranges and secondary muscles come from the original PowerJack reference catalog.
    // Borderline fatigue levels round up: too much rest beats too little.
    static let entries: [Entry] = [
        Entry("barbell-bench-press", "Barbell Bench Press", .barbell, .chest, 5, 12, .high, [.triceps, .shoulders]),
        Entry("incline-barbell-bench-press", "Incline Barbell Bench Press", .barbell, .chest, 6, 12, .high, [.triceps, .shoulders]),
        Entry("dumbbell-bench-press", "Dumbbell Bench Press", .dumbbell, .chest, 6, 12, .moderate, [.triceps, .shoulders]),
        Entry("incline-dumbbell-bench-press", "Incline Dumbbell Bench Press", .dumbbell, .chest, 6, 12, .moderate, [.triceps, .shoulders]),
        Entry("cable-chest-fly", "Cable Chest Fly", .cable, .chest, 10, 20, .low, [.shoulders]),
        Entry("push-up", "Push Up", .bodyweight, .chest, 8, 25, .moderate, [.triceps, .shoulders, .abs]),
        Entry("pull-up", "Pull Up", .bodyweight, .back, 5, 12, .moderate, [.biceps, .forearms, .abs]),
        Entry("chin-up", "Chin Up", .bodyweight, .back, 5, 12, .moderate, [.biceps, .forearms, .abs]),
        Entry("lat-pulldown", "Lat Pulldown", .cable, .back, 8, 15, .moderate, [.biceps, .forearms]),
        Entry("seated-cable-row", "Seated Cable Row", .cable, .back, 8, 15, .moderate, [.biceps, .forearms]),
        Entry("barbell-row", "Barbell Row", .barbell, .back, 6, 12, .high, [.biceps, .forearms, .abs]),
        Entry("one-arm-dumbbell-row", "One Arm Dumbbell Row", .dumbbell, .back, 8, 15, .moderate, [.biceps, .forearms, .abs]),
        Entry("barbell-deadlift", "Barbell Deadlift", .barbell, .back, 4, 8, .high, [.glutes, .hamstrings, .quads, .forearms]),
        Entry("barbell-overhead-press", "Barbell Overhead Press", .barbell, .shoulders, 5, 10, .high, [.triceps, .abs]),
        Entry("dumbbell-shoulder-press", "Dumbbell Shoulder Press", .dumbbell, .shoulders, 6, 12, .moderate, [.triceps, .abs]),
        Entry("dumbbell-lateral-raise", "Dumbbell Lateral Raise", .dumbbell, .shoulders, 8, 20, .low),
        Entry("cable-lateral-raise", "Cable Lateral Raise", .cable, .shoulders, 10, 25, .low),
        Entry("dumbbell-reverse-fly", "Dumbbell Reverse Fly", .dumbbell, .shoulders, 10, 25, .low, [.back]),
        Entry("cable-face-pull", "Cable Face Pull", .cable, .shoulders, 12, 25, .low, [.back]),
        Entry("barbell-curl", "Barbell Curl", .barbell, .biceps, 8, 15, .low, [.forearms]),
        Entry("dumbbell-curl", "Dumbbell Curl", .dumbbell, .biceps, 8, 15, .low, [.forearms]),
        Entry("dumbbell-hammer-curl", "Dumbbell Hammer Curl", .dumbbell, .biceps, 8, 15, .low, [.forearms]),
        Entry("cable-curl", "Cable Curl", .cable, .biceps, 10, 20, .low, [.forearms]),
        Entry("cable-triceps-pushdown", "Cable Triceps Pushdown", .cable, .triceps, 10, 20, .low),
        Entry("cable-overhead-extension", "Cable Overhead Extension", .cable, .triceps, 10, 20, .low, [.shoulders]),
        Entry("dumbbell-triceps-extension", "Dumbbell Triceps Extension", .dumbbell, .triceps, 10, 20, .low, [.shoulders]),
        Entry("barbell-skull-crusher", "Barbell Skull Crusher", .barbell, .triceps, 8, 15, .low, [.shoulders]),
        Entry("barbell-back-squat", "Barbell Back Squat", .barbell, .quads, 6, 12, .high, [.glutes, .hamstrings, .abs]),
        Entry("barbell-front-squat", "Barbell Front Squat", .barbell, .quads, 6, 12, .high, [.glutes, .abs]),
        Entry("goblet-squat", "Goblet Squat", .kettlebell, .quads, 8, 15, .moderate, [.glutes, .abs]),
        Entry("leg-press", "Leg Press", .legPress, .quads, 8, 15, .high, [.glutes, .hamstrings]),
        Entry("leg-extension", "Leg Extension", .machine, .quads, 10, 20, .low),
        Entry("barbell-romanian-deadlift", "Barbell Romanian Deadlift", .barbell, .hamstrings, 6, 12, .high, [.glutes, .back, .forearms]),
        Entry("dumbbell-romanian-deadlift", "Dumbbell Romanian Deadlift", .dumbbell, .hamstrings, 8, 15, .moderate, [.glutes, .back, .forearms]),
        Entry("seated-leg-curl", "Seated Leg Curl", .machine, .hamstrings, 10, 20, .low),
        Entry("lying-leg-curl", "Lying Leg Curl", .machine, .hamstrings, 10, 20, .low),
        Entry("barbell-hip-thrust", "Barbell Hip Thrust", .barbell, .glutes, 6, 12, .high, [.hamstrings, .abs]),
        Entry("glute-bridge", "Glute Bridge", .bodyweight, .glutes, 10, 25, .low, [.hamstrings]),
        Entry("cable-glute-kickback", "Cable Glute Kickback", .cable, .glutes, 12, 25, .low, [.hamstrings]),
        Entry("standing-calf-raise", "Standing Calf Raise", .machine, .calves, 8, 20, .low),
        Entry("seated-calf-raise", "Seated Calf Raise", .machine, .calves, 10, 25, .low),
        Entry("crunch", "Crunch", .bodyweight, .abs, 10, 25, .low),
        Entry("hanging-knee-raise", "Hanging Knee Raise", .bodyweight, .abs, 8, 20, .low, [.forearms]),
        Entry("cable-crunch", "Cable Crunch", .cable, .abs, 10, 25, .low),
        Entry("cable-woodchop", "Cable Woodchop", .cable, .obliques, 10, 20, .low, [.abs]),
        Entry("side-plank", "Side Plank", .bodyweight, .obliques, 2, 12, .low, [.abs]),
        Entry("dumbbell-wrist-curl", "Dumbbell Wrist Curl", .dumbbell, .forearms, 8, 20, .low),
        Entry("dumbbell-reverse-wrist-curl", "Dumbbell Reverse Wrist Curl", .dumbbell, .forearms, 8, 20, .low),
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
