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

    /// A substitute is usually needed because the equipment is taken, so other equipment ranks first.
    var searchContext: ExerciseSearch.Context {
        guard let source else { return .browse }
        return .replacing(source: source.searchKey, sameEquipment: !isSubstitution)
    }
}

struct ExercisePickerResults {
    /// Best first. With no query: the lifts the lifter trains, then everything else by name,
    /// or when replacing, the source's closest neighbours.
    let matches: [Exercise]
    /// With no query when replacing: everything else by name.
    let others: [Exercise]
    var isEmpty: Bool { matches.isEmpty && others.isEmpty }

    init(exercises: [Exercise], index: ExerciseSearch.Index?, familiarity: ExerciseFamiliarity = .none,
         query: String, muscles: Set<Muscle>, mode: ExercisePickerMode) {
        let source = mode.source
        let eligible = exercises.filter { exercise in
            exercise !== source && (muscles.isEmpty || muscles.contains(exercise.primaryMuscleFocus)
                || !muscles.isDisjoint(with: exercise.secondaryMuscles))
        }
        // The muscle filter lists lifts that work a chosen muscle most before those that assist.
        func assists(_ exercise: Exercise) -> Bool {
            !muscles.isEmpty && !muscles.contains(exercise.primaryMuscleFocus)
        }
        let byName = eligible.sorted { left, right in
            if assists(left) != assists(right) { return !assists(left) }
            return left.exerciseName.localizedStandardCompare(right.exerciseName) == .orderedAscending
        }

        let searchQuery = ExerciseQuery(query)
        guard let index else {
            matches = searchQuery.isEmpty ? byName : []
            others = []
            return
        }
        let byKey = Dictionary(eligible.map { ($0.searchKey, $0) }, uniquingKeysWith: { first, _ in first })
        let ranked = index.rank(searchQuery, context: mode.searchContext, familiarity: familiarity)
            .compactMap { byKey[$0.key] }
        let filtered = ranked.filter { !assists($0) } + ranked.filter(assists)
        guard searchQuery.isEmpty else {
            matches = filtered
            others = []
            return
        }
        let shown = Set(filtered.map(\.persistentModelID))
        let rest = byName.filter { !shown.contains($0.persistentModelID) }
        if source == nil {
            matches = filtered + rest
            others = []
        } else {
            matches = filtered
            others = rest
        }
    }
}
