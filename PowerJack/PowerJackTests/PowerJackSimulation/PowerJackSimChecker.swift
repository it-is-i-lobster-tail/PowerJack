//
//  PowerJackSimChecker.swift
//  PowerJackTests
//
//  The rules every week the PowerJack planner writes must keep, whatever the lifter did. Each check names
//  the rulebook rule it guards (PowerJacking rules, revision 2). Checks read the stored week, the logs the
//  engine reads, and the plan the engine gives for the same logs.
//

import Foundation
@testable import PowerJack

struct PowerJackSimViolation: CustomStringConvertible {
    var rule: String
    var place: String
    var detail: String

    var description: String { "[\(rule)] \(place): \(detail)" }
}

@MainActor
struct PowerJackSimChecker {
    /// Where the lifter is, for messages: program, template and week.
    var place = ""
    /// Exercise names by the id the engine knows them by.
    var names: [AnyHashable: String] = [:]
    private(set) var violations: [PowerJackSimViolation] = []
    private(set) var weeksChecked = 0

    // MARK: Entry points

    /// A new program's week 1: BUILD block week 1 at column 1, main lifts from anchors or calibrating.
    /// Returns the engine's plan, for the trace.
    mutating func checkFirstWeek(of program: Program) -> PowerJackWeekPlan? {
        guard let week = program.programWeeks.first else {
            fail("PROGRAM", place, "a new program has no weeks")
            return nil
        }
        weeksChecked += 1
        let here = "\(place) week 1"
        let plan = PowerJackPlanner.firstPlan(for: week, in: program)
        let header = plan.header
        expect(header.type == .build && header.blockNumber == 1 && header.blockWeek == 1 && header.column == 1 && header.isBlockStart,
               "R5.1", here, "week 1 is \(PowerJackSimText.describe(header)), not BUILD block week 1")
        let exercises = week.workouts.flatMap { $0.workoutExercises.compactMap(\.exercise) }
        let builder = PowerJackWeekBuilder(
            context: PowerJackPlanner.context(for: program, exercises: exercises),
            weeks: [],
            structure: plan.workouts.map { $0.map(\.exercise) },
            warmupsDisabled: []
        )
        checkStored(week, against: plan, at: here)
        checkSlots(plan, builder: builder, logs: [], at: here)
        return plan
    }

    /// A week the planner just built from the finished week before it. Returns the engine's plan.
    mutating func checkBuild(of program: Program, week index: Int) -> PowerJackWeekPlan? {
        let weeks = program.programWeeks
        guard weeks.indices.contains(index), index > 0 else { return nil }
        weeksChecked += 1
        let here = "\(place) week \(index + 1)"
        let closed = Array(weeks[..<index])
        guard let plan = PowerJackPlanner.nextPlan(after: closed, in: program), let source = closed.last else {
            fail("ENG", here, "the engine planned nothing after \(closed.count) weeks")
            return nil
        }
        let logs = PowerJackPlanner.weekLogs(closed, programWeeks: program.programLengthWeeks)
        let exercises = source.workouts.flatMap { $0.workoutExercises.compactMap(\.exercise) }
        let builder = PowerJackWeekBuilder(
            context: PowerJackPlanner.context(for: program, exercises: exercises),
            weeks: logs,
            structure: plan.workouts.map { $0.map(\.exercise) },
            warmupsDisabled: []
        )
        checkStored(weeks[index], against: plan, at: here)
        checkCalendar(logs, next: plan.header, builder: builder, programWeeks: program.programLengthWeeks, at: here)
        checkSlots(plan, builder: builder, logs: logs, at: here)
        checkProgression(plan, builder: builder, logs: logs, at: here)
        return plan
    }

    // MARK: The stored week

    /// The planner stored exactly what the engine plans from the same logs: week type and block week,
    /// and each slot's sets, reps, loads, target, TOP sets and check-in.
    private mutating func checkStored(_ week: ProgramWeek, against plan: PowerJackWeekPlan, at here: String) {
        let kind: WeekKind = plan.header.type == .deload ? .deload : .build
        expect(week.weekKind == kind && week.blockWeek == plan.header.blockWeek, "ENG-04", here,
               "stored as \(week.weekKind?.rawValue ?? "unset") \(week.blockWeek), the engine planned \(PowerJackSimText.describe(plan.header))")
        expect(week.workouts.count == plan.workouts.count, "ENG-04", here, "stored \(week.workouts.count) workouts, planned \(plan.workouts.count)")
        for (workout, entries) in zip(week.workouts, plan.workouts) {
            let stored = workout.workoutExercises.filter { $0.exercise != nil }
            expect(stored.count == entries.count, "ENG-04", here, "workout \(workout.order + 1) stored \(stored.count) slots, planned \(entries.count)")
            for (workoutExercise, entry) in zip(stored, entries) {
                let name = "\(here) \(workoutExercise.exercise?.exerciseName ?? "?")"
                let sets = workoutExercise.workingSets
                let planned = entry.sets.prefix(WorkoutExercise.maxSets)
                let reps = planned.map { $0.reps.flatMap { WorkoutSet.isValidReps($0) ? $0 : nil } }
                let loads = planned.map { $0.load.map { Int(($0 * 10).rounded()) } }
                expect(sets.map(\.repsPlanned) == reps && sets.map(\.weightTenthsPlannedPounds) == loads, "ENG-04", name,
                       "stored \(PowerJackSimText.describe(sets)), the engine planned \(PowerJackSimText.describe(entry))")
                let target = plan.header.type == .deload ? PowerJackRules.deloadRIR : entry.target
                expect(workoutExercise.rirTarget == target && workoutExercise.topSets == entry.topSets
                       && workoutExercise.calibrating == entry.calibrating, "ENG-04", name,
                       "stored aim \(workoutExercise.rirTarget.map(String.init) ?? "none"), \(workoutExercise.topSets) TOP sets, "
                       + "calibrating \(workoutExercise.calibrating); planned aim \(target.map(String.init) ?? "none"), \(entry.topSets), \(entry.calibrating)")
                expect(workoutExercise.checkInPending == (entry.checkInPain != nil), "ENG-04", name,
                       "check-in \(workoutExercise.checkIn.rawValue), planned \(entry.checkInPain?.label ?? "none")")
                if !workoutExercise.warmupsDisabled {
                    expect(workoutExercise.warmupSets.count == entry.warmups.count, "ENG-04", name,
                           "stored \(workoutExercise.warmupSets.count) warm-ups, planned \(entry.warmups.count)")
                }
            }
        }
    }

    // MARK: The calendar

    /// Week types and block weeks (R5.1, R5.2, R6.1 to R6.4).
    private mutating func checkCalendar(
        _ logs: [PowerJackWeekLog],
        next: PowerJackWeekPlanHeader,
        builder: PowerJackWeekBuilder,
        programWeeks: Int,
        at here: String
    ) {
        guard let last = logs.last else { return }
        let blockStart = (logs.lastIndex { $0.type == .deload }.map { $0 + 1 }) ?? 0
        let block = Array(logs[min(blockStart, logs.count)...])
        let counted = block.filter { $0.type == .build && !$0.isPartial }

        switch (last.type, next.type) {
        case (.deload, .deload):
            // R6.3: never more than 2 in a row.
            let previous = logs.dropLast().last
            expect(previous?.type != .deload, "R6.3", here, "a third deload in a row")
        case (.deload, .build):
            expect(next.isBlockStart && next.blockNumber == last.blockNumber + 1 && next.blockWeek == 1 && next.column == 1,
                   "R5.1", here, "after a deload came \(PowerJackSimText.describe(next)), not block \(last.blockNumber + 1) week 1")
        case (.build, .deload):
            // R5.1, R6.4: a deload needs 3 counted BUILD weeks in its block.
            expect(counted.count >= PowerJackRules.minBuildWeeks, "R6.4", here,
                   "a deload after \(counted.count) counted BUILD weeks")
            // R5.2, R6.2: without strain, the block runs every BUILD week its layout planned (k) before deloading,
            // and its last one is the final column, where main lifts aim at 1 rep left (decision 20).
            var run = 0
            for week in counted.reversed() {
                guard builder.isStrained(week) else { break }
                run += 1
            }
            let early = run >= 3 || (run >= PowerJackRules.strainWeeks && counted.count >= PowerJackRules.minBuildWeeks)
            if !early, !block.contains(where: \.isPartial) {
                let planned = PowerJackCalendar.layout(weeks: programWeeks - blockStart, carry: 0).prefix { $0 == .build }.count
                expect(counted.count >= planned, "R5.2", here,
                       "the block deloads after \(counted.count) BUILD weeks with no strain; its layout planned \(planned)")
                expect(counted.last?.column == 4, "R4.3", here,
                       "the block deloads after column \(counted.last?.column ?? 0) without reaching the final column")
            }
        case (.build, .build):
            expect(next.blockNumber == last.blockNumber && !next.isBlockStart, "R5.1", here,
                   "BUILD after BUILD changed block: \(PowerJackSimText.describe(next))")
            expect(next.blockWeek == counted.count + 1, "R6.1", here,
                   "block week \(next.blockWeek) after \(counted.count) counted BUILD weeks")
            expect(next.blockWeek <= PowerJackRules.maxBuildWeeks, "R5.1", here,
                   "BUILD week \(next.blockWeek) of a block, past \(PowerJackRules.maxBuildWeeks)")
            let lastColumn = counted.map(\.column).max() ?? 0
            expect((1...4).contains(next.column) && next.column >= lastColumn, "R4.3", here,
                   "column \(next.column) after column \(lastColumn)")
        }
    }

    // MARK: Every slot

    /// What every planned slot must look like, whatever came before: sets, reps, loads and targets within
    /// what the app can log and the rules allow.
    private mutating func checkSlots(_ plan: PowerJackWeekPlan, builder: PowerJackWeekBuilder, logs: [PowerJackWeekLog], at here: String) {
        let header = plan.header
        let build = header.type == .build
        let heavy = builder.heavyReps
        let volume = builder.volumeReps
        for (w, entries) in plan.workouts.enumerated() {
            var repOuts = 0
            for (e, entry) in entries.enumerated() {
                let slot = SlotRef(workout: w, entry: e)
                let name = "\(here) w\(w + 1) \(PowerJackSimText.name(entry, in: names))"
                let exercise = entry.exercise
                let role = entry.role.role

                // The app's limits: 1-5 working sets of 1-50 reps, loads up to 1,000 lb.
                expect((1...WorkoutExercise.maxSets).contains(entry.sets.count), "LIMITS", name, "\(entry.sets.count) working sets")
                expect(entry.topSets <= entry.sets.count, "LIMITS", name, "\(entry.topSets) TOP sets of \(entry.sets.count)")
                for set in entry.sets {
                    guard let reps = set.reps else {
                        fail("LIMITS", name, "a set planned with no reps: \(PowerJackSimText.describe(entry))")
                        continue
                    }
                    expect(WorkoutSet.isValidReps(reps), "LIMITS", name, "\(reps) reps, which a set can't hold")
                    if let load = set.load {
                        expect(load.isFinite && load > 0 && load <= Double(WorkoutSet.maxWeightPounds), "LIMITS", name,
                               "planned \(PowerJackSimText.pounds(load)) lb, outside what a set can log (0-\(WorkoutSet.maxWeightPounds) lb)")
                    }
                }
                if exercise.repsOnly {
                    expect(entry.sets.allSatisfy { $0.load == nil }, "R2.6", name, "a bodyweight exercise planned with a load")
                } else if !entry.calibrating, let previous = base(slot, builder: builder, logs: logs, deload: !build) {
                    // A set that had a load keeps one: only calibration leaves the weight to the lifter.
                    for (index, set) in entry.sets.enumerated() {
                        let before = previous.sets[min(index, previous.sets.count - 1)]
                        guard before.plannedLoad != nil || (before.isComplete && before.load != nil) else { continue }
                        expect(set.load != nil, "R2.2", name, "set \(index + 1) planned with no load after \(PowerJackSimText.describe(previous))")
                    }
                }

                // R2.1, decision 1: main lifts keep their heavy and volume reps (band mode adds up to 4), never under 3.
                if role == .main {
                    for (index, set) in entry.sets.enumerated() {
                        guard let reps = set.reps else { continue }
                        expect(reps >= PowerJackRules.mainHeavyMinReps, "R2.1", name, "a main-lift set of \(reps) reps")
                        guard build else { continue }
                        let isHeavy = index < entry.topSets || (entry.topSets == 0 && entry.role.tag == .heavy)
                        let base = isHeavy ? heavy : volume
                        expect((base...(base + 4)).contains(reps), "R2.1", name,
                               "a \(isHeavy ? "heavy" : "volume") set of \(reps) reps, outside \(base)-\(base + 4): \(PowerJackSimText.describe(entry))")
                    }
                } else if build {
                    // R2.4, R2.6: S and A reps widen at most 10 over the range's top, and never past 30.
                    let top = entry.sets.compactMap(\.reps).max() ?? 0
                    expect(top <= PowerJackRules.bodyweightRepCap, "R2.4", name, "\(top) reps, past \(PowerJackRules.bodyweightRepCap)")
                }

                // R4.3, R4.4: targets.
                if build {
                    guard let target = entry.target else {
                        fail("R4.3", name, "no target in a BUILD week")
                        continue
                    }
                    let floor = role == .accessory ? 0 : 1
                    expect((floor...PowerJackRules.calibrationRIR).contains(target), "R4.3", name, "aims at \(target) reps left")
                    if target == 0 || entry.repOut {
                        repOuts += 1
                        expect(entry.repOut && role == .accessory && exercise.fatigue == .low && header.column == 4, "R4.4", name,
                               "a rep-out (target \(target)) on a \(role) slot, \(exercise.fatigue.name) fatigue, column \(header.column)")
                    }
                    if entry.calibrating {
                        expect(target >= PowerJackRules.calibrationRIR, "R4.3", name, "calibrating at \(target) reps left")
                    }
                    if builder.painState(builder.exercise(slot)).inEpisode {
                        expect(target >= PowerJackRules.painRIRFloor, "R10.2", name, "in a pain episode at \(target) reps left")
                    }
                } else {
                    expect(entry.target == nil && !entry.repOut, "R6.3", name, "a deload slot aims at \(entry.target.map(String.init) ?? "-") reps left")
                }

                // R10.8: warm-ups below the first working load, at most 3, never under the empty bar.
                expect(entry.warmups.count <= 3, "R10.8", name, "\(entry.warmups.count) warm-ups")
                if let first = entry.sets.first?.load {
                    for warmup in entry.warmups {
                        guard let load = warmup.load else { continue }
                        expect(load > 0 && load < first, "R10.8", name, "a warm-up at \(PowerJackSimText.pounds(load)) before a first set at \(PowerJackSimText.pounds(first))")
                        if exercise.isBarbell {
                            expect(load >= PowerJackRules.barPounds, "R10.8", name, "a barbell warm-up at \(PowerJackSimText.pounds(load))")
                        }
                    }
                }

                // R2.5, R10.7: no automatic rise past max(10% over the best load of the last 14 days, one step),
                // except right after a calibrating exposure (decision 30).
                if build, let cap = loadCap(slot, builder: builder, logs: logs) {
                    for load in entry.sets.compactMap(\.load) where load > cap + 1e-6 {
                        fail("R2.5", name, "planned \(PowerJackSimText.pounds(load)) over the cap of \(PowerJackSimText.pounds(cap)): \(PowerJackSimText.describe(entry)) \(entry.reasons.map(\.rawValue))")
                        break
                    }
                }

                // R10.4: Severe or Extreme pain last time opens the check-in before the next exposure.
                let history = builder.context.history(exercise.id).filter { $0.entry.pain != nil }
                if let latest = history.last, let pain = latest.entry.pain, pain.rawValue >= LevelOfPain.severe.rawValue {
                    expect(entry.checkInPain != nil, "R10.4", name,
                           "\(pain.label) pain the last time it was done (\(PowerJackSimText.day(latest.date))), but no check-in")
                }
            }
            expect(repOuts <= PowerJackRules.maxRepOutsPerSession, "R4.4", "\(here) w\(w + 1)", "\(repOuts) rep-outs in one session")
        }
    }

    /// The entry a slot's plan comes from: the latest BUILD week's for a deload (R6.3), else last week's,
    /// when the slot kept its exercise and role.
    private func base(_ slot: SlotRef, builder: PowerJackWeekBuilder, logs: [PowerJackWeekLog], deload: Bool) -> PowerJackEntryLog? {
        guard let last = logs.last, let entry = deload ? builder.latestBuildLog(slot) ?? builder.log(slot, in: last) : builder.log(slot, in: last),
              !entry.sets.isEmpty, !entry.unplanned, entry.role.map({ $0 == builder.role(slot) }) ?? true
        else { return nil }
        return entry
    }

    /// R2.5's cap for a slot, or nil where none applies: no completed load yet, or right after a calibrating
    /// exposure (decision 30).
    private func loadCap(_ slot: SlotRef, builder: PowerJackWeekBuilder, logs: [PowerJackWeekLog]) -> Double? {
        let exercise = builder.exercise(slot)
        guard !exercise.repsOnly else { return nil }
        if let last = logs.last, let entry = builder.log(slot, in: last), entry.calibrating, entry.hasCompletedSets {
            return nil
        }
        guard let best = builder.bestRecentLoad(exercise) else { return nil }
        return max(PowerJackSteps().roundDown(best * (1 + PowerJackRules.maxJumpPct / 100)), best + PowerJackRules.stepPounds)
    }

    // MARK: Week to week

    /// One week's plan against the last: what may rise, what must hold and what must fall.
    private mutating func checkProgression(_ plan: PowerJackWeekPlan, builder: PowerJackWeekBuilder, logs: [PowerJackWeekLog], at here: String) {
        guard let last = logs.last else { return }
        let header = plan.header
        var adds = 0
        for (w, entries) in plan.workouts.enumerated() {
            for (e, entry) in entries.enumerated() {
                let slot = SlotRef(workout: w, entry: e)
                let name = "\(here) w\(w + 1) \(PowerJackSimText.name(entry, in: names))"
                guard let previous = builder.log(slot, in: last) else { continue }

                switch header.type {
                case .deload:
                    // R6.3: the first half of the latest BUILD sets (round half up), no heavier and no more reps.
                    // A second deload repeats the first.
                    guard last.type == .build, let base = builder.latestBuildLog(slot) ?? Optional(previous) else { break }
                    let kept = max(1, (Double(base.sets.count) * PowerJackRules.deloadSetFactor).roundedHalfUp)
                    expect(entry.sets.count == kept, "R6.3", name, "a deload of \(entry.sets.count) sets after \(base.sets.count)")
                    for (set, before) in zip(entry.sets, base.sets) {
                        let baseLoad = before.isComplete ? (before.load ?? before.plannedLoad) : before.plannedLoad
                        if let load = set.load, let baseLoad {
                            expect(load <= baseLoad + 1e-6, "R6.3", name, "a deload at \(PowerJackSimText.pounds(load)) after \(PowerJackSimText.pounds(baseLoad))")
                        }
                        if let reps = set.reps, let baseReps = before.plannedReps ?? before.reps {
                            // Main lifts never go under 3 reps (R2.1).
                            let most = entry.role.role == .main ? max(baseReps, PowerJackRules.mainHeavyMinReps) : baseReps
                            expect(reps <= most, "R6.3", name, "a deload of \(reps) reps after \(baseReps)")
                        }
                    }
                case .build where !header.isBlockStart:
                    guard last.type == .build else { break }
                    // R6.8: a skipped workout's slots repeat their plan, never heavier. Only the validator lowers
                    // it (R10.7, R10.2). A slot whose exercise or role changed starts again instead (R1.4).
                    let restarted = previous.unplanned || previous.role.map { $0 != builder.role(slot) } ?? false
                    if builder.workoutSkipped(slot, in: last), !restarted {
                        let same = entry.sets.count == previous.sets.count
                            && zip(entry.sets, previous.sets).allSatisfy { set, before in
                                set.reps == (before.plannedReps ?? set.reps)
                                    && (before.plannedLoad.map { load in (set.load ?? 0) <= load + 1e-6 } ?? true)
                            }
                        expect(same, "R6.8", name,
                               "skipped, but \(PowerJackSimText.describe(previous)) became \(PowerJackSimText.describe(entry))")
                    }
                    // R3.5, R10.7: at most one set more than last week, and a set and more load never come together (1.3).
                    expect(entry.sets.count <= previous.sets.count + PowerJackRules.blockStepSets, "R10.7", name,
                           "\(previous.sets.count) sets became \(entry.sets.count)")
                    if entry.reasons.contains(.addedSet) {
                        adds += 1
                        if let load = entry.sets.first?.load, let before = previous.parts.first?.firstLoad {
                            expect(load <= before + 1e-6, "1.3", name, "an added set and a rise from \(PowerJackSimText.pounds(before)) to \(PowerJackSimText.pounds(load))")
                        }
                    }
                    // R10.2: an exercise in a pain episode, or with rising pain, gets no more load and no added set.
                    let pain = builder.painState(builder.exercise(slot))
                    if pain.inEpisode || pain.action == .hold(floor: false), previous.hasCompletedSets {
                        for (index, part) in previous.parts.enumerated() {
                            guard let before = part.heaviestLoad else { continue }
                            let range = previous.isTopAndBack ? (index == 0 ? 0..<entry.topSets : entry.topSets..<entry.sets.count) : 0..<entry.sets.count
                            for set in range.compactMap({ entry.sets.indices.contains($0) ? entry.sets[$0] : nil }) {
                                guard let load = set.load else { continue }
                                expect(load <= before + 1e-6, "R10.2", name,
                                       "pain \(previous.pain?.label ?? "untapped") (\(pain.action)), but \(PowerJackSimText.pounds(before)) became \(PowerJackSimText.pounds(load))")
                            }
                        }
                        expect(!entry.reasons.contains(.addedSet), "R10.2", name, "a set added in a pain episode")
                    }
                case .build:
                    // R10.2, R8.4: a block start never raises an exercise in a pain episode.
                    let pain = builder.painState(builder.exercise(slot))
                    if pain.inEpisode, let latest = builder.latestBuildLog(slot), latest.hasCompletedSets {
                        for (index, part) in latest.parts.enumerated() {
                            guard let before = part.heaviestLoad else { continue }
                            let range = latest.isTopAndBack ? (index == 0 ? 0..<entry.topSets : entry.topSets..<entry.sets.count) : 0..<entry.sets.count
                            for set in range.compactMap({ entry.sets.indices.contains($0) ? entry.sets[$0] : nil }) {
                                guard let load = set.load else { continue }
                                expect(load <= before + 1e-6, "R10.2", name,
                                       "in a pain episode (\(pain.action)), but the block starts at \(PowerJackSimText.pounds(load)) after \(PowerJackSimText.pounds(before))")
                            }
                        }
                    }
                }
            }
        }
        expect(adds <= PowerJackRules.maxAddsPerWeek, "R3.5", here, "\(adds) sets added in one week")
    }

    // MARK: Helpers

    private mutating func expect(_ condition: Bool, _ rule: String, _ place: String, _ detail: @autoclosure () -> String) {
        guard !condition else { return }
        fail(rule, place, detail())
    }

    private mutating func fail(_ rule: String, _ place: String, _ detail: String = "") {
        violations.append(PowerJackSimViolation(rule: rule, place: place, detail: detail))
    }
}

//
// Text for messages and traces
//
enum PowerJackSimText {
    /// "225", "47.5", or "bw" for no load.
    static func pounds(_ pounds: Double?) -> String {
        guard let pounds else { return "bw" }
        let tenths = Int((pounds * 10).rounded())
        return tenths % 10 == 0 ? "\(tenths / 10)" : String(format: "%.1f", Double(tenths) / 10)
    }

    static func pounds(tenths: Int?) -> String {
        pounds(tenths.map { Double($0) / 10 })
    }

    static func day(_ date: Date) -> String {
        "day \(Int(date.timeIntervalSince(PowerJackSimDriver.firstDay) / 86_400))"
    }

    static func name(_ entry: PowerJackEntryPlan, in names: [AnyHashable: String]) -> String {
        names[entry.exercise.id] ?? "?"
    }

    static func describe(_ header: PowerJackWeekPlanHeader) -> String {
        switch header.type {
        case .deload: "deload (block \(header.blockNumber))"
        case .build: "build \(header.blockWeek) col \(header.column) (block \(header.blockNumber))\(header.caution ? " caution" : "")\(header.holdFlagged ? " hold" : "")"
        }
    }

    static func describe(_ entry: PowerJackEntryPlan) -> String {
        let sets = groups(entry.sets.map { ($0.reps, $0.load) })
        let aim = entry.target.map { " aim \($0)" } ?? ""
        let flags = [entry.calibrating ? "calibrating" : nil, entry.repOut ? "rep-out" : nil, entry.checkInPain.map { "check-in \($0.label)" }]
            .compactMap { $0 }
        return "\(sets)\(aim) \(entry.reasons.map(\.rawValue).joined(separator: ","))\(flags.isEmpty ? "" : " " + flags.joined(separator: " "))"
    }

    static func describe(_ entry: PowerJackEntryLog) -> String {
        let planned = groups(entry.sets.map { ($0.plannedReps, $0.plannedLoad) })
        let done = entry.sets.map { $0.isComplete ? "\($0.reps ?? 0)@\(pounds($0.load))" : "-" }.joined(separator: ",")
        return "\(planned) did \(done) rir \(entry.rir.map(String.init) ?? "-")\(entry.topSets > 0 ? "/top \(entry.topRIR.map(String.init) ?? "-")" : "") pain \(entry.pain?.rawValue ?? -1)"
    }

    static func describe(_ sets: [WorkoutSet]) -> String {
        groups(sets.map { ($0.repsPlanned, $0.weightInPoundsPlanned) })
    }

    /// "1×5@260 + 2×8@235": runs of equal sets.
    private static func groups(_ sets: [(reps: Int?, load: Double?)]) -> String {
        var runs: [(count: Int, reps: Int?, load: Double?)] = []
        for set in sets {
            if let last = runs.last, last.reps == set.reps, last.load == set.load {
                runs[runs.count - 1].count += 1
            } else {
                runs.append((1, set.reps, set.load))
            }
        }
        return runs.map { "\($0.count)×\($0.reps.map(String.init) ?? "?")@\(pounds($0.load))" }.joined(separator: " + ")
    }
}
