//
//  ProgressionEngine.swift
//  PowerJack
//
//  Decides the next planned version of an exercise.
//  Port of the original `generateNextLiftPrescription` (see docs/progression-system.md on `main`).
//

import Foundation

/// A logged set, detached from SwiftData so the engine stays a pure function.
struct ProgressionSet: Equatable {
    var plannedReps: Int?
    var plannedWeightTenthsPounds: Int?
    var actualReps: Int?
    var actualWeightTenthsPounds: Int?
    var status: Status
}

/// One program week's performance of a single exercise.
struct ProgressionHistory: Equatable {
    /// 1-based program week.
    var programWeek: Int
    var status: Status
    var pain: LevelOfPain?
    var effort: LevelOfEffort?
    var checkIn: ManualCheckIn = .none
    var checkInSourcePain: LevelOfPain?
    var sets: [ProgressionSet]
}

struct ProgressionExerciseInfo: Equatable {
    var minReps: Int
    var maxReps: Int
    var primaryMuscle: Muscle
    var secondaryMuscles: [Muscle]
    var repsOnly: Bool
    /// Weighted pull-ups and dips: 0 is bodyweight, so a set at 0 can add load.
    var addsToBodyweight: Bool = false
}

struct ProgressionInput {
    var current: ProgressionHistory
    var previous: ProgressionHistory?
    var exercise: ProgressionExerciseInfo
    var focusMuscles: Set<Muscle>
    /// Completed set credits per muscle in `current`'s program week.
    var currentWeekMuscleSetCredits: [Muscle: Double]
    /// Half reps a reps-only exercise banked in earlier weeks (0 or 1), from the last `Prescription`.
    var repCarryHalves = 0
}

struct SetPrescription: Equatable {
    var plannedReps: Int?
    var plannedWeightTenthsPounds: Int?
}

enum ProgressionGate: Equatable {
    case skippedCarryForward
    case held
    case highPain
    case underMinimum
    case moderatePain
    case maxEffort
    case load
    case reps
}

struct Prescription: Equatable {
    var gate: ProgressionGate
    /// Non-nil when the next exercise must wait on a manual check-in.
    var checkInSourcePain: LevelOfPain?
    var sets: [SetPrescription]
    /// A set was added on top of this week's step.
    var addedSet = false
    /// Half reps banked for next week by a reps-only exercise (0 or 1).
    var repCarryHalves = 0
}

/// Pain and missed reps hold progression back, reps left schedule more sets, and weight keeps reps inside
/// the exercise's range. Otherwise every set adds a rep.
enum ProgressionEngine {
    static let loadIncrementTenthsPounds = 50
    static let loadReadyRepFraction = 0.85
    /// From 200 lb, a 5 lb step is 2.5% of the load or less, less than one more rep is worth.
    static let heavyLoadTenthsPounds = 2000
    /// The reps left a clean week needs, the aim lifters are shown.
    static let cleanWeekRepsInReserve = 2
    static let weeklyMuscleSetCap = 25.0
    static let primaryMuscleSetCredit = 1.0
    static let secondaryMuscleSetCredit = 0.5

    static var maxWorkingSets: Int { WorkoutExercise.maxSets }

    static func nextPrescription(_ input: ProgressionInput) -> Prescription {
        let current = input.current
        let exercise = input.exercise
        let cap = repCap(exercise)
        func hold(_ gate: ProgressionGate, _ sets: [SetPrescription], checkIn: LevelOfPain? = nil) -> Prescription {
            Prescription(gate: gate, checkInSourcePain: checkIn, sets: sets, repCarryHalves: input.repCarryHalves)
        }

        // A check-in that ended in "skip" keeps holding the same prescription.
        if current.status == .skipped,
           current.checkIn == .resolved,
           let sourcePain = current.checkInSourcePain {
            return hold(.skippedCarryForward, carryForward(current.sets), checkIn: sourcePain)
        }

        let completed = completedSets(current)

        guard !completed.isEmpty else {
            return hold(.held, carryForward(current.sets))
        }

        guard let pain = current.pain, let effort = current.effort else {
            return hold(.held, copyActual(completed, cap: cap))
        }

        if pain.rawValue >= LevelOfPain.severe.rawValue {
            return hold(.highPain, copyActual(completed, cap: cap), checkIn: pain)
        }

        if let firstUnder = completed.firstIndex(where: { $0.reps < exercise.minReps }) {
            let retained = completed.enumerated().filter { index, set in
                set.reps >= exercise.minReps || index == firstUnder
            }
            return hold(.underMinimum, retained.map { _, set in
                SetPrescription(
                    plannedReps: min(max(set.reps, exercise.minReps), cap),
                    plannedWeightTenthsPounds: set.weight
                )
            })
        }

        if pain == .moderate {
            return hold(.moderatePain, copyActual(completed, cap: cap))
        }

        if effort == .brutal {
            return hold(.maxEffort, copyActual(completed, cap: cap))
        }

        var prescription = exercise.repsOnly
            ? halfRepStep(completed, repsInReserve: repsInReserve(effort), carry: input.repCarryHalves, cap: cap)
            : weightOrRepStep(completed, exercise: exercise, cap: cap)

        // Sets are their own track: clean weeks add one on top of the step.
        let isFocus = input.focusMuscles.contains(exercise.primaryMuscle)
        let isClean = { (history: ProgressionHistory?) in isCleanWeek(history, exercise: exercise) }
        if completed.count < maxWorkingSets,
           fitsWeeklyMuscleCap(exercise, credits: input.currentWeekMuscleSetCredits),
           isClean(current), isFocus || isClean(input.previous),
           let last = completed.last {
            prescription.sets.append(SetPrescription(
                plannedReps: min(max(last.reps - 3, exercise.minReps), cap),
                plannedWeightTenthsPounds: last.weight
            ))
            prescription.addedSet = true
        }
        return prescription
    }

    /// Set credits an added set would contribute to each muscle.
    static func setCredits(primary: Muscle, secondary: [Muscle]) -> [Muscle: Double] {
        var credits: [Muscle: Double] = [primary: primaryMuscleSetCredit]
        for muscle in Set(secondary) where muscle != primary {
            credits[muscle, default: 0] += secondaryMuscleSetCredit
        }
        return credits
    }
}

//
// Private
//
private extension ProgressionEngine {
    struct CompletedSet {
        let reps: Int
        let weight: Int?
    }

    /// No set plans past the top of the exercise's range.
    static func repCap(_ exercise: ProgressionExerciseInfo) -> Int {
        min(exercise.maxReps, Exercise.maxRepsAllowed)
    }

    /// Effort is stored as 5 minus reps left (see `RepsInReserve.storedValue`).
    static func repsInReserve(_ effort: LevelOfEffort) -> Int {
        5 - effort.rawValue
    }

    static func completedSets(_ history: ProgressionHistory) -> [CompletedSet] {
        history.sets.compactMap { set in
            guard set.status == .complete,
                  let reps = set.actualReps ?? set.plannedReps
            else {
                return nil
            }
            return CompletedSet(
                reps: reps,
                weight: set.actualWeightTenthsPounds ?? set.plannedWeightTenthsPounds
            )
        }
    }

    static func copyActual(_ sets: [CompletedSet], cap: Int) -> [SetPrescription] {
        sets.map { SetPrescription(plannedReps: min($0.reps, cap), plannedWeightTenthsPounds: $0.weight) }
    }

    /// Repeats what was logged where possible, otherwise what was planned.
    static func carryForward(_ sets: [ProgressionSet]) -> [SetPrescription] {
        let carried = sets.map {
            SetPrescription(
                plannedReps: $0.actualReps ?? $0.plannedReps,
                plannedWeightTenthsPounds: $0.actualWeightTenthsPounds ?? $0.plannedWeightTenthsPounds
            )
        }
        return carried.isEmpty
            ? Array(repeating: SetPrescription(), count: WorkoutExercise.initialSets)
            : carried
    }

    /// Weight keeps the reps in range: 5 lb more at the same reps once any set is near the top of the range or
    /// every set is past its middle. Otherwise a rep on every set. From 200 lb a rep is the bigger step, so the
    /// weight waits for every set to pass the middle, and until then only the set with the fewest reps adds one.
    static func weightOrRepStep(_ sets: [CompletedSet], exercise: ProgressionExerciseInfo, cap: Int) -> Prescription {
        let canLoad = sets.allSatisfy { set in
            guard let weight = set.weight else { return false }
            return weight > 0 || exercise.addsToBodyweight
        }
        let heavy = sets.contains { ($0.weight ?? 0) >= heavyLoadTenthsPounds }
        let pastMiddle = sets.allSatisfy { 2 * $0.reps >= exercise.minReps + exercise.maxReps }
        let loadReadyReps = Int((loadReadyRepFraction * Double(exercise.maxReps)).rounded(.up))
        let nearTop = sets.contains { $0.reps >= loadReadyReps }

        if canLoad, pastMiddle || (!heavy && nearTop) {
            return Prescription(gate: .load, checkInSourcePain: nil, sets: sets.map {
                SetPrescription(plannedReps: min($0.reps, cap), plannedWeightTenthsPounds: ($0.weight ?? 0) + loadIncrementTenthsPounds)
            })
        }
        let fewest = sets.indices.min { sets[$0].reps < sets[$1].reps }
        return Prescription(gate: .reps, checkInSourcePain: nil, sets: sets.indices.map { index in
            let adds = !(canLoad && heavy) || index == fewest
            return SetPrescription(
                plannedReps: min(sets[index].reps + (adds ? 1 : 0), cap),
                plannedWeightTenthsPounds: sets[index].weight
            )
        })
    }

    /// Bodyweight has no weight to add, so every set adds half the reps left, and a half rep waits for the next.
    static func halfRepStep(_ sets: [CompletedSet], repsInReserve: Int, carry: Int, cap: Int) -> Prescription {
        let halves = carry + repsInReserve
        return Prescription(
            gate: .reps,
            checkInSourcePain: nil,
            sets: sets.map { SetPrescription(plannedReps: min($0.reps + halves / 2, cap), plannedWeightTenthsPounds: $0.weight) },
            repCarryHalves: halves % 2
        )
    }

    static func fitsWeeklyMuscleCap(_ exercise: ProgressionExerciseInfo, credits: [Muscle: Double]) -> Bool {
        setCredits(primary: exercise.primaryMuscle, secondary: exercise.secondaryMuscles)
            .allSatisfy { muscle, added in
                credits[muscle, default: 0] + added <= weeklyMuscleSetCap
            }
    }

    /// Done with the aim's reps left or more, pain no worse than noticeable, and every set inside the range.
    static func isCleanWeek(_ history: ProgressionHistory?, exercise: ProgressionExerciseInfo) -> Bool {
        guard
            let history,
            history.status != .skipped,
            let pain = history.pain,
            let effort = history.effort,
            pain.rawValue <= LevelOfPain.noticeable.rawValue,
            repsInReserve(effort) >= cleanWeekRepsInReserve
        else {
            return false
        }
        let sets = completedSets(history)
        return !sets.isEmpty && sets.allSatisfy { $0.reps >= exercise.minReps }
    }
}
