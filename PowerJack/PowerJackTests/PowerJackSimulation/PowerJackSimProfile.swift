//
//  PowerJackSimProfile.swift
//  PowerJackTests
//
//  Who a simulated PowerJack lifter is: how their body responds to training, and how they log, rate,
//  skip and pick programs. Random profiles spread over every kind of user; archetypes each pin down one.
//

import Foundation
@testable import PowerJack

struct PowerJackSimProfile {
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
        /// A rep or two short once a set gets hard.
        case shortOfPlan
        /// A rep or two extra when the set is easy.
        case beyondPlan
    }

    enum Loads: String {
        case asPlanned
        /// 2.5 lb plates, so loads they pick land on 2.5 lb.
        case microplates
        /// What the equipment offers: 10 lb on machines and stacks, 5 lb elsewhere.
        case equipmentSteps
        /// Their own pick, near the plan.
        case ownChoice
        /// Typed in kilograms, rounded to their plates.
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
    var setDrop = 0.5
    /// Reps at a share of max against R8.1's table: above 1, more reps than the table expects.
    var endurance = 1.0

    // MARK: Logging

    var rating = Rating.honest
    /// Added to the reps that were really left before tapping.
    var ratingBias = 0
    /// Chance a rating lands one away from what was meant.
    var ratingNoise = 0.1
    var reps = Reps.asPlanned
    var loads = Loads.asPlanned
    /// The smallest plate pair in kilograms, for `.kilograms`.
    var kilogramStep = 2.5
    /// How far off a weight picked by feel lands, as a share of the right one.
    var misjudge = 0.08
    /// Rates the TOP set right after it rather than in the feedback at the end.
    var inlineTopRating = 0.8
    /// Chance an exercise is rated with an old effort word, as history from before the reps-left scale holds.
    var legacyRating = 0.0
    /// Finishes the workout without rating an exercise.
    var noRating = 0.0

    // MARK: Habits, each a chance per occasion

    var missDay = 0.03
    var skipWorkout = 0.02
    var doubleSession = 0.0
    var skipExercise = 0.0
    var stopEarly = 0.0
    var addSet = 0.0
    var removeSet = 0.0
    var swapExercise = 0.0
    /// Edits an exercise's fatigue level, or a custom exercise's equipment, in a given week.
    var editExercise = 0.0
    var disableWarmups = 0.0
    /// A break starting in a given week, and how long breaks run.
    var breakChance = 0.0
    var breakDays = [10, 14, 15, 21, 28, 42, 90]
    /// An injury starting on an exposure.
    var injuryChance = 0.0
    /// Pain tapped as Mild or Noticeable with no injury.
    var achyChance = 0.03
    var checkIn: [(ManualCheckInDecision, Double)] = [(.continue, 3), (.reset, 1), (.skip, 1)]
    /// Finishes the workout without answering a check-in.
    var ignoreCheckIn = 0.0

    // MARK: Programs

    var programWeeks = 8...12
    var sameTemplate = 0.5
    /// Builds a PowerJack template of their own.
    var customTemplate = 0.0
    /// Runs a Build or Strengthen program instead, so PowerJack reads another style's history.
    var otherStyle = 0.0
    /// Starts another program partway through, in a given week.
    var abandonProgram = 0.0
    var daysBetweenPrograms = [0, 2, 7]

    /// Lifters with an ordinary body who rate honestly, show up and stay healthy. Their plans should
    /// track what they can lift.
    var isWellBehaved: Bool {
        dayNoise <= 0.04 && fatiguePerSet <= 0.003 && recovery >= 0.4 && (0.85...1.2).contains(endurance)
            && rating == .honest && abs(ratingBias) <= 1 && ratingNoise <= 0.2 && legacyRating == 0 && noRating == 0
            && reps == .asPlanned && loads != .ownChoice
            && skipWorkout <= 0.05 && skipExercise <= 0.02 && stopEarly <= 0.02
            && swapExercise == 0 && editExercise == 0 && breakChance == 0 && injuryChance == 0
            && customTemplate == 0 && otherStyle == 0 && abandonProgram == 0
    }
}

//
// Random lifters
//
extension PowerJackSimProfile {
    /// Every trait drawn from `seed`. Most draws are ordinary; a few sit at the extremes.
    static func random(seed: UInt64) -> PowerJackSimProfile {
        var rng = PowerJackSimRandom(seed: seed ^ 0x5EED_0F_70CA)
        var profile = PowerJackSimProfile(name: "random")

        let strengthBand = rng.pick(weighted: [(0.15...0.45, 1), (0.45...1.6, 8), (1.6...3.6, 1)])
        profile.strength = rng.double(strengthBand)
        profile.weeklyGain = rng.pick(weighted: [(-0.002, 1), (0, 1), (0.0015, 2), (0.004, 3), (0.008, 2), (0.015, 1)])
        profile.gainCeiling = rng.double(0.1...0.8)
        profile.recovery = rng.double(0.25...0.8)
        profile.fatiguePerSet = rng.double(0.0005...0.006)
        profile.dayNoise = rng.double(0.01...0.06)
        profile.setDrop = rng.double(0.1...1.3)
        profile.endurance = rng.double(0.7...1.35)

        profile.rating = rng.pick(weighted: [(.honest, 16), (.alwaysFivePlus, 1), (.alwaysZero, 1), (.random, 1)])
        profile.ratingBias = rng.pick(weighted: [(-1, 2), (0, 5), (1, 3), (2, 1)])
        profile.ratingNoise = rng.double(0...0.4)
        profile.reps = rng.pick(weighted: [(.asPlanned, 5), (.failureOnLastSet, 2), (.shortOfPlan, 2), (.beyondPlan, 2)])
        profile.loads = rng.pick(weighted: [(.asPlanned, 5), (.microplates, 1), (.equipmentSteps, 3), (.ownChoice, 1), (.kilograms, 2)])
        profile.kilogramStep = rng.pick([1.25, 2.5, 2.5, 5])
        profile.misjudge = rng.double(0.02...0.3)
        profile.inlineTopRating = rng.double(0...1)
        profile.legacyRating = rng.chance(0.05) ? rng.double(0.05...0.3) : 0
        profile.noRating = rng.chance(0.1) ? rng.double(0.02...0.2) : 0

        profile.missDay = rng.double(0...0.2)
        profile.skipWorkout = rng.chance(0.1) ? rng.double(0.2...0.45) : rng.double(0...0.1)
        profile.doubleSession = rng.chance(0.2) ? rng.double(0...0.15) : 0
        profile.skipExercise = rng.double(0...0.08)
        profile.stopEarly = rng.double(0...0.08)
        profile.addSet = rng.double(0...0.05)
        profile.removeSet = rng.double(0...0.05)
        profile.swapExercise = rng.chance(0.3) ? rng.double(0...0.02) : 0
        profile.editExercise = rng.chance(0.3) ? rng.double(0...0.1) : 0
        profile.disableWarmups = rng.double(0...0.05)
        profile.breakChance = rng.double(0...0.04)
        profile.breakDays = [7, 8, 10, 13, 14, 15, 20, 21, 27, 28, 29, 35, 42, 56, 83, 84, 85, 100, 150, 200]
        profile.injuryChance = rng.chance(0.15) ? rng.double(0.01...0.04) : rng.double(0...0.008)
        profile.achyChance = rng.double(0...0.15)
        profile.checkIn = [(.continue, rng.double(0...3)), (.reset, rng.double(0...2)), (.skip, rng.double(0...2)), (.continue, 0.1)]
        profile.ignoreCheckIn = rng.chance(0.2) ? rng.double(0...0.3) : 0

        let shortest = rng.int(1...10)
        profile.programWeeks = shortest...rng.int(shortest...12)
        profile.sameTemplate = rng.double(0...1)
        profile.customTemplate = rng.double(0...0.35)
        profile.otherStyle = rng.chance(0.2) ? rng.double(0...0.3) : 0
        profile.abandonProgram = rng.double(0...0.03)
        profile.daysBetweenPrograms = [0, 1, 3, 7, 14, 21, 30, 60, 120, 200]
        return profile
    }
}

//
// Archetypes
//
extension PowerJackSimProfile {
    /// One of each kind of user. Each runs in the fast suite; the full sweep runs them for two years.
    static let archetypes: [PowerJackSimProfile] = [
        steady, strongResponder, weakResponder, stalled, sandbagger, grinder, misser, injured, skipper,
        breakTaker, heavy, tinyWeights, kilograms, microplates, machineStacks, ownTemplates, styleHopper,
        poorRecovery, legacy, chaos,
    ]

    static func archetype(named name: String) -> PowerJackSimProfile? {
        archetypes.first { $0.name == name }
    }

    /// Rates honestly, follows the plan and almost never misses a workout.
    static var steady: Self {
        PowerJackSimProfile(name: "steady")
    }

    /// Gains fast and often has a rep more than the plan expects.
    static var strongResponder: Self {
        var profile = PowerJackSimProfile(name: "strongResponder")
        profile.weeklyGain = 0.012
        profile.gainCeiling = 0.6
        profile.ratingBias = 1
        return profile
    }

    static var weakResponder: Self {
        var profile = PowerJackSimProfile(name: "weakResponder")
        profile.weeklyGain = 0.0012
        profile.gainCeiling = 0.12
        return profile
    }

    /// Gets slowly weaker whatever they do, as when dieting hard.
    static var stalled: Self {
        var profile = PowerJackSimProfile(name: "stalled")
        profile.weeklyGain = -0.0015
        return profile
    }

    /// Taps 5+ after every exercise and its TOP set, and does extra reps.
    static var sandbagger: Self {
        var profile = PowerJackSimProfile(name: "sandbagger")
        profile.rating = .alwaysFivePlus
        profile.reps = .beyondPlan
        return profile
    }

    /// Takes every last set to failure and taps 0.
    static var grinder: Self {
        var profile = PowerJackSimProfile(name: "grinder")
        profile.rating = .alwaysZero
        profile.reps = .failureOnLastSet
        return profile
    }

    /// Falls a rep or two short of plan often, more as fatigue builds.
    static var misser: Self {
        var profile = PowerJackSimProfile(name: "misser")
        profile.reps = .shortOfPlan
        profile.endurance = 0.8
        profile.fatiguePerSet = 0.004
        profile.recovery = 0.4
        return profile
    }

    /// Gets hurt now and then: pain taps, check-ins answered every way, some left unanswered.
    static var injured: Self {
        var profile = PowerJackSimProfile(name: "injured")
        profile.injuryChance = 0.04
        profile.achyChance = 0.15
        profile.skipExercise = 0.02
        profile.ignoreCheckIn = 0.15
        profile.checkIn = [(.continue, 2), (.reset, 1), (.skip, 2)]
        return profile
    }

    /// Misses days, skips workouts, exercises and sets, stops early and changes set counts.
    static var skipper: Self {
        var profile = PowerJackSimProfile(name: "skipper")
        profile.missDay = 0.25
        profile.skipWorkout = 0.25
        profile.skipExercise = 0.12
        profile.stopEarly = 0.1
        profile.addSet = 0.05
        profile.removeSet = 0.08
        profile.inlineTopRating = 0.3
        return profile
    }

    /// Takes breaks from a week to half a year, inside programs and between them.
    static var breakTaker: Self {
        var profile = PowerJackSimProfile(name: "breakTaker")
        profile.breakChance = 0.06
        profile.breakDays = [7, 8, 13, 14, 15, 20, 27, 28, 35, 60, 83, 84, 100, 180]
        profile.programWeeks = 6...12
        profile.daysBetweenPrograms = [0, 14, 30, 90, 200]
        return profile
    }

    /// Strong enough that loads near the app's 1,000 lb limit, in templates that lead with the leg press.
    static var heavy: Self {
        var profile = PowerJackSimProfile(name: "heavy")
        profile.strength = 3.4
        profile.weeklyGain = 0.008
        profile.customTemplate = 0.5
        return profile
    }

    /// Light enough that most main lifts sit under 100 lb, where a 5 lb step is over 5% (band mode).
    static var tinyWeights: Self {
        var profile = PowerJackSimProfile(name: "tinyWeights")
        profile.strength = 0.2
        profile.loads = .equipmentSteps
        return profile
    }

    /// Types every weight in kilograms, rounded to plates.
    static var kilograms: Self {
        var profile = PowerJackSimProfile(name: "kilograms")
        profile.loads = .kilograms
        profile.kilogramStep = 2.5
        return profile
    }

    /// Owns 2.5 lb plates and picks loads on them.
    static var microplates: Self {
        var profile = PowerJackSimProfile(name: "microplates")
        profile.loads = .microplates
        profile.misjudge = 0.15
        return profile
    }

    /// Trains where machines and stacks move in 10 lb steps.
    static var machineStacks: Self {
        var profile = PowerJackSimProfile(name: "machineStacks")
        profile.loads = .equipmentSteps
        profile.customTemplate = 0.3
        return profile
    }

    /// Builds their own PowerJack templates: any days, repeats, bodyweight work, no main lifts at all.
    static var ownTemplates: Self {
        var profile = PowerJackSimProfile(name: "ownTemplates")
        profile.customTemplate = 1
        profile.sameTemplate = 0.3
        profile.programWeeks = 1...12
        profile.swapExercise = 0.02
        profile.editExercise = 0.05
        return profile
    }

    /// Runs Build and Strengthen programs between PowerJack ones.
    static var styleHopper: Self {
        var profile = PowerJackSimProfile(name: "styleHopper")
        profile.otherStyle = 0.4
        profile.programWeeks = 3...8
        profile.sameTemplate = 0.2
        return profile
    }

    /// Builds fatigue fast and clears it slowly, so misses and strain pile up.
    static var poorRecovery: Self {
        var profile = PowerJackSimProfile(name: "poorRecovery")
        profile.recovery = 0.2
        profile.fatiguePerSet = 0.006
        profile.dayNoise = 0.05
        return profile
    }

    /// Rates many exercises with the old effort words, as history from before the reps-left scale holds.
    static var legacy: Self {
        var profile = PowerJackSimProfile(name: "legacy")
        profile.legacyRating = 0.5
        profile.noRating = 0.05
        return profile
    }

    /// Does everything the app allows, often.
    static var chaos: Self {
        var profile = PowerJackSimProfile(name: "chaos")
        profile.rating = .random
        profile.reps = .beyondPlan
        profile.loads = .ownChoice
        profile.misjudge = 0.3
        profile.inlineTopRating = 0.5
        profile.legacyRating = 0.1
        profile.noRating = 0.1
        profile.missDay = 0.15
        profile.skipWorkout = 0.1
        profile.doubleSession = 0.2
        profile.skipExercise = 0.08
        profile.stopEarly = 0.08
        profile.addSet = 0.1
        profile.removeSet = 0.1
        profile.swapExercise = 0.05
        profile.editExercise = 0.25
        profile.disableWarmups = 0.1
        profile.breakChance = 0.04
        profile.breakDays = [8, 13, 14, 15, 28, 84, 200]
        profile.injuryChance = 0.02
        profile.achyChance = 0.2
        profile.ignoreCheckIn = 0.2
        profile.programWeeks = 1...12
        profile.sameTemplate = 0.2
        profile.customTemplate = 0.5
        profile.otherStyle = 0.15
        profile.abandonProgram = 0.05
        profile.daysBetweenPrograms = [0, 1, 200]
        return profile
    }
}
