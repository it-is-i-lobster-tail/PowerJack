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

        init(
            _ id: String,
            _ name: String,
            _ equipment: Equipment,
            _ primaryMuscle: Muscle,
            _ fatigueLevel: FatigueLevel,
            _ profile: MovementCatalog.Profile,
            _ secondaryMuscles: [Muscle] = [],
            equipmentName: String? = nil,
            was previousFatigueLevel: FatigueLevel? = nil
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

        /// Refreshes secondary muscles on an already-seeded catalog exercise.
        /// Display fields are left alone so renamed rows stay renamed, and rep range
        /// and fatigue are left alone because the user can edit them.
        func backfill(_ exercise: Exercise) -> Bool {
            guard exercise.secondaryMusclesValue != secondaryMuscles else { return false }
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
        Entry("barbell-bench-press", "Barbell Bench Press", .barbell, .chest, .moderate, .bench, [.triceps, .shoulders], was: .high),
        Entry("incline-barbell-bench-press", "Incline Barbell Bench Press", .barbell, .chest, .moderate, .bench, [.triceps, .shoulders], was: .high),
        Entry("dumbbell-bench-press", "Dumbbell Bench Press", .dumbbell, .chest, .moderate, .bench, [.triceps, .shoulders]),
        Entry("incline-dumbbell-bench-press", "Incline Dumbbell Bench Press", .dumbbell, .chest, .moderate, .bench, [.triceps, .shoulders]),
        Entry("cable-chest-fly", "Cable Chest Fly", .cable, .chest, .low, .fly, [.shoulders]),
        Entry("push-up", "Push Up", .bodyweight, .chest, .moderate, .bench.braced, [.triceps, .shoulders, .abs]),
        Entry("pull-up", "Pull Up", .bodyweight, .back, .moderate, .pullUp.braced, [.biceps, .forearms, .abs]),
        Entry("chin-up", "Chin Up", .bodyweight, .back, .moderate, .chinUp, [.biceps, .forearms, .abs]),
        Entry("lat-pulldown", "Lat Pulldown", .cable, .back, .moderate, .pullUp, [.biceps, .forearms]),
        Entry("seated-cable-row", "Seated Cable Row", .cable, .back, .moderate, .row, [.biceps, .forearms]),
        Entry("barbell-row", "Barbell Row", .barbell, .back, .moderate, .row.braced, [.biceps, .forearms, .abs], was: .high),
        Entry("one-arm-dumbbell-row", "One Arm Dumbbell Row", .dumbbell, .back, .moderate, .row.braced, [.biceps, .forearms, .abs]),
        Entry("barbell-deadlift", "Barbell Deadlift", .barbell, .back, .high, .deadlift, [.glutes, .hamstrings, .quads, .forearms]),
        Entry("barbell-overhead-press", "Barbell Overhead Press", .barbell, .shoulders, .moderate, .overhead.braced, [.triceps, .abs], was: .high),
        Entry("dumbbell-shoulder-press", "Dumbbell Shoulder Press", .dumbbell, .shoulders, .moderate, .overhead.braced, [.triceps, .abs]),
        Entry("dumbbell-lateral-raise", "Dumbbell Lateral Raise", .dumbbell, .shoulders, .low, .lateralRaise),
        Entry("cable-lateral-raise", "Cable Lateral Raise", .cable, .shoulders, .low, .lateralRaise),
        Entry("dumbbell-reverse-fly", "Dumbbell Reverse Fly", .dumbbell, .shoulders, .low, .reverseFly, [.back]),
        Entry("cable-face-pull", "Cable Face Pull", .cable, .shoulders, .low, .facePull, [.back]),
        Entry("barbell-curl", "Barbell Curl", .barbell, .biceps, .low, .curl, [.forearms]),
        Entry("dumbbell-curl", "Dumbbell Curl", .dumbbell, .biceps, .low, .curl, [.forearms]),
        Entry("dumbbell-hammer-curl", "Dumbbell Hammer Curl", .dumbbell, .biceps, .low, .curl, [.forearms]),
        Entry("cable-curl", "Cable Curl", .cable, .biceps, .low, .curl, [.forearms]),
        Entry("cable-triceps-pushdown", "Cable Triceps Pushdown", .cable, .triceps, .low, .triceps),
        Entry("cable-overhead-extension", "Cable Overhead Extension", .cable, .triceps, .low, .triceps, [.shoulders]),
        Entry("dumbbell-triceps-extension", "Dumbbell Triceps Extension", .dumbbell, .triceps, .low, .triceps, [.shoulders]),
        Entry("barbell-skull-crusher", "Barbell Skull Crusher", .barbell, .triceps, .low, .triceps, [.shoulders]),
        Entry("barbell-back-squat", "Barbell Back Squat", .barbell, .quads, .high, .squat, [.glutes, .hamstrings, .abs]),
        Entry("barbell-front-squat", "Barbell Front Squat", .barbell, .quads, .high, .squat, [.glutes, .abs]),
        Entry("goblet-squat", "Goblet Squat", .kettlebell, .quads, .moderate, .squat, [.glutes, .abs]),
        Entry("dumbbell-bulgarian-split-squat", "Dumbbell Bulgarian Split Squat", .dumbbell, .quads, .high, .lunge, [.glutes, .hamstrings]),
        Entry("dumbbell-walking-lunge", "Dumbbell Walking Lunge", .dumbbell, .quads, .high, .lunge, [.glutes, .hamstrings], was: .moderate),
        Entry("leg-press", "Leg Press", .legPress, .quads, .high, .legPress, [.glutes, .hamstrings]),
        Entry("leg-extension", "Leg Extension", .machine, .quads, .low, .legExtension, equipmentName: "Leg Extension"),
        Entry("barbell-romanian-deadlift", "Barbell Romanian Deadlift", .barbell, .hamstrings, .high, .hinge, [.glutes, .back, .forearms]),
        Entry("dumbbell-romanian-deadlift", "Dumbbell Romanian Deadlift", .dumbbell, .hamstrings, .moderate, .hinge, [.glutes, .back, .forearms]),
        Entry("seated-leg-curl", "Seated Leg Curl", .machine, .hamstrings, .low, .legCurl, equipmentName: "Seated Leg Curl"),
        Entry("lying-leg-curl", "Lying Leg Curl", .machine, .hamstrings, .low, .legCurl, equipmentName: "Lying Leg Curl"),
        Entry("barbell-hip-thrust", "Barbell Hip Thrust", .barbell, .glutes, .high, .bridge.braced, [.hamstrings, .abs]),
        Entry("glute-bridge", "Glute Bridge", .bodyweight, .glutes, .low, .bridge, [.hamstrings]),
        Entry("cable-glute-kickback", "Cable Glute Kickback", .cable, .glutes, .low, .kickback, [.hamstrings]),
        Entry("cable-pull-through", "Cable Pull Through", .cable, .glutes, .low, .hinge, [.hamstrings]),
        Entry("standing-calf-raise", "Standing Calf Raise", .machine, .calves, .low, .calf, equipmentName: "Calf Raise"),
        Entry("seated-calf-raise", "Seated Calf Raise", .machine, .calves, .low, .calf, equipmentName: "Seated Calf"),
        Entry("dumbbell-calf-raise", "Dumbbell Calf Raise", .dumbbell, .calves, .low, .calf),
        Entry("crunch", "Crunch", .bodyweight, .abs, .low, .crunch),
        Entry("hanging-knee-raise", "Hanging Knee Raise", .bodyweight, .abs, .low, .legRaise, [.forearms]),
        Entry("cable-crunch", "Cable Crunch", .cable, .abs, .low, .crunch),
        Entry("cable-woodchop", "Cable Woodchop", .cable, .obliques, .low, .chop, [.abs]),
        Entry("side-plank", "Side Plank", .bodyweight, .obliques, .low, .sidePlank, [.abs]),
        Entry("dumbbell-wrist-curl", "Dumbbell Wrist Curl", .dumbbell, .forearms, .low, .wristCurl),
        Entry("dumbbell-reverse-wrist-curl", "Dumbbell Reverse Wrist Curl", .dumbbell, .forearms, .low, .reverseWristCurl),
        // Added for the home and small gym templates. Smith machine lifts use `.machine`.
        Entry("dumbbell-goblet-squat", "Dumbbell Goblet Squat", .dumbbell, .quads, .moderate, .squat, [.glutes, .abs]),
        Entry("sliding-leg-curl", "Sliding Leg Curl", .bodyweight, .hamstrings, .low, .legCurl),
        Entry("smith-machine-squat", "Smith Machine Squat", .machine, .quads, .high, .squat, [.glutes, .abs], equipmentName: "Smith Machine"),
        Entry("smith-machine-hip-thrust", "Smith Machine Hip Thrust", .machine, .glutes, .high, .bridge.braced, [.abs], equipmentName: "Smith Machine"),
        Entry("cable-hip-abduction", "Cable Hip Abduction", .cable, .glutes, .low, .hipAbduction),
        // Added for the second set of built-in templates.
        Entry("hack-squat", "Hack Squat", .machine, .quads, .high, .squat, [.glutes], equipmentName: "Hack Squat"),
        Entry("chest-supported-dumbbell-row", "Chest Supported Dumbbell Row", .dumbbell, .back, .moderate, .row, [.biceps, .forearms]),
        Entry("dip", "Dip", .bodyweight, .chest, .moderate, .dip, [.triceps, .shoulders]),
        Entry("close-grip-bench-press", "Close Grip Bench Press", .barbell, .triceps, .moderate, .closeGripBench, [.chest, .shoulders], was: .high),
        Entry("incline-dumbbell-curl", "Incline Dumbbell Curl", .dumbbell, .biceps, .low, .curl, [.forearms]),
        Entry("hanging-leg-raise", "Hanging Leg Raise", .bodyweight, .abs, .low, .legRaise, [.forearms]),
        // Loadable bodyweight: a weight of 0 is bodyweight alone. See `adoptOwnCopies`.
        Entry("weighted-pull-up", "Weighted Pull-Ups", .loadableBodyweight, .back, .moderate, .pullUp.braced, [.biceps, .forearms, .abs]),
        Entry("weighted-dip", "Weighted Dips", .loadableBodyweight, .chest, .moderate, .dip, [.triceps, .shoulders]),
        Entry("sit-up", "Sit-Up", .loadableBodyweight, .abs, .low, .crunch, [.obliques]),
        Entry("lateral-lunge", "Lateral Lunge", .loadableBodyweight, .quads, .moderate, .lunge, [.glutes, .hamstrings]),
        Entry("ab-wheel-rollout", "Ab Wheel Rollout", .bodyweight, .abs, .low, .rollout, [.obliques, .shoulders], equipmentName: "Ab Wheel"),
        Entry("single-leg-romanian-deadlift", "Single-Leg Romanian Deadlift", .loadableBodyweight, .hamstrings, .moderate, .hinge, [.glutes, .back]),
        Entry("mountain-climber", "Mountain Climber", .bodyweight, .abs, .low, .mountainClimber, [.shoulders, .quads]),
        Entry("split-squat", "Split Squat", .loadableBodyweight, .quads, .moderate, .lunge, [.glutes, .hamstrings]),
        Entry("trap-bar-deadlift", "Trap Bar Deadlift", .barbell, .quads, .high, .trapBarDeadlift, [.glutes, .hamstrings, .back, .forearms], equipmentName: "Trap Bar"),
        Entry("burpee", "Burpee", .bodyweight, .quads, .moderate, .burpee, [.chest, .glutes, .shoulders]),
        Entry("dumbbell-arnold-press", "Dumbbell Arnold Press", .dumbbell, .shoulders, .moderate, .overhead, [.triceps]),
        Entry("machine-chest-press", "Machine Chest Press", .machine, .chest, .moderate, .bench, [.triceps, .shoulders]),
        Entry("dumbbell-shrug", "Dumbbell Shrug", .dumbbell, .back, .low, .shrug, [.forearms]),
        Entry("barbell-good-morning", "Barbell Good Morning", .barbell, .hamstrings, .moderate, .hinge.braced, [.glutes, .back, .abs]),
        Entry("reverse-lunge", "Reverse Lunge", .loadableBodyweight, .quads, .moderate, .lunge, [.glutes, .hamstrings]),
        Entry("kettlebell-swing", "Kettlebell Swing", .kettlebell, .glutes, .moderate, .swing, [.hamstrings, .back, .abs]),
        Entry("ez-bar-preacher-curl", "EZ-Bar Preacher Curl", .barbell, .biceps, .low, .curl, [.forearms], equipmentName: "EZ Bar"),
        Entry("russian-twist", "Russian Twist", .loadableBodyweight, .obliques, .low, .chop, [.abs]),

        // Chest.
        Entry("decline-barbell-bench-press", "Decline Barbell Bench Press", .barbell, .chest, .moderate, .bench, [.triceps, .shoulders]),
        Entry("dumbbell-floor-press", "Dumbbell Floor Press", .dumbbell, .chest, .moderate, .bench, [.triceps, .shoulders]),
        Entry("dumbbell-fly", "Dumbbell Fly", .dumbbell, .chest, .low, .fly, [.shoulders]),
        Entry("incline-dumbbell-fly", "Incline Dumbbell Fly", .dumbbell, .chest, .low, .fly, [.shoulders]),
        Entry("pec-deck", "Pec Deck", .machine, .chest, .low, .fly, [.shoulders], equipmentName: "Pec Deck"),
        Entry("incline-push-up", "Incline Push Up", .bodyweight, .chest, .moderate, .bench.braced, [.triceps, .shoulders, .abs]),

        // Back and shoulders.
        Entry("inverted-row", "Inverted Row", .loadableBodyweight, .back, .moderate, .row.braced, [.biceps, .forearms, .abs]),
        Entry("pendlay-row", "Pendlay Row", .barbell, .back, .moderate, .row.braced, [.biceps, .forearms, .abs]),
        Entry("machine-high-row", "Machine High Row", .machine, .back, .moderate, .row, [.biceps, .forearms]),
        Entry("neutral-grip-lat-pulldown", "Neutral Grip Lat Pulldown", .cable, .back, .moderate, .pullUp, [.biceps, .forearms]),
        Entry("barbell-shrug", "Barbell Shrug", .barbell, .back, .low, .shrug, [.forearms]),
        Entry("trap-bar-shrug", "Trap Bar Shrug", .barbell, .back, .low, .shrug, [.forearms], equipmentName: "Trap Bar"),
        Entry("machine-shoulder-press", "Machine Shoulder Press", .machine, .shoulders, .moderate, .overhead, [.triceps]),
        Entry("single-arm-kettlebell-press", "Single-Arm Kettlebell Press", .kettlebell, .shoulders, .moderate, .overhead.braced, [.triceps, .abs]),

        // Arms and forearms.
        Entry("ez-bar-curl", "EZ-Bar Curl", .barbell, .biceps, .low, .curl, [.forearms], equipmentName: "EZ Bar"),
        Entry("ez-bar-reverse-curl", "EZ-Bar Reverse Curl", .barbell, .biceps, .low, .curl, [.forearms], equipmentName: "EZ Bar"),
        Entry("ez-bar-skull-crusher", "EZ-Bar Skull Crusher", .barbell, .triceps, .low, .triceps, equipmentName: "EZ Bar"),
        Entry("dumbbell-concentration-curl", "Dumbbell Concentration Curl", .dumbbell, .biceps, .low, .curl, [.forearms]),
        Entry("cable-rope-hammer-curl", "Cable Rope Hammer Curl", .cable, .biceps, .low, .curl, [.forearms]),
        Entry("dumbbell-triceps-kickback", "Dumbbell Triceps Kickback", .dumbbell, .triceps, .low, .triceps),
        Entry("barbell-wrist-curl", "Barbell Wrist Curl", .barbell, .forearms, .low, .wristCurl),
        Entry("barbell-reverse-wrist-curl", "Barbell Reverse Wrist Curl", .barbell, .forearms, .low, .reverseWristCurl),

        // Legs and glutes.
        Entry("sumo-deadlift", "Sumo Deadlift", .barbell, .quads, .high, .trapBarDeadlift, [.glutes, .hamstrings, .back, .forearms]),
        Entry("barbell-box-squat", "Barbell Box Squat", .barbell, .quads, .high, .squat, [.glutes, .abs]),
        Entry("dumbbell-step-up", "Dumbbell Step Up", .dumbbell, .quads, .moderate, .lunge, [.glutes, .hamstrings]),
        Entry("kettlebell-deadlift", "Kettlebell Deadlift", .kettlebell, .glutes, .moderate, .hinge, [.hamstrings, .back, .forearms]),
        Entry("single-leg-glute-bridge", "Single-Leg Glute Bridge", .bodyweight, .glutes, .low, .bridge, [.hamstrings]),
        Entry("machine-hip-abduction", "Machine Hip Abduction", .machine, .glutes, .low, .hipAbduction, equipmentName: "Hip Abduction"),
        Entry("nordic-hamstring-curl", "Nordic Hamstring Curl", .bodyweight, .hamstrings, .moderate, .legCurl),
        Entry("standing-single-leg-calf-raise", "Standing Single-Leg Calf Raise", .loadableBodyweight, .calves, .low, .calf),

        // Core.
        Entry("reverse-crunch", "Reverse Crunch", .bodyweight, .abs, .low, .crunch),
        Entry("machine-ab-crunch", "Machine Ab Crunch", .machine, .abs, .low, .crunch),
        Entry("lying-leg-raise", "Lying Leg Raise", .bodyweight, .abs, .low, .legRaise),

        // Smith machine.
        Entry("smith-machine-bench-press", "Smith Machine Bench Press", .machine, .chest, .moderate, .bench, [.triceps, .shoulders], equipmentName: "Smith Machine"),
        Entry("smith-machine-incline-bench-press", "Smith Machine Incline Bench Press", .machine, .chest, .moderate, .bench, [.triceps, .shoulders], equipmentName: "Smith Machine"),
        Entry("smith-machine-close-grip-bench-press", "Smith Machine Close Grip Bench Press", .machine, .triceps, .moderate, .closeGripBench, [.chest, .shoulders], equipmentName: "Smith Machine"),
        Entry("smith-machine-shoulder-press", "Smith Machine Shoulder Press", .machine, .shoulders, .moderate, .overhead, [.triceps], equipmentName: "Smith Machine"),
        Entry("smith-machine-row", "Smith Machine Row", .machine, .back, .moderate, .row.braced, [.biceps, .forearms], equipmentName: "Smith Machine"),
        Entry("smith-machine-shrug", "Smith Machine Shrug", .machine, .back, .low, .shrug, [.forearms], equipmentName: "Smith Machine"),
        Entry("smith-machine-romanian-deadlift", "Smith Machine Romanian Deadlift", .machine, .hamstrings, .high, .hinge, [.glutes, .back], equipmentName: "Smith Machine"),
        Entry("smith-machine-front-squat", "Smith Machine Front Squat", .machine, .quads, .high, .squat, [.glutes, .abs], equipmentName: "Smith Machine"),
        Entry("smith-machine-split-squat", "Smith Machine Split Squat", .machine, .quads, .moderate, .lunge, [.glutes, .hamstrings], equipmentName: "Smith Machine"),
        Entry("smith-machine-bulgarian-split-squat", "Smith Machine Bulgarian Split Squat", .machine, .quads, .high, .lunge, [.glutes, .hamstrings], equipmentName: "Smith Machine"),
        Entry("smith-machine-reverse-lunge", "Smith Machine Reverse Lunge", .machine, .quads, .moderate, .lunge, [.glutes, .hamstrings], equipmentName: "Smith Machine"),
        Entry("smith-machine-calf-raise", "Smith Machine Calf Raise", .machine, .calves, .low, .calf, equipmentName: "Smith Machine"),
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

    /// Built-in equipment by type, in the type's order: the plain type first, then its named equipment.
    static let equipmentOptionsByType: [(base: Equipment, options: [EquipmentOption])] = Equipment.allCases.map { base in
        let options = equipmentOptions.filter { $0.base == base }
        return (base, options.filter { $0.name == nil } + options.filter { $0.name != nil })
    }

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
            let oldestFirst = copies.sorted(by: survivesBefore)
            let survivor = oldestFirst[0]
            for duplicate in oldestFirst.dropFirst() {
                survivor.takeOverRows(of: duplicate)
                context.delete(duplicate)
            }
            TraceLog.record(.data, "Catalog dedupe: kept the oldest \(survivor.catalogID ?? "?"), deleted \(oldestFirst.count - 1) copies")
            changed = true
        }
        // Only the iPhone fills names, so an older iPhone's snapshot never fights a newer watch over them.
        if SyncDevice.current == SyncDevice.iPhone {
            changed = try fillEquipmentNames(in: context) || changed
        }
        return changed
    }

    /// The copy every device keeps: the oldest. Rows saved before `createdAtValue` existed all read as
    /// the oldest, so ties go to the row seeded as built-in (no sync ID), then the lowest sync ID.
    /// Every field read here syncs, so every device keeps the same row.
    static func survivesBefore(_ a: Exercise, _ b: Exercise) -> Bool {
        if a.createdAtValue != b.createdAtValue { return a.createdAtValue < b.createdAtValue }
        switch (a.syncIDValue, b.syncIDValue) {
        case (nil, nil): return false
        case (nil, _): return true
        case (_, nil): return false
        case let (a?, b?): return a.uuidString < b.uuidString
        }
    }

    /// Gives built-in rows seeded before their equipment had a name that name, such as "Smith Machine".
    /// Display only. A row whose equipment type the lifter changed keeps what it shows.
    /// - Returns: Whether anything changed. The caller saves.
    @MainActor
    static func fillEquipmentNames(in context: ModelContext) throws -> Bool {
        let rows = try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.catalogID != nil && $0.customEquipmentName == nil }))
        var changed = false
        for exercise in rows where !exercise.userCreated {
            guard let entry = exercise.catalogID.flatMap({ entriesByID[$0] }),
                  let name = entry.equipmentName,
                  exercise.equipment == entry.equipment
            else { continue }
            exercise.customEquipmentName = name
            changed = true
        }
        return changed
    }

    static let entriesByID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    /// Built-in entries by `matchingName`, so an own "smith machine squat" finds Smith Machine Squat.
    static let entriesByMatchingName = Dictionary(entries.map { (matchingName($0.name), $0) }, uniquingKeysWith: { first, _ in first })

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
