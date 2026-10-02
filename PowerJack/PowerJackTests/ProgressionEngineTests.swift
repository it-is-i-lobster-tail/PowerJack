//
//  ProgressionEngineTests.swift
//  PowerJackTests
//

import Testing
@testable import PowerJack

@MainActor
struct ProgressionEngineTests {
    private let chestPress = ProgressionExerciseInfo(
        minReps: 6,
        maxReps: 12,
        primaryMuscle: .chest,
        secondaryMuscles: [.triceps, .shoulders],
        repsOnly: false
    )

    // MARK: Hold rules

    @Test("Severe pain repeats the logged sets and requires a check-in")
    func highPain() {
        let result = next(current: history(sets: [(10, 1000), (10, 1000)], pain: .severe))
        #expect(result.gate == .highPain)
        #expect(result.checkInSourcePain == .severe)
        #expect(result.sets == [prescription(10, 1000), prescription(10, 1000)])
    }

    @Test("Extreme pain also requires a check-in, ahead of the under-minimum rule")
    func extremePainBeatsUnderMinimum() {
        let result = next(current: history(sets: [(3, 1000)], pain: .extreme))
        #expect(result.gate == .highPain)
        #expect(result.checkInSourcePain == .extreme)
    }

    @Test("Under-minimum keeps successful sets plus the first miss, raised to the minimum")
    func underMinimum() {
        let result = next(current: history(sets: [(8, 1000), (5, 1000), (4, 1000)]))
        #expect(result.gate == .underMinimum)
        #expect(result.sets == [prescription(8, 1000), prescription(6, 1000)])
    }

    @Test("Moderate pain repeats the logged sets")
    func moderatePain() {
        let result = next(current: history(sets: [(10, 1000)], pain: .moderate))
        #expect(result.gate == .moderatePain)
        #expect(result.sets == [prescription(10, 1000)])
    }

    @Test("Brutal effort repeats the logged sets")
    func maxEffort() {
        let result = next(current: history(sets: [(10, 1000)], effort: .brutal))
        #expect(result.gate == .maxEffort)
        #expect(result.sets == [prescription(10, 1000)])
    }

    @Test("Missing feedback holds the logged sets")
    func missingFeedbackHolds() {
        var current = history(sets: [(9, 1000)])
        current.pain = nil
        let result = next(current: current)
        #expect(result.gate == .held)
        #expect(result.sets == [prescription(9, 1000)])
    }

    @Test("A skipped exercise with nothing logged carries its plan forward")
    func skippedCarriesPlan() {
        let current = ProgressionHistory(
            programWeek: 1,
            status: .skipped,
            pain: nil,
            effort: nil,
            sets: [
                ProgressionSet(plannedReps: 10, plannedWeightTenthsPounds: 900, actualReps: nil, actualWeightTenthsPounds: nil, status: .skipped),
            ]
        )
        let result = next(current: current)
        #expect(result.gate == .held)
        #expect(result.sets == [prescription(10, 900)])
    }

    @Test("A check-in resolved with skip keeps holding and asks again")
    func skippedCheckInCarriesForward() {
        let current = ProgressionHistory(
            programWeek: 2,
            status: .skipped,
            pain: nil,
            effort: nil,
            checkIn: .resolved,
            checkInSourcePain: .severe,
            sets: [
                ProgressionSet(plannedReps: 10, plannedWeightTenthsPounds: 900, actualReps: nil, actualWeightTenthsPounds: nil, status: .skipped),
            ]
        )
        let result = next(current: current)
        #expect(result.gate == .skippedCarryForward)
        #expect(result.checkInSourcePain == .severe)
        #expect(result.sets == [prescription(10, 900)])
    }

    // MARK: Volume

    @Test("Focus muscles add a set after two eligible weeks")
    func focusVolume() {
        let result = next(
            current: history(week: 2, sets: [(10, 1000), (10, 1000)]),
            previous: history(week: 1, sets: [(9, 1000), (9, 1000)]),
            focus: [.chest]
        )
        #expect(result.gate == .focusVolume)
        #expect(result.sets.count == 3)
        #expect(result.sets.last == SetPrescription(plannedReps: nil, plannedWeightTenthsPounds: 1000))
    }

    @Test("Non-focus muscles need three eligible weeks")
    func nonFocusVolume() {
        let twoWeeks = next(
            current: history(week: 3, sets: [(10, 1000)]),
            previous: history(week: 2, sets: [(10, 1000)])
        )
        #expect(twoWeeks.gate != .nonFocusVolume)

        let threeWeeks = next(
            current: history(week: 3, sets: [(10, 1000)]),
            previous: history(week: 2, sets: [(10, 1000)]),
            twoWeeksAgo: history(week: 1, sets: [(10, 1000)])
        )
        #expect(threeWeeks.gate == .nonFocusVolume)
    }

    @Test("Effort above the program-progress ceiling blocks volume")
    func effortCeiling() {
        #expect(ProgressionEngine.targetEffortCeiling(programWeek: 2, programLengthWeeks: 10) == 2)
        #expect(ProgressionEngine.targetEffortCeiling(programWeek: 5, programLengthWeeks: 10) == 3)
        #expect(ProgressionEngine.targetEffortCeiling(programWeek: 6, programLengthWeeks: 10) == 4)

        // Week 1 of 4 allows effort 3 at most; "very hard" (4) is too hard to add volume.
        let result = next(
            current: history(week: 2, sets: [(10, 1000)]),
            previous: history(week: 1, sets: [(10, 1000)], effort: .veryHard),
            focus: [.chest]
        )
        #expect(result.gate != .focusVolume)
    }

    @Test("The weekly muscle cap allows exactly 25 sets")
    func weeklyCap() {
        let atCap = next(
            current: history(week: 2, sets: [(10, 1000)]),
            previous: history(week: 1, sets: [(10, 1000)]),
            focus: [.chest],
            credits: [.chest: 24]
        )
        #expect(atCap.gate == .focusVolume)

        let overCap = next(
            current: history(week: 2, sets: [(10, 1000)]),
            previous: history(week: 1, sets: [(10, 1000)]),
            focus: [.chest],
            credits: [.chest: 24, .triceps: 24.75]
        )
        #expect(overCap.gate != .focusVolume)
    }

    @Test("Volume stops at the max working sets")
    func maxSets() {
        let sets = Array(repeating: (10, 1000), count: WorkoutExercise.maxSets)
        let result = next(
            current: history(week: 2, sets: sets),
            previous: history(week: 1, sets: sets),
            focus: [.chest]
        )
        #expect(result.gate != .focusVolume)
        #expect(result.sets.count == WorkoutExercise.maxSets)
    }

    // MARK: Load and reps

    @Test("Load adds 5 lb when every set reaches 85% of max reps")
    func load() {
        let result = next(current: history(sets: [(11, 1350), (11, 1350)]))
        #expect(result.gate == .load)
        #expect(result.sets == [prescription(11, 1400), prescription(11, 1400)])
    }

    @Test("Load is refused when 5 lb is more than 10% of the weight")
    func loadRelativeJump() {
        let result = next(current: history(sets: [(12, 400)]))
        #expect(result.gate == .reps)
        #expect(result.sets == [prescription(12, 400)])
    }

    @Test("Reps-only exercises never add load")
    func repsOnly() {
        var exercise = chestPress
        exercise.repsOnly = true
        let result = next(current: history(sets: [(11, nil)]), exercise: exercise)
        #expect(result.gate == .reps)
        #expect(result.sets == [prescription(12, nil)])
    }

    @Test("Rep progression adds one rep, capped at the exercise max")
    func repProgression() {
        let result = next(current: history(sets: [(9, 1000), (12, 400)]))
        #expect(result.gate == .reps)
        #expect(result.sets == [prescription(10, 1000), prescription(12, 400)])
    }

    @Test("Logged weight falls back to the planned weight")
    func plannedWeightFallback() {
        var current = history(sets: [(11, nil)])
        current.sets[0].plannedWeightTenthsPounds = 1350
        let result = next(current: current)
        #expect(result.gate == .load)
        #expect(result.sets == [prescription(11, 1400)])
    }

    // MARK: Helpers

    private func next(
        current: ProgressionHistory,
        previous: ProgressionHistory? = nil,
        twoWeeksAgo: ProgressionHistory? = nil,
        exercise: ProgressionExerciseInfo? = nil,
        focus: Set<Muscle> = [],
        credits: [Muscle: Double] = [:]
    ) -> Prescription {
        ProgressionEngine.nextPrescription(
            ProgressionInput(
                current: current,
                previous: previous,
                twoWeeksAgo: twoWeeksAgo,
                exercise: exercise ?? chestPress,
                focusMuscles: focus,
                programLengthWeeks: 4,
                currentWeekMuscleSetCredits: credits
            )
        )
    }

    private func history(
        week: Int = 1,
        sets: [(Int, Int?)],
        effort: LevelOfEffort = .easy,
        pain: LevelOfPain = .none
    ) -> ProgressionHistory {
        ProgressionHistory(
            programWeek: week,
            status: .complete,
            pain: pain,
            effort: effort,
            sets: sets.map { reps, weight in
                ProgressionSet(
                    plannedReps: nil,
                    plannedWeightTenthsPounds: nil,
                    actualReps: reps,
                    actualWeightTenthsPounds: weight,
                    status: .complete
                )
            }
        )
    }

    private func prescription(_ reps: Int?, _ weight: Int?) -> SetPrescription {
        SetPrescription(plannedReps: reps, plannedWeightTenthsPounds: weight)
    }
}
