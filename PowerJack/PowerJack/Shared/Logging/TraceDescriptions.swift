//
//  TraceDescriptions.swift
//  PowerJack
//
//  How models read in the trace (see `TraceLog`). Rows go by the first part of their sync ID, the
//  same on the iPhone and the watch. Names the lifter typed never appear: a custom exercise or
//  a program is only its ID, while built-in exercises keep their catalog name.
//

import Foundation

extension TraceLog {
    /// The first 8 characters of a sync ID, like 1A2B3C4D.
    nonisolated static func id(_ uuid: UUID?) -> String {
        uuid.map { String($0.uuidString.prefix(8)) } ?? "no-id"
    }

    /// e.g. "135 lb × 8", "BW × 12" or "– × –". Weights are stored in pounds.
    nonisolated static func load(tenthsPounds: Int?, reps: Int?) -> String {
        let weight = tenthsPounds.map { tenths in
            switch tenths {
            case 0: "BW"
            case let whole where whole % 10 == 0: "\(whole / 10) lb"
            default: "\(Double(tenths) / 10) lb"
            }
        } ?? "–"
        return "\(weight) × \(reps.map(String.init) ?? "–")"
    }
}

extension TraceLog {
    /// A day's exercises in order, superset members marked by their superset's letter,
    /// e.g. "Barbell Back Squat, A:Dumbbell Curl, A:custom exercise 1A2B3C4D".
    static func layout(_ entries: [(exercise: Exercise?, supersetID: UUID?)]) -> String {
        var letters: [UUID: String] = [:]
        let names = entries.map { entry in
            let name = entry.exercise?.traceName ?? "no exercise"
            guard let supersetID = entry.supersetID else { return name }
            if letters[supersetID] == nil {
                letters[supersetID] = String(UnicodeScalar(UInt8(65 + letters.count % 26)))
            }
            return "\(letters[supersetID] ?? "?"):\(name)"
        }
        return names.isEmpty ? "no exercises" : names.joined(separator: ", ")
    }
}

extension Workout {
    /// This day's exercises, as `TraceLog.layout` writes them.
    var traceLayout: String {
        TraceLog.layout(workoutExercises.map { (exercise: $0.exercise, supersetID: $0.supersetID) })
    }
}

extension Program {
    var traceDescription: String {
        "program \(TraceLog.id(syncID)) \(templateType.rawValue) \(status.rawValue)"
    }
}

extension Workout {
    var traceDescription: String {
        "workout \(TraceLog.id(syncID)) \(status.rawValue)"
    }
}

extension WorkoutExercise {
    var traceDescription: String {
        "\(exercise?.traceName ?? "no exercise") (\(TraceLog.id(syncID))) \(status.rawValue)"
    }
}

extension WorkoutSet {
    var traceDescription: String {
        let logged = TraceLog.load(tenthsPounds: weightTenthsPounds, reps: reps)
        let planned = TraceLog.load(tenthsPounds: weightTenthsPlannedPounds, reps: repsPlanned)
        return "\(setType.rawValue) set \(TraceLog.id(syncID)) \(status.rawValue) \(logged), plan \(planned)"
    }
}

extension Exercise {
    var traceName: String {
        userCreated ? "custom exercise \(TraceLog.id(syncIDValue))" : exerciseName
    }
}
