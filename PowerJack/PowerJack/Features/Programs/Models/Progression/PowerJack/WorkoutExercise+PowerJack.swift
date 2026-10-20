//
//  WorkoutExercise+PowerJack.swift
//  PowerJack
//
//  A PowerJack slot's plan, its TOP set tap (R4.1) and its rest (R9.2).
//

import Foundation
import OSLog

extension WorkoutExercise {
    var powerJackRole: PowerJackRole? { powerJackRoleValue.flatMap { PowerJackRole(storedValue: $0) } }
    var powerJackTag: PowerJackTag? { powerJackTagValue.flatMap(PowerJackTag.init(rawValue:)) }
    /// TOP sets at the front of a TOP + BACK entry; 0 for straight sets.
    var topSets: Int { powerJackTopSetsValue }
    var topSetRepsInReserve: RepsInReserve? { powerJackTopRIRValue.flatMap(RepsInReserve.init(rawValue:)) }
    var calibrating: Bool { powerJackCalibratingValue }

    /// Part of a PowerJack program, so its plan, taps and rest follow the PowerJacking rules.
    var isPowerJack: Bool { templateType == .powerJack }

    /// Whether `workoutSet` is one of the TOP sets.
    func isTopSet(_ workoutSet: WorkoutSet) -> Bool {
        topSets > 0 && !workoutSet.isWarmup && number(of: workoutSet) <= topSets
    }

    func isLastTopSet(_ workoutSet: WorkoutSet) -> Bool {
        topSets > 0 && !workoutSet.isWarmup && number(of: workoutSet) == topSets
    }

    /// The TOP sets are done and BACK sets wait, so the lifter rates the TOP sets first (R4.1).
    var needsTopSetRating: Bool {
        guard topSets > 0, powerJackTopRIRValue == nil, status == .active else { return false }
        let top = workingSets.prefix(topSets)
        let back = workingSets.dropFirst(topSets)
        return top.allSatisfy(\.isDone) && top.contains { $0.status == .complete } && back.contains { !$0.isDone }
    }

    /// BACK sets were logged before the TOP sets were rated, so the feedback asks for both.
    var topSetsNeedRating: Bool {
        topSets > 0 && powerJackTopRIRValue == nil && workingSets.dropFirst(topSets).contains { $0.status == .complete }
    }

    func rateTopSets(_ repsInReserve: RepsInReserve) {
        guard topSets > 0 else {
            Logger.workoutExercise.warning("Only an entry with TOP sets rates them apart.")
            return
        }
        powerJackTopRIRValue = repsInReserve.rawValue
    }

    /// Records the engine's plan for this planned slot.
    func setPowerJackPlan(_ plan: PowerJackEntryPlan) {
        guard status == .planned else {
            Logger.workoutExercise.warning("Can only set the PowerJack plan of a planned WorkoutExercise.")
            return
        }
        powerJackRoleValue = plan.role.role.storedValue
        powerJackTagValue = plan.role.tag?.rawValue
        powerJackTopSetsValue = plan.topSets
        powerJackTopRIRValue = nil
        powerJackLoadTargetValue = plan.loadTarget
        powerJackTopLoadTargetValue = plan.topLoadTarget
        powerJackCalibratingValue = plan.calibrating
    }

    /// A replaced exercise starts its own plan.
    func clearPowerJackPlan() {
        powerJackRoleValue = nil
        powerJackTagValue = nil
        powerJackTopSetsValue = 0
        powerJackTopRIRValue = nil
        powerJackLoadTargetValue = nil
        powerJackTopLoadTargetValue = nil
        powerJackCalibratingValue = false
    }

    /// The rest after this exercise's latest set. PowerJack rests by role and tag (R9.2): longest after
    /// heavy main-lift sets, a minute more after a short M or S set, and a minute after a warm-up.
    var restDuration: Duration {
        guard let exercise else { return .zero }
        guard isPowerJack, let role = powerJackRole else { return exercise.restDuration }
        let latest = workoutSets
            .filter { $0.status == .complete }
            .max { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        guard let latest, !latest.isWarmup else { return .seconds(PowerJackRules.minRest) }

        let table = switch role {
        case .main where powerJackTag == .heavy || isTopSet(latest): PowerJackRules.heavyRest
        case .main: PowerJackRules.volumeRest
        case .secondary: PowerJackRules.secondaryRest
        case .accessory: PowerJackRules.accessoryRest(exercise.fatigueLevel)
        }
        var seconds = max(PowerJackRules.minRest, exercise.customRestTime ?? table)
        if role.isLifting, let reps = latest.reps, let planned = latest.repsPlanned, reps < planned {
            seconds += PowerJackRules.missRestExtra
        }
        return .seconds(seconds)
    }
}

extension PowerJackRole {
    /// Main lifts and other multi-joint exercises, which rest longer after a short set.
    var isLifting: Bool {
        switch self {
        case .main, .secondary: true
        case .accessory: false
        }
    }

    var storedValue: String {
        switch self {
        case .main: "main"
        case .secondary: "secondary"
        case .accessory: "accessory"
        }
    }

    init?(storedValue: String) {
        guard let role = [PowerJackRole.main, .secondary, .accessory].first(where: { $0.storedValue == storedValue }) else { return nil }
        self = role
    }
}
