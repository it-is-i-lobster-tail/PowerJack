//
//  StrengthSimLifter.swift
//  PowerJackTests
//
//  A simulated lifter: a body whose one-rep maxes grow, tire, fade and get hurt, and the habits that decide
//  the weights, reps, ratings and pain that end up in the log. Reps at a load follow the engine's own
//  %1RM curve (4.7), stretched by the lifter's endurance, so an honest rating is what the rules expect.
//

import Foundation
@testable import PowerJack

final class StrengthSimLifter {
    let profile: StrengthSimProfile
    var rng: StrengthSimRandom
    private let seed: UInt64

    /// True strength per exercise name: a one-rep max in kg, or the most reps for bodyweight.
    private var maxes: [String: Double] = [:]
    private var startMaxes: [String: Double] = [:]
    /// Sets this week at 75% of max or more, ended 4 reps or fewer from failure: what drives strength.
    private var heavySetsThisWeek: [String: Int] = [:]
    private var hardSetsThisWeek = 0
    private var lastTrained: [String: Date] = [:]
    private var injuries: [String: Injury] = [:]
    /// Builds with hard sets and clears each week; at 0.4 the lifter is 20% weaker.
    private(set) var fatigue = 0.0
    /// Today's strength against usual.
    private var form = 1.0

    private struct Injury {
        var pain: LevelOfPain
        /// Exposures left at this level before it eases by one.
        var exposuresAtLevel: Int
    }

    init(profile: StrengthSimProfile, seed: UInt64) {
        self.profile = profile
        self.seed = seed
        rng = StrengthSimRandom(seed: seed)
    }

    func decides(_ probability: Double) -> Bool {
        rng.chance(probability)
    }

    /// Strength is tracked per exercise, and apart for its bodyweight form if the lifter's own exercise changes equipment.
    private func key(_ exercise: Exercise) -> String {
        exercise.repsOnly ? exercise.exerciseName + " (reps)" : exercise.exerciseName
    }
}

//
// Body
//
extension StrengthSimLifter {
    func trueMax(_ exercise: Exercise) -> Double {
        let name = key(exercise)
        if let known = maxes[name] { return known }
        var draw = StrengthSimRandom(seed: seed ^ StrengthSimRandom.seed(name))
        let start = Self.typicalMax(exercise) * draw.double(0.8...1.25)
            * (exercise.repsOnly ? max(0.4, min(profile.strength, 1.6)) : profile.strength)
        maxes[name] = start
        startMaxes[name] = start
        return start
    }

    /// Strength now against where the exercise started.
    func growth(of exercise: Exercise) -> Double {
        let name = key(exercise)
        guard let start = startMaxes[name], let now = maxes[name], start > 0 else { return 1 }
        return now / start
    }

    /// Draws today's form, once per session.
    func startSession() {
        form = max(0.85, 1 + profile.dayNoise * rng.bell())
    }

    /// Reps to failure on the `setIndex`th working set of an exercise today, at `loadKg`. Can fall below 1.
    func repsToFailure(_ exercise: Exercise, loadKg: Double?, setIndex: Int) -> Double {
        let today = trueMax(exercise) * form * (1 - fatigue / 2)
        let fresh: Double
        if exercise.repsOnly {
            fresh = today
        } else {
            guard let loadKg, loadKg > 0 else { return 0 }
            fresh = Self.repsToFailure(share: loadKg / today, curve: StrengthLifts.curve(for: exercise)) * profile.endurance
        }
        return min(60, fresh - profile.setDrop * Double(setIndex))
    }

    /// Reps left on a fresh first set at `loadKg` for `reps`, with today's fatigue but an average day's form.
    func slack(_ exercise: Exercise, loadKg: Double?, reps: Int) -> Double? {
        let today = trueMax(exercise) * (1 - fatigue / 2)
        if exercise.repsOnly { return today - Double(reps) }
        guard let loadKg, loadKg > 0 else { return nil }
        return Self.repsToFailure(share: loadKg / today, curve: StrengthLifts.curve(for: exercise)) * profile.endurance - Double(reps)
    }

    /// The curve turned around: reps to failure at a share of the one-rep max, between the table's points,
    /// Epley's slope past 15 reps and a rep lost per 2.5% over the max.
    static func repsToFailure(share: Double, curve: StrengthCurve) -> Double {
        if share >= 1 { return max(0, 1 - (share - 1) / 0.025) }
        let last = curve.share(repsToFailure: 15)
        if share <= last { return 15 + 30 * (last / share - 1) }
        for n in 1..<15 {
            let upper = curve.share(repsToFailure: n)
            let lower = curve.share(repsToFailure: n + 1)
            if share >= lower {
                return Double(n) + (upper - share) / (upper - lower)
            }
        }
        return 15
    }

    /// Counts a completed set toward this week's training.
    func didSet(_ exercise: Exercise, loadKg: Double?, repsLeft: Double, at date: Date) {
        let name = key(exercise)
        lastTrained[name] = date
        guard repsLeft <= 4 else { return }
        hardSetsThisWeek += 1
        if exercise.repsOnly || (loadKg ?? 0) >= 0.75 * trueMax(exercise) {
            heavySetsThisWeek[name, default: 0] += 1
        }
    }

    /// Adapts to the week just trained: maxes grow toward their ceiling with enough heavy sets, or fade with
    /// time off, and fatigue builds or clears.
    func endWeek(at date: Date) {
        fatigue = min(0.4, fatigue * (1 - profile.recovery) + Double(hardSetsThisWeek) * profile.fatiguePerSet)
        // Sorted, so the same seed adapts in the same order every run.
        for name in maxes.keys.sorted() {
            guard let current = maxes[name], let start = startMaxes[name] else { continue }
            var next = current
            if profile.weeklyGain < 0 {
                next *= 1 + profile.weeklyGain
            } else if let sets = heavySetsThisWeek[name] {
                let stimulus = min(1, Double(sets) / 5)
                let room = Swift.max(0, 1 - (current / start - 1) / profile.gainCeiling)
                next *= 1 + profile.weeklyGain * stimulus * room
            }
            if let trained = lastTrained[name], date.timeIntervalSince(trained) > 14 * 86_400 {
                next *= 1 - profile.detraining
            }
            maxes[name] = Swift.max(next, start * 0.6)
        }
        heavySetsThisWeek = [:]
        hardSetsThisWeek = 0
    }
}

//
// Habits
//
extension StrengthSimLifter {
    /// The weight typed for a working set, in tenths of a pound: the prefilled one unless habit changes it,
    /// or one picked by feel to leave about `aim` reps. Nil for bodyweight exercises.
    func load(for exercise: Exercise, prefilled: Int?, reps: Int?, aim: Int, grid: LoadGrid?) -> Int? {
        guard !exercise.repsOnly else { return nil }
        if let prefilled, prefilled > 0 {
            switch profile.loads {
            case .asPlanned:
                return clamped(prefilled)
            case .ownChoice:
                guard let grid, rng.chance(0.15) else { return clamped(prefilled) }
                let moved = grid.moved(WeightUnit.kilograms(fromTenthsPounds: prefilled), bySteps: rng.chance(0.5) ? 1 : -1)
                return clamped(WeightUnit.tenthsPounds(fromKilograms: moved))
            case .ownPlates:
                guard let grid, rng.chance(0.3) else { return clamped(prefilled) }
                // A change plate they own, half a kilo or a pound, that the app's steps don't offer.
                let nudge = Double(rng.pick([-2, -1, 1, 2])) * (grid.unit == .kilograms ? 0.5 : WeightUnit.kilogramsPerPound)
                return clamped(WeightUnit.tenthsPounds(fromKilograms: WeightUnit.kilograms(fromTenthsPounds: prefilled) + nudge))
            }
        }
        // Nothing prefilled: a weight they could lift reps + aim times, misjudged a little, on the plates they have.
        let target = (reps ?? 8) + aim
        let guess = trueMax(exercise) * (1 - fatigue / 2) * StrengthLifts.curve(for: exercise).share(repsToFailure: target)
            * (1 + profile.feelBias + profile.feelError * rng.bell())
        let loaded = grid.map { $0.nearest(guess) } ?? guess
        return clamped(WeightUnit.tenthsPounds(fromKilograms: loaded))
    }

    /// A warm-up's weight: as planned, or about half the first working weight.
    func warmupLoad(prefilled: Int?, working: Int?, grid: LoadGrid?) -> Int? {
        if let prefilled, prefilled > 0 { return clamped(prefilled) }
        guard let working else { return nil }
        let half = WeightUnit.kilograms(fromTenthsPounds: working) / 2
        return clamped(WeightUnit.tenthsPounds(fromKilograms: grid.map { $0.nearest(half) } ?? half))
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
extension StrengthSimLifter {
    /// A typical trained lifter's one-rep max in kg, or their most reps for bodyweight. Dumbbells are per hand.
    static func typicalMax(_ exercise: Exercise) -> Double {
        let heavy = exercise.fatigueLevel == .high
        let light = exercise.fatigueLevel == .low
        if exercise.repsOnly {
            return heavy ? 12 : light ? 30 : 18
        }
        switch exercise.catalogID {
        case "barbell-back-squat": return 140
        case "barbell-bench-press": return 100
        case "barbell-deadlift": return 170
        case "barbell-front-squat": return 115
        case "incline-barbell-bench-press": return 82
        case "barbell-romanian-deadlift": return 125
        case "barbell-overhead-press": return 62
        case "barbell-row": return 92
        case "barbell-hip-thrust": return 160
        default: break
        }
        // A default rather than every case, so new equipment never breaks the simulation.
        return switch exercise.exerciseEquipment {
        case .legPress: 250
        case .barbell: heavy ? 100 : 45
        case .machine: heavy ? 120 : light ? 50 : 80
        case .dumbbell: heavy ? 40 : light ? 15 : 30
        case .cable: light ? 30 : 70
        case .kettlebell: 32
        default: 40
        }
    }

    /// Within what the weight field takes.
    private func clamped(_ tenths: Int) -> Int {
        min(max(tenths, 1), WorkoutSet.maxWeightPounds * 10)
    }
}
