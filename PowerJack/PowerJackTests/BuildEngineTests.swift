//
//  BuildEngineTests.swift
//  PowerJackTests
//
//  The Build engine against the hypertrophy rulebook. Rule IDs in test names point at the rule tested.
//

import Foundation
import Testing
@testable import PowerJack

@MainActor
struct BuildEngineTests {
    private let bench = BuildExercise(minReps: 6, maxReps: 12, primary: .chest, secondary: [.triceps], fatigueLevel: .high)
    private let fly = BuildExercise(minReps: 10, maxReps: 20, primary: .chest, fatigueLevel: .low)
    private let raise = BuildExercise(minReps: 10, maxReps: 20, primary: .shoulders, fatigueLevel: .low)
    private let pullUp = BuildExercise(minReps: 5, maxReps: 15, primary: .back, repsOnly: true, fatigueLevel: .moderate)

    // MARK: Effort scale and e1RM

    @Test("RIR-05, LOAD-05: the rep table matches the rulebook's test vectors")
    func repTableVectors() throws {
        let vectors: [(load: Int, reps: Int, rir: Int, max: Double, nextReps: Double)] = [
            (2250, 8, 2, 282.7, 9.1),
            (1850, 12, 2, 258.4, 13.0),
            (500, 15, 1, 74.1, 12.7),
            (150, 20, 2, 26.7, 12.4),
            (100, 24, 2, 20.0, 12.3),
        ]
        for vector in vectors {
            let estimated = try #require(EstimatedMax(loadTenths: vector.load, reps: vector.reps, repsInReserve: vector.rir))
            #expect(abs(estimated.tenths / 10 - vector.max) < 0.05, "\(vector)")
            let next = try #require(estimated.repsToFailure(atTenths: vector.load + 50))
            #expect(abs(next - vector.nextReps) < 0.05, "\(vector)")
        }
        // 185 x 12 at 2 left, then 190 lb aiming for 2 left: 11 reps.
        let bench = try #require(EstimatedMax(loadTenths: 1850, reps: 12, repsInReserve: 2))
        #expect(bench.reps(atTenths: 1900, leaving: 2) == 11)
        #expect(EstimatedMax(loadTenths: 1000, reps: 10, repsInReserve: 5)?.isLowerBound == true)
        #expect(EstimatedMax(loadTenths: 1000, reps: 40, repsInReserve: 0) == nil)
    }

    @Test("RIR-01: reps left are stored as 5 minus reps left, tagged with scale version 2")
    func repsInReserveStorage() {
        let feedback = ExerciseFeedback(repsInReserve: .one, levelOfPain: .mild)
        #expect(feedback.levelOfEffort.rawValue == 4)
        #expect(feedback.effortScaleVersion == 2)
        #expect(feedback.repsInReserve == .one)
        #expect(ExerciseFeedback(levelOfEffort: .veryHard, levelOfPain: .none).repsInReserve == nil)
        #expect(RepsInReserve.fiveOrMore.valueText == "5+")
    }

    @Test("EFF-06: a rating is on target within 1 rep, 2 above 12 reps; misses and untapped ratings never read easy")
    func effortReadings() {
        func kind(_ effort: BuildEffort, reps: [Int] = [10, 10], target: Int = 10, exercise: BuildExercise? = nil) -> EffortReading.Kind {
            let slot = BuildSlot(workout: 0, exercise: exercise ?? fly, history: [
                exposure(0, reps: reps, target: target, load: 500, effort: effort, aim: 2),
            ])
            let context = BuildContext(BuildInput(weeks: [week(1)], slots: [slot]))
            return context.reading(0, slot.history[0]).kind
        }
        #expect(kind(.tapped(1)) == .onTarget)
        #expect(kind(.tapped(3)) == .onTarget)
        #expect(kind(.tapped(4)) == .easier)
        #expect(kind(.tapped(0)) == .harder)
        #expect(kind(.tapped(2), reps: [10, 9]) == .harder)
        #expect(kind(.legacy(4)) == .unrated)
        #expect(kind(.missing) == .unrated)
        #expect(kind(.missing, reps: [10, 9]) == .harder)
        // Above 12 reps the band widens to 2.
        #expect(kind(.tapped(4), reps: [15, 15], target: 15) == .onTarget)
        // A 0 on a heavy lift is harder; a light lift may go to failure.
        #expect(kind(.tapped(1), exercise: bench) == .onTarget)
        let heavy = BuildSlot(workout: 0, exercise: bench, history: [
            exposure(0, reps: [10, 10], target: 10, load: 1000, effort: .tapped(0), aim: 1),
        ])
        #expect(BuildContext(BuildInput(weeks: [week(4)], slots: [heavy])).reading(0, heavy.history[0]).kind == .harder)
    }

    @Test("EFF-01, EFF-04, EFF-05: aims ramp 3, 2, 2, 1; failure is offered to light lifts in the last build week")
    func aims() {
        #expect((1...4).map { BuildEngine.aim(for: week($0), exercise: bench, reps: 10, failureBlocked: false) } == [3, 2, 2, 1])
        #expect(BuildEngine.aim(for: week(4), exercise: fly, reps: 12, failureBlocked: false) == 0)
        #expect(BuildEngine.aim(for: week(4), exercise: fly, reps: 12, failureBlocked: true) == 1)
        #expect(BuildEngine.aim(for: week(2), exercise: fly, reps: 15, failureBlocked: false) == 1)
        #expect(BuildEngine.aim(for: week(2), exercise: pullUp, reps: 8, failureBlocked: false) == 1)
        #expect(BuildEngine.aim(for: week(1), exercise: pullUp, reps: 8, failureBlocked: false) == 2)
        #expect(BuildEngine.aim(for: BuildWeek(kind: .deload, blockWeek: 5), exercise: fly, reps: 12, failureBlocked: false) == 3)
        #expect(BuildEngine.aim(for: week(2), exercise: bench, reps: 10, failureBlocked: false, calibrating: true) == 3)
    }

    // MARK: Load and reps

    @Test("LOAD-02: on target adds a rep, easier adds two, from the reps actually done")
    func addReps() throws {
        let onTarget = try slotPlan(bench, [exposure(0, reps: [8, 8], target: 8, load: 1000, effort: .tapped(3), aim: 3)])
        #expect(onTarget.reps == 9)
        #expect(onTarget.load == 1000)
        #expect(onTarget.reason.code == .repsUp)

        let easier = try slotPlan(bench, [exposure(0, reps: [9, 9], target: 9, load: 1000, effort: .tapped(4), aim: 2)])
        #expect(easier.reps == 11)
        #expect(easier.rirTarget == 2)
    }

    @Test("LOAD-03, LOAD-04, LOAD-05: every set at the top with the planned reps left adds 5 lb and resets reps")
    func loadStep() throws {
        let plan = try slotPlan(bench, [exposure(0, reps: [12, 12], target: 12, load: 1850, effort: .tapped(2), aim: 2)])
        #expect(plan.load == 1900)
        #expect(plan.reps == 11)
        #expect(plan.reason.code == .loadUp)

        // At the top but harder than planned: hold.
        let hold = try slotPlan(bench, [exposure(0, reps: [12, 12], target: 12, load: 1850, effort: .tapped(1), aim: 2)])
        #expect(hold.load == 1850)
        #expect(hold.reps == 12)
        #expect(hold.reason.code == .holdHard)
    }

    @Test("LOAD-04: a light lift climbs past its range until 5 lb fits, then steps, and holds at 30 reps")
    func lightLifts() throws {
        // Above 12 reps the next aim is 1 left (EFF-05), so reps reset to 11.
        let fifteen = try slotPlan(fly, [exposure(0, reps: [20, 20], target: 20, load: 150, effort: .tapped(2), aim: 2)])
        #expect(fifteen.load == 200)
        #expect(fifteen.reps == 11)

        let ten = try slotPlan(raise, [exposure(0, reps: [20, 20], target: 20, load: 100, effort: .tapped(2), aim: 2)])
        #expect(ten.load == 100)
        #expect(ten.reps == 21)
        #expect(ten.reason.message.contains("50%"))

        let extended = try slotPlan(raise, [exposure(0, reps: [24, 24], target: 24, load: 100, effort: .tapped(2), aim: 2)])
        #expect(extended.load == 150)
        #expect(extended.reps == 11)

        let stuck = try slotPlan(raise, [exposure(0, reps: [30, 30], target: 30, load: 50, effort: .tapped(2), aim: 2)])
        #expect(stuck.load == 50)
        #expect(stuck.reps == 30)
        #expect(stuck.reason.code == .stepTooLarge)
    }

    @Test("LOAD-04: at the heaviest load a set can log, reps climb instead of the load passing it")
    func heaviestLoad() throws {
        let legPress = BuildExercise(minReps: 5, maxReps: 12, primary: .quads, fatigueLevel: .high)
        let ready = try slotPlan(legPress, [exposure(0, reps: [12, 12], target: 12, load: 10_000, effort: .tapped(2), aim: 2)])
        #expect(ready.load == 10_000)
        #expect(ready.reps == 13)
        #expect(ready.reason.code == .repsUp)

        // At the end of the longer range it holds, saying why.
        let longest = try slotPlan(legPress, [exposure(0, reps: [22, 22], target: 22, load: 10_000, effort: .tapped(2), aim: 2)])
        #expect(longest.load == 10_000)
        #expect(longest.reps == 22)
        #expect(longest.reason.code == .stepTooLarge)

        // Two easy weeks jump at most to the heaviest load.
        let jump = try slotPlan(legPress, [
            exposure(0, reps: [8, 8], target: 8, load: 9_500, effort: .tapped(5), aim: 2),
            exposure(1, reps: [8, 8], target: 8, load: 9_500, effort: .tapped(4), aim: 1),
        ], weeks: [week(2), week(3)])
        #expect(jump.load == 10_000)

        // A calibration re-derives the load, but no further than a set can log.
        let calibrated = try slotPlan(legPress, [
            exposure(0, reps: [20, 20], target: nil, load: 9_000, unplanned: true, effort: .tapped(3), aim: 3, code: .calibrate),
        ])
        #expect(calibrated.load == 10_000)
        #expect(calibrated.reason.code == .calibrated)
    }

    @Test("LOAD-06: far too easy steps 5 lb once, and jumps by the estimated max after two such weeks")
    func easyJump() throws {
        let once = try slotPlan(bench, [
            exposure(0, reps: [8, 8], target: 8, load: 2000, effort: .tapped(2), aim: 2),
            exposure(1, reps: [8, 8], target: 8, load: 2000, effort: .tapped(4), aim: 1),
        ], weeks: [week(2), week(3)])
        #expect(once.load == 2050)

        let twice = try slotPlan(bench, [
            exposure(0, reps: [8, 8], target: 8, load: 2000, effort: .tapped(5), aim: 2),
            exposure(1, reps: [8, 8], target: 8, load: 2000, effort: .tapped(4), aim: 1),
        ], weeks: [week(2), week(3)])
        #expect(twice.load == 2150)
        #expect(twice.reps == 8)
        #expect(twice.reason.message.hasPrefix("+15 lb"))
    }

    @Test("LOAD-07: one miss holds; a second in a row backs off 5% in whole steps and resets reps")
    func missesBackOff() throws {
        let missOnce = try slotPlan(bench, [
            exposure(0, reps: [8, 7], target: 8, load: 2250, effort: .tapped(1), aim: 2),
        ])
        #expect(missOnce.load == 2250)
        #expect(missOnce.reps == 8)
        #expect(missOnce.reason.code == .holdMiss)

        let missTwice = try slotPlan(bench, [
            exposure(0, reps: [8, 7], target: 8, load: 2250, effort: .tapped(1), aim: 2),
            exposure(1, reps: [8, 7], target: 8, load: 2250, effort: .tapped(1), aim: 2, code: .holdMiss),
        ], weeks: [week(1), week(2)])
        #expect(missTwice.load == 2150)
        #expect(missTwice.reps == 8)
        #expect(missTwice.reason.code == .loadDown)

        // Under 50 lb one step is too big a cut, so reps come down to what was done.
        let light = try slotPlan(fly, [
            exposure(0, reps: [15, 12], target: 15, load: 200, effort: .tapped(1), aim: 2),
            exposure(1, reps: [15, 12], target: 15, load: 200, effort: .tapped(1), aim: 2, code: .holdMiss),
        ], weeks: [week(1), week(2)])
        #expect(light.load == 200)
        #expect(light.reps == 12)
    }

    @Test("FREQ-05: a miss soon after a hard session counts half, so it takes three to back off")
    func shortGapMisses() throws {
        var first = exposure(0, reps: [8, 7], target: 8, load: 2250, effort: .tapped(1), aim: 2)
        first.shortGap = true
        var second = exposure(1, reps: [8, 7], target: 8, load: 2250, effort: .tapped(1), aim: 2, code: .holdMiss)
        second.shortGap = true
        let plan = try slotPlan(bench, [first, second], weeks: [week(1), week(2)])
        #expect(plan.reason.code == .holdMiss)
    }

    @Test("LOAD-09: bodyweight reps climb past the range to 40, then hold")
    func bodyweightReps() throws {
        let past = try slotPlan(pullUp, [exposure(0, reps: [15, 15], target: 15, load: nil, effort: .tapped(1), aim: 1)], weeks: [week(2)])
        #expect(past.reps == 16)
        #expect(past.load == nil)

        let capped = try slotPlan(pullUp, [exposure(0, reps: [40, 40], target: 40, load: nil, effort: .tapped(1), aim: 1)], weeks: [week(2)])
        #expect(capped.reps == 40)
        #expect(capped.reason.code == .repCap)
    }

    @Test("ENG-02: without a tapped rating, one rep at a time and 5 lb only after two weeks at the top")
    func unratedSteps() throws {
        let rep = try slotPlan(bench, [exposure(0, reps: [9, 9], target: 9, load: 1000, effort: .legacy(2), aim: 2)])
        #expect(rep.reps == 10)
        #expect(rep.reason.code == .unratedStep)

        let topOnce = try slotPlan(bench, [
            exposure(0, reps: [11, 11], target: 11, load: 1000, effort: .legacy(2), aim: 2),
            exposure(1, reps: [12, 12], target: 12, load: 1000, effort: .legacy(2), aim: 2),
        ], weeks: [week(1), week(2)])
        #expect(topOnce.load == 1000)
        #expect(topOnce.reps == 12)

        let topTwice = try slotPlan(bench, [
            exposure(0, reps: [12, 12], target: 12, load: 1000, effort: .missing, aim: 2),
            exposure(1, reps: [12, 12], target: 12, load: 1000, effort: .legacy(2), aim: 2),
        ], weeks: [week(1), week(2)])
        #expect(topTwice.load == 1050)
        #expect(topTwice.reps == bench.minReps)
    }

    // MARK: Starting

    @Test("START-05: a calibration week sets the next load from what was lifted, rising at most 25%")
    func calibration() throws {
        let calibrated = try slotPlan(bench, [
            exposure(0, reps: [11, 11], target: nil, load: 1350, unplanned: true, effort: .tapped(4), aim: 3, code: .calibrate),
        ])
        #expect(calibrated.load == 1400)
        #expect(calibrated.reps == 12)
        #expect(calibrated.reason.code == .calibrated)

        let capped = try slotPlan(bench, [
            exposure(0, reps: [20, 20], target: nil, load: 1000, unplanned: true, effort: .tapped(5), aim: 3, code: .calibrate),
        ])
        #expect(capped.load == 1250)
        #expect(capped.reps == 12)

        // Unrated: one more calibration week at the same weight.
        let again = try slotPlan(bench, [
            exposure(0, reps: [10, 10], target: nil, load: 1000, unplanned: true, effort: .missing, aim: 3, code: .calibrate),
        ])
        #expect(again.reason.code == .calibrate)
        #expect(again.load == 1000)
        #expect(again.rirTarget == 3)
    }

    // MARK: Pain

    @Test("PAIN-01: severe pain cuts 20% and half the sets behind a check-in; moderate holds")
    func painBands() throws {
        let severe = try slotPlan(bench, [
            exposure(0, sets: 3, reps: 10, target: 10, load: 1000, effort: .tapped(2), aim: 3, pain: .severe),
        ])
        #expect(severe.sets == 2)
        #expect(severe.load == 800)
        #expect(severe.checkInPain == .severe)
        #expect(severe.reason.code == .painCheckIn)
        #expect(!severe.reason.message.contains("professional"))

        let extreme = try slotPlan(bench, [exposure(0, reps: [10, 10], target: 10, load: 1000, effort: .tapped(2), aim: 3, pain: .extreme)])
        #expect(extreme.reason.message.contains("professional"))

        let moderate = try slotPlan(bench, [exposure(0, reps: [10, 10], target: 10, load: 1000, effort: .tapped(4), aim: 3, pain: .moderate)])
        #expect(moderate.load == 1000)
        #expect(moderate.reps == 10)
        #expect(moderate.reason.code == .painHold)
    }

    @Test("PAIN-02: moderate pain twice in a row takes 10% off")
    func painPersists() throws {
        let plan = try slotPlan(bench, [
            exposure(0, reps: [10, 10], target: 10, load: 1000, effort: .tapped(3), aim: 3, pain: .moderate),
            exposure(1, reps: [10, 10], target: 10, load: 1000, effort: .tapped(3), aim: 2, pain: .moderate, code: .painHold),
        ], weeks: [week(1), week(2)])
        #expect(plan.load == 900)
        #expect(plan.reason.code == .painReduce)
    }

    @Test("PAIN-01, PAIN-03: rising pain blocks increases; a settled hold resumes without jumps")
    func painReleases() throws {
        let rising = try slotPlan(bench, [
            exposure(0, reps: [8, 8], target: 8, load: 1000, effort: .tapped(3), aim: 3, pain: LevelOfPain.none),
            exposure(1, reps: [8, 8], target: 8, load: 1000, effort: .tapped(2), aim: 2, pain: .mild),
        ], weeks: [week(1), week(2)])
        #expect(rising.reps == 8)
        #expect(rising.reason.code == .painRising)

        // Held at Moderate, then back to None: progression resumes through reps, with no jump.
        let released = try slotPlan(bench, [
            exposure(0, reps: [8, 8], target: 8, load: 2000, effort: .tapped(3), aim: 3, pain: .moderate),
            exposure(1, reps: [8, 8], target: 8, load: 2000, effort: .tapped(5), aim: 2, pain: LevelOfPain.none, code: .painHold),
        ], weeks: [week(1), week(2)])
        #expect(released.load == 2000)
        #expect(released.reps == 10)
    }

    @Test("PAIN-03: a held exercise left unrated stays held; only a pain tap releases it")
    func untappedHold() throws {
        let plan = try slotPlan(bench, [
            exposure(0, reps: [8, 8], target: 8, load: 1000, effort: .tapped(3), aim: 3, pain: .moderate),
            exposure(1, reps: [8, 8], target: 8, load: 1000, effort: .missing, aim: 2, pain: nil, code: .painHold),
        ], weeks: [week(1), week(2)])
        #expect(plan.load == 1000)
        #expect(plan.reps == 8)
        #expect(plan.sets == 2)
        #expect(plan.reason.code == .painHold)
    }

    @Test("PAIN-02, ENG-02: a set a severe cut took comes back only after a rated exposure")
    func setBackNeedsRating() throws {
        let cut = [
            exposure(0, sets: 4, reps: 10, target: 10, load: 1000, effort: .tapped(2), aim: 3, pain: .severe),
            exposure(1, sets: 2, reps: 10, target: 10, load: 800, effort: .tapped(3), aim: 2, code: .painCheckIn),
        ]
        let weeks = [week(1), week(2), week(3)]
        let unrated = try slotPlan(bench, cut + [
            exposure(2, sets: 3, reps: 10, target: 10, load: 800, effort: .missing, aim: 2, pain: nil, code: .painSetBack),
        ], weeks: weeks)
        #expect(unrated.sets == 3)
        #expect(unrated.reason.code == .unratedStep)
        let legacy = try slotPlan(bench, cut + [
            exposure(2, sets: 3, reps: 10, target: 10, load: 800, effort: .legacy(2), aim: 2, code: .painSetBack),
        ], weeks: weeks)
        #expect(legacy.sets == 3)
        let rated = try slotPlan(bench, cut + [
            exposure(2, sets: 3, reps: 10, target: 10, load: 800, effort: .tapped(2), aim: 2, code: .painSetBack),
        ], weeks: weeks)
        #expect(rated.sets == 4)
        #expect(rated.reason.code == .painSetBack)
    }

    @Test("PAIN-03: a hold released in the deload resumes the next block from the cut, not the load before it")
    func releasedInDeload() throws {
        let row = BuildExercise(minReps: 6, maxReps: 12, primary: .back, fatigueLevel: .moderate)
        var history = (0..<3).map { exposure($0, sets: 1, reps: 10, target: 10, load: 1000, effort: .tapped(2), aim: 2) }
        history.append(exposure(3, sets: 1, reps: 10, target: 10, load: 1000, effort: .tapped(1), aim: 1, pain: .severe))
        let deload = BuildEngine.plan(BuildInput(weeks: (1...4).map(week), slots: [BuildSlot(workout: 0, exercise: row, history: history)]))
        let cut = try #require(deload.slots.first)
        #expect(deload.week.kind == .deload)
        #expect(cut.checkInPain == .severe)
        #expect(cut.load == 800)

        var pending = exposure(4, sets: cut.sets, reps: cut.reps ?? 10, target: cut.reps, load: cut.load, effort: .tapped(5), aim: 3, pain: .mild, code: cut.reason.code)
        pending.checkIn = .resolved
        pending.checkInSourcePain = .severe
        history.append(pending)
        let next = BuildEngine.plan(BuildInput(weeks: (1...4).map(week) + [deload.week], slots: [BuildSlot(workout: 0, exercise: row, history: history)]))
        #expect(next.week == week(1))
        #expect(next.slots.first?.load == 800)
    }

    // MARK: Blocks and deloads

    @Test("BLK-02, BLK-04: after 4 build weeks comes a deload with half the sets at 90%, same reps")
    func plannedDeload() throws {
        let plan = BuildEngine.plan(BuildInput(
            weeks: (1...4).map(week),
            slots: [
                BuildSlot(workout: 0, exercise: bench, history: (0..<4).map {
                    exposure($0, sets: 3, reps: 10, target: 10, load: 650, effort: .tapped(2), aim: 2)
                }),
                BuildSlot(workout: 0, exercise: raise, history: (0..<4).map {
                    exposure($0, sets: 4, reps: 12, target: 12, load: 200, effort: .tapped(2), aim: 2)
                }),
                BuildSlot(workout: 0, exercise: pullUp, history: (0..<4).map {
                    exposure($0, sets: 3, reps: 10, target: 10, load: nil, effort: .tapped(2), aim: 1)
                }),
            ]
        ))
        #expect(plan.week == BuildWeek(kind: .deload, blockWeek: 5))
        #expect(plan.slots.map(\.sets) == [2, 2, 2])
        #expect(plan.slots.map(\.load) == [550, 200, nil])
        // 20 lb would drop 25%, so the load stays and reps drop to 60%.
        #expect(plan.slots.map(\.reps) == [10, 7, 6])
        #expect(plan.slots.allSatisfy { $0.rirTarget == 3 && $0.reason.code == .deloadPlanned })
    }

    @Test("BLK-06: a new block keeps the last build load and sets reps for 3 left")
    func rebaseline() throws {
        var history = (0..<4).map { exposure($0, reps: [11, 11], target: 11, load: 1000, effort: .tapped(1), aim: 1) }
        history.append(exposure(4, reps: [11, 11], target: 11, load: 900, effort: .tapped(4), aim: 3, code: .deloadPlanned))
        let plan = BuildEngine.plan(BuildInput(
            weeks: (1...4).map(week) + [BuildWeek(kind: .deload, blockWeek: 5)],
            slots: [BuildSlot(workout: 0, exercise: bench, history: history)]
        ))
        #expect(plan.week == week(1))
        let slot = try #require(plan.slots.first)
        #expect(slot.load == 1000)
        #expect(slot.reps == 9)
        #expect(slot.rirTarget == 3)
        #expect(slot.reason.code == .blockRebase)
    }

    @Test("FREQ-06: a fully skipped build week repeats; a skipped deload still ends the block")
    func skippedWeeks() throws {
        let skipped = BuildEngine.plan(BuildInput(
            weeks: [week(1), week(2)],
            slots: [BuildSlot(workout: 0, exercise: bench, history: [
                exposure(0, reps: [8, 8], target: 8, load: 1000, effort: .tapped(3), aim: 3),
                exposure(1, sets: 2, reps: 9, target: 9, load: 1000, effort: .missing, aim: 2, done: false),
            ])]
        ))
        #expect(skipped.week == week(2))
        #expect(skipped.slots.first?.reps == 9)
        #expect(skipped.slots.first?.reason.code == .repeatNotDone)

        var history = (0..<4).map { exposure($0, reps: [10, 10], target: 10, load: 1000, effort: .tapped(2), aim: 2) }
        history.append(exposure(4, sets: 1, reps: 10, target: 10, load: 900, effort: .missing, aim: 3, code: .deloadPlanned, done: false))
        let afterDeload = BuildEngine.plan(BuildInput(
            weeks: (1...4).map(week) + [BuildWeek(kind: .deload, blockWeek: 5)],
            slots: [BuildSlot(workout: 0, exercise: bench, history: history)]
        ))
        #expect(afterDeload.week == week(1))
    }

    // MARK: Fatigue

    @Test("FAT-03: when 40% of lifts miss two build weeks running, next week is a deload")
    func reactiveDeload() throws {
        let missing = { (week: Int) in exposure(week, reps: [8, 6], target: 8, load: 1000, effort: .tapped(0), aim: 2) }
        let fine = { (week: Int) in exposure(week, reps: [8, 8], target: 8, load: 1000, effort: .tapped(2), aim: 2) }
        let plan = BuildEngine.plan(BuildInput(
            weeks: [week(1), week(2)],
            slots: [
                BuildSlot(workout: 0, exercise: bench, history: [missing(0), missing(1)]),
                BuildSlot(workout: 0, exercise: raise, history: [missing(0), missing(1)]),
                BuildSlot(workout: 1, exercise: pullUp, history: [fine(0), fine(1)]),
            ]
        ))
        #expect(plan.week == BuildWeek(kind: .deload, blockWeek: 3))
        #expect(plan.slots.allSatisfy { $0.reason.code == .deloadReactive })
    }

    @Test("FAT-02: a muscle fatigued two weeks running loses one set on a flagged slot, once a block")
    func localFatigueCut() throws {
        let missing = { (week: Int) in exposure(week, sets: 3, reps: 8, target: 8, load: 1000, effort: .tapped(0), aim: 2, missLast: true) }
        let fine = { (week: Int) in exposure(week, reps: [12, 12], target: 12, load: 1000, effort: .tapped(2), aim: 2) }
        let plan = BuildEngine.plan(BuildInput(
            weeks: [week(1), week(2)],
            slots: [
                BuildSlot(workout: 0, exercise: bench, history: [missing(0), missing(1)]),
                BuildSlot(workout: 0, exercise: raise, history: [fine(0), fine(1)]),
                BuildSlot(workout: 1, exercise: pullUp, history: [fine(0), fine(1)]),
                BuildSlot(workout: 1, exercise: BuildExercise(minReps: 6, maxReps: 12, primary: .quads), history: [fine(0), fine(1)]),
            ]
        ))
        #expect(plan.week == week(3))
        let cut = try #require(plan.slots.first)
        #expect(cut.sets == 2)
        #expect(cut.load == 1000)
        #expect(cut.reason.code == .fatigueCut)
    }

    // MARK: Volume

    @Test("VOL-02, FREQ-04, VOL-07: a muscle under 10 weekly sets gains one set on an on-target slot, same load, one rep fewer")
    func rampIn() throws {
        let plan = BuildEngine.plan(BuildInput(
            weeks: [week(1)],
            slots: [
                BuildSlot(workout: 0, exercise: bench, history: [exposure(0, sets: 3, reps: 8, target: 8, load: 1000, effort: .tapped(3), aim: 3)]),
                BuildSlot(workout: 1, exercise: fly, history: [exposure(0, reps: [12, 12], target: 12, load: 300, effort: .tapped(3), aim: 3)]),
            ]
        ))
        // Chest has 5 planned sets. The fly has fewer sets, so it takes the ramp-in set.
        #expect(plan.slots[1].sets == 3)
        #expect(plan.slots[1].load == 300)
        #expect(plan.slots[1].reps == 11)
        #expect(plan.slots[1].reason.code == .volumeRamp)
        #expect(plan.slots[0].sets == 3)
        #expect(plan.slots[0].reason.code == .repsUp)

        // A slot already ramped this block doesn't ramp again, and an easy slot gets load, not sets.
        let next = BuildEngine.plan(BuildInput(
            weeks: [week(1), week(2)],
            slots: [
                BuildSlot(workout: 0, exercise: bench, history: [
                    exposure(0, sets: 3, reps: 8, target: 8, load: 1000, effort: .tapped(3), aim: 3),
                    exposure(1, sets: 3, reps: 9, target: 9, load: 1000, effort: .tapped(5), aim: 2),
                ]),
                BuildSlot(workout: 1, exercise: fly, history: [
                    exposure(0, reps: [12, 12], target: 12, load: 300, effort: .tapped(3), aim: 3),
                    exposure(1, sets: 3, reps: 11, target: 11, load: 300, effort: .tapped(2), aim: 2, code: .volumeRamp),
                ]),
            ]
        ))
        #expect(next.slots.map(\.sets) == [3, 3])
    }

    @Test("FREQ-02: no added set takes any muscle it trains past 12 sets in one workout")
    func sessionCap() throws {
        let press = BuildExercise(minReps: 6, maxReps: 12, primary: .shoulders, secondary: [.chest], fatigueLevel: .high)
        let chest = { (exercise: BuildExercise) in
            BuildSlot(workout: 0, exercise: exercise, history: [
                exposure(0, sets: 4, reps: 8, target: 8, load: 1000, effort: .tapped(3), aim: 3),
            ])
        }
        let plan = BuildEngine.plan(BuildInput(
            weeks: [week(1)],
            slots: [
                chest(bench),
                chest(fly),
                chest(BuildExercise(minReps: 6, maxReps: 12, primary: .chest)),
                BuildSlot(workout: 0, exercise: press, history: [
                    exposure(0, reps: [8, 8], target: 8, load: 800, effort: .tapped(3), aim: 3),
                ]),
            ]
        ))
        // Shoulders are under 10 sets, but another press set would give chest 12.5 credits in this workout.
        #expect(plan.slots.map(\.sets) == [4, 4, 4, 2])
    }

    @Test("STALL-02, VOL-05: a recovering muscle flat for a block steps up 20% of its sets")
    func blockReviewStepsUp() throws {
        let weeks = (1...4).map(week) + [BuildWeek(kind: .deload, blockWeek: 5)]
            + (1...4).map(week) + [BuildWeek(kind: .deload, blockWeek: 5)]
        let history = { (load: Int) -> [BuildExposure] in
            (0..<10).map { index in
                index % 5 == 4
                    ? exposure(index, sets: 2, reps: 8, target: 8, load: load - 100, effort: .tapped(4), aim: 3, code: .deloadPlanned)
                    : exposure(index, sets: 4, reps: 8, target: 8, load: load, effort: .tapped(2), aim: 2)
            }
        }
        let plan = BuildEngine.plan(BuildInput(
            weeks: weeks,
            slots: [
                BuildSlot(workout: 0, exercise: bench, history: history(1000)),
                BuildSlot(workout: 1, exercise: BuildExercise(minReps: 6, maxReps: 12, primary: .chest), history: history(800)),
            ]
        ))
        #expect(plan.week == week(1))
        // 8 chest sets planned, so the step is one set (at least 1, 20% rounded down).
        #expect(plan.slots.map(\.sets).reduce(0, +) == 9)
        #expect(plan.slots.contains { $0.reason.code == .volumeUp })
    }

    // MARK: Breaks

    @Test("BLK-07: 28 days off gives one return week at 90% with half the sets; 84 days gives two at 80%")
    func returnWeeks() throws {
        let history = [
            exposure(0, sets: 3, reps: 10, target: 10, load: 1000, effort: .tapped(2), aim: 3),
            exposure(1, sets: 3, reps: 11, target: 11, load: 1000, effort: .tapped(2), aim: 2),
        ]
        let input = BuildInput(weeks: [week(1), week(2)], slots: [BuildSlot(workout: 0, exercise: bench, history: history)])

        let bandTwo = BuildEngine.planAfterBreak(input, band: 2)
        #expect(bandTwo.week == BuildWeek(kind: .return, blockWeek: 1, returnBand: 2))
        #expect(bandTwo.slots.first.map { [$0.sets, $0.load, $0.reps, $0.rirTarget] } == [2, 900, 11, 3])

        let bandThree = BuildEngine.planAfterBreak(input, band: 3)
        #expect(bandThree.slots.first.map { [$0.sets, $0.load] } == [2, 800])
        let weekTwo = BuildEngine.plan(BuildInput(
            weeks: input.weeks + [bandThree.week],
            slots: [BuildSlot(workout: 0, exercise: bench, history: history + [
                exposure(2, sets: 2, reps: 11, target: 11, load: 800, effort: .tapped(4), aim: 3, code: .returnWeek),
            ])]
        ))
        #expect(weekTwo.week == BuildWeek(kind: .return, blockWeek: 2, returnBand: 3))
        #expect(weekTwo.slots.first.map { [$0.sets, $0.load] } == [3, 800])

        // Band 1 starts a new block straight away.
        let bandOne = BuildEngine.planAfterBreak(input, band: 1)
        #expect(bandOne.week == week(1))
        #expect(bandOne.slots.first?.reason.code == .blockRebase)
    }

    @Test("BLK-07, VOL-05: the block after a one-week return holds the sets from before the break")
    func setsAfterReturn() throws {
        let history = [
            exposure(0, sets: 3, reps: 10, target: 10, load: 1000, effort: .tapped(3), aim: 3),
            exposure(1, sets: 3, reps: 11, target: 11, load: 1000, effort: .tapped(2), aim: 2),
            exposure(2, sets: 2, reps: 11, target: 11, load: 900, effort: .tapped(4), aim: 3, code: .returnWeek),
        ]
        let plan = BuildEngine.plan(BuildInput(
            weeks: [week(1), week(2), BuildWeek(kind: .return, blockWeek: 1, returnBand: 2)],
            slots: [BuildSlot(workout: 0, exercise: bench, history: history)]
        ))
        #expect(plan.week == week(1))
        #expect(plan.slots.first?.sets == 3)
        #expect(plan.slots.first?.load == 900)
        #expect(plan.slots.first?.reason.code == .blockRebase)
    }

    @Test("BLK-07: a break that cuts return weeks short starts again from the return weeks' loads")
    func breakDuringReturn() throws {
        let history = [
            exposure(0, sets: 3, reps: 10, target: 10, load: 1000, effort: .tapped(2), aim: 3),
            exposure(1, sets: 2, reps: 10, target: 10, load: 800, effort: .tapped(4), aim: 3, code: .returnWeek),
        ]
        let input = BuildInput(
            weeks: [week(1), BuildWeek(kind: .return, blockWeek: 1, returnBand: 3)],
            slots: [BuildSlot(workout: 0, exercise: bench, history: history)]
        )
        // A month off: another return week, 90% of the return load, with half the sets from before the first break.
        let again = BuildEngine.planAfterBreak(input, band: 2)
        #expect(again.week == BuildWeek(kind: .return, blockWeek: 1, returnBand: 2))
        #expect(again.slots.first.map { [$0.sets, $0.load] } == [2, 700])
        // Three weeks off: a new block from the return load, with the sets from before the first break.
        let block = BuildEngine.planAfterBreak(input, band: 1)
        #expect(block.week == week(1))
        #expect(block.slots.first.map { [$0.sets, $0.load] } == [3, 800])
    }

    @Test("BLK-07: the block after a return keeps loads within 10% of the return load")
    func returnCap() throws {
        let weeks = [week(1), BuildWeek(kind: .return, blockWeek: 1, returnBand: 2), week(1)]
        let plan = try slotPlan(raise, [
            exposure(0, reps: [20, 20], target: 20, load: 300, effort: .tapped(2), aim: 3),
            exposure(1, reps: [20, 20], target: 20, load: 300, effort: .tapped(3), aim: 3, code: .returnWeek),
            exposure(2, reps: [20, 20], target: 20, load: 300, effort: .tapped(4), aim: 3),
        ], weeks: weeks)
        // One step is within the cap of 35 lb, so it's allowed.
        #expect(plan.load == 350)
    }

    @Test("BLK-07: in the block after a return, a hold at the lifter's own heavier load stays a hold")
    func returnCapKeepsHolds() throws {
        let weeks = [week(1), BuildWeek(kind: .return, blockWeek: 1, returnBand: 2), week(1)]
        // The lifter chose 40 lb, over the 35 lb cap, and pain rose: nothing rises, reps included.
        let plan = try slotPlan(raise, [
            exposure(0, reps: [20, 20], target: 20, load: 300, effort: .tapped(2), aim: 3),
            exposure(1, reps: [20, 20], target: 20, load: 300, effort: .tapped(3), aim: 3, code: .returnWeek),
            exposure(2, reps: [20, 20], target: 20, load: 400, effort: .tapped(4), aim: 3, pain: .mild),
        ], weeks: weeks)
        #expect(plan.load == 400)
        #expect(plan.reps == 20)
        #expect(plan.reason.code == .painRising)
    }

    @Test("BLK-07: a calibration from before a break never sizes the block after the return weeks")
    func calibrationBeforeReturn() throws {
        let row = BuildExercise(minReps: 8, maxReps: 12, primary: .back, fatigueLevel: .moderate)
        let plan = BuildEngine.plan(BuildInput(
            weeks: [week(1), BuildWeek(kind: .return, blockWeek: 1, returnBand: 2)],
            slots: [
                BuildSlot(workout: 0, exercise: bench, history: [
                    exposure(0, reps: [10, 10], target: nil, load: 300, unplanned: true, effort: .tapped(3), aim: 3, code: .calibrate),
                    exposure(1, sets: 1, reps: 10, target: 10, load: 250, effort: .missing, aim: 3, code: .returnWeek, done: false),
                ]),
                BuildSlot(workout: 1, exercise: row, history: [
                    exposure(0, reps: [10, 10], target: 10, load: 1000, effort: .tapped(3), aim: 3),
                    exposure(1, sets: 1, reps: 10, target: 10, load: 900, effort: .tapped(4), aim: 3, code: .returnWeek),
                ]),
            ]
        ))
        #expect(plan.week == week(1))
        // The return week's 25 lb, with the sets from before the break, not 25% over the old calibration.
        #expect(plan.slots.first.map { [$0.sets, $0.load] } == [2, 250])
    }

    // MARK: Helpers

    private func week(_ number: Int) -> BuildWeek {
        BuildWeek(kind: .build, blockWeek: number)
    }

    private func exposure(
        _ weekIndex: Int,
        sets: Int? = nil,
        reps: Int? = nil,
        target: Int?,
        load: Int?,
        unplanned: Bool = false,
        effort: BuildEffort,
        aim: Int?,
        pain: LevelOfPain? = LevelOfPain.none,
        code: BuildReason.Code? = .repsUp,
        done: Bool = true,
        missLast: Bool = false
    ) -> BuildExposure {
        exposure(
            weekIndex,
            reps: Array(repeating: reps ?? target ?? 8, count: sets ?? 2).enumerated().map { index, value in
                missLast && index == (sets ?? 2) - 1 ? value - 2 : value
            },
            target: target,
            load: load,
            unplanned: unplanned,
            effort: effort,
            aim: aim,
            pain: pain,
            code: code,
            done: done
        )
    }

    private func exposure(
        _ weekIndex: Int,
        reps: [Int],
        target: Int?,
        load: Int?,
        unplanned: Bool = false,
        effort: BuildEffort,
        aim: Int?,
        pain: LevelOfPain? = LevelOfPain.none,
        code: BuildReason.Code? = .repsUp,
        done: Bool = true
    ) -> BuildExposure {
        let start = Date(timeIntervalSince1970: Double(weekIndex) * 7 * 86_400)
        let planned = unplanned ? nil : load
        return BuildExposure(
            weekIndex: weekIndex,
            sets: reps.enumerated().map { index, value in
                BuildSet(
                    plannedReps: target,
                    plannedLoad: planned,
                    reps: done ? value : nil,
                    load: done ? load : nil,
                    completed: done,
                    completedAt: done ? start.addingTimeInterval(Double(index) * 180) : nil
                )
            },
            effort: done ? effort : .missing,
            pain: done ? pain : nil,
            rirTarget: aim,
            code: code
        )
    }

    /// Plans one slot's next build week through pain (L1) and load and reps (L5), without the
    /// week-wide fatigue and volume layers. `weeks` defaults to one build week per exposure.
    private func slotPlan(
        _ exercise: BuildExercise,
        _ history: [BuildExposure],
        weeks: [BuildWeek]? = nil
    ) throws -> BuildSlotPlan {
        let allWeeks = weeks ?? (0...(history.map(\.weekIndex).max() ?? 0)).map { week($0 + 1) }
        let context = BuildContext(BuildInput(
            weeks: allWeeks,
            slots: [BuildSlot(workout: 0, exercise: exercise, history: history)]
        ))
        let next = week(try #require(allWeeks.last).blockWeek + 1)
        var draft = BuildEngine.startDraft(context, 0)
        if draft.plan == nil {
            BuildEngine.painLayer(context, 0, &draft)
            draft.caps.loadCap = BuildEngine.returnLoadCap(context, 0)
        }
        if draft.plan == nil {
            draft.plan = BuildEngine.progress(context, 0, draft, week: next)
        }
        return try #require(BuildEngine.finish(context, [draft], week: next).slots.first)
    }
}
