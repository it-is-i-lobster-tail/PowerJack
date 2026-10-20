//
//  BuildRules.swift
//  PowerJack
//
//  The Build (hypertrophy) rulebook's parameters. Names follow its parameter registry.
//  Loads are in tenths of a pound, like `WorkoutSet`.
//

import Foundation

enum BuildRules {
    // MARK: Effort (EFF, START)

    /// Reps to leave on the last set in each build week of a block (EFF.rirByWeek). Its length is the block's build weeks.
    static let rirByWeek = [3, 2, 2, 1]
    static var buildWeeks: Int { rirByWeek.count }
    /// Block week 1, calibrating exercises and return weeks (START.rirWeek1).
    static let startRIR = 3
    static let tolerance = 1
    static let highRepTolerance = 2
    static let highRepThreshold = 12
    /// Exercises that may take their last set to failure in the final build week (EFF.failureFatigueLevels).
    static let failureFatigueLevels: Set<FatigueLevel> = [.low, .moderate]
    /// Sets rated with more reps left than this earn no volume credit (VOL.hardSetMaxRIR).
    static let hardSetMaxRIR = 4

    // MARK: Load and reps (LOAD)

    static let stepTenths = 50
    static let maxJumpPct = 10.0
    static let repsPerStep = 1
    static let repsPerStepEasy = 2
    static let easyJumpByRirGap = 3
    static let easyJumpMaxPct = 20.0
    static let calibrationMaxJumpPct = 25.0
    static let repRangeExtensionMax = 10
    static let maxReps = 30
    static let bodyweightRepCap = 40
    static let missStreakForBackoff = 2.0
    static let shortGapMissWeight = 0.5
    static let backoffPct = 5.0

    // MARK: Weekly volume and sessions (VOL, FREQ)

    static let secondaryCredit = 0.5
    static let minRepsForCredit = 5
    static let floor = 10.0
    static let ceiling = 20.0
    static let focusCeiling = 25.0
    static let rampInPerWeek = 1
    static let rampInMaxPerBlock = 2
    static let blockStepPct = 0.2
    static let blockStepSetsMax = 4
    static let maxCreditsPerSessionPerMuscle = 12.0
    static let minSetsPerExercise = 2
    static let maxSetsPerExercise = 5
    static let minHoursBetweenHardSessions = 48.0

    // MARK: Blocks, deloads and returning (BLK, DEL, RET)

    static let minBuildWeeksForReview = 2
    static let deloadSetFactor = 0.5
    static let deloadLoadFactor = 0.9
    static let deloadRIR = 3
    static let deloadRepFactor = 0.6
    static let deloadMaxCutPct = 20.0
    /// Days since the last completed working set that start break bands 1, 2 and 3.
    static let returnBandsDays = [15, 28, 84]
    static let returnLoadCutPct = [0.0, 10.0, 20.0]
    static let returnSetFactor = [1.0, 0.5, 0.5]
    static let returnWeeks = [0, 1, 2]
    static let firstBlockLoadCapPct = 10.0

    // MARK: Fatigue and pain (FAT, PAIN)

    static let weekShare = 0.4
    static let fatigueWeeks = 2
    static let localCutSets = 1
    static let progressMax = LevelOfPain.noticeable
    static let holdAt = LevelOfPain.moderate
    static let checkInAt = LevelOfPain.severe
    static let severeCutPct = 20.0
    static let severeSetFactor = 0.5
    static let streakToReduce = 2
    static let reducePct = 10.0
    static let postHoldExposures = 2

    // MARK: Progress (STALL, TRACK)

    static let windowExposures = 4
    static let minExposures = 3
    /// TRACK.trendWeeks for an intermediate lifter (10 weeks), in blocks.
    static let trendBlocks = 2

    /// One exposure's e1RM error, as a percent (TRACK.typicalErrorPct).
    static func typicalErrorPct(for muscle: Muscle) -> Double {
        isLowerBody(muscle) ? 5 : 4
    }

    /// How far one exposure's e1RM must fall below the two before it to count as fatigue (FAT.dropBandPct).
    static func dropBandPct(for muscle: Muscle) -> Double {
        1.5 * typicalErrorPct(for: muscle) * 1.5.squareRoot()
    }

    static func isLowerBody(_ muscle: Muscle) -> Bool {
        [.quads, .glutes, .hamstrings, .calves].contains(muscle)
    }
}
