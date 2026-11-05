//
//  StrengthRules.swift
//  PowerJack
//
//  Every tunable number of the Strengthen progression rules, in one place.
//  Names and defaults follow the "Strength progression rules" doc; the comments give each rule ID.
//

import Foundation

enum StrengthRules {
    /// Logged with every plan, so a change of numbers can be traced.
    static let version = "strength-2"

    // MARK: 1 Units and load steps
    /// A slot moves to reps mode when one load step is more than this share of its load (1.2).
    static let maxStepShare = 0.075
    /// The most reps reps mode adds before it takes a load step (1.2).
    static let repOffsetMax = 3
    /// Reps mode never plans more reps to failure than this (1.2's fit()).
    static let fitMaxReps = 12

    // MARK: 2 Calibration
    /// Weeks a new lift calibrates. A rated top set pins down e1RM, so one is enough.
    static let calibrationWeeks = 1
    /// A close variant starts at this share of its parent's ratio-scaled e1RM (2.3).
    static let variantFactor = 0.90
    /// Extra reps in reserve on a variant's first week (2.3).
    static let variantRIRAdd = 1

    // MARK: 3 Effort capture
    /// Ratings above this give only a lower bound on e1RM (3.3).
    static let e1rmMaxRIR = 3

    // MARK: 4 Strength estimation
    /// Rated sets past this many reps to failure give no e1RM (4.1).
    static let e1rmMaxReps = 10
    static let alpha = 0.5
    static let alphaFast = 0.8
    /// Weekly updates at `alphaFast` after a return (4.2, 12.4).
    static let fastWeeks = 2
    /// A weekly e1RM this far from the estimate waits a week for confirmation (4.3).
    static let outlierShare = 0.12
    static let outlierConfirmShare = 0.05
    /// e1RM changes below this are noise (4.4).
    static let mdcShare = 0.05
    /// Rated sessions in this window make up `e1rmConf` (4.5).
    static let confidenceWindowDays = 28
    /// Below this many rated sessions a weekly rise is at most one step, and nothing reads e1RM (4.5).
    static let confidenceMin = 3

    // MARK: 5 Prescription defaults
    static let slotSets = 3
    static let secondaryRepsToFailureMax = 10
    static let rirMin = 1
    /// The fewest reps a stored plan falls back to when it has no target.
    static let repsMinNormal = 3
    /// Squat and bench sets at or under this many reps to failure need a spotter or safety arms (5.2).
    static let spotterRepsToFailure = 4
    static let restPrimarySeconds = 180
    static let restSecondarySeconds = 135
    /// Warm-ups for primary slots: share of the first working load × reps (5.7).
    static let primaryWarmups: [(share: Double, reps: Int)] = [(0.5, 5), (0.7, 3), (0.85, 1)]
    static let secondaryWarmups: [(share: Double, reps: Int)] = [(0.5, 5), (0.75, 3)]
    /// The 85% warm-up is dropped when the first working load is under this share of e1RM (5.7).
    static let heavyWarmupGate = 0.80
    /// The most priority lifts a program has (Inputs).
    static let maxPriorityLifts = 4

    // MARK: Top sets
    /// A priority lift's session: one top set, then back-off sets at a share of it. The heavy day's top set
    /// runs a triple, then a double, then a single as the block nears its end; the volume day keeps 4-5 reps.
    struct TopSetScheme: Equatable {
        var reps: Int
        var rir: Int
        var backSets: Int
        var backReps: Int
        /// Back-off load as a share of the top set's.
        var backShare: Double
    }

    /// The scheme for block week `blockWeek` of `trainWeeks`. Weeks before the last two repeat the first.
    static func topSetScheme(zone: StrengthZone?, blockWeek: Int, of trainWeeks: Int) -> TopSetScheme {
        let weeksLeft = max(0, trainWeeks - blockWeek)
        if zone == .moderate {
            switch weeksLeft {
            case 0: return TopSetScheme(reps: 4, rir: 2, backSets: 3, backReps: 4, backShare: 0.93)
            case 1: return TopSetScheme(reps: 5, rir: 2, backSets: 3, backReps: 5, backShare: 0.93)
            default: return TopSetScheme(reps: 5, rir: 3, backSets: 3, backReps: 5, backShare: 0.93)
            }
        }
        switch weeksLeft {
        case 0: return TopSetScheme(reps: 1, rir: 1, backSets: 3, backReps: 3, backShare: 0.87)
        case 1: return TopSetScheme(reps: 2, rir: 2, backSets: 3, backReps: 3, backShare: 0.90)
        default: return TopSetScheme(reps: 3, rir: 2, backSets: 3, backReps: 3, backShare: 0.92)
        }
    }

    /// Back-offs whose top set had no planned weight (a by-feel week) take this share of it.
    static let backShareByFeel = 0.92
    /// Each rep the top set was easier than its aim lifts the back-offs this share, up to `backEasyMaxReps` reps.
    static let backEasyStep = 0.025
    static let backEasyMaxReps = 2
    /// Each rep harder, or missed, lowers them this share, up to `backHardMaxReps` reps.
    static let backHardStep = 0.04
    static let backHardMaxReps = 3
    static let maxBackSets = 4
    static let minBackSets = 1

    // MARK: 6 In-session
    /// Each missing rep cuts the sets still to do by this share (6.2).
    static let missDrop = 0.04

    // MARK: 7 Weekly load progression
    static let kRep = 0.025
    static let deltaMax = 3
    static let nudgeIntermediate = 0.0125
    static let nudgeAdvanced = 0.005
    static let deadbandReps = 2
    static let capUp = 0.075
    /// `CAP_UP` for advanced lifters and calibration weeks (7.3).
    static let capUpCautious = 0.05
    static let capDown = 0.10
    static let minDoneShare = 0.5
    static let ceilingReps = 1

    // MARK: 8 Volume
    static let minLiftSets = 3
    static let maxLiftSets = 12
    static let minSlotSets = 2
    static let maxSlotSets = 5

    // MARK: 9 Blocks
    /// Training weeks of a block that runs past the program's end. Blocks inside it run 3 to 6 to fit its length.
    static var blockTrainWeeks: Int { ProgramBlocks.buildWeeks }
    static let newBlockFactor = 1.0

    // MARK: 10 Fatigue and deload
    static let flagDelta = -2
    static let flagBadSessions = 2
    static let flagLastSessions = 3
    static let flagWindowDays = 14
    static let microLoadCut = 0.05
    static let microSetCut = 1
    static let microMinSets = 2
    static let globalFlagLifts = 2
    static let globalRIR0Share = 0.5
    static let globalRIR0Weeks = 2
    static let deloadSkipWeeks = 3
    static let deloadMaxGapWeeks = 8
    static let deloadSetFactor = 0.5
    /// Deloads keep 90% of the load, as in every style (10.6, Decisions).
    static let deloadLoadFactor = 0.90
    static let deloadRIRAdd = 2
    static let deloadRIRMin = 3

    // MARK: 11 Plateaus
    static let stallWindowIntermediate = 8
    static let stallWindowAdvanced = 12
    static let stallMinGain = 0.01
    static let stallMinAdherence = 0.75
    static let stallSetLimit = 10
    static let resetCut = 0.10
    static let resetRebuildWeeks = 4

    // MARK: 12 Breaks
    /// A lift untrained for more than this many days is on a break (12.1).
    static let breakMinDays = 14

    // MARK: 15 Pain
    static let painWatch = LevelOfPain.noticeable
    static let painHold = LevelOfPain.moderate
    static let painStop = LevelOfPain.severe
    static let painCut = 0.20
    static let painModerateCut = 0.10
    static let painReturnSets = 2
    static let painReturnRIR = 3
    static let painReturnStep = 0.05

    // MARK: 17 Training age
    /// Everyone starts at 1 training year; each trained week adds 1/52 (17.7).
    static let startingTrainingYears = 1.0
    static let advancedMinYears = 3.0
}
