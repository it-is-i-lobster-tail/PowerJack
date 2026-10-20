//
//  BuildReason.swift
//  PowerJack
//
//  Why the engine planned an exercise the way it did, as a stored code and the line the lifter reads (ENG-03).
//

import Foundation

struct BuildReason: Equatable {
    /// Stored with each planned exercise. Raw values never change meaning.
    enum Code: String {
        case calibrate = "CALIBRATE"
        case startHistory = "START_HISTORY"
        case calibrated = "CALIBRATED"
        case painCheckIn = "PAIN_CHECKIN"
        case painHold = "PAIN_HOLD"
        case painRising = "PAIN_RISING"
        case painReduce = "PAIN_REDUCE"
        case painSetBack = "PAIN_SET_BACK"
        case returnWeek = "RETURN"
        case deloadPlanned = "DELOAD_PLANNED"
        case deloadReactive = "DELOAD_REACTIVE"
        case fatigueCut = "FATIGUE_CUT"
        case volumeRamp = "VOL_RAMP"
        case volumeUp = "VOL_STEP"
        case volumeDown = "VOL_DOWN"
        case repsUp = "REPS_UP"
        case loadUp = "LOAD_UP"
        case holdHard = "HOLD_HARD"
        case holdMiss = "HOLD_MISS"
        case loadDown = "LOAD_DOWN"
        case repCap = "REP_CAP"
        case stepTooLarge = "STEP_TOO_LARGE"
        case unratedStep = "UNRATED_STEP"
        case repeatNotDone = "REPEAT_NOT_DONE"
        case blockRebase = "BLOCK_REBASE"
    }

    var code: Code
    var message: String
}

//
// Messages
//
extension BuildReason {
    static func calibrate(repsOnly: Bool) -> Self {
        Self(
            code: .calibrate,
            message: repsOnly
                ? "New exercise: stop with about 3 reps left."
                : "New exercise: pick a weight that leaves 3 reps in reserve."
        )
    }
    static let startHistory = Self(code: .startHistory, message: "Weight from your recent sets.")
    static let calibrated = Self(code: .calibrated, message: "Set from what you lifted last time.")

    static func painCheckIn(_ pain: LevelOfPain, advice: Bool) -> Self {
        let line = "Pain was \(pain.label) last time: lighter, fewer sets. Check in before you lift."
        return Self(code: .painCheckIn, message: advice ? line + " " + professionalAdvice : line)
    }
    static func painHold(_ pain: LevelOfPain) -> Self {
        Self(code: .painHold, message: "Same as last time: pain was \(pain.label.lowercased()).")
    }
    static let painRising = Self(code: .painRising, message: "Holding: pain went up since last time.")
    static let painReduce = Self(code: .painReduce, message: "10% lighter: pain was moderate or worse twice in a row.")
    static let painSetBack = Self(code: .painSetBack, message: "+1 set back: pain settled.")
    static let professionalAdvice = "Pain this strong or lasting needs a health professional's view."

    static func returnWeek(_ week: Int) -> Self {
        Self(
            code: .returnWeek,
            message: week == 1
                ? "Welcome back. Lighter weights and fewer sets while you ramp up."
                : "Welcome back: full sets again, still lighter."
        )
    }
    static func deload(reactive: Bool) -> Self {
        reactive
            ? Self(code: .deloadReactive, message: "Lighter week: lifts were harder than planned two weeks running.")
            : Self(code: .deloadPlanned, message: "Deload week: lighter on purpose to shed fatigue.")
    }

    static func fatigueCut(_ muscle: Muscle) -> Self {
        Self(code: .fatigueCut, message: "−1 set: \(muscle.rawValue) was harder than planned two weeks running.")
    }
    static func volumeRamp(_ muscle: Muscle) -> Self {
        Self(code: .volumeRamp, message: "+1 set, 1 rep fewer: building \(muscle.rawValue) up to 10 sets a week.")
    }
    static func volumeUp(_ muscle: Muscle) -> Self {
        Self(code: .volumeUp, message: "+1 set this block: \(muscle.rawValue) progressed and recovered well.")
    }
    static func volumeDown(_ muscle: Muscle, pain: Bool) -> Self {
        Self(
            code: .volumeDown,
            message: pain ? "−1 set this block: pain on this exercise." : "−1 set this block so \(muscle.rawValue) can recover."
        )
    }

    static func repsUp(by step: Int, rir: Int, aim: Int) -> Self {
        let change = "+\(step) \(step == 1 ? "rep" : "reps")"
        return Self(
            code: .repsUp,
            message: rir > aim + BuildRules.tolerance
                ? "\(change): \(left(rir)), aim was \(aim)."
                : "\(change): \(left(rir)), as planned."
        )
    }
    static func repsBeforeStep(_ reps: Int, jumpPct: Int) -> Self {
        Self(code: .repsUp, message: "Reps up to \(reps) first: 5 lb is a \(jumpPct)% jump.")
    }
    static let returnCap = Self(code: .repsUp, message: "Reps up first: weights stay near your return weeks this block.")
    static func repsAtMaxLoad(_ reps: Int) -> Self {
        Self(code: .repsUp, message: "Reps up to \(reps): \(pounds(BuildRules.maxLoad)) is the most a set can log.")
    }
    static func holdAtMaxLoad(reps: Int) -> Self {
        Self(code: .stepTooLarge, message: "Holding at \(reps) reps: \(pounds(BuildRules.maxLoad)) is the most a set can log.")
    }
    static func loadUp(by tenths: Int, reps: Int, rir: Int) -> Self {
        Self(code: .loadUp, message: "+\(pounds(tenths)): every set hit \(reps) with \(left(rir)).")
    }
    static func easyStep(by tenths: Int, rir: Int, aim: Int, twice: Bool) -> Self {
        Self(code: .loadUp, message: "+\(pounds(tenths)): \(left(rir))\(twice ? " twice" : ""), aim was \(aim).")
    }
    static func holdHard(rir: Int, aim: Int) -> Self {
        Self(code: .holdHard, message: "Same target: \(left(rir)) last time, aim was \(aim).")
    }
    static func holdAtTop(reps: Int, rir: Int, aim: Int) -> Self {
        Self(code: .holdHard, message: "Same plan: \(reps) reps but \(left(rir)), aim was \(aim).")
    }
    static let holdMiss = Self(code: .holdMiss, message: "Same target: a set fell short.")
    static func loadDown(by tenths: Int?) -> Self {
        Self(
            code: .loadDown,
            message: tenths.map { "−\(pounds($0)): reps fell short twice in a row." }
                ?? "Fewer reps: reps fell short twice in a row."
        )
    }
    static let repCap = Self(code: .repCap, message: "40 reps: add weight or pick a harder variation for more.")
    static func stepTooLarge(reps: Int) -> Self {
        Self(code: .stepTooLarge, message: "Holding at \(reps) reps: the next 5 lb is too big a jump.")
    }
    static let unratedRep = Self(code: .unratedStep, message: "+1 rep: effort wasn't rated, so a small step.")
    static let unratedLoad = Self(code: .unratedStep, message: "+5 lb: top of the range twice in a row.")
    static let unratedHold = Self(code: .unratedStep, message: "Same plan: top of the range once more, then more weight.")
    static let repeatNotDone = Self(code: .repeatNotDone, message: "Same plan: nothing was logged last time.")
    static let blockRebase = Self(code: .blockRebase, message: "New block: reps set for 3 reps in reserve.")
    static let breakRebase = Self(code: .blockRebase, message: "Welcome back: your time off counted as a deload.")

    /// "5 lb", "2.5 lb".
    static func pounds(_ tenths: Int) -> String {
        "\((Double(tenths) / 10).formatted(.number)) lb"
    }

    /// "1 rep left", "5+ reps left".
    static func left(_ rir: Int) -> String {
        switch rir {
        case 0: "no reps left"
        case 1: "1 rep left"
        case 5...: "5+ reps left"
        default: "\(rir) reps left"
        }
    }
}
