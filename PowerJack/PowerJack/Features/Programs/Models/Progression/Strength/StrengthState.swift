//
//  StrengthState.swift
//  PowerJack
//
//  What the strength engine remembers between weeks: one record per lift plus the block clock.
//  It is saved after every strength week (`StrengthLog`), so it carries over to the next program.
//

import Foundation

struct StrengthState: Codable, Equatable {
    var clock = StrengthClock()
    var lifts: [String: StrengthLiftRecord] = [:]

    subscript(key: String) -> StrengthLiftRecord {
        get { lifts[key] ?? StrengthLiftRecord() }
        set { lifts[key] = newValue }
    }
}

enum StrengthExperience: String, Codable {
    case intermediate
    case advanced
}

/// Blocks alternate A (the usual reps) and B (one rep fewer on primary slots) (rule 9.2).
enum StrengthBlockType: String, Codable {
    case a
    case b
}

struct StrengthClock: Codable, Equatable {
    /// Weeks with a strength session. Each adds 1/52 of a training year (rule 17.7).
    var trainedWeeks = 0
    var blockWeek = 1
    /// The block's planned training weeks, laid out to fit the program by the planner (9.1). Nil runs 4.
    var blockTrainWeeks: Int?
    var blockType = StrengthBlockType.a
    var weeksSinceDeload = 0
    /// The last few weeks, newest last, for the planned deload's skip rule (10.5).
    var recentWeeks: [WeekMark] = []
    /// Normal weeks in a row where half the rated lifts hit an unplanned RIR 0 (10.4b).
    var rir0Weeks = 0
    /// The week to plan next: a normal week or a deload, and whether it starts a new block.
    var upcoming = WeekKind.build
    var startsBlock = false
    /// After a planned deload the block type flips; after a reactive one the next block is A (9.2).
    var lastDeloadPlanned = true

    struct WeekMark: Codable, Equatable {
        var deload = false
        var returned = false
        var missed = false
    }

    var trainWeeks: Int { blockTrainWeeks ?? StrengthRules.blockTrainWeeks }

    /// Nobody is asked: everyone starts at 1 training year, so as an intermediate (rule 17.7).
    var experience: StrengthExperience {
        let years = StrengthRules.startingTrainingYears + Double(trainedWeeks) / 52
        return years >= StrengthRules.advancedMinYears ? .advanced : .intermediate
    }
}

struct StrengthLiftRecord: Codable, Equatable {
    // 4 Estimation
    var e1rmKg: Double?
    /// When rated sessions gave an e1RM or a lower bound. The recent ones make up `e1rmConf` (4.5).
    var ratedDates: [Date] = []
    var fastUpdatesLeft = 0
    /// A weekly e1RM held back as an outlier until next week confirms it (4.3).
    var suspectKg: Double?

    // 2 Calibration
    var calibrationWeeksLeft = StrengthRules.calibrationWeeks

    // 12 Breaks
    var lastTrained: Date?

    // 10 Fatigue
    /// The last counted sessions, oldest first, and whether each fell 2+ reps short (10.2a).
    var marks: [SessionMark] = []
    var flagged = false
    /// Frozen e1RM a drop is measured against, and how many weeks in a row sat 5% under it (10.2b).
    var dropReferenceKg: Double?
    var dropWeeks = 0

    // 11 Plateaus
    var stallPoints: [StallPoint] = []
    /// The last ordered step taken: 1 for the rep zone, 2 for a set; a reset starts over at 0 (11.5).
    var plateauStage = 0
    /// A step found at a block's end, applied when the next block starts.
    var pendingStep: StallStep?
    /// The step the week being planned applies.
    var stepThisWeek: StallStep?
    /// Stall step 1: the heavy slot runs 2 fewer reps for this block.
    var repShiftActive = false
    /// Normal weeks left whose rises are capped at the nudge after a reset (11.5).
    var rebuildWeeksLeft = 0

    // 15 Pain
    var pain = StrengthPainState()

    func confidence(at date: Date) -> Int {
        let start = date.addingTimeInterval(-Double(StrengthRules.confidenceWindowDays) * 86_400)
        return ratedDates.count { $0 > start }
    }

    var isCalibrating: Bool { calibrationWeeksLeft > 0 }
}

struct SessionMark: Codable, Equatable {
    var date: Date
    var bad: Bool
}

/// One normal week of a lift, for the plateau test (11.3).
struct StallPoint: Codable, Equatable {
    var e1rmKg: Double
    /// The heavy slot's intended load ÷ pct(R + I).
    var planE1rmKg: Double?
    var plannedSets: Int
    var completedSets: Int
    var flagged: Bool
}

/// One change for a stalled lift, cheapest first (11.4, 11.5).
enum StallStep: String, Codable {
    /// The heavy slot runs 2 fewer reps for one block.
    case repZone
    /// One more set per slot.
    case sets
    /// Loads drop 10%, then rise at most by the nudge for 4 weeks.
    case reset
    /// A stall that came with fatigue takes a set away instead (11.4).
    case fewerSets
}

/// Pain is tracked per lift and moves with every session of it, in either slot (rule 15.1).
/// Caps are shares of the slot's intended load, which pain never moves (light sessions repeat the plan).
struct StrengthPainState: Codable, Equatable {
    /// The last few ratings, oldest first.
    var ratings: [Int] = []
    /// What the lift's next session must do.
    var pending: PainAction?
    /// While ramping back: the load cap as a share of the pre-pain load (15.7).
    var capShare: Double?
    /// Sets still left off the plan while ramping back.
    var setsDropped = 0
    /// After Lighter, sets stay at RIR 3 or more until the pre-pain load is back.
    var rirFloor = false

    var isRamping: Bool { capShare != nil || setsDropped > 0 }

    /// Two ratings of Noticeable or worse in a row, or three that rose each time (15.6).
    var holds: Bool {
        let watch = StrengthRules.painWatch.rawValue
        let last2 = ratings.suffix(2)
        if last2.count == 2, last2.allSatisfy({ $0 >= watch }) { return true }
        let last3 = Array(ratings.suffix(3))
        return last3.count == 3 && last3[0] < last3[1] && last3[1] < last3[2]
    }
}

enum PainAction: String, Codable {
    /// Severe or worse: the next session opens with a check-in, Lighter or Skip (15.4).
    case lighter
    /// Moderate: the next session drops a set and 10% of its load (15.5).
    case cut
}
