//
//  PowerJackRoles.swift
//  PowerJack
//
//  Reads main lifts, slot roles and heavy / volume tags from the week's exercises (R1.1, R1.2).
//  The engine never picks, adds or reorders exercises: the template decides.
//

import Foundation

enum PowerJackPattern {
    case squat, hinge, horizontalPush, verticalPush, horizontalPull, verticalPull

    var canBeMainLift: Bool {
        switch self {
        case .squat, .hinge, .horizontalPush, .verticalPush: true
        case .horizontalPull, .verticalPull: false
        }
    }
}

/// What the engine needs to know about an exercise, detached from SwiftData.
struct PowerJackExercise: Equatable {
    var id: AnyHashable
    var pattern: PowerJackPattern?
    var multiJoint: Bool
    var repsOnly: Bool
    var assisted: Bool = false
    var isBarbell: Bool = false
    var fatigue: FatigueLevel
    var primary: Muscle
    var secondaries: [Muscle] = []

    var isMainLiftEligible: Bool {
        multiJoint && (pattern?.canBeMainLift ?? false) && !repsOnly && !assisted
    }
}

extension PowerJackExercise {
    /// Library fields the catalog doesn't store yet, keyed by its permanent IDs. Custom exercises
    /// fall back to R1.1's reading of the primary muscle and fatigue level.
    static func traits(catalogID: String?, primary: Muscle, fatigue: FatigueLevel) -> (PowerJackPattern?, Bool) {
        if let catalogID, catalogIDs.contains(catalogID) {
            // Catalog exercises not listed below are single-joint work.
            return catalogTraits[catalogID] ?? (nil, false)
        }
        let pattern: PowerJackPattern? = switch primary {
        case .quads: .squat
        case .hamstrings, .glutes: .hinge
        case .chest: .horizontalPush
        case .shoulders: .verticalPush
        case .back: .horizontalPull
        default: nil
        }
        return (pattern, fatigue == .high)
    }

    private static let catalogTraits: [String: (PowerJackPattern?, Bool)] = [
        "barbell-back-squat": (.squat, true),
        "barbell-front-squat": (.squat, true),
        "goblet-squat": (.squat, true),
        "dumbbell-goblet-squat": (.squat, true),
        "dumbbell-bulgarian-split-squat": (.squat, true),
        "dumbbell-walking-lunge": (.squat, true),
        "leg-press": (.squat, true),
        "smith-machine-squat": (.squat, true),
        "barbell-deadlift": (.hinge, true),
        "barbell-romanian-deadlift": (.hinge, true),
        "dumbbell-romanian-deadlift": (.hinge, true),
        "barbell-hip-thrust": (.hinge, true),
        "smith-machine-hip-thrust": (.hinge, true),
        "glute-bridge": (.hinge, true),
        "barbell-bench-press": (.horizontalPush, true),
        "incline-barbell-bench-press": (.horizontalPush, true),
        "dumbbell-bench-press": (.horizontalPush, true),
        "incline-dumbbell-bench-press": (.horizontalPush, true),
        "push-up": (.horizontalPush, true),
        "barbell-overhead-press": (.verticalPush, true),
        "dumbbell-shoulder-press": (.verticalPush, true),
        "barbell-row": (.horizontalPull, true),
        "seated-cable-row": (.horizontalPull, true),
        "one-arm-dumbbell-row": (.horizontalPull, true),
        "pull-up": (.verticalPull, true),
        "chin-up": (.verticalPull, true),
        "lat-pulldown": (.verticalPull, true),
    ]

    private static let catalogIDs = Set(ExerciseCatalog.entries.map(\.id))
}

enum PowerJackRole: Equatable {
    case main, secondary, accessory
}

/// A main-lift slot's place in its lift's week (R1.2, R4.6).
enum PowerJackTag: String, Equatable {
    /// Heavy reps: an H slot or a TOP entry.
    case heavy
    /// Volume reps: a V slot or a BACK entry.
    case volume
    /// A once-a-week entry: its first working set is the TOP set, the rest are BACK sets.
    case topAndBack
}

struct PowerJackSlotRole: Equatable {
    var role: PowerJackRole
    var tag: PowerJackTag?
}

enum PowerJackRoles {
    /// Roles and tags for every slot, in the week's workout and entry order.
    static func assign(_ workouts: [[PowerJackExercise]]) -> [[PowerJackSlotRole]] {
        let slots = workouts.joined()
        var mainLifts: [PowerJackExercise] = []
        for exercise in slots where exercise.isMainLiftEligible
            && !mainLifts.contains(where: { $0.pattern == exercise.pattern })
            && mainLifts.count < PowerJackRules.mainLiftsMax {
            mainLifts.append(exercise)
        }
        let mainIDs = Set(mainLifts.map(\.id))

        // Exposures: the workouts holding each main lift, in order.
        var exposureIndex: [AnyHashable: Int] = [:]
        var exposures: [AnyHashable: Int] = [:]
        for workout in workouts {
            for id in Set(workout.map(\.id)) where mainIDs.contains(id) {
                exposures[id, default: 0] += 1
            }
        }

        return workouts.map { workout in
            var seenInWorkout: Set<AnyHashable> = []
            return workout.map { exercise -> PowerJackSlotRole in
                guard mainIDs.contains(exercise.id) else {
                    return PowerJackSlotRole(role: exercise.multiJoint ? .secondary : .accessory, tag: nil)
                }
                let entries = workout.filter { $0.id == exercise.id }.count
                defer { seenInWorkout.insert(exercise.id) }
                if seenInWorkout.contains(exercise.id) {
                    return PowerJackSlotRole(role: .main, tag: .volume)
                }
                exposureIndex[exercise.id, default: 0] += 1
                if entries > 1 { return PowerJackSlotRole(role: .main, tag: .heavy) }
                if exposures[exercise.id] == 1 { return PowerJackSlotRole(role: .main, tag: .topAndBack) }
                let isOdd = exposureIndex[exercise.id, default: 1] % 2 == 1
                return PowerJackSlotRole(role: .main, tag: isOdd ? .heavy : .volume)
            }
        }
    }
}
