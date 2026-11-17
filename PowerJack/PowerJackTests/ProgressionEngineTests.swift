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

    @Test("A focus muscle adds a set after one clean week, on top of the rep step")
    func focusVolume() {
        let result = next(current: history(sets: [(8, 1000), (8, 1000)]), focus: [.chest])
        #expect(result.gate == .reps)
        #expect(result.addedSet)
        #expect(result.sets == [prescription(9, 1000), prescription(9, 1000), prescription(6, 1000)])
    }

    @Test("An added set uses the last set's logged weight with 3 fewer reps, next to a weight step")
    func addedSetTargets() {
        let result = next(current: history(sets: [(12, 1000), (11, 950)]), focus: [.chest])
        #expect(result.gate == .load)
        #expect(result.sets == [prescription(12, 1050), prescription(11, 1000), prescription(8, 950)])
    }

    @Test("Other muscles need two clean weeks in a row")
    func nonFocusVolume() {
        let oneWeek = next(current: history(week: 2, sets: [(8, 1000)]))
        #expect(!oneWeek.addedSet)
        #expect(oneWeek.sets == [prescription(9, 1000)])

        let twoWeeks = next(
            current: history(week: 2, sets: [(8, 1000)]),
            previous: history(week: 1, sets: [(8, 1000)])
        )
        #expect(twoWeeks.addedSet)
        #expect(twoWeeks.sets == [prescription(9, 1000), prescription(6, 1000)])
    }

    @Test("A week with fewer than 2 reps left isn't clean")
    func cleanWeekNeedsTwoRepsLeft() {
        let result = next(
            current: history(week: 2, sets: [(8, 1000)]),
            previous: history(week: 1, sets: [(8, 1000)], effort: .veryHard)
        )
        #expect(!result.addedSet)

        let onAim = next(
            current: history(week: 2, sets: [(8, 1000)], effort: .challenge),
            previous: history(week: 1, sets: [(8, 1000)], effort: .challenge)
        )
        #expect(onAim.addedSet)
    }

    @Test("The weekly muscle cap allows exactly 25 sets")
    func weeklyCap() {
        let atCap = next(current: history(sets: [(10, 1000)]), focus: [.chest], credits: [.chest: 24])
        #expect(atCap.addedSet)

        let overCap = next(current: history(sets: [(10, 1000)]), focus: [.chest], credits: [.chest: 24, .triceps: 24.75])
        #expect(!overCap.addedSet)
    }

    @Test("Volume stops at the max working sets")
    func maxSets() {
        let sets = Array(repeating: (8, 1000), count: WorkoutExercise.maxSets)
        let result = next(current: history(sets: sets), focus: [.chest])
        #expect(!result.addedSet)
        #expect(result.sets.count == WorkoutExercise.maxSets)
    }

    // MARK: Load and reps

    @Test("Load adds 5 lb when every set reaches 85% of max reps")
    func load() {
        let result = next(current: history(sets: [(11, 1350), (11, 1350)]))
        #expect(result.gate == .load)
        #expect(result.sets == [prescription(11, 1400), prescription(11, 1400)])
    }

    @Test("One set near the top of the range is enough to add weight, and every set keeps its reps")
    func loadFromOneSet() {
        let result = next(current: history(sets: [(12, 1000), (7, 1000)]))
        #expect(result.gate == .load)
        #expect(result.sets == [prescription(12, 1050), prescription(7, 1050)])
    }

    @Test("Every set past the middle of the range adds weight")
    func loadPastMiddle() {
        let result = next(current: history(sets: [(9, 1000), (9, 1000)]))
        #expect(result.gate == .load)
        #expect(result.sets == [prescription(9, 1050), prescription(9, 1050)])
    }

    @Test("Light weights still add 5 lb and keep the reps")
    func loadLightWeight() {
        let result = next(current: history(sets: [(12, 200), (11, 200)]))
        #expect(result.gate == .load)
        #expect(result.sets == [prescription(12, 250), prescription(11, 250)])
    }

    @Test("Rep progression adds one rep to every set")
    func repProgression() {
        let result = next(current: history(sets: [(8, 1000), (7, 1000)]))
        #expect(result.gate == .reps)
        #expect(result.sets == [prescription(9, 1000), prescription(8, 1000)])
    }

    @Test("Reps above the range come back to its top, whatever the week")
    func repsNeverPassMax() {
        let load = next(current: history(sets: [(14, 1000), (13, 1000)]))
        #expect(load.sets == [prescription(12, 1050), prescription(12, 1050)])

        let held = next(current: history(sets: [(14, 1000)], effort: .brutal))
        #expect(held.gate == .maxEffort)
        #expect(held.sets == [prescription(12, 1000)])
    }

    @Test("From 200 lb, the set with the fewest reps adds one until every set is past the middle")
    func heavyLoad() {
        let squat = ProgressionExerciseInfo(minReps: 5, maxReps: 8, primaryMuscle: .quads, secondaryMuscles: [.glutes], repsOnly: false)
        let first = next(current: history(sets: [(7, 4000), (6, 4000), (5, 4000)]), exercise: squat)
        #expect(first.gate == .reps)
        #expect(first.sets == [prescription(7, 4000), prescription(6, 4000), prescription(6, 4000)])

        let second = next(current: history(sets: [(7, 4000), (6, 4000), (6, 4000)]), exercise: squat)
        #expect(second.sets == [prescription(7, 4000), prescription(7, 4000), prescription(6, 4000)])

        // A set near the top doesn't add weight on its own once the lift is heavy.
        let nearTop = next(current: history(sets: [(8, 4000), (6, 4000), (6, 4000)]), exercise: squat)
        #expect(nearTop.gate == .reps)

        let ready = next(current: history(sets: [(7, 4000), (7, 4000), (7, 4000)]), exercise: squat)
        #expect(ready.gate == .load)
        #expect(ready.sets == Array(repeating: prescription(7, 4050), count: 3))
    }

    @Test("Reps-only exercises add half the reps left, banking a half rep for next week")
    func repsOnly() {
        var exercise = chestPress
        exercise.repsOnly = true
        // 3 reps left: one more rep, half a rep banked.
        let first = next(current: history(sets: [(8, nil), (7, nil)]), exercise: exercise)
        #expect(first.gate == .reps)
        #expect(first.sets == [prescription(9, nil), prescription(8, nil)])
        #expect(first.repCarryHalves == 1)

        // 3 reps left again, plus the banked half: two more reps.
        let second = next(current: history(sets: [(9, nil), (8, nil)]), exercise: exercise, carry: 1)
        #expect(second.sets == [prescription(11, nil), prescription(10, nil)])
        #expect(second.repCarryHalves == 0)

        // 1 rep left banks half a rep and adds none.
        let close = next(current: history(sets: [(9, nil)], effort: .veryHard), exercise: exercise)
        #expect(close.sets == [prescription(9, nil)])
        #expect(close.repCarryHalves == 1)

        // A held week keeps the banked half.
        let held = next(current: history(sets: [(9, nil)], pain: .moderate), exercise: exercise, carry: 1)
        #expect(held.repCarryHalves == 1)
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
        exercise: ProgressionExerciseInfo? = nil,
        focus: Set<Muscle> = [],
        credits: [Muscle: Double] = [:],
        carry: Int = 0
    ) -> Prescription {
        ProgressionEngine.nextPrescription(
            ProgressionInput(
                current: current,
                previous: previous,
                exercise: exercise ?? chestPress,
                focusMuscles: focus,
                currentWeekMuscleSetCredits: credits,
                repCarryHalves: carry
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
