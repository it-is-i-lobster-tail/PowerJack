import SwiftData

enum ExerciseCatalog {
    struct Entry {
        let id: String
        let name: String
        let equipment: Equipment
        let primaryMuscle: Muscle
        let minReps: Int
        let maxReps: Int
        let secondaryMuscles: [Muscle]

        init(
            _ id: String,
            _ name: String,
            _ equipment: Equipment,
            _ primaryMuscle: Muscle,
            _ minReps: Int,
            _ maxReps: Int,
            _ secondaryMuscles: [Muscle] = []
        ) {
            self.id = id
            self.name = name
            self.equipment = equipment
            self.primaryMuscle = primaryMuscle
            self.minReps = minReps
            self.maxReps = maxReps
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
                maxReps: maxReps
            )
            exercise.catalogID = id
            return exercise
        }

        /// Refreshes progression data on an already-seeded catalog exercise.
        /// Display fields are left alone so renamed rows stay renamed.
        func backfill(_ exercise: Exercise) -> Bool {
            guard exercise.minReps != minReps ||
                    exercise.maxReps != maxReps ||
                    exercise.secondaryMusclesValue != secondaryMuscles
            else {
                return false
            }
            exercise.minReps = minReps
            exercise.maxReps = maxReps
            exercise.secondaryMuscles = secondaryMuscles
            return true
        }
    }

    // IDs are permanent: changing a display name must not create another exercise.
    // Rep ranges and secondary muscles come from the original PowerJack reference catalog.
    static let entries: [Entry] = [
        Entry("barbell-bench-press", "Barbell Bench Press", .barbell, .chest, 5, 12, [.triceps, .shoulders]),
        Entry("incline-barbell-bench-press", "Incline Barbell Bench Press", .barbell, .chest, 6, 12, [.triceps, .shoulders]),
        Entry("dumbbell-bench-press", "Dumbbell Bench Press", .dumbbell, .chest, 6, 12, [.triceps, .shoulders]),
        Entry("incline-dumbbell-bench-press", "Incline Dumbbell Bench Press", .dumbbell, .chest, 6, 12, [.triceps, .shoulders]),
        Entry("cable-chest-fly", "Cable Chest Fly", .cable, .chest, 10, 20, [.shoulders]),
        Entry("push-up", "Push Up", .bodyweight, .chest, 8, 25, [.triceps, .shoulders, .abs]),
        Entry("pull-up", "Pull Up", .bodyweight, .back, 5, 12, [.biceps, .forearms, .abs]),
        Entry("chin-up", "Chin Up", .bodyweight, .back, 5, 12, [.biceps, .forearms, .abs]),
        Entry("lat-pulldown", "Lat Pulldown", .cable, .back, 8, 15, [.biceps, .forearms]),
        Entry("seated-cable-row", "Seated Cable Row", .cable, .back, 8, 15, [.biceps, .forearms]),
        Entry("barbell-row", "Barbell Row", .barbell, .back, 6, 12, [.biceps, .forearms, .abs]),
        Entry("one-arm-dumbbell-row", "One Arm Dumbbell Row", .dumbbell, .back, 8, 15, [.biceps, .forearms, .abs]),
        Entry("barbell-deadlift", "Barbell Deadlift", .barbell, .back, 4, 8, [.glutes, .hamstrings, .quads, .forearms]),
        Entry("barbell-overhead-press", "Barbell Overhead Press", .barbell, .shoulders, 5, 10, [.triceps, .abs]),
        Entry("dumbbell-shoulder-press", "Dumbbell Shoulder Press", .dumbbell, .shoulders, 6, 12, [.triceps, .abs]),
        Entry("dumbbell-lateral-raise", "Dumbbell Lateral Raise", .dumbbell, .shoulders, 8, 20),
        Entry("cable-lateral-raise", "Cable Lateral Raise", .cable, .shoulders, 10, 25),
        Entry("dumbbell-reverse-fly", "Dumbbell Reverse Fly", .dumbbell, .shoulders, 10, 25, [.back]),
        Entry("cable-face-pull", "Cable Face Pull", .cable, .shoulders, 12, 25, [.back]),
        Entry("barbell-curl", "Barbell Curl", .barbell, .biceps, 8, 15, [.forearms]),
        Entry("dumbbell-curl", "Dumbbell Curl", .dumbbell, .biceps, 8, 15, [.forearms]),
        Entry("dumbbell-hammer-curl", "Dumbbell Hammer Curl", .dumbbell, .biceps, 8, 15, [.forearms]),
        Entry("cable-curl", "Cable Curl", .cable, .biceps, 10, 20, [.forearms]),
        Entry("cable-triceps-pushdown", "Cable Triceps Pushdown", .cable, .triceps, 10, 20),
        Entry("cable-overhead-extension", "Cable Overhead Extension", .cable, .triceps, 10, 20, [.shoulders]),
        Entry("dumbbell-triceps-extension", "Dumbbell Triceps Extension", .dumbbell, .triceps, 10, 20, [.shoulders]),
        Entry("barbell-skull-crusher", "Barbell Skull Crusher", .barbell, .triceps, 8, 15, [.shoulders]),
        Entry("barbell-back-squat", "Barbell Back Squat", .barbell, .quads, 6, 12, [.glutes, .hamstrings, .abs]),
        Entry("barbell-front-squat", "Barbell Front Squat", .barbell, .quads, 6, 12, [.glutes, .abs]),
        Entry("goblet-squat", "Goblet Squat", .kettlebell, .quads, 8, 15, [.glutes, .abs]),
        Entry("leg-press", "Leg Press", .legPress, .quads, 8, 15, [.glutes, .hamstrings]),
        Entry("leg-extension", "Leg Extension", .machine, .quads, 10, 20),
        Entry("barbell-romanian-deadlift", "Barbell Romanian Deadlift", .barbell, .hamstrings, 6, 12, [.glutes, .back, .forearms]),
        Entry("dumbbell-romanian-deadlift", "Dumbbell Romanian Deadlift", .dumbbell, .hamstrings, 8, 15, [.glutes, .back, .forearms]),
        Entry("seated-leg-curl", "Seated Leg Curl", .machine, .hamstrings, 10, 20),
        Entry("lying-leg-curl", "Lying Leg Curl", .machine, .hamstrings, 10, 20),
        Entry("barbell-hip-thrust", "Barbell Hip Thrust", .barbell, .glutes, 6, 12, [.hamstrings, .abs]),
        Entry("glute-bridge", "Glute Bridge", .bodyweight, .glutes, 10, 25, [.hamstrings]),
        Entry("cable-glute-kickback", "Cable Glute Kickback", .cable, .glutes, 12, 25, [.hamstrings]),
        Entry("standing-calf-raise", "Standing Calf Raise", .machine, .calves, 8, 20),
        Entry("seated-calf-raise", "Seated Calf Raise", .machine, .calves, 10, 25),
        Entry("crunch", "Crunch", .bodyweight, .abs, 10, 25),
        Entry("hanging-knee-raise", "Hanging Knee Raise", .bodyweight, .abs, 8, 20, [.forearms]),
        Entry("cable-crunch", "Cable Crunch", .cable, .abs, 10, 25),
        Entry("cable-woodchop", "Cable Woodchop", .cable, .obliques, 10, 20, [.abs]),
        Entry("side-plank", "Side Plank", .bodyweight, .obliques, 2, 12, [.abs]),
        Entry("dumbbell-wrist-curl", "Dumbbell Wrist Curl", .dumbbell, .forearms, 8, 20),
        Entry("dumbbell-reverse-wrist-curl", "Dumbbell Reverse Wrist Curl", .dumbbell, .forearms, 8, 20),
    ]

    @MainActor
    static func seed(in context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<Exercise>())
        let existingByID = Dictionary(
            existing.compactMap { exercise in exercise.catalogID.map { ($0, exercise) } },
            uniquingKeysWith: { first, _ in first }
        )
        var changed = false

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
}
