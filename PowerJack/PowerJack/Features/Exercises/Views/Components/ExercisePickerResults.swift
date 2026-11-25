import Foundation
import SwiftData

enum ExercisePickerMode {
    case add
    case change(Exercise?)
    case substitute(WorkoutExercise)

    var source: Exercise? {
        switch self {
        case .add: nil
        case .change(let exercise): exercise
        case .substitute(let row): row.exercise
        }
    }

    var isSubstitution: Bool {
        if case .substitute = self { return true }
        return false
    }
}

struct ExercisePickerResults {
    let suggested: [Exercise]
    let named: [Exercise]
    var isEmpty: Bool { suggested.isEmpty && named.isEmpty }

    init(exercises: [Exercise], index: ExerciseChartSearch.Index?, query: String,
         muscles: Set<Muscle>, mode: ExercisePickerMode) {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = mode.source
        let eligible = exercises.filter { exercise in
            exercise !== source && (muscles.isEmpty || muscles.contains(exercise.primaryMuscleFocus)
                || !muscles.isDisjoint(with: exercise.secondaryMuscles))
        }
        func muscleTier(_ exercise: Exercise) -> Int {
            muscles.isEmpty || muscles.contains(exercise.primaryMuscleFocus) ? 0 : 1
        }
        let alphabetical = eligible.sorted { left, right in
            let lhs = muscleTier(left), rhs = muscleTier(right)
            if lhs != rhs { return lhs < rhs }
            return left.exerciseName.localizedStandardCompare(right.exerciseName) == .orderedAscending
        }

        let search = index?.results(for: text)
        let ranks = search?.ranks ?? [:]
        let ranksPerTier = search?.ranksPerTier ?? 1
        let related = source.flatMap { index?.relatedness(to: $0.persistentModelID) } ?? [:]
        func contextScore(_ exercise: Exercise) -> Float {
            let similarity = related[exercise.persistentModelID] ?? 0
            // Even when a query points away from the original movement (e.g. squat
            // instead of bench), favor available equipment among equally good hits.
            let equipmentPenalty: Float = mode.isSubstitution && exercise.equipment == source?.equipment ? 2 : 0
            return similarity - equipmentPenalty
        }
        // Stable sorting keeps alphabetical order for equally good matches.
        let candidates = alphabetical.filter { exercise in
            let id = exercise.persistentModelID
            return text.isEmpty ? related[id] != nil : ranks[id] != nil
        }
        func suggestionRank(_ exercise: Exercise) -> (Int, Int, Float) {
            let rank = ranks[exercise.persistentModelID] ?? 0
            let distance = Float(rank % ranksPerTier) / Float(ranksPerTier)
            // Each point of source similarity can offset 0.02 of semantic distance
            // inside a query tier. Exact names and primary-muscle tiers take precedence.
            return (muscleTier(exercise), rank / ranksPerTier, distance - 0.02 * contextScore(exercise))
        }
        suggested = Array(candidates.sorted { suggestionRank($0) < suggestionRank($1) }.prefix(3))
        let promoted = Set(suggested.map(\.persistentModelID))
        named = alphabetical.filter {
            !promoted.contains($0.persistentModelID) && (text.isEmpty || $0.exerciseName.localizedStandardContains(text))
        }
    }
}
