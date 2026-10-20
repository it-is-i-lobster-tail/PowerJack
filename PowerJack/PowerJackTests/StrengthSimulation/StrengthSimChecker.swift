//
//  StrengthSimChecker.swift
//  PowerJackTests
//
//  The rules every Strengthen week and workout must keep, whatever the lifter did. Each check names the
//  rulebook rule it guards. Checks read the stored plans, the lift records the planner logged, and what the
//  simulation knows really happened: when each lift was last trained and the pain last rated on it.
//

import Foundation
@testable import PowerJack

struct StrengthSimViolation: CustomStringConvertible {
    var rule: String
    var place: String
    var detail: String

    var description: String { "[\(rule)] \(place): \(detail)" }
}

/// What really happened to one lift, by its record key, for checking the planner's view of it.
struct StrengthSimTruth {
    /// The last completed working set, in any program.
    var lastTrained: Date?
    /// What the pain rated after the last trained Strengthen session of the lift asks of the next one (15.4, 15.5).
    var painAction: PainAction?
}

/// One exercise of a Strengthen week as stored, with the plan the planner wrote on it.
struct StrengthSimSlot {
    let workoutExercise: WorkoutExercise
    let exercise: Exercise

    var name: String { exercise.exerciseName }
    var key: String { StrengthLifts.key(for: exercise) }
    var role: StrengthRole? { workoutExercise.strengthRole }
    var isLoaded: Bool { role == .primary || role == .secondary }
    var parsed: (kind: StrengthSlotKind, returnBand: Int, rules: [String])? { StrengthSlotPlan.parse(code: workoutExercise.progressionCode) }
    var kind: StrengthSlotKind? { parsed?.kind }
    var rules: [String] { parsed?.rules ?? [] }
    var sets: [WorkoutSet] { workoutExercise.workingSets }
    var reps: Int? { sets.first?.repsPlanned }
    var load: Int? { sets.first?.weightTenthsPlannedPounds }
    var loadKg: Double? { load.map { WeightUnit.kilograms(fromTenthsPounds: $0) } }
    /// R and I.
    var target: Int? { workoutExercise.targetReps }
    var rir: Int? { workoutExercise.rirTarget }

    /// The last completed working set: the rated set (3.1).
    var ratedSet: WorkoutSet? {
        sets.last { $0.status == .complete && ($0.reps ?? 0) > 0 }
    }

    /// Slots in workout order, then by place in the workout.
    static func all(in week: ProgramWeek, plannedOnly: Bool = false) -> [StrengthSimSlot] {
        week.workouts
            .filter { !plannedOnly || $0.status == .planned }
            .flatMap(\.workoutExercises)
            .compactMap { workoutExercise in
                workoutExercise.exercise.map { StrengthSimSlot(workoutExercise: workoutExercise, exercise: $0) }
            }
    }

    static func all(in workout: Workout) -> [StrengthSimSlot] {
        workout.workoutExercises.compactMap { workoutExercise in
            workoutExercise.exercise.map { StrengthSimSlot(workoutExercise: workoutExercise, exercise: $0) }
        }
    }

    /// The same slot in earlier weeks of the program, newest first, as the planner matches them: same day,
    /// same exercise, same place among its repeats.
    func history(in program: Program) -> [StrengthSimSlot] {
        guard
            let workout = workoutExercise.workoutValue,
            let week = program.programWeek(containing: workout)
        else { return [] }
        let repeats = workout.workoutExercises.filter { $0.exercise === exercise }
        guard let occurrence = repeats.firstIndex(where: { $0 === workoutExercise }) else { return [] }
        return program.programWeeks.filter { $0.order < week.order }.reversed().compactMap { earlier in
            guard let earlierWorkout = earlier.workouts.first(where: { $0.order == workout.order }) else { return nil }
            let matches = earlierWorkout.workoutExercises.filter { $0.exercise === exercise }
            guard matches.indices.contains(occurrence) else { return nil }
            return StrengthSimSlot(workoutExercise: matches[occurrence], exercise: exercise)
        }
    }
}

@MainActor
struct StrengthSimChecker {
    /// Where the lifter is, for messages: program, template and week.
    var place = ""
    /// The load grid the lifter's settings give each equipment type right now.
    var gridFor: (Equipment) -> LoadGrid? = { LoadGrid(equipment: $0) }
    private(set) var violations: [StrengthSimViolation] = []
    private(set) var weeksChecked = 0
    private(set) var workoutsChecked = 0

    /// Half a tenth of a pound, the most a stored weight can sit off the load it was planned at.
    private static let tolerance = 0.05

    // MARK: Entry points

    /// A week the planner just built from the finished week before it.
    mutating func checkBuild(of program: Program, week index: Int, records: StrengthState) {
        let weeks = program.programWeeks
        guard weeks.indices.contains(index), index > 0 else { return }
        weeksChecked += 1
        let week = weeks[index]
        let here = "\(place) week \(index + 1)"
        let clock = records.clock
        expect(week.weekKind == clock.upcoming && week.blockWeek == clock.blockWeek, "9.5", here,
               "stored as \(week.weekKind?.rawValue ?? "nil") block week \(week.blockWeek), the records say "
               + "\(clock.upcoming.rawValue) block week \(clock.blockWeek)")

        for slot in StrengthSimSlot.all(in: week) {
            let at = "\(here) \(slot.name)"
            let history = slot.history(in: program)
            checkSlot(slot, records: records, at: at, checksGrid: true, history: history)
            if week.weekKind == .deload {
                checkDeload(slot, history: history, at: at)
            } else {
                checkRise(slot, history: history, at: at)
            }
        }
    }

    /// A workout right after the planner prepared it to start: breaks, pain and a new program's records (2.6,
    /// 12.1, 15.4, 15.5). `before` holds each slot's code and first load from before the planner ran.
    mutating func checkStart(
        of workout: Workout,
        in program: Program,
        at date: Date,
        records: StrengthState,
        truth: [String: StrengthSimTruth],
        before: [ObjectIdentifier: String]
    ) {
        workoutsChecked += 1
        let here = "\(place) workout \(workout.order + 1)"
        for slot in StrengthSimSlot.all(in: workout) where slot.workoutExercise.status == .planned {
            let at = "\(here) \(slot.name)"
            let changed = before[ObjectIdentifier(slot.workoutExercise)] != Self.signature(of: slot)
            checkSlot(slot, records: records, at: at, checksGrid: changed, history: slot.history(in: program))
            let lift = truth[slot.key] ?? StrengthSimTruth()

            if slot.isLoaded, gridFor(slot.exercise.exerciseEquipment) != nil,
               let days = StrengthSessionRules.daysOff(since: lift.lastTrained, at: date),
               days > StrengthRules.breakMinDays {
                expect(slot.rules.contains("12.1"), "12.1", at,
                       "\(days) days since it was last trained, but planned as \(Self.describe(slot))")
            }
            switch lift.painAction {
            case .lighter:
                expect(slot.workoutExercise.checkInPending && slot.kind == .painLighter, "15.4", at,
                       "rated Severe pain or worse last time, but planned as \(Self.describe(slot)) "
                       + "\(slot.workoutExercise.checkInPending ? "behind" : "without") a check-in")
            case .cut:
                expect(slot.kind == .painCut && slot.rules.contains("15.5"), "15.5", at,
                       "rated Moderate pain last time, but planned as \(Self.describe(slot))")
            case nil:
                break
            }
            if slot.isLoaded, gridFor(slot.exercise.exerciseEquipment) != nil, slot.kind == .normal, slot.load == nil,
               records[slot.key].e1rmKg != nil {
                fail("2.6", at, "the lift has an e1RM but is planned without a weight: \(Self.describe(slot))")
            }
        }
    }

    /// The week that just finished, or the program that stopped partway through one, logged the lift records
    /// once (the weekly loop): every session counts toward e1RM, pain and the block clock.
    mutating func checkClose(logsBefore: Int, logsAfter: Int, expected: Int, at here: String) {
        expect(logsAfter - logsBefore == expected, "WEEK", here,
               "logged the lift records \(logsAfter - logsBefore) times, expected \(expected)")
    }

    /// The records a week close logged: a block clock that keeps to its rules and estimates that make sense.
    mutating func checkRecords(_ state: StrengthState, previous: StrengthState, lifter: StrengthSimLifter, exercises: [String: Exercise], at here: String) {
        let clock = state.clock
        expect((1...StrengthRules.blockTrainWeeks).contains(clock.blockWeek), "9.5", here, "block week \(clock.blockWeek)")
        expect(clock.trainedWeeks >= previous.clock.trainedWeeks, "17.7", here,
               "trained weeks fell from \(previous.clock.trainedWeeks) to \(clock.trainedWeeks)")
        if clock.weeksSinceDeload >= StrengthRules.deloadMaxGapWeeks {
            expect(clock.upcoming == .deload, "10.5", here, "\(clock.weeksSinceDeload) weeks since a deload and none planned next")
        }
        expect(clock.weeksSinceDeload <= StrengthRules.deloadMaxGapWeeks, "10.5", here,
               "\(clock.weeksSinceDeload) weeks since the last deload")
        for key in state.lifts.keys.sorted() {
            let record = state[key]
            if let e1rm = record.e1rmKg {
                expect(e1rm.isFinite && e1rm > 0 && e1rm < 1_000, "4.2", "\(here) \(key)", "e1RM \(e1rm) kg")
                if let exercise = exercises[key], !exercise.repsOnly, e1rm.isFinite {
                    let ratio = e1rm / lifter.trueMax(exercise)
                    expect(ratio > 0.33 && ratio < 3, "4.1", "\(here) \(key)",
                           "e1RM \(Self.format(e1rm)) kg is \(String(format: "%.2f", ratio))× the lifter's true max")
                }
            }
            let pain = record.pain
            expect(pain.capShare.map { $0 > 0 && $0 <= 1 } ?? true && pain.setsDropped >= 0, "15.7", "\(here) \(key)",
                   "pain cap \(pain.capShare.map { Self.format($0) } ?? "nil"), \(pain.setsDropped) sets dropped")
        }
    }

    /// A short set lowered the weights of the sets still to do (6.2).
    mutating func checkMiss(_ slot: StrengthSimSlot, short set: WorkoutSet, nextWeightBefore: Int?, at here: String) {
        guard
            slot.role != nil,
            let load = set.weightTenthsPounds,
            let next = slot.sets.first(where: { $0.order > set.order && $0.status == .active }),
            let after = next.weightTenthsPounds,
            let nextWeightBefore, nextWeightBefore == load,
            let grid = gridFor(slot.exercise.exerciseEquipment),
            // Nothing goes under the bar or one step.
            WeightUnit.kilograms(fromTenthsPounds: load) > grid.minimumKilograms + LoadGrid.storedTolerance
        else { return }
        expect(after < load, "6.2", "\(here) \(slot.name)",
               "set \(set.order) fell short at \(Self.pounds(load)) but the next set stayed at \(Self.pounds(after))")
    }

    // MARK: Slots

    /// What every planned slot must look like, whatever came before (1.1, 1.3, 5.1, 5.2, 5.7, 5.9, 10.6, 15.4).
    private mutating func checkSlot(_ slot: StrengthSimSlot, records: StrengthState, at here: String, checksGrid: Bool, history: [StrengthSimSlot]) {
        guard slot.role != nil, let kind = slot.kind else {
            fail("ENG", here, "no Strengthen plan (role \(slot.role?.rawValue ?? "nil"), code \(slot.workoutExercise.progressionCode ?? "nil"))")
            return
        }
        let sets = slot.sets
        expect((1...WorkoutExercise.maxSets).contains(sets.count), "LIMITS", here, "\(sets.count) working sets")
        for set in sets {
            if let reps = set.repsPlanned {
                expect(WorkoutSet.isValidReps(reps), "LIMITS", here, "a set planned at \(reps) reps")
            }
            if let load = set.weightTenthsPlannedPounds {
                expect(WorkoutSet.isValidWeightTenthsPounds(load), "1.1", here,
                       "a set planned at \(Self.pounds(load)), outside what a set can log (0-\(WorkoutSet.maxWeightPounds) lb)")
            }
        }
        if let intended = slot.workoutExercise.intendedLoadKg {
            expect(intended.isFinite && intended >= 0, "LIMITS", here, "intended load \(intended)")
        }
        if slot.exercise.repsOnly {
            expect(sets.allSatisfy { $0.weightTenthsPlannedPounds == nil }, "1.3", here, "a bodyweight exercise planned with a weight")
        }
        guard slot.isLoaded, let grid = gridFor(slot.exercise.exerciseEquipment) else {
            expect(slot.rir == nil || kind != .accessory, "5.1", here, "an accessory with a reps-left aim")
            return
        }

        expect(Set(sets.map(\.repsPlanned)).count <= 1 && Set(sets.map(\.weightTenthsPlannedPounds)).count <= 1, "5.1", here,
               "sets planned unevenly: \(sets.map { "\($0.repsPlanned ?? 0)@\(Self.pounds($0.weightTenthsPlannedPounds))" })")
        guard let target = slot.target, let rir = slot.rir else {
            fail("5.1", here, "no reps or reps-left target: \(Self.describe(slot))")
            return
        }
        if let reps = slot.reps {
            expect((1...12).contains(reps), "5.9", here, "planned \(reps) reps, outside Building Strength's 1-12")
        }
        let painFloor = records[slot.key].pain.rirFloor
        switch kind {
        case .normal, .calibration:
            if slot.role == .primary {
                expect((StrengthRules.repsMinNormal...6).contains(target), "5.2", here, "a normal week at \(target) reps")
                expect(target + rir <= StrengthRules.primaryRepsToFailureMax || painFloor, "5.2", here,
                       "\(target) @ \(rir) is \(target + rir) reps to failure, over \(StrengthRules.primaryRepsToFailureMax)")
            } else {
                expect(target + rir <= StrengthRules.secondaryRepsToFailureMax || painFloor, "5.2", here,
                       "\(target) @ \(rir) is \(target + rir) reps to failure on a variant")
            }
            expect(rir >= StrengthRules.rirMin, "3.4", here, "plans failure: \(target) @ \(rir)")
        case .deload:
            expect(rir >= StrengthRules.deloadRIRMin, "10.6", here, "a deload at \(rir) reps in reserve")
        case .painLighter:
            expect(rir >= StrengthRules.painReturnRIR && sets.count <= StrengthRules.painReturnSets, "15.4", here,
                   "Lighter after pain planned as \(Self.describe(slot))")
        default:
            break
        }
        if StrengthLifts.needsSpotter(slot.exercise) {
            expect(target + rir > StrengthRules.spotterRepsToFailure, "5.2", here,
                   "a near-max squat or bench at \(target) @ \(rir) with no spotter check")
        }

        if checksGrid, let load = slot.loadKg {
            let logged = history.first.map { $0.sets.compactMap(\.weightTenthsPounds).map { WeightUnit.kilograms(fromTenthsPounds: $0) } } ?? []
            let onGrid = abs(grid.nearest(load) - load) <= Self.tolerance
            let asLogged = logged.contains { abs($0 - load) <= Self.tolerance }
            expect(onGrid || asLogged, "1.1", here,
                   "planned at \(Self.format(load)) kg, off the \(grid.step) \(grid.unit.symbol) grid and not a weight last logged")
            expect(load >= grid.minimumKilograms - Self.tolerance, "1.1", here, "planned at \(Self.format(load)) kg, under the bar or one step")
        }
        // Calibration weeks keep the warm-ups the lifter logged (5.7).
        if let working = slot.load, kind != .calibration {
            for warmup in slot.workoutExercise.warmupSets {
                guard let warmupLoad = warmup.weightTenthsPlannedPounds else { continue }
                expect(warmupLoad < working, "5.7", here,
                       "a warm-up planned at \(Self.pounds(warmupLoad)), at or over the first working set's \(Self.pounds(working)) (\(Self.describe(slot)))")
            }
        }
    }

    /// 10.6: in a deload week every slot keeps its reps, with half the sets, 90% of the load and 3 or more reps in reserve.
    private mutating func checkDeload(_ slot: StrengthSimSlot, history: [StrengthSimSlot], at here: String) {
        guard let kind = slot.kind else { return }
        guard slot.isLoaded, let grid = gridFor(slot.exercise.exerciseEquipment) else {
            expect(kind == .deload || slot.exercise.repsOnly, "10.6", here, "an accessory in a deload week planned as \(Self.describe(slot))")
            return
        }
        // A lift with nothing to deload from calibrates by feel instead (2.2).
        expect(kind == .deload || (kind == .calibration && slot.load == nil), "10.6", here, "planned as \(Self.describe(slot)) in a deload week")
        guard kind == .deload else { return }
        guard let source = history.first(where: { $0.kind == .normal || $0.kind == .calibration }) ?? history.first else { return }
        let sets = max(1, source.sets.count / 2)
        expect(slot.sets.count == sets, "10.6", here, "\(slot.sets.count) sets, half of \(source.sets.count) is \(sets)")
        let base = source.workoutExercise.intendedLoadKg ?? source.ratedSet?.weightTenthsPounds.map { WeightUnit.kilograms(fromTenthsPounds: $0) }
        if let base, let load = slot.loadKg {
            let expected = grid.nearest(base * StrengthRules.deloadLoadFactor)
            expect(abs(load - expected) <= Self.tolerance, "10.6", here,
                   "planned at \(Self.format(load)) kg, 90% of \(Self.format(base)) kg is \(Self.format(expected)) kg")
        }
    }

    /// Module 7's caps: a weekly rise is at most last week's bar × 1.075 rounded down, or one step (1.1, 7.3),
    /// and in reps mode at most one step (1.2).
    private mutating func checkRise(_ slot: StrengthSimSlot, history: [StrengthSimSlot], at here: String) {
        guard
            slot.isLoaded,
            let grid = gridFor(slot.exercise.exerciseEquipment),
            let load = slot.loadKg,
            let last = history.first,
            let rated = last.ratedSet?.weightTenthsPounds.map { WeightUnit.kilograms(fromTenthsPounds: $0) }, rated > 0
        else { return }
        if slot.rules.contains("7.3") {
            let limit = max(grid.down(rated * (1 + StrengthRules.capUp)), grid.moved(rated, bySteps: 1))
            expect(load <= limit + Self.tolerance, "7.3", here,
                   "rose from \(Self.format(rated)) kg to \(Self.format(load)) kg, over the cap \(Self.format(limit)) kg")
        }
        if slot.rules.contains("1.2") {
            let limit = grid.moved(rated, bySteps: 1)
            expect(load <= limit + Self.tolerance, "1.2", here,
                   "reps mode moved from \(Self.format(rated)) kg to \(Self.format(load)) kg, more than a step")
        }
        if slot.kind == .microDeload, let lastLoad = last.loadKg {
            expect(load <= lastLoad + Self.tolerance, "10.3", here, "a micro-deload at \(Self.format(load)) kg after \(Self.format(lastLoad)) kg")
        }
    }

    // MARK: Helpers

    /// A slot's code and planned working sets, to tell whether the planner rewrote it.
    static func signature(of slot: StrengthSimSlot) -> String {
        "\(slot.workoutExercise.progressionCode ?? "")|" + slot.sets.map { "\($0.repsPlanned ?? 0)@\($0.weightTenthsPlannedPounds ?? 0)" }.joined(separator: ",")
    }

    static func describe(_ slot: StrengthSimSlot) -> String {
        let load = slot.load.map { Self.pounds($0) } ?? "by feel"
        let target = slot.target.map { "R\($0)" } ?? "R-"
        let rir = slot.rir.map { "@\($0)" } ?? ""
        return "\(slot.sets.count)×\(slot.reps.map(String.init) ?? "-") \(load) (\(target)\(rir)) \(slot.workoutExercise.progressionCode ?? "no code")"
    }

    private static func pounds(_ tenths: Int?) -> String {
        guard let tenths else { return "none" }
        return "\(WeightUnit.pounds.format(tenthsPounds: tenths)) lb"
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private mutating func expect(_ condition: Bool, _ rule: String, _ place: String, _ detail: @autoclosure () -> String) {
        if !condition {
            fail(rule, place, detail())
        }
    }

    private mutating func fail(_ rule: String, _ place: String, _ detail: String) {
        violations.append(StrengthSimViolation(rule: rule, place: place, detail: detail))
    }
}
