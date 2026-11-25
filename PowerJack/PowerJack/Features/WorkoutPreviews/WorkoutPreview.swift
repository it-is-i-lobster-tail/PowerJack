import Foundation
import SwiftData

struct WorkoutPreview: Equatable {
    enum SetRole: Equatable {
        case top, backOff, working

        var title: String? {
            switch self {
            case .top: "Top set"
            case .backOff: "Back-off"
            case .working: nil
            }
        }
    }

    struct SetGroup: Equatable {
        let role: SetRole
        let reps: Int?
        let weight: Int?
        let byFeel: Bool
        var count = 1

        func text(unit: WeightUnit) -> String {
            var text = reps.map { "\(count) × \($0)" } ?? "\(count) \(count == 1 ? "set" : "sets")"
            if let weight {
                text += " at \(unit.format(tenthsPounds: weight)) \(unit.symbol)"
            } else if byFeel {
                text += " · By feel"
            }
            return text
        }
    }

    struct Lift: Equatable {
        let name: String
        let catalogID: String?
        let key: String?
        let equipment: Equipment
        let curve: StrengthCurve?
        let order: Int
        let occurrence: Int
        let muscle: Muscle
        let sets: [SetGroup]
        let allowsPR: Bool

        init?(_ entry: WorkoutExercise, occurrence: Int = 0) {
            guard let exercise = entry.shownExercise, !entry.workingSets.isEmpty else { return nil }
            order = entry.order
            self.occurrence = occurrence
            key = exercise.syncKey
            equipment = exercise.equipment
            let supported = [StrengthLifts.benchID, StrengthLifts.squatID, StrengthLifts.deadliftID,
                             "barbell-overhead-press", "dumbbell-bench-press"]
            curve = (supported.contains(exercise.catalogID ?? "") || StrengthLifts.isCompound(exercise))
                && !exercise.repsOnly && !exercise.addsToBodyweight ? StrengthLifts.curve(for: exercise) : nil
            name = exercise.exerciseName
            catalogID = exercise.catalogID
            muscle = exercise.primaryMuscleFocus
            allowsPR = entry.checkIn != .pending
            var groups: [SetGroup] = []
            for set in entry.workingSets where set.status == .planned {
                let role: SetRole = entry.isTopSet(set) ? .top : (entry.topSets > 0 ? .backOff : .working)
                let group = SetGroup(
                    role: role, reps: set.repsPlanned, weight: set.weightTenthsPlannedPounds,
                    byFeel: !exercise.repsOnly && !exercise.addsToBodyweight && set.weightTenthsPlannedPounds == nil
                )
                guard let previous = groups.last,
                      previous.role == group.role, previous.reps == group.reps,
                      previous.weight == group.weight, previous.byFeel == group.byFeel else {
                    groups.append(group)
                    continue
                }
                groups[groups.count - 1].count += 1
            }
            guard !groups.isEmpty else { return nil }
            sets = groups
        }
    }

    let type: TemplateType
    let weekKind: WeekKind?
    let lifts: [Lift]

    init(program: Program, workout: Workout) {
        type = program.templateType
        weekKind = program.programWeek(containing: workout)?.weekKind
        var occurrences: [String: Int] = [:]
        lifts = workout.workoutExercises.compactMap { entry in
            let key = entry.shownExercise?.syncKey ?? ""
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            return Lift(entry, occurrence: occurrence)
        }
    }

    var mainMuscle: Muscle? {
        let totals = Dictionary(grouping: lifts, by: \.muscle).mapValues { lifts in
            lifts.flatMap(\.sets).reduce(0) { $0 + $1.count }
        }
        return lifts.map(\.muscle).max { totals[$0, default: 0] < totals[$1, default: 0] }
    }

    var teaser: String {
        guard let first = lifts.first else { return "Your next workout is ready to preview." }
        if weekKind == .deload { return "A lighter session starts with \(first.name)." }
        if let top = first.sets.first(where: { $0.role == .top }),
           first.sets.contains(where: { $0.role == .backOff }) {
            if let reps = top.reps {
                return "\(first.name) opens with a \(reps)-rep top set, then back-offs."
            }
            return "\(first.name) leads with a top set and back-offs."
        }
        if let second = lifts.dropFirst().first {
            return "\(first.name) first, then \(second.name)."
        }
        return "\(first.name) is up next."
    }

    var focusOptions: [String] {
        if weekKind == .deload { return ["A lighter session to make room for recovery."] }
        var options = [teaser]
        if let first = lifts.first, let muscle = mainMuscle {
            options.append("\(first.name) leads a session with an emphasis on \(muscle.rawValue).")
        }
        return options
    }
}
