//
//  PowerJackRules.swift
//  PowerJack
//
//  The PowerJacking rulebook's parameters (revision 2). Names follow the rulebook's
//  `DOMAIN.name`, so each value can be found in its Implementation tab.
//

import Foundation

/// The goal slider (R1.3). It tilts reps, ranges, effort and volume toward strength or size.
enum PowerJackGoal: CaseIterable {
    case stronger
    case balanced
    case bigger
}

enum PowerJackRules {
    // R1 Template
    static let mainLiftsMax = 4
    static let topSets = 1

    // R2 Load and reps
    static func heavyReps(_ goal: PowerJackGoal) -> Int { pick(goal, 4, 5, 6) }
    static func volumeReps(_ goal: PowerJackGoal) -> Int { pick(goal, 6, 8, 10) }
    static func secondaryRange(_ goal: PowerJackGoal) -> ClosedRange<Int> { pick(goal, 5...8, 6...10, 8...12) }
    static func accessoryRange(_ fatigue: FatigueLevel) -> ClosedRange<Int> {
        switch fatigue {
        case .high: 8...12
        case .moderate: 10...15
        case .low: 12...20
        }
    }
    static let mainHeavyMinReps = 3
    static let easyStepPct = 2.5
    static let missCutPerRepPct = 2.5
    static let missCutMaxPct = 10.0
    static let bandModePct = 5.0
    static let saJumpPct = 2.5
    static let repCostPct = 2.5
    static let repsPerStep = 1
    static let repsPerStepEasy = 2
    static let repRangeExtensionMax = 10
    static let bodyweightRepCap = 30
    static let backoffPct = 5.0
    static let missStreakForBackoff = 2
    /// The smallest jump in lb mode. Loads are in pounds until the app has kg mode.
    static let stepPounds = 5.0
    static let maxJumpPct = 10.0
    static let lookbackDays = 14

    // R3 Volume
    static let secondaryCredit = 0.5
    static let hardSetMaxRIR = 4
    static let minRepsForCredit = 5
    static let lowRepFactor = 0.5
    static func muscleStart(_ goal: PowerJackGoal) -> Int { pick(goal, 8, 10, 12) }
    static func muscleCap(_ goal: PowerJackGoal) -> Int { pick(goal, 14, 16, 20) }
    static func focusCap(_ goal: PowerJackGoal) -> Int { pick(goal, 18, 20, 24) }
    static let focusStartBonus = 2
    static let maintenanceSets = 4
    static func liftSets(_ goal: PowerJackGoal) -> Int { pick(goal, 9, 6, 6) }
    static let hingeFactor = 0.5
    static let liftSetsFloor = 3
    static let liftSetsCap = 10
    static let minSetsPerExposure = 2
    static let maxSetsPerSlot = 5
    static let secondaryStartSets = 3
    static let accessoryStartSets = 2
    static let maxCreditsPerSessionPerMuscle = 10.0
    static let creditTolerance = 1.0
    static let addEligibleWeeks = 2
    static let focusAddEligibleWeeks = 1
    static let addMaxPain = LevelOfPain.mild
    static let blockAddPct = 20.0
    static let maxAddsPerWeek = 4
    static let newSetRepsOffset = -1
    static let blockStepSets = 1

    // R4 Effort
    /// Target RIR by block column 1-4.
    static func rirByColumn(_ role: PowerJackRole, _ goal: PowerJackGoal) -> [Int] {
        switch role {
        case .main: [3, 2, 2, 1]
        case .secondary: pick(goal, [3, 3, 2, 2], [3, 2, 2, 1], [3, 2, 1, 1])
        case .accessory: pick(goal, [3, 2, 2, 1], [3, 2, 2, 1], [3, 2, 1, 1])
        }
    }
    static let calibrationRIR = 3
    static let highRepThreshold = 12
    static let highRepOffset = -1
    static let veryHighRepThreshold = 20
    static let maxRepOutsPerSession = 2
    static let tolerance = 1
    static let highRepTolerance = 2
    static let missBigReps = 2
    static let rirCensor = 5

    // R5 Blocks
    static let buildWeeks = 4
    static let minBuildWeeks = 3
    static let maxBuildWeeks = 6

    // R6 Deloads and fatigue
    static let partialShare = 0.5
    static let deloadSetFactor = 0.5
    static let deloadLoadFactor = 0.9
    static let deloadRIR = 3
    static let deloadRepFactor = 0.6
    static let deloadMaxCutPct = 20.0
    static let secondDeloadShare = 0.33
    static let strainWeekShare = 0.4
    static let strainWeeks = 2
    static let strainLoadTolerance = 0.95
    static let gapBandsDays = [14, 28, 84]
    static let gapLoadCutPct = [0.0, 10.0, 20.0]

    // R8 Tracking
    static let anchorWindow = 3
    static let anchorMaxAgeDays = 42
    static let anchorMaxRisePct = 7.5
    static let historyMaxAgeWeeks = 12

    // R9 Rest, in seconds
    static let heavyRest = 240
    static let volumeRest = 180
    static let secondaryRest = 150
    static func accessoryRest(_ fatigue: FatigueLevel) -> Int {
        switch fatigue {
        case .low: 90
        case .moderate: 120
        case .high: 150
        }
    }
    static let minRest = 60
    static let missRestExtra = 60

    // R10 Pain
    static let painRIRFloor = 2
    static let painCutPct = 10.0
    static let painMaxTotalCutPct = 30.0
    static let painReturnStepPct = 5.0
    static let painClearAfterExposures = 2
    static let painContinueSetFactor = 0.5
    /// Barbell warm-ups never go under the empty bar (R10.8).
    static let barPounds = 45.0

    private static func pick<T>(_ goal: PowerJackGoal, _ stronger: T, _ balanced: T, _ bigger: T) -> T {
        switch goal {
        case .stronger: stronger
        case .balanced: balanced
        case .bigger: bigger
        }
    }
}
