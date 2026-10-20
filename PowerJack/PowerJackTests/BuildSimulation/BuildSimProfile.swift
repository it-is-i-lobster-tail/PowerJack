//
//  BuildSimProfile.swift
//  PowerJackTests
//
//  Who a simulated lifter is: how their body responds to training, and how they log, rate, skip and pick
//  programs. Random profiles spread over every kind of user; archetypes each pin down one kind.
//

import Foundation
@testable import PowerJack

struct BuildSimProfile {
    enum Rating: String {
        /// The reps they think were left, give or take their bias and noise.
        case honest
        case alwaysFivePlus
        case alwaysZero
        case random
    }

    enum Reps: String {
        case asPlanned
        /// Every rep they have on the last set.
        case failureOnLastSet
        /// Sometimes a rep short on purpose.
        case shortOfPlan
        /// A rep or two extra when the set is easy.
        case beyondPlan
    }

    enum Loads: String {
        case asPlanned
        /// Rounded to what the equipment offers: 10 lb on machine stacks, 5 lb elsewhere.
        case equipmentSteps
        /// Their own pick, near the plan.
        case ownChoice
        /// Typed in kilograms, rounded to 1.25 kg plates.
        case kilograms
    }

    var name: String

    // MARK: Body

    /// Starting maxes against a typical trained lifter.
    var strength = 1.0
    /// Share of max gained in a hard week while far from the ceiling. Below 0, the lifter gets weaker anyway.
    var weeklyGain = 0.004
    /// The most a max grows, as a share of where it started.
    var gainCeiling = 0.4
    /// Share of fatigue that clears each week.
    var recovery = 0.6
    /// Fatigue each hard set adds in a week.
    var fatiguePerSet = 0.0015
    /// Day-to-day spread of strength, as a share of max.
    var dayNoise = 0.025
    /// Reps lost on each later set of an exercise.
    var setDrop = 0.6
    /// Reps at a given share of max, against a typical lifter.
    var endurance = 1.0

    // MARK: Logging

    var rating = Rating.honest
    /// Added to the reps that were really left before tapping.
    var ratingBias = 0
    /// Chance a rating lands one away from what was meant.
    var ratingNoise = 0.1
    var reps = Reps.asPlanned
    var loads = Loads.asPlanned
    /// Chance an exercise is rated with an old effort word, as in programs from before the reps-left scale.
    var legacyRating = 0.0

    // MARK: Habits, each a chance per occasion

    var missDay = 0.03
    var skipWorkout = 0.02
    var doubleSession = 0.0
    var skipExercise = 0.0
    var stopEarly = 0.0
    /// Finishes the workout without rating an exercise.
    var noRating = 0.0
    var addSet = 0.0
    var removeSet = 0.0
    var swapExercise = 0.0
    /// Edits an exercise's rep range or fatigue level in a given week.
    var editExercise = 0.0
    /// A break starting in a given week, and how long breaks run.
    var breakChance = 0.0
    var breakDays = [10, 14, 15, 21, 28, 42, 90]
    /// An injury starting on an exposure.
    var injuryChance = 0.0
    /// Pain tapped as Mild or Noticeable with no injury.
    var achyChance = 0.03
    var checkIn: [(ManualCheckInDecision, Double)] = [(.continue, 3), (.reset, 1), (.skip, 1)]

    // MARK: Programs

    var programWeeks = 12...12
    var sameTemplate = 1.0
    var customTemplate = 0.0
    /// Starts another program partway through, in a given week.
    var abandonProgram = 0.0
    var daysBetweenPrograms = [0, 2, 7]

    /// Lifters who rate honestly, show up and stay healthy. Their plans should track what they can lift.
    var isWellBehaved: Bool {
        rating == .honest && abs(ratingBias) <= 1 && ratingNoise <= 0.2 && legacyRating == 0
            && reps == .asPlanned && loads != .ownChoice
            && skipWorkout <= 0.05 && skipExercise <= 0.02 && stopEarly <= 0.02 && noRating <= 0.02
            && swapExercise == 0 && editExercise == 0 && breakChance == 0 && injuryChance == 0
            && customTemplate == 0 && abandonProgram == 0
    }
}

//
// Random lifters
//
extension BuildSimProfile {
    /// Every trait drawn from `seed`. Most draws are ordinary; a few sit at the extremes.
    static func random(seed: UInt64) -> BuildSimProfile {
        var rng = BuildSimRandom(seed: seed ^ 0x5EED_0F_B0D1)
        var profile = BuildSimProfile(name: "random")

        let strengthBand = rng.pick(weighted: [(0.1...0.4, 1), (0.4...1.6, 8), (1.6...3.5, 1)])
        profile.strength = rng.double(strengthBand)
        profile.weeklyGain = rng.pick(weighted: [(-0.002, 1), (0, 1), (0.0015, 2), (0.004, 3), (0.008, 2), (0.015, 1)])
        profile.gainCeiling = rng.double(0.1...0.8)
        profile.recovery = rng.double(0.25...0.8)
        profile.fatiguePerSet = rng.double(0.0005...0.006)
        profile.dayNoise = rng.double(0.01...0.06)
        profile.setDrop = rng.double(0.2...1.5)
        profile.endurance = rng.double(0.75...1.3)

        profile.rating = rng.pick(weighted: [(.honest, 16), (.alwaysFivePlus, 1), (.alwaysZero, 1), (.random, 1)])
        profile.ratingBias = rng.pick(weighted: [(-1, 2), (0, 5), (1, 3), (2, 1)])
        profile.ratingNoise = rng.double(0...0.4)
        profile.reps = rng.pick(weighted: [(.asPlanned, 5), (.failureOnLastSet, 2), (.shortOfPlan, 1), (.beyondPlan, 2)])
        profile.loads = rng.pick(weighted: [(.asPlanned, 5), (.equipmentSteps, 3), (.ownChoice, 1), (.kilograms, 2)])
        profile.legacyRating = rng.chance(0.1) ? rng.double(0.05...0.4) : 0

        profile.missDay = rng.double(0...0.2)
        profile.skipWorkout = rng.chance(0.1) ? rng.double(0.2...0.4) : rng.double(0...0.1)
        profile.doubleSession = rng.chance(0.2) ? rng.double(0...0.15) : 0
        profile.skipExercise = rng.double(0...0.08)
        profile.stopEarly = rng.double(0...0.08)
        profile.noRating = rng.chance(0.1) ? rng.double(0.1...0.4) : rng.double(0...0.05)
        profile.addSet = rng.double(0...0.05)
        profile.removeSet = rng.double(0...0.05)
        profile.swapExercise = rng.chance(0.3) ? rng.double(0...0.02) : 0
        profile.editExercise = rng.chance(0.3) ? rng.double(0...0.1) : 0
        profile.breakChance = rng.double(0...0.04)
        profile.breakDays = [7, 10, 13, 14, 15, 16, 20, 21, 27, 28, 29, 35, 42, 56, 83, 84, 85, 100, 150, 200]
        profile.injuryChance = rng.chance(0.15) ? rng.double(0.01...0.04) : rng.double(0...0.008)
        profile.achyChance = rng.double(0...0.15)
        profile.checkIn = [(.continue, rng.double(0...3)), (.reset, rng.double(0...2)), (.skip, rng.double(0...2)), (.continue, 0.1)]

        let shortest = rng.int(1...10)
        profile.programWeeks = shortest...rng.int(shortest...12)
        profile.sameTemplate = rng.double(0...1)
        profile.customTemplate = rng.double(0...0.3)
        profile.abandonProgram = rng.double(0...0.03)
        profile.daysBetweenPrograms = [0, 1, 3, 7, 14, 21, 30, 60, 120, 200]
        return profile
    }
}

//
// Archetypes
//
extension BuildSimProfile {
    /// One of each kind of user. Each runs in the fast suite; the full sweep runs them for two years.
    static let archetypes: [BuildSimProfile] = [
        steady, fastGainer, slowGainer, stalled, sandbagger, grinder, injured, skipper, breakTaker,
        heavy, kilograms, machineStacks, bodyweight, tinyWeights, poorRecovery, legacy, chaos,
    ]

    static func archetype(named name: String) -> BuildSimProfile? {
        archetypes.first { $0.name == name }
    }

    /// Rates honestly, follows the plan and almost never misses a workout.
    static var steady: Self {
        BuildSimProfile(name: "steady")
    }

    static var fastGainer: Self {
        var profile = BuildSimProfile(name: "fastGainer")
        profile.weeklyGain = 0.012
        profile.gainCeiling = 0.6
        profile.ratingBias = 1
        return profile
    }

    static var slowGainer: Self {
        var profile = BuildSimProfile(name: "slowGainer")
        profile.weeklyGain = 0.0015
        profile.gainCeiling = 0.15
        return profile
    }

    /// Gets slowly weaker whatever they do, as when dieting hard.
    static var stalled: Self {
        var profile = BuildSimProfile(name: "stalled")
        profile.weeklyGain = -0.0015
        return profile
    }

    /// Taps 5+ after every exercise.
    static var sandbagger: Self {
        var profile = BuildSimProfile(name: "sandbagger")
        profile.rating = .alwaysFivePlus
        profile.reps = .beyondPlan
        return profile
    }

    /// Takes every last set to failure and taps 0.
    static var grinder: Self {
        var profile = BuildSimProfile(name: "grinder")
        profile.rating = .alwaysZero
        profile.reps = .failureOnLastSet
        return profile
    }

    static var injured: Self {
        var profile = BuildSimProfile(name: "injured")
        profile.injuryChance = 0.04
        profile.achyChance = 0.15
        profile.skipExercise = 0.02
        return profile
    }

    /// Misses days, skips workouts and exercises, stops early and leaves exercises unrated.
    static var skipper: Self {
        var profile = BuildSimProfile(name: "skipper")
        profile.missDay = 0.25
        profile.skipWorkout = 0.25
        profile.skipExercise = 0.12
        profile.stopEarly = 0.1
        profile.noRating = 0.25
        profile.removeSet = 0.05
        return profile
    }

    /// Takes long breaks, from just under two weeks to half a year.
    static var breakTaker: Self {
        var profile = BuildSimProfile(name: "breakTaker")
        profile.breakChance = 0.06
        profile.breakDays = [14, 15, 20, 27, 28, 35, 60, 83, 84, 100, 180]
        profile.programWeeks = 6...12
        profile.sameTemplate = 0.5
        profile.daysBetweenPrograms = [0, 14, 30, 90, 200]
        return profile
    }

    /// Strong enough that leg press sets reach the app's 1,000 lb limit.
    static var heavy: Self {
        var profile = BuildSimProfile(name: "heavy")
        profile.strength = 3.4
        profile.weeklyGain = 0.008
        profile.sameTemplate = 0.3
        return profile
    }

    /// Types every weight in kilograms, rounded to plates, and sometimes picks their own.
    static var kilograms: Self {
        var profile = BuildSimProfile(name: "kilograms")
        profile.loads = .kilograms
        profile.sameTemplate = 0.5
        return profile
    }

    /// Trains on machines that move in 10 lb steps.
    static var machineStacks: Self {
        var profile = BuildSimProfile(name: "machineStacks")
        profile.loads = .equipmentSteps
        profile.sameTemplate = 0.3
        return profile
    }

    /// Trains with only bodyweight exercises, in their own templates.
    static var bodyweight: Self {
        var profile = BuildSimProfile(name: "bodyweight")
        profile.customTemplate = 1
        profile.sameTemplate = 0.5
        profile.weeklyGain = 0.006
        return profile
    }

    /// Light enough that most dumbbells sit under 10 lb.
    static var tinyWeights: Self {
        var profile = BuildSimProfile(name: "tinyWeights")
        profile.strength = 0.12
        profile.loads = .equipmentSteps
        profile.injuryChance = 0.01
        return profile
    }

    /// Builds fatigue fast and clears it slowly, so misses pile up.
    static var poorRecovery: Self {
        var profile = BuildSimProfile(name: "poorRecovery")
        profile.recovery = 0.2
        profile.fatiguePerSet = 0.006
        profile.dayNoise = 0.05
        return profile
    }

    /// Rates most exercises with the old effort words.
    static var legacy: Self {
        var profile = BuildSimProfile(name: "legacy")
        profile.legacyRating = 0.6
        return profile
    }

    /// Does everything the app allows, often: swaps, edits, extra and fewer sets, odd templates, short programs.
    static var chaos: Self {
        var profile = BuildSimProfile(name: "chaos")
        profile.rating = .random
        profile.reps = .beyondPlan
        profile.loads = .ownChoice
        profile.legacyRating = 0.1
        profile.missDay = 0.15
        profile.skipWorkout = 0.1
        profile.doubleSession = 0.2
        profile.skipExercise = 0.08
        profile.stopEarly = 0.08
        profile.noRating = 0.1
        profile.addSet = 0.1
        profile.removeSet = 0.1
        profile.swapExercise = 0.05
        profile.editExercise = 0.25
        profile.breakChance = 0.04
        profile.breakDays = [13, 14, 15, 28, 84, 200]
        profile.injuryChance = 0.02
        profile.achyChance = 0.2
        profile.programWeeks = 1...12
        profile.sameTemplate = 0.2
        profile.customTemplate = 0.5
        profile.abandonProgram = 0.05
        profile.daysBetweenPrograms = [0, 1, 200]
        return profile
    }
}
