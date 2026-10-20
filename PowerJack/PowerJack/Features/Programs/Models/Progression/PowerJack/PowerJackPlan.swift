//
//  PowerJackPlan.swift
//  PowerJack
//
//  What the engine hands back: next week's type and, for every slot, its working sets, warm-ups,
//  target RIR and the state the week after needs.
//

import Foundation

struct PowerJackSetPlan: Equatable {
    var reps: Int?
    /// Nil asks the lifter to load it: a calibrating exposure or a new exercise.
    var load: Double?
}

/// Why a slot changed, kept for tests and the log (R10.1's reason codes).
enum PowerJackReason: String, Equatable {
    case blockStart, calibrate, ramp, easyStep, hold, missCut, repStep, loadJump, widenRange, backoff
    case addedSet, setCut, deload, repeatSkipped, painHold, painReduce, painCheckIn, painReturn
}

struct PowerJackEntryPlan: Equatable {
    var exercise: PowerJackExercise
    var role: PowerJackSlotRole
    var sets: [PowerJackSetPlan]
    /// TOP sets at the front of a TOP + BACK entry.
    var topSets = 0
    var warmups: [PowerJackSetPlan] = []
    /// Reps to leave on the last working set. Nil in a deload, which asks for 3 or more on every set.
    var target: Int?
    /// The last set is a planned rep-out (R4.4).
    var repOut = false
    var loadTarget: Double?
    var topLoadTarget: Double?
    var calibrating = false
    /// Severe pain last time: the check-in opens first (R10.4).
    var checkInPain: LevelOfPain?
    var warmupsDisabled = false
    var reasons: [PowerJackReason] = []

    var straightSets: [PowerJackSetPlan] { Array(sets.dropFirst(topSets)) }
}

struct PowerJackWeekPlan: Equatable {
    var header: PowerJackWeekPlanHeader
    var workouts: [[PowerJackEntryPlan]]
}
