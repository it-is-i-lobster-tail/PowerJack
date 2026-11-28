import OSLog
import Foundation
import SwiftData

enum ExerciseCatalog {
    struct Entry {
        let profile: MovementCatalog.Profile
        let id: String
        let name: String
        let equipment: Equipment
        let equipmentName: String?
        let primaryMuscle: Muscle
        let fatigueLevel: FatigueLevel
        let secondaryMuscles: [Muscle]
        /// The level earlier versions seeded, when it has since changed.
        let previousFatigueLevel: FatigueLevel?
        /// Up to three other built-ins, by catalog ID, this one moves like, closest first.
        /// Empty when no other built-in moves like it, such as the burpee.
        let movesLike: [String]

        init(
            _ id: String,
            _ name: String,
            _ equipment: Equipment,
            _ primaryMuscle: Muscle,
            _ fatigueLevel: FatigueLevel,
            _ profile: MovementCatalog.Profile,
            _ secondaryMuscles: [Muscle] = [],
            equipmentName: String? = nil,
            was previousFatigueLevel: FatigueLevel? = nil,
            movesLike: [String] = []
        ) {
            self.profile = profile
            self.id = id
            self.name = name
            self.equipment = equipment
            self.equipmentName = equipmentName
            self.primaryMuscle = primaryMuscle
            self.fatigueLevel = fatigueLevel
            self.secondaryMuscles = secondaryMuscles
            self.previousFatigueLevel = previousFatigueLevel
            self.movesLike = movesLike
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
            exercise.customEquipmentName = equipmentName
            exercise.catalogID = id
            return exercise
        }

        /// Refreshes the muscles on an already-seeded catalog exercise.
        /// Display fields are left alone so renamed rows stay renamed, and rep range
        /// and fatigue are left alone because the user can edit them.
        func backfill(_ exercise: Exercise) -> Bool {
            guard exercise.secondaryMusclesValue != secondaryMuscles || exercise.primaryMuscleFocus != primaryMuscle else {
                return false
            }
            exercise.primaryMuscleFocus = primaryMuscle
            exercise.secondaryMuscles = secondaryMuscles
            return true
        }

        /// Moves a row still on the level earlier versions seeded to the current one. A level the
        /// user picked is kept. Max reps follows, as it does when the user changes the level.
        func updateFatigueLevel(_ exercise: Exercise) -> Bool {
            guard let previousFatigueLevel, exercise.fatigueLevel == previousFatigueLevel else { return false }
            if exercise.maxReps == previousFatigueLevel.defaultMaxReps {
                exercise.maxReps = max(fatigueLevel.defaultMaxReps, exercise.minReps)
            }
            exercise.fatigueLevel = fatigueLevel
            return true
        }
    }

    // IDs are permanent: changing a display name must not create another exercise.
    // Secondary muscles come from the original PowerJack reference catalog.
    // Rep ranges are the defaults: 5 reps up to the fatigue level's max.
    // High is kept for big lower-body lifts: squats, deadlifts, leg presses, lunges and hip thrusts.
    // `was:` marks a level that changed.
    static let entries: [Entry] = [
        Entry("barbell-bench-press", "Barbell Bench Press", .barbell, .chest, .moderate, .bench, [.triceps, .shoulders], was: .high,
              movesLike: ["dumbbell-bench-press", "machine-chest-press", "push-up"]),
        Entry("incline-barbell-bench-press", "Incline Barbell Bench Press", .barbell, .chest, .moderate, .inclineBench, [.triceps, .shoulders], was: .high,
              movesLike: ["incline-dumbbell-bench-press", "barbell-bench-press", "machine-chest-press"]),
        Entry("dumbbell-bench-press", "Dumbbell Bench Press", .dumbbell, .chest, .moderate, .bench, [.triceps, .shoulders],
              movesLike: ["barbell-bench-press", "machine-chest-press", "incline-dumbbell-bench-press"]),
        Entry("incline-dumbbell-bench-press", "Incline Dumbbell Bench Press", .dumbbell, .chest, .moderate, .inclineBench, [.triceps, .shoulders],
              movesLike: ["incline-barbell-bench-press", "dumbbell-bench-press", "machine-chest-press"]),
        Entry("cable-chest-fly", "Cable Chest Fly", .cable, .chest, .low, .fly, [.shoulders],
              movesLike: ["dumbbell-fly", "pec-deck", "incline-dumbbell-fly"]),
        Entry("push-up", "Push Up", .bodyweight, .chest, .moderate, .pushUp, [.triceps, .shoulders, .abs],
              movesLike: ["incline-push-up", "barbell-bench-press", "dumbbell-bench-press"]),
        Entry("pull-up", "Pull Up", .bodyweight, .back, .moderate, .pullUp.braced, [.biceps, .forearms, .abs],
              movesLike: ["weighted-pull-up", "lat-pulldown", "chin-up"]),
        Entry("chin-up", "Chin Up", .bodyweight, .back, .moderate, .chinUp, [.biceps, .forearms, .abs],
              movesLike: ["pull-up", "lat-pulldown", "weighted-pull-up"]),
        Entry("lat-pulldown", "Lat Pulldown", .cable, .back, .moderate, .pullUp, [.biceps, .forearms],
              movesLike: ["neutral-grip-lat-pulldown", "pull-up", "weighted-pull-up"]),
        Entry("seated-cable-row", "Seated Cable Row", .cable, .back, .moderate, .row, [.biceps, .forearms],
              movesLike: ["chest-supported-dumbbell-row", "one-arm-dumbbell-row", "barbell-row"]),
        Entry("barbell-row", "Barbell Row", .barbell, .back, .moderate, .bentOverRow, [.biceps, .forearms, .abs], was: .high,
              movesLike: ["pendlay-row", "seated-cable-row", "one-arm-dumbbell-row"]),
        Entry("one-arm-dumbbell-row", "One Arm Dumbbell Row", .dumbbell, .back, .moderate, .oneArmRow, [.biceps, .forearms, .abs],
              movesLike: ["chest-supported-dumbbell-row", "seated-cable-row", "barbell-row"]),
        Entry("barbell-deadlift", "Barbell Deadlift", .barbell, .back, .high, .deadlift, [.glutes, .hamstrings, .quads, .forearms],
              movesLike: ["trap-bar-deadlift", "barbell-romanian-deadlift", "barbell-good-morning"]),
        Entry("barbell-overhead-press", "Barbell Overhead Press", .barbell, .shoulders, .moderate, .frontPress, [.triceps, .abs], was: .high,
              movesLike: ["dumbbell-shoulder-press", "dumbbell-arnold-press"]),
        Entry("dumbbell-shoulder-press", "Dumbbell Shoulder Press", .dumbbell, .shoulders, .moderate, .overhead.braced, [.triceps, .abs],
              movesLike: ["barbell-overhead-press", "dumbbell-arnold-press"]),
        Entry("dumbbell-lateral-raise", "Dumbbell Lateral Raise", .dumbbell, .shoulders, .low, .lateralRaise,
              movesLike: ["cable-lateral-raise"]),
        Entry("cable-lateral-raise", "Cable Lateral Raise", .cable, .shoulders, .low, .lateralRaise,
              movesLike: ["dumbbell-lateral-raise"]),
        Entry("dumbbell-reverse-fly", "Dumbbell Reverse Fly", .dumbbell, .shoulders, .low, .reverseFly, [.back],
              movesLike: ["cable-face-pull"]),
        Entry("cable-face-pull", "Cable Face Pull", .cable, .shoulders, .low, .facePull, [.back],
              movesLike: ["dumbbell-reverse-fly"]),
        Entry("barbell-curl", "Barbell Curl", .barbell, .biceps, .low, .curl, [.forearms],
              movesLike: ["ez-bar-curl", "dumbbell-curl", "cable-curl"]),
        Entry("dumbbell-curl", "Dumbbell Curl", .dumbbell, .biceps, .low, .supinatingCurl, [.forearms],
              movesLike: ["barbell-curl", "incline-dumbbell-curl", "cable-curl"]),
        Entry("dumbbell-hammer-curl", "Dumbbell Hammer Curl", .dumbbell, .biceps, .low, .curl, [.forearms],
              movesLike: ["cable-rope-hammer-curl", "ez-bar-reverse-curl", "dumbbell-curl"]),
        Entry("cable-curl", "Cable Curl", .cable, .biceps, .low, .curl, [.forearms],
              movesLike: ["barbell-curl", "dumbbell-curl", "ez-bar-preacher-curl"]),
        Entry("cable-triceps-pushdown", "Cable Triceps Pushdown", .cable, .triceps, .low, .triceps,
              movesLike: ["cable-overhead-extension", "barbell-skull-crusher", "dumbbell-triceps-extension"]),
        Entry("cable-overhead-extension", "Cable Overhead Extension", .cable, .triceps, .low, .triceps, [.shoulders],
              movesLike: ["dumbbell-triceps-extension", "barbell-skull-crusher", "cable-triceps-pushdown"]),
        Entry("dumbbell-triceps-extension", "Dumbbell Triceps Extension", .dumbbell, .triceps, .low, .triceps, [.shoulders],
              movesLike: ["cable-overhead-extension", "barbell-skull-crusher", "cable-triceps-pushdown"]),
        Entry("barbell-skull-crusher", "Barbell Skull Crusher", .barbell, .triceps, .low, .triceps, [.shoulders],
              movesLike: ["ez-bar-skull-crusher", "dumbbell-triceps-extension", "cable-overhead-extension"]),
        Entry("barbell-back-squat", "Barbell Back Squat", .barbell, .quads, .high, .squat, [.glutes, .hamstrings, .abs],
              movesLike: ["barbell-front-squat", "smith-machine-squat", "goblet-squat"]),
        Entry("barbell-front-squat", "Barbell Front Squat", .barbell, .quads, .high, .squat, [.glutes, .abs],
              movesLike: ["barbell-back-squat", "goblet-squat", "smith-machine-squat"]),
        Entry("goblet-squat", "Goblet Squat", .kettlebell, .quads, .moderate, .squat, [.glutes, .abs],
              movesLike: ["dumbbell-goblet-squat", "barbell-front-squat", "barbell-back-squat"]),
        Entry("dumbbell-bulgarian-split-squat", "Dumbbell Bulgarian Split Squat", .dumbbell, .quads, .high, .lunge, [.glutes, .hamstrings],
              movesLike: ["split-squat", "reverse-lunge", "dumbbell-walking-lunge"]),
        Entry("dumbbell-walking-lunge", "Dumbbell Walking Lunge", .dumbbell, .quads, .high, .lunge, [.glutes, .hamstrings], was: .moderate,
              movesLike: ["reverse-lunge", "split-squat", "dumbbell-bulgarian-split-squat"]),
        Entry("leg-press", "Leg Press", .legPress, .quads, .high, .legPress, [.glutes, .hamstrings],
              movesLike: ["hack-squat", "smith-machine-squat", "barbell-back-squat"]),
        Entry("leg-extension", "Leg Extension", .machine, .quads, .low, .legExtension),
        Entry("barbell-romanian-deadlift", "Barbell Romanian Deadlift", .barbell, .hamstrings, .high, .hinge, [.glutes, .back, .forearms],
              movesLike: ["dumbbell-romanian-deadlift", "barbell-good-morning", "cable-pull-through"]),
        Entry("dumbbell-romanian-deadlift", "Dumbbell Romanian Deadlift", .dumbbell, .hamstrings, .moderate, .hinge, [.glutes, .back, .forearms],
              movesLike: ["barbell-romanian-deadlift", "single-leg-romanian-deadlift", "cable-pull-through"]),
        Entry("seated-leg-curl", "Seated Leg Curl", .machine, .hamstrings, .low, .legCurl,
              movesLike: ["lying-leg-curl", "sliding-leg-curl"]),
        Entry("lying-leg-curl", "Lying Leg Curl", .machine, .hamstrings, .low, .legCurl,
              movesLike: ["seated-leg-curl", "sliding-leg-curl"]),
        Entry("barbell-hip-thrust", "Barbell Hip Thrust", .barbell, .glutes, .high, .bridge.braced, [.hamstrings, .abs],
              movesLike: ["smith-machine-hip-thrust", "glute-bridge", "cable-glute-kickback"]),
        Entry("glute-bridge", "Glute Bridge", .bodyweight, .glutes, .low, .bridge, [.hamstrings],
              movesLike: ["single-leg-glute-bridge", "barbell-hip-thrust", "smith-machine-hip-thrust"]),
        Entry("cable-glute-kickback", "Cable Glute Kickback", .cable, .glutes, .low, .kickback, [.hamstrings],
              movesLike: ["glute-bridge", "barbell-hip-thrust", "cable-pull-through"]),
        Entry("cable-pull-through", "Cable Pull Through", .cable, .glutes, .low, .hinge, [.hamstrings],
              movesLike: ["kettlebell-swing", "barbell-romanian-deadlift", "dumbbell-romanian-deadlift"]),
        Entry("standing-calf-raise", "Standing Calf Raise", .machine, .calves, .low, .calf,
              movesLike: ["seated-calf-raise", "dumbbell-calf-raise"]),
        Entry("seated-calf-raise", "Seated Calf Raise", .machine, .calves, .low, .calf,
              movesLike: ["standing-calf-raise", "dumbbell-calf-raise"]),
        Entry("dumbbell-calf-raise", "Dumbbell Calf Raise", .dumbbell, .calves, .low, .calf,
              movesLike: ["standing-calf-raise", "seated-calf-raise"]),
        Entry("crunch", "Crunch", .bodyweight, .abs, .low, .crunch,
              movesLike: ["cable-crunch", "sit-up"]),
        Entry("hanging-knee-raise", "Hanging Knee Raise", .bodyweight, .abs, .low, .legRaise, [.forearms],
              movesLike: ["hanging-leg-raise", "mountain-climber"]),
        Entry("cable-crunch", "Cable Crunch", .cable, .abs, .low, .crunch,
              movesLike: ["crunch", "sit-up"]),
        Entry("cable-woodchop", "Cable Woodchop", .cable, .obliques, .low, .chop, [.abs],
              movesLike: ["russian-twist"]),
        Entry("side-plank", "Side Plank", .bodyweight, .obliques, .low, .sidePlank, [.abs]),
        Entry("dumbbell-wrist-curl", "Dumbbell Wrist Curl", .dumbbell, .forearms, .low, .wristCurl,
              movesLike: ["barbell-wrist-curl"]),
        Entry("dumbbell-reverse-wrist-curl", "Dumbbell Reverse Wrist Curl", .dumbbell, .forearms, .low, .reverseWristCurl,
              movesLike: ["barbell-reverse-wrist-curl"]),
        // Added for the home and small gym templates. Smith machine lifts use `.machine`.
        Entry("dumbbell-goblet-squat", "Dumbbell Goblet Squat", .dumbbell, .quads, .moderate, .squat, [.glutes, .abs],
              movesLike: ["goblet-squat", "barbell-front-squat", "smith-machine-squat"]),
        Entry("sliding-leg-curl", "Sliding Leg Curl", .bodyweight, .hamstrings, .low, .hipsHeldLegCurl,
              movesLike: ["nordic-hamstring-curl", "lying-leg-curl", "seated-leg-curl"]),
        Entry("smith-machine-squat", "Smith Machine Squat", .machine, .quads, .high, .squat, [.glutes, .abs],
              movesLike: ["barbell-back-squat", "hack-squat", "barbell-front-squat"]),
        Entry("smith-machine-hip-thrust", "Smith Machine Hip Thrust", .machine, .glutes, .high, .bridge.braced, [.abs],
              movesLike: ["barbell-hip-thrust", "glute-bridge", "cable-glute-kickback"]),
        Entry("cable-hip-abduction", "Cable Hip Abduction", .cable, .glutes, .low, .hipAbduction,
              movesLike: ["machine-hip-abduction"]),
        // Added for the second set of built-in templates.
        Entry("hack-squat", "Hack Squat", .machine, .quads, .high, .hackSquat, [.glutes],
              movesLike: ["leg-press", "smith-machine-squat", "barbell-back-squat"]),
        Entry("chest-supported-dumbbell-row", "Chest Supported Dumbbell Row", .dumbbell, .back, .moderate, .row, [.biceps, .forearms],
              movesLike: ["seated-cable-row", "one-arm-dumbbell-row", "barbell-row"]),
        Entry("dip", "Dip", .bodyweight, .chest, .moderate, .dip, [.triceps, .shoulders],
              movesLike: ["weighted-dip", "close-grip-bench-press", "push-up"]),
        Entry("close-grip-bench-press", "Close Grip Bench Press", .barbell, .triceps, .moderate, .closeGripBench, [.chest, .shoulders], was: .high,
              movesLike: ["barbell-bench-press", "dip", "dumbbell-bench-press"]),
        Entry("incline-dumbbell-curl", "Incline Dumbbell Curl", .dumbbell, .biceps, .low, .curl, [.forearms],
              movesLike: ["dumbbell-curl", "barbell-curl", "cable-curl"]),
        Entry("hanging-leg-raise", "Hanging Leg Raise", .bodyweight, .abs, .low, .legRaise, [.forearms],
              movesLike: ["hanging-knee-raise", "lying-leg-raise", "mountain-climber"]),
        // Loadable bodyweight: a weight of 0 is bodyweight alone. See `adoptOwnCopies`.
        Entry("weighted-pull-up", "Weighted Pull-Ups", .loadableBodyweight, .back, .moderate, .pullUp.braced, [.biceps, .forearms, .abs],
              movesLike: ["pull-up", "lat-pulldown", "chin-up"]),
        Entry("weighted-dip", "Weighted Dips", .loadableBodyweight, .chest, .moderate, .dip, [.triceps, .shoulders],
              movesLike: ["dip", "close-grip-bench-press", "push-up"]),
        Entry("sit-up", "Sit-Up", .loadableBodyweight, .abs, .low, .trunkAndHipFlexion, [.obliques],
              movesLike: ["reverse-crunch", "crunch", "cable-crunch"]),
        Entry("lateral-lunge", "Lateral Lunge", .loadableBodyweight, .quads, .moderate, .lateralLunge, [.glutes, .hamstrings],
              movesLike: ["reverse-lunge", "split-squat", "dumbbell-walking-lunge"]),
        Entry("ab-wheel-rollout", "Ab Wheel Rollout", .bodyweight, .abs, .low, .rollout, [.obliques, .shoulders], equipmentName: "Ab Wheel",
              movesLike: ["crunch", "cable-crunch"]),
        Entry("single-leg-romanian-deadlift", "Single-Leg Romanian Deadlift", .loadableBodyweight, .hamstrings, .moderate, .singleLegHinge, [.glutes, .back],
              movesLike: ["dumbbell-romanian-deadlift", "barbell-romanian-deadlift", "cable-pull-through"]),
        Entry("mountain-climber", "Mountain Climber", .bodyweight, .abs, .low, .mountainClimber, [.shoulders, .quads],
              movesLike: ["hanging-knee-raise", "hanging-leg-raise"]),
        Entry("split-squat", "Split Squat", .loadableBodyweight, .quads, .moderate, .lunge, [.glutes, .hamstrings],
              movesLike: ["dumbbell-bulgarian-split-squat", "reverse-lunge", "dumbbell-walking-lunge"]),
        Entry("trap-bar-deadlift", "Trap Bar Deadlift", .barbell, .quads, .high, .trapBarDeadlift, [.glutes, .hamstrings, .back, .forearms], equipmentName: "Trap Bar",
              movesLike: ["sumo-deadlift", "barbell-deadlift", "barbell-back-squat"]),
        Entry("burpee", "Burpee", .bodyweight, .quads, .moderate, .burpee, [.chest, .glutes, .shoulders]),
        Entry("dumbbell-arnold-press", "Dumbbell Arnold Press", .dumbbell, .shoulders, .moderate, .arnoldPress, [.triceps],
              movesLike: ["dumbbell-shoulder-press", "barbell-overhead-press"]),
        Entry("machine-chest-press", "Machine Chest Press", .machine, .chest, .moderate, .bench, [.triceps, .shoulders],
              movesLike: ["barbell-bench-press", "dumbbell-bench-press", "push-up"]),
        Entry("dumbbell-shrug", "Dumbbell Shrug", .dumbbell, .back, .low, .shrug, [.forearms],
              movesLike: ["barbell-shrug", "trap-bar-shrug"]),
        Entry("barbell-good-morning", "Barbell Good Morning", .barbell, .hamstrings, .moderate, .goodMorning, [.glutes, .back, .abs],
              movesLike: ["barbell-romanian-deadlift", "barbell-deadlift", "kettlebell-swing"]),
        Entry("reverse-lunge", "Reverse Lunge", .loadableBodyweight, .quads, .moderate, .lunge, [.glutes, .hamstrings],
              movesLike: ["split-squat", "dumbbell-walking-lunge", "dumbbell-bulgarian-split-squat"]),
        Entry("kettlebell-swing", "Kettlebell Swing", .kettlebell, .glutes, .moderate, .swing, [.hamstrings, .back, .abs],
              movesLike: ["cable-pull-through", "barbell-romanian-deadlift", "barbell-hip-thrust"]),
        Entry("ez-bar-preacher-curl", "EZ-Bar Preacher Curl", .barbell, .biceps, .low, .curl, [.forearms], equipmentName: "EZ Bar",
              movesLike: ["barbell-curl", "dumbbell-curl", "cable-curl"]),
        Entry("russian-twist", "Russian Twist", .loadableBodyweight, .obliques, .low, .twist, [.abs],
              movesLike: ["cable-woodchop"]),

        // Chest.
        Entry("decline-barbell-bench-press", "Decline Barbell Bench Press", .barbell, .chest, .moderate, .bench, [.triceps, .shoulders],
              movesLike: ["barbell-bench-press", "dumbbell-floor-press", "machine-chest-press"]),
        Entry("dumbbell-floor-press", "Dumbbell Floor Press", .dumbbell, .chest, .moderate, .bench, [.triceps, .shoulders],
              movesLike: ["dumbbell-bench-press", "barbell-bench-press", "machine-chest-press"]),
        Entry("dumbbell-fly", "Dumbbell Fly", .dumbbell, .chest, .low, .fly, [.shoulders],
              movesLike: ["cable-chest-fly", "pec-deck", "incline-dumbbell-fly"]),
        Entry("incline-dumbbell-fly", "Incline Dumbbell Fly", .dumbbell, .chest, .low, .inclineFly, [.shoulders],
              movesLike: ["dumbbell-fly", "cable-chest-fly", "pec-deck"]),
        Entry("pec-deck", "Pec Deck", .machine, .chest, .low, .fly, [.shoulders],
              movesLike: ["cable-chest-fly", "dumbbell-fly", "incline-dumbbell-fly"]),
        Entry("incline-push-up", "Incline Push Up", .bodyweight, .chest, .moderate, .pushUp, [.triceps, .shoulders, .abs],
              movesLike: ["push-up", "dumbbell-bench-press", "machine-chest-press"]),

        // Back and shoulders.
        Entry("inverted-row", "Inverted Row", .loadableBodyweight, .back, .moderate, .invertedRow, [.biceps, .forearms, .abs],
              movesLike: ["barbell-row", "seated-cable-row", "chest-supported-dumbbell-row"]),
        Entry("pendlay-row", "Pendlay Row", .barbell, .back, .moderate, .bentOverRow, [.biceps, .forearms, .abs],
              movesLike: ["barbell-row", "one-arm-dumbbell-row", "seated-cable-row"]),
        Entry("machine-high-row", "Machine High Row", .machine, .back, .moderate, .row, [.biceps, .forearms],
              movesLike: ["seated-cable-row", "chest-supported-dumbbell-row", "lat-pulldown"]),
        Entry("neutral-grip-lat-pulldown", "Neutral Grip Lat Pulldown", .cable, .back, .moderate, .pullUp, [.biceps, .forearms],
              movesLike: ["lat-pulldown", "pull-up", "chin-up"]),
        Entry("barbell-shrug", "Barbell Shrug", .barbell, .back, .low, .shrug, [.forearms],
              movesLike: ["dumbbell-shrug", "trap-bar-shrug"]),
        Entry("trap-bar-shrug", "Trap Bar Shrug", .barbell, .back, .low, .shrug, [.forearms], equipmentName: "Trap Bar",
              movesLike: ["barbell-shrug", "dumbbell-shrug"]),
        Entry("machine-shoulder-press", "Machine Shoulder Press", .machine, .shoulders, .moderate, .overhead, [.triceps],
              movesLike: ["dumbbell-shoulder-press", "barbell-overhead-press", "dumbbell-arnold-press"]),
        Entry("single-arm-kettlebell-press", "Single-Arm Kettlebell Press", .kettlebell, .shoulders, .moderate, .singleArmPress, [.triceps, .abs],
              movesLike: ["dumbbell-shoulder-press", "barbell-overhead-press", "machine-shoulder-press"]),

        // Arms and forearms.
        Entry("ez-bar-curl", "EZ-Bar Curl", .barbell, .biceps, .low, .curl, [.forearms], equipmentName: "EZ Bar",
              movesLike: ["barbell-curl", "dumbbell-curl", "cable-curl"]),
        Entry("ez-bar-reverse-curl", "EZ-Bar Reverse Curl", .barbell, .biceps, .low, .curl, [.forearms], equipmentName: "EZ Bar",
              movesLike: ["dumbbell-hammer-curl", "cable-rope-hammer-curl", "ez-bar-curl"]),
        Entry("ez-bar-skull-crusher", "EZ-Bar Skull Crusher", .barbell, .triceps, .low, .triceps, equipmentName: "EZ Bar",
              movesLike: ["barbell-skull-crusher", "dumbbell-triceps-extension", "cable-triceps-pushdown"]),
        Entry("dumbbell-concentration-curl", "Dumbbell Concentration Curl", .dumbbell, .biceps, .low, .curl, [.forearms],
              movesLike: ["ez-bar-preacher-curl", "dumbbell-curl", "incline-dumbbell-curl"]),
        Entry("cable-rope-hammer-curl", "Cable Rope Hammer Curl", .cable, .biceps, .low, .curl, [.forearms],
              movesLike: ["dumbbell-hammer-curl", "ez-bar-reverse-curl", "cable-curl"]),
        Entry("dumbbell-triceps-kickback", "Dumbbell Triceps Kickback", .dumbbell, .triceps, .low, .triceps,
              movesLike: ["cable-triceps-pushdown", "dumbbell-triceps-extension", "cable-overhead-extension"]),
        Entry("barbell-wrist-curl", "Barbell Wrist Curl", .barbell, .forearms, .low, .wristCurl,
              movesLike: ["dumbbell-wrist-curl"]),
        Entry("barbell-reverse-wrist-curl", "Barbell Reverse Wrist Curl", .barbell, .forearms, .low, .reverseWristCurl,
              movesLike: ["dumbbell-reverse-wrist-curl"]),

        // Legs and glutes.
        Entry("sumo-deadlift", "Sumo Deadlift", .barbell, .glutes, .high, .sumoDeadlift, [.quads, .hamstrings, .back, .forearms],
              movesLike: ["barbell-deadlift", "trap-bar-deadlift", "kettlebell-deadlift"]),
        Entry("barbell-box-squat", "Barbell Box Squat", .barbell, .quads, .high, .squat, [.glutes, .abs],
              movesLike: ["barbell-back-squat", "barbell-front-squat", "smith-machine-squat"]),
        Entry("dumbbell-step-up", "Dumbbell Step Up", .dumbbell, .quads, .moderate, .lunge, [.glutes, .hamstrings],
              movesLike: ["dumbbell-bulgarian-split-squat", "reverse-lunge", "split-squat"]),
        Entry("kettlebell-deadlift", "Kettlebell Deadlift", .kettlebell, .glutes, .moderate, .hinge, [.hamstrings, .back, .forearms],
              movesLike: ["dumbbell-romanian-deadlift", "kettlebell-swing", "barbell-romanian-deadlift"]),
        Entry("single-leg-glute-bridge", "Single-Leg Glute Bridge", .bodyweight, .glutes, .low, .singleLegBridge, [.hamstrings],
              movesLike: ["glute-bridge", "barbell-hip-thrust", "cable-glute-kickback"]),
        Entry("machine-hip-abduction", "Machine Hip Abduction", .machine, .glutes, .low, .hipAbduction,
              movesLike: ["cable-hip-abduction"]),
        Entry("nordic-hamstring-curl", "Nordic Hamstring Curl", .bodyweight, .hamstrings, .moderate, .hipsHeldLegCurl,
              movesLike: ["sliding-leg-curl", "lying-leg-curl", "seated-leg-curl"]),
        Entry("standing-single-leg-calf-raise", "Standing Single-Leg Calf Raise", .loadableBodyweight, .calves, .low, .calf,
              movesLike: ["standing-calf-raise", "dumbbell-calf-raise", "seated-calf-raise"]),

        // Core.
        Entry("reverse-crunch", "Reverse Crunch", .bodyweight, .abs, .low, .trunkAndHipFlexion,
              movesLike: ["sit-up", "hanging-knee-raise", "crunch"]),
        Entry("machine-ab-crunch", "Machine Ab Crunch", .machine, .abs, .low, .crunch,
              movesLike: ["cable-crunch", "crunch", "sit-up"]),
        Entry("lying-leg-raise", "Lying Leg Raise", .bodyweight, .abs, .low, .legRaise,
              movesLike: ["hanging-leg-raise", "hanging-knee-raise", "reverse-crunch"]),
    ]

    /// Named equipment uses its base type for loading and its existing label for storage and sync.
    struct EquipmentOption: Hashable {
        let base: Equipment
        var name: String? = nil
        var displayName: String { name ?? base.displayName }
    }

    static let equipmentOptions: [EquipmentOption] = {
        let bases = Equipment.allCases.map { EquipmentOption(base: $0) }
        let named = entries.compactMap { entry in
            entry.equipmentName.map { EquipmentOption(base: entry.equipment, name: $0) }
        }
        return Set(bases + named).sorted { $0.displayName < $1.displayName }
    }()

    /// The lifter's own exercises that a built-in one now replaces, by catalog ID, as `matchingName` reads their names.
    static let replacedOwnNames: [String: Set<String>] = [
        "weighted-pull-up": ["weightedpullup", "weightedpullups", "weightpullup", "weightpullups"],
        "weighted-dip": ["weighteddip", "weighteddips", "weightdip", "weightdips"],
    ]

    /// "Weighted Pull-ups" and "weighted pullups" both read "weightedpullups".
    static func matchingName(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Bumped when catalog fatigue levels change, so each device moves its rows once.
    static let fatigueLevelsRevision = 1
    static let fatigueLevelsRevisionKey = "catalog.fatigueLevelsRevision"

    @MainActor
    static func seed(in context: ModelContext, defaults: UserDefaults = .standard) throws {
        var changed = try mergeExerciseRows(in: context)
        let existing = try context.fetch(FetchDescriptor<Exercise>())
        let existingByID = Dictionary(
            existing.compactMap { exercise in exercise.catalogID.map { ($0, exercise) } },
            uniquingKeysWith: { first, _ in first }
        )

        let updatesFatigue = defaults.integer(forKey: fatigueLevelsRevisionKey) < fatigueLevelsRevision

        for entry in entries {
            if let exercise = existingByID[entry.id] {
                changed = entry.backfill(exercise) || changed
                if updatesFatigue {
                    changed = entry.updateFatigueLevel(exercise) || changed
                }
            } else {
                context.insert(entry.makeExercise())
                changed = true
            }
        }

        let updatedMetadata = try MovementCatalog.reconcile(try context.fetch(FetchDescriptor<Exercise>()), in: context)
        if changed || updatedMetadata {
            try context.save()
        }
        // Only rows already on this device move. Rows iCloud brings in later, on a new iPhone or after
        // a reinstall, were moved by the device that saved them, and a level the lifter set again since
        // must stay. A device still on an older version moves its own rows once it updates.
        if updatesFatigue {
            defaults.set(fatigueLevelsRevision, forKey: fatigueLevelsRevisionKey)
        }
    }

    /// Merges copies of the same catalog exercise. A new device seeds the catalog before its
    /// synced data arrives, so both copies can end up stored. The oldest copy survives on every
    /// device, and rows that used a duplicate are pointed at it.
    /// The lifter's own copies of a newer built-in exercise become that exercise first (`adoptOwnCopies`).
    /// This runs at launch and after every iCloud import, so copies an older device syncs later move too.
    /// - Returns: Whether anything changed. The caller saves.
    @MainActor
    static func removeDuplicates(in context: ModelContext) throws -> Bool {
        let merged = try mergeExerciseRows(in: context)
        let updatedMetadata = try MovementCatalog.reconcile(try context.fetch(FetchDescriptor<Exercise>()), in: context)
        return merged || updatedMetadata
    }

    @MainActor
    private static func mergeExerciseRows(in context: ModelContext) throws -> Bool {
        var changed = try adoptOwnCopies(in: context)
        let catalogExercises = try context.fetch(FetchDescriptor<Exercise>()).filter { $0.catalogID != nil }

        for copies in Dictionary(grouping: catalogExercises, by: \.catalogID).values where copies.count > 1 {
            let oldestFirst = copies.sorted { $0.createdAtValue < $1.createdAtValue }
            let survivor = oldestFirst[0]
            for duplicate in oldestFirst.dropFirst() {
                survivor.takeOverRows(of: duplicate)
                context.delete(duplicate)
            }
            TraceLog.record(.data, "Catalog dedupe: kept the oldest \(survivor.catalogID ?? "?"), deleted \(oldestFirst.count - 1) copies")
            changed = true
        }
        return changed
    }

    /// Turns the lifter's own exercise named like a newer built-in one (see `replacedOwnNames`) into that
    /// built-in exercise, in place, so every template, program and logged set that used it stays with it.
    /// It takes the built-in name, equipment and muscles, and keeps its own rep range, fatigue level and rest.
    /// Where the catalog row exists too, `removeDuplicates` then keeps whichever is older on every device.
    /// - Returns: Whether anything changed. The caller saves.
    @MainActor
    static func adoptOwnCopies(in context: ModelContext) throws -> Bool {
        let own = try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.catalogID == nil && !$0.keepsCustomIdentity }))
        var changed = false
        for exercise in own where exercise.customEquipmentName == nil {
            let name = matchingName(exercise.exerciseName)
            guard
                let id = replacedOwnNames.first(where: { $0.value.contains(name) })?.key,
                let entry = entries.first(where: { $0.id == id })
            else {
                exercise.keepsCustomIdentity = true
                changed = true
                continue
            }
            exercise.catalogID = entry.id
            exercise.userCreatedValue = false
            exercise.exerciseName = entry.name
            exercise.equipment = entry.equipment
            exercise.primaryMuscleFocus = entry.primaryMuscle
            exercise.secondaryMuscles = entry.secondaryMuscles
            Logger.sync.info("Moved an own exercise to the built-in \(entry.id, privacy: .public)")
            changed = true
        }
        return changed
    }
}
