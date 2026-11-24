//
//  Workout+SupersetEditing.swift
//  PowerJack
//
//  Supersets changed from a workout's ••• menu, before it starts or while it's in progress.
//  The exercise the menu was opened from always leads the superset it joins, and an exercise
//  taken out of a superset goes just before it. Logged sets are never touched.
//

import Foundation
import OSLog
import SwiftUI

extension Workout {
    /// Supersets change before the workout starts and while it's in progress, never once it's finished.
    var canEditSupersets: Bool { status == .planned || status == .active }

    /// A new superset can start until the workout has five.
    var canStartSuperset: Bool { supersets.count < SupersetStyle.maxPerWorkout }

    /// What `workoutExercise` can be stacked with: each other exercise on its own and each superset, in order.
    /// Finished ones are left out, since there's nothing left to do in turn with them. Once the workout
    /// has five supersets, only those can be joined.
    func supersetChoices(for workoutExercise: WorkoutExercise) -> [[WorkoutExercise]] {
        exerciseGroups.filter { group in
            !group.contains { $0 === workoutExercise }
                && !group.allSatisfy(\.isDone)
                && (group.count > 1 || canStartSuperset)
        }
    }

    /// Stacks `workoutExercise` with `group`, an exercise on its own or a whole superset. The group moves to
    /// just after `workoutExercise`, so the exercise the user started from leads the superset.
    func addToSuperset(_ workoutExercise: WorkoutExercise, with group: [WorkoutExercise], newSupersetID: UUID = UUID()) {
        guard
            canEditSupersets,
            group.count > 1 || canStartSuperset,
            workoutExercise.supersetPartners.isEmpty,
            let first = group.first,
            !group.contains(where: { $0 === workoutExercise })
        else {
            Logger.workout.warning("Can only add an exercise on its own to another exercise or superset in a live Workout.")
            return
        }
        // Joining a superset keeps its ID, so it stays the same superset everywhere it's shown.
        let supersetID = group.count > 1 ? first.supersetID ?? newSupersetID : newSupersetID
        var ordered = workoutExercises.filter { member in !group.contains { $0 === member } }
        guard let index = ordered.firstIndex(where: { $0 === workoutExercise }) else { return }
        ordered.insert(contentsOf: group, at: index + 1)
        for member in [workoutExercise] + group {
            member.setSuperset(supersetID)
        }
        renumber(ordered)
    }

    /// Takes `workoutExercise` out of its superset and puts it on its own just before what's left.
    /// A superset left with one exercise ends.
    func removeFromSuperset(_ workoutExercise: WorkoutExercise) {
        let rest = group(of: workoutExercise).filter { $0 !== workoutExercise }
        guard canEditSupersets, let first = rest.first else { return }
        var ordered = workoutExercises.filter { $0 !== workoutExercise }
        guard let start = ordered.firstIndex(where: { $0 === first }) else { return }
        ordered.insert(workoutExercise, at: start)
        workoutExercise.setSuperset(nil)
        if rest.count == 1 {
            first.setSuperset(nil)
        }
        renumber(ordered)
    }

    /// Splits a superset back into exercises on their own, in the order they were in.
    func removeSuperset(_ supersetID: UUID) {
        guard canEditSupersets, let superset = superset(supersetID) else { return }
        for member in superset {
            member.setSuperset(nil)
        }
    }

    /// Reorders the exercises inside one superset. The rest of the workout stays put.
    func moveExercises(inSuperset supersetID: UUID, from source: IndexSet, to destination: Int) {
        guard
            canEditSupersets,
            let superset = superset(supersetID),
            destination >= 0, destination <= superset.count,
            source.allSatisfy({ superset.indices.contains($0) })
        else {
            return
        }
        var ordered = workoutExercises
        guard let start = ordered.firstIndex(where: { $0 === superset[0] }) else { return }
        var members = superset
        members.move(fromOffsets: source, toOffset: destination)
        ordered.replaceSubrange(start..<start + members.count, with: members)
        renumber(ordered)
    }

    private func renumber(_ ordered: [WorkoutExercise]) {
        for (order, workoutExercise) in ordered.enumerated() where workoutExercise.order != order {
            workoutExercise.order = order
        }
        TraceLog.record(.workout, "Changed the supersets of \(traceDescription)")
    }
}

extension WorkoutExercise {
    /// The color of this exercise's superset, or nil when it stands alone.
    var supersetColor: Color? {
        supersetIndex.map(SupersetStyle.color(at:))
    }
}
