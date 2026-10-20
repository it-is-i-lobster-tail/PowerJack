//
//  PowerJackEngine.swift
//  PowerJack
//
//  Builds each PowerJack week from the logs when the one before it closes, following the
//  PowerJacking rulebook's weekly loop (1.1): read the week, pain first, then the week type,
//  loads and reps, sets, targets and warm-ups. A pure function of the logs, so it's testable
//  without SwiftData.
//

import Foundation

struct PowerJackContext {
    var programWeeks: Int
    var focusMuscles: Set<Muscle> = []
    /// Balanced until Settings has the goal slider (R1.3).
    var goal: PowerJackGoal = .balanced
    var now: Date = .now
    /// Every exposure of an exercise, from any program or style, oldest first (R9.1).
    var history: (AnyHashable) -> [PowerJackExposure] = { _ in [] }
}

struct SlotRef: Hashable {
    var workout: Int
    var entry: Int
}

enum PowerJackEngine {
    /// Week 1 of a program: block start, main lifts from their anchors or calibrating (R2.2, R8.8),
    /// sets from the volume plan (R3.3, R3.4).
    static func firstWeek(
        _ workouts: [[PowerJackExercise]],
        warmupsDisabled: [[Bool]] = [],
        context: PowerJackContext
    ) -> PowerJackWeekPlan {
        let builder = PowerJackWeekBuilder(
            context: context,
            weeks: [],
            structure: workouts,
            warmupsDisabled: warmupsDisabled
        )
        return builder.build(header: PowerJackCalendar.firstWeek(programWeeks: context.programWeeks))
    }

    /// The week after `weeks`, which are every week of the program built so far, all closed.
    static func nextWeek(after weeks: [PowerJackWeekLog], context: PowerJackContext) -> PowerJackWeekPlan? {
        guard let last = weeks.last else { return nil }
        let builder = PowerJackWeekBuilder(
            context: context,
            weeks: weeks,
            structure: last.workouts.map { $0.entries.map(\.exercise) },
            warmupsDisabled: last.workouts.map { $0.entries.map(\.warmupsDisabled) }
        )
        let header = PowerJackCalendar.nextWeek(
            after: weeks,
            programWeeks: context.programWeeks,
            strained: builder.isStrained,
            anyStrainSign: { week in !builder.flaggedExercises(in: week).isEmpty },
            hardDeload: builder.deloadWasHard(last)
        )
        return builder.build(header: header)
    }
}

/// One week's build. Slots match last week's by position, since a program keeps its template's layout.
struct PowerJackWeekBuilder {
    let context: PowerJackContext
    let weeks: [PowerJackWeekLog]
    let structure: [[PowerJackExercise]]
    let warmupsDisabled: [[Bool]]
    let roles: [[PowerJackSlotRole]]

    init(context: PowerJackContext, weeks: [PowerJackWeekLog], structure: [[PowerJackExercise]], warmupsDisabled: [[Bool]]) {
        self.context = context
        self.weeks = weeks
        self.structure = structure
        self.warmupsDisabled = warmupsDisabled
        self.roles = PowerJackRoles.assign(structure)
    }

    var goal: PowerJackGoal { context.goal }
    var slots: [SlotRef] {
        structure.indices.flatMap { w in structure[w].indices.map { SlotRef(workout: w, entry: $0) } }
    }

    func exercise(_ slot: SlotRef) -> PowerJackExercise { structure[slot.workout][slot.entry] }
    func role(_ slot: SlotRef) -> PowerJackSlotRole { roles[slot.workout][slot.entry] }

    /// The slot's entry in `week`, when that week held the same exercise there.
    func log(_ slot: SlotRef, in week: PowerJackWeekLog) -> PowerJackEntryLog? {
        guard week.workouts.indices.contains(slot.workout),
              week.workouts[slot.workout].entries.indices.contains(slot.entry)
        else { return nil }
        let entry = week.workouts[slot.workout].entries[slot.entry]
        return entry.exercise.id == exercise(slot).id ? entry : nil
    }

    func workoutSkipped(_ slot: SlotRef, in week: PowerJackWeekLog) -> Bool {
        week.workouts.indices.contains(slot.workout) && week.workouts[slot.workout].skipped
    }

    // MARK: Building

    func build(header: PowerJackWeekPlanHeader) -> PowerJackWeekPlan {
        var plans: [SlotRef: PowerJackEntryPlan]
        switch header.type {
        case .deload:
            plans = deloadPlans()
        case .build where header.isBlockStart:
            plans = blockStartPlans()
        case .build:
            plans = continuedPlans(header: header)
        }
        finish(&plans, header: header)
        return PowerJackWeekPlan(
            header: header,
            workouts: structure.indices.map { w in
                structure[w].indices.map { plans[SlotRef(workout: w, entry: $0)]! }
            }
        )
    }

    func emptyPlan(_ slot: SlotRef) -> PowerJackEntryPlan {
        PowerJackEntryPlan(
            exercise: exercise(slot),
            role: role(slot),
            sets: [],
            warmupsDisabled: warmupsDisabled.indices.contains(slot.workout)
                && warmupsDisabled[slot.workout].indices.contains(slot.entry)
                && warmupsDisabled[slot.workout][slot.entry]
        )
    }

    // MARK: Reading closed weeks

    /// Weeks of the open block, BUILD only, oldest first.
    var currentBlockBuildWeeks: [PowerJackWeekLog] {
        guard let last = weeks.last else { return [] }
        return weeks.filter { $0.blockNumber == last.blockNumber && $0.type == .build }
    }

    /// The pain state of an exercise as of `date` (everything logged when nil).
    func painState(_ exercise: PowerJackExercise, upTo date: Date? = nil) -> PowerJackPainState {
        let exposures = context.history(exercise.id).filter { exposure in
            date.map { exposure.date <= $0 } ?? true
        }
        return PowerJackPainState.replay(exposures)
    }

    /// Each part's outcome class for the slot's exposure in `week`, or nil with no exposure (R4.5).
    func classes(_ slot: SlotRef, in week: PowerJackWeekLog) -> [PowerJackClass]? {
        guard !workoutSkipped(slot, in: week), let entry = log(slot, in: week) else { return nil }
        let noSignal = week.type != .build
            || (entry.hasCompletedSets && painState(entry.exercise, upTo: entry.lastCompletedAt).lastExposureAffected)
        let previous = previousBuildWeek(before: week).flatMap { classes(slot, in: $0) }
        let target = entry.target ?? PowerJackRules.calibrationRIR
        return entry.parts.enumerated().map { index, part in
            let previousClass = previous.flatMap { $0.indices.contains(index) ? $0[index] : nil }
            return part.outcome(
                role: role(slot).role,
                target: target,
                previous: previousClass == PowerJackClass.none ? nil : previousClass,
                noSignal: noSignal
            )
        }
    }

    /// The BUILD week before `week` in the same block.
    func previousBuildWeek(before week: PowerJackWeekLog) -> PowerJackWeekLog? {
        guard let index = weeks.firstIndex(of: week), index > 0 else { return nil }
        let earlier = weeks[index - 1]
        return earlier.blockNumber == week.blockNumber && earlier.type == .build ? earlier : nil
    }

    /// R6.4: M slots on a miss or HARD; S and A slots on HARD or a set under the range at full load.
    func strainSign(_ slot: SlotRef, in week: PowerJackWeekLog) -> Bool {
        guard let classes = classes(slot, in: week), let entry = log(slot, in: week) else { return false }
        if classes.allSatisfy({ $0 == .none }) { return false }
        switch role(slot).role {
        case .main:
            return classes.contains { $0.isMiss || $0 == .hard }
        case .secondary, .accessory:
            if classes.contains(.hard) { return true }
            let low = repRange(slot).lowerBound
            return entry.sets.contains { set in
                guard set.isComplete, let reps = set.reps, reps < low else { return false }
                guard let load = set.load, let planned = set.plannedLoad, planned > 0 else { return true }
                return load >= PowerJackRules.strainLoadTolerance * planned
            }
        }
    }

    /// Exercises with any exposure showing strain this week.
    func flaggedExercises(in week: PowerJackWeekLog) -> Set<AnyHashable> {
        Set(slots.filter { strainSign($0, in: week) }.map { exercise($0).id })
    }

    /// R6.4: enough exercises showed strain.
    func isStrained(_ week: PowerJackWeekLog) -> Bool {
        guard week.type == .build else { return false }
        let assessable = Set(slots.filter { slot in
            classes(slot, in: week)?.contains { $0 != .none } ?? false
        }.map { exercise($0).id })
        let flagged = flaggedExercises(in: week).count
        return flagged >= max(2, Int((PowerJackRules.strainWeekShare * Double(assessable.count)).rounded(.up)))
    }

    /// R6.3: a third or more of the rated exercises ended a deload set at 1 rep in reserve or less.
    func deloadWasHard(_ week: PowerJackWeekLog) -> Bool {
        guard week.type == .deload else { return false }
        var rated: Set<AnyHashable> = []
        var hard: Set<AnyHashable> = []
        for workout in week.workouts where !workout.skipped {
            for entry in workout.entries where entry.rir != nil && entry.hasCompletedSets {
                rated.insert(entry.exercise.id)
                if entry.parts.contains(where: { ($0.effectiveRIR ?? 5) <= 1 }) {
                    hard.insert(entry.exercise.id)
                }
            }
        }
        guard !rated.isEmpty else { return false }
        return Double(hard.count) / Double(rated.count) >= PowerJackRules.secondDeloadShare
    }

    // MARK: Reps

    /// R2.1: an S slot's range by slider, an A slot's by fatigue level.
    func repRange(_ slot: SlotRef) -> ClosedRange<Int> {
        switch role(slot).role {
        case .main:
            let reps = PowerJackRules.volumeReps(goal)
            return reps...reps
        case .secondary:
            return PowerJackRules.secondaryRange(goal)
        case .accessory:
            return PowerJackRules.accessoryRange(exercise(slot).fatigue)
        }
    }

    var heavyReps: Int { max(PowerJackRules.heavyReps(goal), PowerJackRules.mainHeavyMinReps) }
    var volumeReps: Int { PowerJackRules.volumeReps(goal) }
}
