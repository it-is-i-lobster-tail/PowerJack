//
//  BuildSimLifter.swift
//  PowerJackTests
//
//  A simulated lifter: a body whose maxes grow, tire, fade and get hurt, and the habits that decide
//  the weights, reps, ratings and pain that end up in the log.
//

import Foundation
@testable import PowerJack

final class BuildSimLifter {
    let profile: BuildSimProfile
    var rng: BuildSimRandom
    private let seed: UInt64

    /// True strength per exercise name: a one-rep max in tenths of a pound, or the most reps for bodyweight.
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

    init(profile: BuildSimProfile, seed: UInt64) {
        self.profile = profile
        self.seed = seed
        rng = BuildSimRandom(seed: seed)
    }

    func decides(_ probability: Double) -> Bool {
        rng.chance(probability)
    }

    /// Strength right now against where the exercise started, for the run's summary.
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
extension BuildSimLifter {
    func trueMax(_ exercise: Exercise) -> Double {
        let name = key(exercise)
        if let known = maxes[name] { return known }
        var draw = BuildSimRandom(seed: seed ^ BuildSimRandom.seed(name))
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

    /// Reps to failure on the `setIndex`th working set of an exercise today. Can fall below 1.
    func repsToFailure(_ exercise: Exercise, load: Int?, setIndex: Int) -> Double {
        let max = trueMax(exercise) * form * (1 - fatigue / 2)
        let fresh: Double
        if exercise.repsOnly {
            fresh = max
        } else {
            guard let load, load > 0 else { return 0 }
            // Epley turned around: reps = 30 × (max ÷ load − 1), stretched by the lifter's endurance.
            fresh = 30 * (max / Double(load) - 1) * profile.endurance
        }
        return min(60, fresh - profile.setDrop * Double(setIndex))
    }

    /// Reps left on a first set at `load` for `reps`, with today's fatigue but an average day's form.
    func slack(_ exercise: Exercise, load: Int?, reps: Int) -> Double? {
        let max = trueMax(exercise) * (1 - fatigue / 2)
        if exercise.repsOnly { return max - Double(reps) }
        guard let load, load > 0 else { return nil }
        return 30 * (max / Double(load) - 1) * profile.endurance - Double(reps)
    }

    /// Counts a completed set toward this week's training.
    func didSet(_ exercise: Exercise, repsLeft: Double, at date: Date) {
        lastTrained[key(exercise)] = date
        if repsLeft <= 4 {
            hardSetsThisWeek[key(exercise), default: 0] += 1
        }
    }

    /// Adapts to the week just trained: maxes grow toward their ceiling or fade with time off, and fatigue builds or clears.
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
}

//
// Habits
//
extension BuildSimLifter {
    /// The weight typed for a working set: the planned one unless habit or equipment changes it.
    /// Nil for bodyweight exercises.
    func load(for exercise: Exercise, planned: Int?, reps: Int?, aim: Int) -> Int? {
        guard !exercise.repsOnly else { return nil }
        var load: Double
        if let planned, planned > 0 {
            // Past the app's limit the field starts empty, so the lifter types the most it takes.
            let entry = min(planned, WorkoutSet.maxWeightPounds * 10)
            switch profile.loads {
            case .asPlanned:
                return entry
            case .equipmentSteps, .kilograms:
                load = Double(entry)
            case .ownChoice:
                load = Double(entry) * (1 + 0.06 * rng.bell())
            }
        } else {
            // No weight planned: guess one that leaves about `aim` reps, misjudged a little.
            let target = Double((reps ?? 10) + aim)
            load = trueMax(exercise) * (1 + 0.12 * rng.bell()) / (1 + target / 30)
        }
        if profile.loads == .kilograms {
            let plates = max(1.25, (WeightUnit.kilograms(fromTenthsPounds: Int(load.rounded())) / 1.25).rounded() * 1.25)
            return clamped(WeightUnit.tenthsPounds(fromKilograms: plates))
        }
        let step = Self.equipmentStep(exercise.exerciseEquipment)
        return clamped(Int((load / Double(step)).rounded()) * step, atLeast: step)
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
                wanted = rng.chance(0.3) ? planned - 1 : planned
            case .beyondPlan:
                wanted = most - planned >= 3 ? planned + rng.int(1...2) : planned
            }
        } else {
            wanted = most - aim + (rng.chance(0.3) ? rng.int(-1...1) : 0)
        }
        return min(max(1, min(wanted, most)), WorkoutSet.maxReps)
    }

    /// The reps-left tap for a last set that really had `repsLeft` to spare.
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
extension BuildSimLifter {
    /// A typical trained lifter's one-rep max in tenths of a pound, or their most reps for bodyweight.
    static func typicalMax(_ exercise: Exercise) -> Double {
        if exercise.repsOnly {
            return switch exercise.fatigueLevel {
            case .low: 30
            case .moderate: 18
            case .high: 12
            }
        }
        let pounds: Double = switch (exercise.exerciseEquipment, exercise.fatigueLevel) {
        case (.legPress, _): 500
        case (.barbell, .high): 250
        case (.barbell, _): 100
        case (.machine, .high): 250
        case (.machine, _): 150
        case (.dumbbell, .high): 70
        case (.dumbbell, .moderate): 60
        case (.dumbbell, .low): 30
        case (.cable, .low): 70
        case (.cable, _): 150
        case (.kettlebell, _): 60
        case (.bodyweight, _): 100
        }
        return pounds * 10
    }

    /// The smallest change the equipment allows, in tenths of a pound.
    static func equipmentStep(_ equipment: Equipment) -> Int {
        switch equipment {
        case .machine, .legPress, .kettlebell: 100
        case .barbell, .dumbbell, .cable, .bodyweight: 50
        }
    }

    /// Within what the weight field takes.
    private func clamped(_ tenths: Int, atLeast floor: Int = 1) -> Int {
        min(max(tenths, floor), WorkoutSet.maxWeightPounds * 10)
    }
}
