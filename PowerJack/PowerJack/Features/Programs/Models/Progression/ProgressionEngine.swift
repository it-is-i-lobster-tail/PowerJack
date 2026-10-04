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
}

struct ProgressionInput {
    var current: ProgressionHistory
    var previous: ProgressionHistory?
    var twoWeeksAgo: ProgressionHistory?
    var exercise: ProgressionExerciseInfo
    var focusMuscles: Set<Muscle>
    var programLengthWeeks: Int
    /// Completed set credits per muscle in `current`'s program week.
    var currentWeekMuscleSetCredits: [Muscle: Double]
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
    case focusVolume
    case nonFocusVolume
    case load
    case reps
}

struct Prescription: Equatable {
    var gate: ProgressionGate
    /// Non-nil when the next exercise must wait on a manual check-in.
    var checkInSourcePain: LevelOfPain?
    var sets: [SetPrescription]
}

enum ProgressionEngine {
    static let loadIncrementTenthsPounds = 50
    static let loadReadyRepFraction = 0.85
    static let weeklyMuscleSetCap = 25.0
    static let primaryMuscleSetCredit = 1.0
    static let secondaryMuscleSetCredit = 0.5

    static var maxWorkingSets: Int { WorkoutExercise.maxSets }

    static func nextPrescription(_ input: ProgressionInput) -> Prescription {
        let current = input.current
        let exercise = input.exercise

        // A check-in that ended in "skip" keeps holding the same prescription.
        if current.status == .skipped,
           current.checkIn == .resolved,
           let sourcePain = current.checkInSourcePain {
            return Prescription(
                gate: .skippedCarryForward,
                checkInSourcePain: sourcePain,
                sets: carryForward(current.sets)
            )
        }

        let completed = completedSets(current)

        guard !completed.isEmpty else {
            return Prescription(gate: .held, checkInSourcePain: nil, sets: carryForward(current.sets))
        }

        guard let pain = current.pain, let effort = current.effort else {
            return Prescription(gate: .held, checkInSourcePain: nil, sets: copyActual(completed))
        }

        if pain.rawValue >= LevelOfPain.severe.rawValue {
            return Prescription(gate: .highPain, checkInSourcePain: pain, sets: copyActual(completed))
        }

        if let firstUnder = completed.firstIndex(where: { $0.reps < exercise.minReps }) {
            let retained = completed.enumerated().filter { index, set in
                set.reps >= exercise.minReps || index == firstUnder
            }
            return Prescription(
                gate: .underMinimum,
                checkInSourcePain: nil,
                sets: retained.map { _, set in
                    SetPrescription(
                        plannedReps: max(set.reps, exercise.minReps),
                        plannedWeightTenthsPounds: set.weight
                    )
                }
            )
        }

        if pain == .moderate {
            return Prescription(gate: .moderatePain, checkInSourcePain: nil, sets: copyActual(completed))
        }

        if effort == .brutal {
            return Prescription(gate: .maxEffort, checkInSourcePain: nil, sets: copyActual(completed))
        }

        let isFocus = input.focusMuscles.contains(exercise.primaryMuscle)
        let canAddSet = completed.count < maxWorkingSets &&
            fitsWeeklyMuscleCap(exercise, credits: input.currentWeekMuscleSetCredits)
        let eligible = { (history: ProgressionHistory?) in
            isEligibleForVolume(history, exercise: exercise, programLengthWeeks: input.programLengthWeeks)
        }

        if canAddSet, eligible(current), eligible(input.previous) {
            if isFocus {
                return addVolumeSet(.focusVolume, completed)
            }
            if eligible(input.twoWeeksAgo) {
                return addVolumeSet(.nonFocusVolume, completed)
            }
        }

        let loadReadyReps = Int((loadReadyRepFraction * Double(exercise.maxReps)).rounded(.up))
        let canIncreaseLoad = !exercise.repsOnly && completed.allSatisfy { set in
            guard let weight = set.weight, weight > 0 else { return false }
            return set.reps >= loadReadyReps
        }

        if canIncreaseLoad {
            return Prescription(
                gate: .load,
                checkInSourcePain: nil,
                sets: completed.map {
                    SetPrescription(
                        plannedReps: $0.reps,
                        plannedWeightTenthsPounds: ($0.weight ?? 0) + loadIncrementTenthsPounds
                    )
                }
            )
        }

        let repCap = min(exercise.maxReps, Exercise.maxRepsAllowed)
        return Prescription(
            gate: .reps,
            checkInSourcePain: nil,
            sets: completed.map {
                SetPrescription(
                    plannedReps: min($0.reps + 1, repCap),
                    plannedWeightTenthsPounds: $0.weight
                )
            }
        )
    }

    /// Effort allowed for volume increases at a given point in the program.
    static func targetEffortCeiling(programWeek: Int, programLengthWeeks: Int) -> Int {
        let progress = Double(programWeek) / Double(max(1, programLengthWeeks))
        if progress <= 0.2 { return 2 }
        if progress <= 0.5 { return 3 }
        return 4
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

    static func copyActual(_ sets: [CompletedSet]) -> [SetPrescription] {
        sets.map { SetPrescription(plannedReps: $0.reps, plannedWeightTenthsPounds: $0.weight) }
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

    static func addVolumeSet(_ gate: ProgressionGate, _ sets: [CompletedSet]) -> Prescription {
        Prescription(
            gate: gate,
            checkInSourcePain: nil,
            sets: copyActual(sets) + [
                SetPrescription(plannedReps: nil, plannedWeightTenthsPounds: sets.last?.weight),
            ]
        )
    }

    static func fitsWeeklyMuscleCap(_ exercise: ProgressionExerciseInfo, credits: [Muscle: Double]) -> Bool {
        setCredits(primary: exercise.primaryMuscle, secondary: exercise.secondaryMuscles)
            .allSatisfy { muscle, added in
                credits[muscle, default: 0] + added <= weeklyMuscleSetCap
            }
    }

    static func isEligibleForVolume(
        _ history: ProgressionHistory?,
        exercise: ProgressionExerciseInfo,
        programLengthWeeks: Int
    ) -> Bool {
        guard
            let history,
            history.status != .skipped,
            let pain = history.pain,
            let effort = history.effort,
            pain.rawValue <= LevelOfPain.noticeable.rawValue,
            effort.rawValue <= targetEffortCeiling(
                programWeek: history.programWeek,
                programLengthWeeks: programLengthWeeks
            )
        else {
            return false
        }
        let sets = completedSets(history)
        return !sets.isEmpty && sets.allSatisfy { $0.reps >= exercise.minReps }
    }
}
