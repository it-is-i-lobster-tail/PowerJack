import SwiftData

enum ExerciseCatalog {
    struct Entry {
        let id: String
        let name: String
        let equipment: Equipment
        let primaryMuscle: Muscle

        init(_ id: String, _ name: String, _ equipment: Equipment, _ primaryMuscle: Muscle) {
            self.id = id
            self.name = name
            self.equipment = equipment
            self.primaryMuscle = primaryMuscle
        }

        func makeExercise() -> Exercise {
            let exercise = Exercise(
                exerciseName: name,
                exerciseEquipment: equipment,
                primaryMuscleFocus: primaryMuscle,
                userCreated: false
            )
            exercise.catalogID = id
            return exercise
        }
    }

    // IDs are permanent: changing a display name must not create another exercise.
    static let entries: [Entry] = [
        Entry("barbell-bench-press", "Barbell Bench Press", .barbell, .chest),
        Entry("incline-barbell-bench-press", "Incline Barbell Bench Press", .barbell, .chest),
        Entry("dumbbell-bench-press", "Dumbbell Bench Press", .dumbbell, .chest),
        Entry("incline-dumbbell-bench-press", "Incline Dumbbell Bench Press", .dumbbell, .chest),
        Entry("cable-chest-fly", "Cable Chest Fly", .cable, .chest),
        Entry("push-up", "Push Up", .bodyweight, .chest),
        Entry("pull-up", "Pull Up", .bodyweight, .back),
        Entry("chin-up", "Chin Up", .bodyweight, .back),
        Entry("lat-pulldown", "Lat Pulldown", .cable, .back),
        Entry("seated-cable-row", "Seated Cable Row", .cable, .back),
        Entry("barbell-row", "Barbell Row", .barbell, .back),
        Entry("one-arm-dumbbell-row", "One Arm Dumbbell Row", .dumbbell, .back),
        Entry("barbell-deadlift", "Barbell Deadlift", .barbell, .back),
        Entry("barbell-overhead-press", "Barbell Overhead Press", .barbell, .shoulders),
        Entry("dumbbell-shoulder-press", "Dumbbell Shoulder Press", .dumbbell, .shoulders),
        Entry("dumbbell-lateral-raise", "Dumbbell Lateral Raise", .dumbbell, .shoulders),
        Entry("cable-lateral-raise", "Cable Lateral Raise", .cable, .shoulders),
        Entry("dumbbell-reverse-fly", "Dumbbell Reverse Fly", .dumbbell, .shoulders),
        Entry("cable-face-pull", "Cable Face Pull", .cable, .shoulders),
        Entry("barbell-curl", "Barbell Curl", .barbell, .biceps),
        Entry("dumbbell-curl", "Dumbbell Curl", .dumbbell, .biceps),
        Entry("dumbbell-hammer-curl", "Dumbbell Hammer Curl", .dumbbell, .biceps),
        Entry("cable-curl", "Cable Curl", .cable, .biceps),
        Entry("cable-triceps-pushdown", "Cable Triceps Pushdown", .cable, .triceps),
        Entry("cable-overhead-extension", "Cable Overhead Extension", .cable, .triceps),
        Entry("dumbbell-triceps-extension", "Dumbbell Triceps Extension", .dumbbell, .triceps),
        Entry("barbell-skull-crusher", "Barbell Skull Crusher", .barbell, .triceps),
        Entry("barbell-back-squat", "Barbell Back Squat", .barbell, .quads),
        Entry("barbell-front-squat", "Barbell Front Squat", .barbell, .quads),
        Entry("goblet-squat", "Goblet Squat", .kettlebell, .quads),
        Entry("leg-press", "Leg Press", .legPress, .quads),
        Entry("leg-extension", "Leg Extension", .machine, .quads),
        Entry("barbell-romanian-deadlift", "Barbell Romanian Deadlift", .barbell, .hamstrings),
        Entry("dumbbell-romanian-deadlift", "Dumbbell Romanian Deadlift", .dumbbell, .hamstrings),
        Entry("seated-leg-curl", "Seated Leg Curl", .machine, .hamstrings),
        Entry("lying-leg-curl", "Lying Leg Curl", .machine, .hamstrings),
        Entry("barbell-hip-thrust", "Barbell Hip Thrust", .barbell, .glutes),
        Entry("glute-bridge", "Glute Bridge", .bodyweight, .glutes),
        Entry("cable-glute-kickback", "Cable Glute Kickback", .cable, .glutes),
        Entry("standing-calf-raise", "Standing Calf Raise", .machine, .calves),
        Entry("seated-calf-raise", "Seated Calf Raise", .machine, .calves),
        Entry("crunch", "Crunch", .bodyweight, .abs),
        Entry("hanging-knee-raise", "Hanging Knee Raise", .bodyweight, .abs),
        Entry("cable-crunch", "Cable Crunch", .cable, .abs),
        Entry("cable-woodchop", "Cable Woodchop", .cable, .obliques),
        Entry("side-plank", "Side Plank", .bodyweight, .obliques),
        Entry("dumbbell-wrist-curl", "Dumbbell Wrist Curl", .dumbbell, .forearms),
        Entry("dumbbell-reverse-wrist-curl", "Dumbbell Reverse Wrist Curl", .dumbbell, .forearms),
    ]

    @MainActor
    static func seed(in context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<Exercise>())
        let existingIDs = Set(existing.compactMap(\.catalogID))
        let missing = entries.filter { !existingIDs.contains($0.id) }
        guard !missing.isEmpty else { return }

        for entry in missing {
            context.insert(entry.makeExercise())
        }
        try context.save()
    }
}
