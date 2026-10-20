//
//  PowerJackSimLifter.swift
//  PowerJackTests
//
//  A simulated lifter: a body whose maxes grow, tire, fade and get hurt, and the habits that decide the
//  weights, reps, reps-left taps and pain that end up in the log. Weights are pounds here and tenths of
//  a pound in the app.
//

import Foundation
@testable import PowerJack

final class PowerJackSimLifter {
    let profile: PowerJackSimProfile
    var rng: PowerJackSimRandom
    private let seed: UInt64

    /// True strength per exercise name: a one-rep max in pounds, or the most reps for bodyweight work.
    private var maxes: [String: Double] = [:]
    private var startMaxes: [String: Double] = [:]
    private var hardSetsThisWeek: [String: Int] = [:]
    private var lastTrained: [String: Date] = [:]
    private var injuries: [String: Injury] = [:]
    /// Builds with hard sets and clears each week; at 0.5 the lifter is 25% weaker.
    private(set) var fatigue = 0.0
    /// Today's strength against usual.
    private var form = 1.0

    private struct Injury {
        var pain: LevelOfPain
        /// Exposures left at this level before it eases by one.
        var exposuresAtLevel: Int
    }

    init(profile: PowerJackSimProfile, seed: UInt64) {
        self.profile = profile
        self.seed = seed
        rng = PowerJackSimRandom(seed: seed)
    }

    func decides(_ probability: Double) -> Bool {
        rng.chance(probability)
    }

    /// Strength right now against where the exercise started.
    func growth(of exercise: Exercise) -> Double {
        let name = key(exercise)
        guard let start = startMaxes[name], let now = maxes[name], start > 0 else { return 1 }
        return now / start
    }

    /// Strength is tracked per exercise, and apart for its bodyweight form if the lifter's own exercise changes equipment.
    private func key(_ exercise: Exercise) -> String {
        exercise.repsOnly ? exercise.exerciseName + " (reps)" : exercise.exerciseName
    }
}

//
// Body
//
extension PowerJackSimLifter {
    func trueMax(_ exercise: Exercise) -> Double {
        let name = key(exercise)
        if let known = maxes[name] { return known }
        var draw = PowerJackSimRandom(seed: seed ^ PowerJackSimRandom.seed(name))
        let start = Self.typicalMax(exercise) * draw.double(0.8...1.25)
            * (exercise.repsOnly ? max(0.4, min(profile.strength, 1.6)) : profile.strength)
        maxes[name] = start
        startMaxes[name] = start
        return start
    }

    /// Draws today's form, once per session.
    func startSession() {
        form = max(0.8, 1 + profile.dayNoise * rng.bell())
    }

    /// Reps to failure on the `setIndex`th working set of an exercise today. Below 1, not even one rep.
    func repsToFailure(_ exercise: Exercise, pounds: Double?, setIndex: Int) -> Double {
        let strength = trueMax(exercise) * form * (1 - fatigue / 2)
        let fresh: Double
        if exercise.repsOnly {
            fresh = strength
        } else {
            guard let pounds, pounds > 0 else { return 0 }
            fresh = 1 + (Self.tableReps(share: pounds / strength) - 1) * profile.endurance
        }
        return min(60, fresh - profile.setDrop * Double(setIndex))
    }

    /// Reps left on a fresh first set of `reps` at `pounds`, with today's fatigue but an average day's form.
    func slack(_ exercise: Exercise, pounds: Double?, reps: Int) -> Double? {
        let strength = trueMax(exercise) * (1 - fatigue / 2)
        if exercise.repsOnly { return strength - Double(reps) }
        guard let pounds, pounds > 0 else { return nil }
        return 1 + (Self.tableReps(share: pounds / strength) - 1) * profile.endurance - Double(reps)
    }

    /// Counts a completed set toward this week's training.
    func didSet(_ exercise: Exercise, repsLeft: Double, at date: Date) {
        lastTrained[key(exercise)] = date
        if repsLeft <= 4 {
            hardSetsThisWeek[key(exercise), default: 0] += 1
        }
    }

    /// Adapts to the week just trained: maxes grow toward their ceiling or fade with time off, and
    /// fatigue builds or clears.
    func endWeek(at date: Date) {
        let hardSets = hardSetsThisWeek.values.reduce(0, +)
        fatigue = min(0.5, fatigue * (1 - profile.recovery) + Double(hardSets) * profile.fatiguePerSet)
        // Sorted, so the same seed adapts in the same order every run.
        for name in maxes.keys.sorted() {
            guard let current = maxes[name], let start = startMaxes[name] else { continue }
            var next = current
            if profile.weeklyGain < 0 {
                next *= 1 + profile.weeklyGain
            } else if let sets = hardSetsThisWeek[name] {
                let stimulus = min(1, Double(sets) / 6)
                let room = Swift.max(0, 1 - (current / start - 1) / profile.gainCeiling)
                next *= 1 + profile.weeklyGain * stimulus * room
            }
            if let trained = lastTrained[name], date.timeIntervalSince(trained) > 14 * 86_400 {
                next *= 0.993
            }
            maxes[name] = Swift.max(next, start * 0.6)
        }
        hardSetsThisWeek = [:]
    }

    /// Reps to failure at a share of max, from R8.1's table read backwards and carried on past its ends.
    static func tableReps(share: Double) -> Double {
        let anchors: [(reps: Double, percent: Double)] = [
            (1, 100), (3.3, 95), (4.9, 90), (9.8, 80), (14.8, 70), (19.5, 60), (26.0, 50), (35.8, 40),
        ]
        let percent = share * 100
        // Past the max: under one rep, so the set fails.
        if percent >= 100 { return 1 - (percent - 100) / 5 }
        for (high, low) in zip(anchors, anchors.dropFirst()) where percent >= low.percent {
            return high.reps + (low.reps - high.reps) * (high.percent - percent) / (high.percent - low.percent)
        }
        let (high, low) = (anchors[6], anchors[7])
        return low.reps + (low.reps - high.reps) * (low.percent - percent) / (high.percent - low.percent)
    }
}

//
// Habits
//
extension PowerJackSimLifter {
    /// The weight typed for a working set, in tenths of a pound: the planned one unless habit or
    /// equipment changes it, or a guess that leaves about `aim` reps when none is planned. Nil for
    /// bodyweight exercises.
    func load(for exercise: Exercise, planned: Int?, reps: Int?, aim: Int) -> Int? {
        guard !exercise.repsOnly else { return nil }
        var pounds: Double
        if let planned, planned > 0 {
            // Past the app's limit the field starts empty, so the lifter types the most it takes.
            let entry = Double(min(planned, WorkoutSet.maxWeightPounds * 10)) / 10
            switch profile.loads {
            case .asPlanned:
                return Int((entry * 10).rounded())
            case .microplates, .equipmentSteps, .kilograms:
                pounds = entry
            case .ownChoice:
                pounds = entry * (1 + 0.06 * rng.bell())
            }
        } else {
            // Nothing planned: a weight that should leave about `aim` reps today, misjudged a little.
            let share = (PowerJackPercent.percent(reps: Double((reps ?? 10) + aim)) ?? 60) / 100
            pounds = trueMax(exercise) * (1 - fatigue / 2) * share * (1 + profile.misjudge * rng.bell())
        }
        let tenths: Int
        switch profile.loads {
        case .kilograms:
            let kilograms = max(profile.kilogramStep, (pounds * WeightUnit.kilogramsPerPound / profile.kilogramStep).rounded() * profile.kilogramStep)
            tenths = WeightUnit.tenthsPounds(fromKilograms: kilograms)
        case .microplates:
            tenths = Int(max(2.5, (pounds / 2.5).rounded() * 2.5) * 10)
        default:
            let step = Self.equipmentStep(exercise.exerciseEquipment, loads: profile.loads)
            tenths = Int(max(step, (pounds / step).rounded() * step) * 10)
        }
        return min(max(tenths, 1), WorkoutSet.maxWeightPounds * 10)
    }

    /// A lighter weight after a set that didn't allow a single rep, in tenths of a pound.
    func lighter(_ tenths: Int) -> Int {
        max(1, Int((Double(tenths) * 0.85 / 50).rounded(.down)) * 50)
    }

    /// Reps done on a set, or nil when not even one is possible.
    func reps(planned: Int?, repsToFailure: Double, isLast: Bool, aim: Int) -> Int? {
        let most = Int(repsToFailure.rounded(.down))
        guard most >= 1 else { return nil }
        var wanted: Int
        if let planned {
            switch profile.reps {
            case .asPlanned:
                wanted = planned
            case .failureOnLastSet:
                wanted = isLast ? max(planned, most) : planned
            case .shortOfPlan:
                // Gives up a rep or two early once a set gets hard.
                wanted = most - planned <= 2 && rng.chance(0.5) ? planned - rng.int(1...2) : planned
            case .beyondPlan:
                wanted = most - planned >= 3 ? planned + rng.int(1...2) : planned
            }
        } else {
            wanted = most - aim + (rng.chance(0.3) ? rng.int(-1...1) : 0)
        }
        return min(max(1, min(wanted, most)), WorkoutSet.maxReps)
    }

    /// The reps-left tap for a set that really had `repsLeft` to spare.
    func rating(repsLeft: Double) -> RepsInReserve {
        switch profile.rating {
        case .alwaysFivePlus:
            return .fiveOrMore
        case .alwaysZero:
            return .zero
        case .random:
            return RepsInReserve(rawValue: rng.int(0...5)) ?? .two
        case .honest:
            var value = Int(max(0, repsLeft).rounded(.down)) + profile.ratingBias
            if rng.chance(profile.ratingNoise) {
                value += rng.chance(0.5) ? 1 : -1
            }
            return RepsInReserve(rawValue: min(max(value, 0), 5)) ?? .two
        }
    }

    /// An old effort word for the same set, as programs from before the reps-left scale stored.
    func legacyWord(repsLeft: Double) -> LevelOfEffort {
        switch Int(max(0, repsLeft).rounded(.down)) {
        case 0: .brutal
        case 1: .veryHard
        case 2, 3: .challenge
        case 4: .easy
        default: rng.chance(0.2) ? .none : .veryEasy
        }
    }

    /// Whether an injury makes this exercise hurt badly today.
    func isHurt(_ exercise: Exercise) -> Bool {
        (injuries[exercise.exerciseName]?.pain.rawValue ?? 0) >= LevelOfPain.severe.rawValue
    }

    /// The pain felt doing an exercise: an injury's current level, an ache, or none. An injury eases a
    /// level every exposure or two, and now and then flares a level first.
    func pain(after exercise: Exercise) -> LevelOfPain {
        let name = exercise.exerciseName
        if var injury = injuries[name] {
            let felt = injury.pain
            injury.exposuresAtLevel -= 1
            if injury.exposuresAtLevel <= 0 {
                let flare = rng.chance(0.15) && felt.rawValue < LevelOfPain.extreme.rawValue
                let next = felt.rawValue + (flare ? 1 : -1)
                injury.pain = LevelOfPain(rawValue: next) ?? .none
                injury.exposuresAtLevel = rng.int(1...2)
            }
            injuries[name] = injury.pain == .none ? nil : injury
            return felt
        }
        if rng.chance(profile.injuryChance) {
            let start = rng.pick(weighted: [(LevelOfPain.noticeable, 2), (.moderate, 4), (.severe, 2), (.extreme, 1)])
            injuries[name] = Injury(pain: start, exposuresAtLevel: rng.int(1...3))
            return start
        }
        return rng.chance(profile.achyChance) ? rng.pick([.mild, .mild, .noticeable]) : .none
    }
}

//
// Equipment
//
extension PowerJackSimLifter {
    /// A typical trained lifter's one-rep max in pounds, or their most reps for bodyweight work.
    static func typicalMax(_ exercise: Exercise) -> Double {
        let heavy = exercise.fatigueLevel == .high
        let light = exercise.fatigueLevel == .low
        if exercise.repsOnly {
            return heavy ? 12 : light ? 30 : 18
        }
        if let catalogID = exercise.catalogID, let pounds = mainLiftMaxes[catalogID] {
            return pounds
        }
        // A default rather than every case, so new equipment never breaks the simulation.
        return switch exercise.exerciseEquipment {
        case .legPress: 500
        case .barbell: heavy ? 250 : 100
        case .machine: heavy ? 250 : 150
        case .dumbbell: heavy ? 70 : light ? 30 : 60
        case .cable: light ? 70 : 150
        default: 60
        }
    }

    /// Typical maxes of the lifts PowerJack reads as main lifts, so presses sit below squats and pulls.
    private static let mainLiftMaxes: [String: Double] = [
        "barbell-back-squat": 315, "barbell-front-squat": 255, "barbell-deadlift": 405,
        "barbell-romanian-deadlift": 275, "barbell-hip-thrust": 365, "barbell-bench-press": 245,
        "incline-barbell-bench-press": 205, "barbell-overhead-press": 145, "barbell-row": 205,
        "dumbbell-bench-press": 95, "incline-dumbbell-bench-press": 80, "dumbbell-shoulder-press": 60,
        "dumbbell-goblet-squat": 110, "goblet-squat": 110, "leg-press": 600, "smith-machine-squat": 285,
    ]

    /// The smallest change the equipment allows, in pounds: 10 lb on stacks and sleds when the lifter
    /// follows the equipment, 5 lb elsewhere.
    static func equipmentStep(_ equipment: Equipment, loads: PowerJackSimProfile.Loads) -> Double {
        guard loads == .equipmentSteps else { return 5 }
        return switch equipment {
        case .barbell, .dumbbell, .kettlebell: 5
        default: 10
        }
    }
}
