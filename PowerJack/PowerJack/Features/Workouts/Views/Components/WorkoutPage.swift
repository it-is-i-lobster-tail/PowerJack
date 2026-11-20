import SwiftUI

/// A horizontal page keeps the workout's exercise indices for review links, logging and menu actions.
struct WorkoutPage {
    let exercises: [WorkoutExercise]
    let startIndex: Int
    let supersetNumber: Int?

    var indices: Range<Int> { startIndex..<(startIndex + exercises.count) }
    var entryIndex: Int {
        if let current = exercises.first?.workoutValue?.currentExerciseIndex, indices.contains(current) {
            return current
        }
        return startIndex + (exercises.firstIndex { !$0.isDone } ?? 0)
    }

    var letter: String? { supersetNumber.map(Workout.supersetLetter(at:)) }
    var header: WorkoutPageHeader {
        if let letter { return .superset(letter) }
        return .exercise(exercises.first?.shownExercise)
    }

    static func pages(for workout: Workout) -> [Self] {
        var start = 0
        var supersets = 0
        return workout.exerciseGroups.map { group in
            let number = group.count > 1 ? supersets : nil
            let page = Self(exercises: group, startIndex: start, supersetNumber: number)
            start += group.count
            if number != nil { supersets += 1 }
            return page
        }
    }
}

enum WorkoutPageHeader {
    case exercise(Exercise?), superset(String), review

    var title: String {
        switch self {
        case .exercise(let exercise): exercise?.exerciseName ?? "Exercise"
        case .superset(let letter): "Superset \(letter)"
        case .review: "Review"
        }
    }

    var equipment: String? {
        if case .exercise(let exercise) = self { return exercise?.equipment.displayName }
        return nil
    }
}
