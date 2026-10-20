//
//  StrengthLifts.swift
//  PowerJack
//
//  Which exercises of a strength program are its priority lifts, and the role each exercise plays
//  (Definitions, Inputs, rules 5.3 and 14.6). Nothing here is asked; it all comes from the template.
//

import Foundation

/// Priority lifts get the full load rules, their close variants a lighter version, everything else
/// keeps a simple double progression (rule 14.6).
enum StrengthRole: String, Codable {
    case primary
    case secondary
    case accessory
}

/// A priority lift trained twice a week has a heavy slot, then a moderate one (rule 5.3).
enum StrengthZone: String, Codable {
    case heavy
    case moderate
}

enum StrengthLifts {
    static let squatID = "barbell-back-squat"
    static let benchID = "barbell-bench-press"
    static let deadliftID = "barbell-deadlift"

    /// Close variants and their share of the parent's e1RM (rules 2.3 and 14.6).
    static let variants: [String: (parentID: String, ratio: Double)] = [
        "barbell-front-squat": (squatID, 0.85),
        "incline-barbell-bench-press": (benchID, 0.80),
        "barbell-romanian-deadlift": (deadliftID, 0.70),
    ]

    /// Flat bench presses read the bench curve (rule 4.7).
    private static let benchCurveIDs: Set = [benchID, "dumbbell-bench-press"]

    /// The lift's record key. Catalog exercises use their permanent ID; one the user made uses when it was
    /// made, which syncs with it and never changes.
    static func key(for exercise: Exercise) -> String {
        if let catalogID = exercise.catalogID { return catalogID }
        return "user.\(Int(exercise.createdAtValue.timeIntervalSince1970)).\(exercise.exerciseName)"
    }

    static func curve(for exercise: Exercise) -> StrengthCurve {
        benchCurveIDs.contains(exercise.catalogID ?? "") ? .bench : .main
    }

    /// Squats, bench presses and their variants ask for a spotter or safety arms on near-max sets (rule 5.2).
    static func needsSpotter(_ exercise: Exercise) -> Bool {
        guard let id = exercise.catalogID else { return false }
        return id == squatID || id == benchID || [squatID, benchID].contains(variants[id]?.parentID)
    }

    /// Multi-joint and loaded: trains more than one muscle on top of its main one.
    static func isCompound(_ exercise: Exercise) -> Bool {
        !exercise.repsOnly && exercise.secondaryMuscles.count >= 2
    }

    /// Up to 4 priority lift keys in rank order: the squat, bench press and deadlift when the program has them,
    /// then the first compound lift of each workout, without repeats or variants of a lift already chosen.
    static func priorityKeys(in workouts: [[Exercise]]) -> [String] {
        let exercises = workouts.flatMap { $0 }
        var keys: [String] = [squatID, benchID, deadliftID].filter { id in exercises.contains { $0.catalogID == id } }

        for workout in workouts where keys.count < StrengthRules.maxPriorityLifts {
            guard let first = workout.first(where: { isCompound($0) }) else { continue }
            let key = key(for: first)
            let parent = first.catalogID.flatMap { variants[$0]?.parentID }
            guard !keys.contains(key), !keys.contains(parent ?? "") else { continue }
            keys.append(key)
        }
        return keys
    }

    /// Primary for priority lifts, secondary for a catalog variant of a lift, otherwise an accessory.
    static func role(of exercise: Exercise, priorityKeys: [String]) -> StrengthRole {
        if priorityKeys.contains(key(for: exercise)) { return .primary }
        if !exercise.repsOnly, let id = exercise.catalogID, variants[id] != nil { return .secondary }
        return .accessory
    }
}
