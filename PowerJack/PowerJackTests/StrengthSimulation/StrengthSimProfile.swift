//
//  StrengthSimProfile.swift
//  PowerJackTests
//
//  Who a simulated lifter is: how their body responds to heavy training, the units and plates they set up,
//  and how they log, rate, skip and pick programs. Random profiles spread over every kind of user;
//  archetypes each pin down one kind.
//

import Foundation
@testable import PowerJack

struct StrengthSimProfile {
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
        /// Now and then a step off the plan, typed on the first set and carried to the rest.
        case ownChoice
        /// Rounded to the plates they own, which can sit off the app's grid.
        case ownPlates
    }

    /// The smallest load steps set in Settings (1.5).
    enum Steps: String {
        case defaults
        case smallest
        case largest
        /// A random option for each equipment type.
        case mixed
    }

    var name: String

    // MARK: Body

    /// Starting maxes against a typical trained lifter.
    var strength = 1.0
    /// Share of 1RM gained in a week of enough heavy sets while far from the ceiling. Below 0, weaker anyway.
    var weeklyGain = 0.004
    /// The most a max grows, as a share of where it started.
    var gainCeiling = 0.35
    /// Share of fatigue that clears each week.
    var recovery = 0.6
    /// Fatigue each hard set adds in a week.
    var fatiguePerSet = 0.0015
    /// Day-to-day spread of strength, as a share of max.
    var dayNoise = 0.02
    /// Reps lost on each later set of an exercise.
    var setDrop = 0.4
    /// Reps at a given share of max, against the average lifter on the engine's own curve (4.7).
    var endurance = 1.0
    /// Share of max lost each week a lift goes untrained past two weeks.
    var detraining = 0.008

    // MARK: Settings

    var unit = WeightUnit.pounds
    var steps = Steps.defaults
    /// Chance in a given week of switching between kg and lb in Settings (1.4).
    var unitSwitch = 0.0
    /// Chance in a given week of picking new smallest steps in Settings (1.4).
    var stepChange = 0.0

    // MARK: Logging

    var rating = Rating.honest
    /// Added to the reps that were really left before tapping. Lifters under-rate by about a rep (3.5).
    var ratingBias = 0
    /// Chance a rating lands one away from what was meant.
    var ratingNoise = 0.1
    var reps = Reps.asPlanned
    var loads = Loads.asPlanned
    /// How far a weight picked by feel lands from one that leaves the aimed reps, as a share of it.
    var feelError = 0.06
    /// The lean of weights picked by feel: lifters pick a little light (2.2).
    var feelBias = -0.03

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
    /// Edits an exercise's rep range, fatigue level or equipment in a given week.
    var editExercise = 0.0
    /// Logs the warm-ups rather than going straight to the working sets.
    var logWarmups = 0.7
    var disableWarmups = 0.0
    /// A break starting in a given week, and how long breaks run.
    var breakChance = 0.0
    var breakDays = [10, 14, 15, 21, 28, 42, 90]
    /// An injury starting on an exposure.
    var injuryChance = 0.0
    /// Pain tapped as Mild or Noticeable with no injury.
    var achyChance = 0.03
    /// Answers to the pain check-in. Strengthen offers Lighter (continue) or Skip (15.4).
    var checkIn: [(ManualCheckInDecision, Double)] = [(.continue, 3), (.skip, 1)]

    // MARK: Programs

    var programWeeks = 12...12
    var sameTemplate = 1.0
    var customTemplate = 0.0
    /// Starts another program partway through, in a given week.
    var abandonProgram = 0.0
    var daysBetweenPrograms = [0, 2, 7]
    /// Chance a new program is a Build or PowerJack one instead of Strengthen.
    var otherStyles = 0.0
    /// Strength weeks already logged before the run, so the lifter turns advanced partway through (17.7).
    var trainedWeeksBefore = 0

    /// Lifters with an ordinary body who rate honestly, follow the plan, show up and stay healthy. Their plans
    /// and estimates should track what they can lift.
    var isWellBehaved: Bool {
        dayNoise <= 0.03 && fatiguePerSet <= 0.003 && recovery >= 0.4 && weeklyGain >= 0 && abs(endurance - 1) <= 0.15
            && rating == .honest && abs(ratingBias) <= 1 && ratingNoise <= 0.2
            && reps == .asPlanned && loads != .ownPlates
            && skipWorkout <= 0.05 && skipExercise <= 0.02 && stopEarly <= 0.02 && noRating <= 0.02
            && swapExercise == 0 && editExercise == 0 && breakChance == 0 && injuryChance == 0
            && customTemplate == 0 && abandonProgram == 0 && otherStyles == 0
    }
}

//
// Random lifters
//
extension StrengthSimProfile {
    /// Every trait drawn from `seed`. Most draws are ordinary; a few sit at the extremes.
    static func random(seed: UInt64) -> StrengthSimProfile {
        var rng = StrengthSimRandom(seed: seed ^ 0x5EED_57_2E46)
        var profile = StrengthSimProfile(name: "random")

        let strengthBand = rng.pick(weighted: [(0.2...0.5, 1), (0.5...1.6, 8), (1.6...2.4, 1)])
        profile.strength = rng.double(strengthBand)
        profile.weeklyGain = rng.pick(weighted: [(-0.002, 1), (0, 1), (0.0015, 2), (0.004, 3), (0.008, 2), (0.012, 1)])
        profile.gainCeiling = rng.double(0.08...0.6)
        profile.recovery = rng.double(0.25...0.8)
        profile.fatiguePerSet = rng.double(0.0005...0.005)
        profile.dayNoise = rng.double(0.01...0.05)
        profile.setDrop = rng.double(0.1...1.0)
        profile.endurance = rng.double(0.75...1.3)
        profile.detraining = rng.double(0.003...0.015)

        profile.unit = rng.chance(0.5) ? .kilograms : .pounds
        profile.steps = rng.pick(weighted: [(.defaults, 5), (.smallest, 2), (.largest, 1), (.mixed, 2)])
        profile.unitSwitch = rng.chance(0.15) ? rng.double(0...0.03) : 0
        profile.stepChange = rng.chance(0.15) ? rng.double(0...0.03) : 0

        profile.rating = rng.pick(weighted: [(.honest, 16), (.alwaysFivePlus, 1), (.alwaysZero, 1), (.random, 1)])
        profile.ratingBias = rng.pick(weighted: [(-2, 1), (-1, 4), (0, 5), (1, 2)])
        profile.ratingNoise = rng.double(0...0.4)
        profile.reps = rng.pick(weighted: [(.asPlanned, 5), (.failureOnLastSet, 2), (.shortOfPlan, 1), (.beyondPlan, 2)])
        profile.loads = rng.pick(weighted: [(.asPlanned, 6), (.ownChoice, 2), (.ownPlates, 1)])
        profile.feelError = rng.double(0.02...0.15)
        profile.feelBias = rng.double(-0.1...0.05)

        profile.missDay = rng.double(0...0.2)
        profile.skipWorkout = rng.chance(0.1) ? rng.double(0.2...0.4) : rng.double(0...0.1)
        profile.doubleSession = rng.chance(0.2) ? rng.double(0...0.15) : 0
        profile.skipExercise = rng.double(0...0.08)
        profile.stopEarly = rng.double(0...0.08)
        profile.noRating = rng.chance(0.1) ? rng.double(0.3...1) : rng.double(0...0.05)
        profile.addSet = rng.double(0...0.05)
        profile.removeSet = rng.double(0...0.05)
        profile.swapExercise = rng.chance(0.3) ? rng.double(0...0.02) : 0
        profile.editExercise = rng.chance(0.3) ? rng.double(0...0.1) : 0
        profile.logWarmups = rng.double(0...1)
        profile.disableWarmups = rng.chance(0.2) ? rng.double(0...0.05) : 0
        profile.breakChance = rng.double(0...0.04)
        profile.breakDays = [7, 10, 13, 14, 15, 16, 20, 21, 27, 28, 29, 35, 42, 56, 57, 83, 89, 90, 91, 92, 100, 150, 200]
        profile.injuryChance = rng.chance(0.15) ? rng.double(0.01...0.04) : rng.double(0...0.008)
        profile.achyChance = rng.double(0...0.15)
        profile.checkIn = [(.continue, rng.double(0...3)), (.skip, rng.double(0...2)), (.continue, 0.1)]

        let shortest = rng.int(1...10)
        profile.programWeeks = shortest...rng.int(shortest...12)
        profile.sameTemplate = rng.double(0...1)
        profile.customTemplate = rng.double(0...0.3)
        profile.abandonProgram = rng.double(0...0.03)
        profile.daysBetweenPrograms = [0, 1, 3, 7, 14, 21, 30, 60, 120, 200]
        profile.otherStyles = rng.chance(0.2) ? rng.double(0...0.4) : 0
        profile.trainedWeeksBefore = rng.chance(0.15) ? rng.int(60...103) : 0
        return profile
    }
}

//
// Archetypes
//
extension StrengthSimProfile {
    /// One of each kind of user. Each runs in the fast suite; the full sweep runs them for two years.
    static let archetypes: [StrengthSimProfile] = [
        steady, kilograms, fineSteps, coarseSteps, unitSwitcher, fastGainer, slowGainer, stalled,
        underRater, sandbagger, grinder, unrated, injured, skipper, breakTaker, shortPrograms,
        heavy, light, veteran, styleHopper, chaos,
    ]

    static func archetype(named name: String) -> StrengthSimProfile? {
        archetypes.first { $0.name == name }
    }

    /// Rates honestly, follows the plan in pounds and almost never misses a workout.
    static var steady: Self {
        StrengthSimProfile(name: "steady")
    }

    /// Trains in kilograms with the default 2.5 kg barbell step.
    static var kilograms: Self {
        var profile = StrengthSimProfile(name: "kilograms")
        profile.unit = .kilograms
        profile.sameTemplate = 0.5
        return profile
    }

    /// Owns fractional plates: the smallest step for every equipment type, in kilograms.
    static var fineSteps: Self {
        var profile = StrengthSimProfile(name: "fineSteps")
        profile.unit = .kilograms
        profile.steps = .smallest
        profile.weeklyGain = 0.006
        return profile
    }

    /// The biggest steps Settings offers, so most lifts run in reps mode (1.2).
    static var coarseSteps: Self {
        var profile = StrengthSimProfile(name: "coarseSteps")
        profile.steps = .largest
        profile.sameTemplate = 0.3
        return profile
    }

    /// Switches between kg and lb, and changes steps, now and then (1.4).
    static var unitSwitcher: Self {
        var profile = StrengthSimProfile(name: "unitSwitcher")
        profile.steps = .mixed
        profile.unitSwitch = 0.06
        profile.stepChange = 0.06
        profile.loads = .ownChoice
        return profile
    }

    static var fastGainer: Self {
        var profile = StrengthSimProfile(name: "fastGainer")
        profile.weeklyGain = 0.012
        profile.gainCeiling = 0.6
        return profile
    }

    static var slowGainer: Self {
        var profile = StrengthSimProfile(name: "slowGainer")
        profile.weeklyGain = 0.0012
        profile.gainCeiling = 0.1
        profile.unit = .kilograms
        return profile
    }

    /// Gets slowly weaker whatever they do, as when dieting hard.
    static var stalled: Self {
        var profile = StrengthSimProfile(name: "stalled")
        profile.weeklyGain = -0.0015
        return profile
    }

    /// Taps a rep fewer than were left, as most lifters do (3.5).
    static var underRater: Self {
        var profile = StrengthSimProfile(name: "underRater")
        profile.ratingBias = -1
        profile.ratingNoise = 0.3
        return profile
    }

    /// Taps 5+ after every exercise and adds reps when sets are easy.
    static var sandbagger: Self {
        var profile = StrengthSimProfile(name: "sandbagger")
        profile.rating = .alwaysFivePlus
        profile.reps = .beyondPlan
        return profile
    }

    /// Takes every last set to failure and taps 0.
    static var grinder: Self {
        var profile = StrengthSimProfile(name: "grinder")
        profile.rating = .alwaysZero
        profile.reps = .failureOnLastSet
        return profile
    }

    /// Never rates an exercise, so the rules run on reps alone (Level 0).
    static var unrated: Self {
        var profile = StrengthSimProfile(name: "unrated")
        profile.noRating = 1
        profile.unit = .kilograms
        return profile
    }

    static var injured: Self {
        var profile = StrengthSimProfile(name: "injured")
        profile.injuryChance = 0.04
        profile.achyChance = 0.15
        profile.skipExercise = 0.02
        profile.checkIn = [(.continue, 2), (.skip, 1)]
        return profile
    }

    /// Misses days, skips workouts and exercises, stops early and leaves exercises unrated.
    static var skipper: Self {
        var profile = StrengthSimProfile(name: "skipper")
        profile.missDay = 0.25
        profile.skipWorkout = 0.25
        profile.skipExercise = 0.12
        profile.stopEarly = 0.1
        profile.noRating = 0.25
        profile.removeSet = 0.05
        profile.logWarmups = 0.2
        return profile
    }

    /// Takes long breaks, from just under two weeks to half a year (12.1-12.2).
    static var breakTaker: Self {
        var profile = StrengthSimProfile(name: "breakTaker")
        profile.breakChance = 0.06
        profile.breakDays = [14, 15, 20, 28, 29, 35, 56, 57, 60, 89, 90, 91, 100, 180]
        profile.programWeeks = 6...12
        profile.sameTemplate = 0.5
        profile.daysBetweenPrograms = [0, 14, 30, 90, 200]
        return profile
    }

    /// Runs one- to three-week programs back to back, so most weeks are a program's last.
    static var shortPrograms: Self {
        var profile = StrengthSimProfile(name: "shortPrograms")
        profile.programWeeks = 1...3
        profile.sameTemplate = 0.6
        profile.daysBetweenPrograms = [0, 1, 2]
        return profile
    }

    /// Strong enough that deadlifts and leg presses reach the app's 1,000 lb limit (1.1).
    static var heavy: Self {
        var profile = StrengthSimProfile(name: "heavy")
        profile.strength = 2.3
        profile.weeklyGain = 0.006
        profile.customTemplate = 0.5
        profile.sameTemplate = 0.3
        return profile
    }

    /// Light enough that barbell lifts sit near the empty bar and dumbbells move in big steps.
    static var light: Self {
        var profile = StrengthSimProfile(name: "light")
        profile.strength = 0.25
        profile.weeklyGain = 0.01
        profile.unit = .kilograms
        profile.injuryChance = 0.01
        return profile
    }

    /// Has trained with the app for almost two years, so turns advanced early in the run (17.7).
    static var veteran: Self {
        var profile = StrengthSimProfile(name: "veteran")
        profile.trainedWeeksBefore = 96
        profile.strength = 1.5
        profile.weeklyGain = 0.0015
        profile.gainCeiling = 0.15
        return profile
    }

    /// Switches between Strengthen, Build and PowerJack programs.
    static var styleHopper: Self {
        var profile = StrengthSimProfile(name: "styleHopper")
        profile.otherStyles = 0.45
        profile.programWeeks = 3...8
        profile.sameTemplate = 0.2
        profile.daysBetweenPrograms = [0, 3, 10]
        return profile
    }

    /// Does everything the app allows, often: swaps, edits, extra and fewer sets, odd templates, short programs.
    static var chaos: Self {
        var profile = StrengthSimProfile(name: "chaos")
        profile.rating = .random
        profile.reps = .beyondPlan
        profile.loads = .ownPlates
        profile.steps = .mixed
        profile.unitSwitch = 0.03
        profile.stepChange = 0.03
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
        profile.logWarmups = 0.5
        profile.disableWarmups = 0.05
        profile.breakChance = 0.04
        profile.breakDays = [13, 14, 15, 28, 84, 200]
        profile.injuryChance = 0.02
        profile.achyChance = 0.2
        profile.programWeeks = 1...12
        profile.sameTemplate = 0.2
        profile.customTemplate = 0.5
        profile.abandonProgram = 0.05
        profile.daysBetweenPrograms = [0, 1, 200]
        profile.otherStyles = 0.15
        return profile
    }
}
