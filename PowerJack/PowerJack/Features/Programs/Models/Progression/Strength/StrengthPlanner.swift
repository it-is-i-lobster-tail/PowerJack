//
//  StrengthPlanner.swift
//  PowerJack
//
//  Writes the weeks of Strengthen programs. It reads the program's weeks into the rules' value types,
//  runs them, and writes the plans back onto the next week's exercises.
//

import Foundation
import OSLog
import SwiftData

enum StrengthPlanner: WeekPlanner {
    /// The time the planner reads as now, when it closes a week or sets up a new program. Nil is now; tests
    /// set it to replay programs on a simulated calendar.
    @TaskLocal static var currentDate: Date?

    /// Program.init runs this before the program is saved, so lift records can't be read yet: week 1
    /// is planned by feel here, and `prepareToStart` reloads each workout from the records as it starts.
    static func setUpFirstWeek(_ week: ProgramWeek, in program: Program) {
        week.setBlock(kind: .build, blockWeek: 1)
        plan(week, history: [], state: StrengthState(), at: currentDate ?? .now)
    }

    /// Closes the week before `week`, logs the lift records and plans `week` from them.
    static func build(_ week: ProgramWeek, in program: Program) {
        let weeks = program.programWeeks
        guard
            week.workouts.isEmpty,
            let index = weeks.firstIndex(where: { $0 === week }),
            index > 0
        else {
            Logger.program.warning("Can only build an empty ProgramWeek that follows another week.")
            return
        }
        let now = currentDate ?? .now
        let source = weeks[index - 1]
        let state = close(source, in: program, at: now)

        for sourceWorkout in source.workouts {
            guard let workout = week.addWorkout() else { continue }
            for sourceExercise in sourceWorkout.workoutExercises {
                guard
                    let exercise = sourceExercise.exercise,
                    let workoutExercise = workout.addWorkoutExercise(exercise: exercise)
                else { continue }
                workoutExercise.inheritWarmupsDisabled(from: sourceExercise)
                // Last week's warmups carry over until the plan writes its own (5.7).
                for warmup in sourceExercise.warmupSets.prefix(WorkoutExercise.maxWarmupSets) {
                    workoutExercise.addPlannedSet(
                        type: .warmup,
                        plannedReps: warmup.reps ?? warmup.repsPlanned,
                        plannedWeightTenthsPounds: warmup.weightTenthsPounds ?? warmup.weightTenthsPlannedPounds
                    )
                }
            }
        }
        week.setBlock(kind: state.clock.upcoming, blockWeek: state.clock.blockWeek)
        plan(week, history: Array(weeks[..<index].reversed()), state: state, at: now)
        Logger.program.info("Built strength week \(index + 1): \(state.clock.upcoming.rawValue), block week \(state.clock.blockWeek)")
    }

    /// A program's last week, or the week it stopped in, has no next week to build, but its sessions still
    /// move the lift records and the block clock, which carry over to the next program (4, 9.5, 15.1).
    static func close(_ week: ProgramWeek, in program: Program) {
        close(week, in: program, at: currentDate ?? .now)
    }

    /// Folds a finished week into the lift records and logs them (the weekly loop, steps 1-4).
    @discardableResult
    private static func close(_ week: ProgramWeek, in program: Program, at now: Date) -> StrengthState {
        var state = StrengthLog.latestState(in: program.modelContext)
        StrengthWeekClose.close(&state, week: closedWeek(week, at: now))
        program.modelContext?.insert(StrengthLog(date: now, state: state))
        return state
    }

    /// Runs the rules that depend on what happened since the week was planned: a lift's first week loads
    /// from its record, a break restarts it lighter (12.1), and pain lowers it or opens a check-in (15).
    static func prepareToStart(_ workout: Workout, in program: Program, at date: Date) {
        guard let week = program.programWeek(containing: workout) else { return }
        let earlierWeeks = Array(program.programWeeks.filter { $0.order < week.order }.reversed())
        var state = StrengthLog.latestState(in: program.modelContext)
        let slots = slotsByExercise(in: week)

        // This week's finished sessions move pain and the break clock, as the week's close will.
        var returnBands: [String: Int] = [:]
        let finished = week.workouts.filter { $0 !== workout && $0.isFinished }.flatMap(\.workoutExercises)
        let sessions = finished.compactMap { workoutExercise in
            slots[ObjectIdentifier(workoutExercise)].map { ($0, session(of: workoutExercise, role: $0.role)) }
        }
        for (slot, session) in sessions.sorted(by: { ($0.1.date ?? .distantPast) < ($1.1.date ?? .distantPast) }) {
            StrengthPain.record(&state[slot.key].pain, session: session)
            if session.plan.kind == .returnWeek1, session.trained { returnBands[slot.key] = session.plan.returnBand }
        }
        // A new program starts where the block clock left off.
        if week.order == 0, !week.workouts.contains(where: { $0.status != .planned && $0 !== workout }) {
            week.setBlock(kind: state.clock.upcoming, blockWeek: state.clock.blockWeek)
        }

        for workoutExercise in workout.workoutExercises where workoutExercise.status == .planned {
            guard
                let slot = slots[ObjectIdentifier(workoutExercise)],
                let exercise = workoutExercise.exercise
            else { continue }
            let history = slotHistory(of: workoutExercise, in: workout, weeks: earlierWeeks, slots: slot)
            let record = state[slot.key]
            let context = slotContext(slot, exercise: exercise, history: history, state: state)
            let stored = storedPlan(of: workoutExercise, role: slot.role)
            var plan = history.isEmpty
                ? StrengthPrescriber.plan(context, record: record, clock: state.clock, at: date)
                : stored

            if slot.role != .accessory, let grid = context.grid, plan.kind != .returnWeek1 {
                // A lift the records show trained in the last 14 days is not on a break, which spares searching every
                // set it ever had for training in other programs.
                let breakBand = record.lastTrained != nil && returnBand(since: record.lastTrained, at: date) == nil
                    ? nil
                    : returnBand(since: [record.lastTrained, lastCompleted(exercise, before: workout)].compactMap { $0 }.max(), at: date)
                let band = returnBands[slot.key] ?? breakBand
                if let band {
                    let preBreak = history.first { ($0.plan.kind == .normal || $0.plan.kind == .calibration) && $0.hasLoad }
                    StrengthSessionRules.applyReturn(
                        band: band,
                        to: &plan,
                        preBreakKg: preBreak?.plan.intendedKg,
                        e1rmKg: record.e1rmKg,
                        curve: context.curve,
                        grid: grid
                    )
                }
            }
            let needsCheckIn = StrengthPain.apply(
                record.pain,
                to: &plan,
                lastSession: history.first(where: \.trained),
                grid: context.grid
            )
            if plan != stored {
                // A break or pain moves the working load, and the warm-ups follow it (5.7).
                if slot.role != .accessory {
                    plan.warmups = StrengthPrescriber.warmups(for: plan, slot: context, record: record)
                }
                write(plan, to: workoutExercise, role: slot.role)
            }
            if needsCheckIn, let pain = record.pain.ratings.last.flatMap(LevelOfPain.init(rawValue:)) {
                workoutExercise.requireCheckIn(sourcePain: pain)
            }
        }
    }

    // MARK: Planning

    private static func plan(_ week: ProgramWeek, history: [ProgramWeek], state: StrengthState, at now: Date) {
        let slots = slotsByExercise(in: week)
        var plans: [(workoutExercise: WorkoutExercise, slot: Slot, plan: StrengthSlotPlan)] = []
        for workout in week.workouts {
            for workoutExercise in workout.workoutExercises {
                guard
                    let slot = slots[ObjectIdentifier(workoutExercise)],
                    let exercise = workoutExercise.exercise
                else { continue }
                let sessions = slotHistory(of: workoutExercise, in: workout, weeks: history, slots: slot)
                let context = slotContext(slot, exercise: exercise, history: sessions, state: state)
                plans.append((workoutExercise, slot, StrengthPrescriber.plan(context, record: state[slot.key], clock: state.clock, at: now)))
            }
        }
        // When a lift's heavy and moderate slots share a load, the heavy one keeps the lower reps (adopted fix 4).
        for index in plans.indices where plans[index].slot.zone == .heavy {
            let heavy = plans[index]
            guard let moderate = plans.first(where: { $0.slot.key == heavy.slot.key && $0.slot.zone == .moderate })?.plan,
                  heavy.plan.loadKg != nil, heavy.plan.loadKg == moderate.loadKg,
                  heavy.plan.targetReps > moderate.targetReps
            else { continue }
            plans[index].plan.repOffset = moderate.targetReps - heavy.plan.reps
            plans[index].plan.sets = StrengthSlotPlan.uniform(heavy.plan.sets.count, reps: moderate.targetReps, loadKg: heavy.plan.loadKg)
        }
        for (workoutExercise, slot, plan) in plans {
            write(plan, to: workoutExercise, role: slot.role)
        }
    }

    private static func write(_ plan: StrengthSlotPlan, to workoutExercise: WorkoutExercise, role: StrengthRole) {
        let loaded = role != .accessory
        workoutExercise.replacePlannedWorkingSets(plan.sets.map { ($0.reps, $0.loadKg.map { WeightUnit.tenthsPounds(fromKilograms: $0) }) })
        if let warmups = plan.warmups {
            workoutExercise.replacePlannedWarmups(warmups.map { ($0.reps, $0.loadKg.map { WeightUnit.tenthsPounds(fromKilograms: $0) }) })
        }
        workoutExercise.setProgression(rirTarget: loaded ? plan.rir : nil, code: plan.code, note: note(for: plan))
        workoutExercise.setStrengthTargets(
            role: role,
            reps: loaded ? plan.reps : nil,
            repOffset: loaded ? plan.repOffset : nil,
            intendedLoadKg: plan.intendedKg
        )
    }

    /// The line under an exercise's aim that says why its plan looks the way it does.
    static func note(for plan: StrengthSlotPlan) -> String? {
        switch plan.kind {
        case .calibration where plan.loadKg == nil:
            "Pick a weight you could lift \(plan.repsToFailure) times. Do \(plan.reps)."
        case .deload: "Deload week: lighter, to shed fatigue."
        case .microDeload: "One lighter week for this lift."
        case .returnWeek1, .returnWeek2: "Back from a break, a little lighter."
        case .painLighter: "Lighter while the pain settles."
        case .painCut: "Eased off for pain. It builds back with each pain-free session."
        case .normal where plan.rules.contains("11.5"): "Changed up to get past a plateau."
        default: nil
        }
    }

    // MARK: Reading the program

    struct Slot {
        var key: String
        var role: StrengthRole
        var zone: StrengthZone?
        /// Which of this exercise's slots in its workout it is, for matching across weeks.
        var occurrence: Int
    }

    /// Every exercise of the week with its role. A priority lift's slots alternate heavy and moderate
    /// in workout order (5.3).
    static func slotsByExercise(in week: ProgramWeek) -> [ObjectIdentifier: Slot] {
        let priorityKeys = StrengthLifts.priorityKeys(in: week.workouts.map { $0.workoutExercises.compactMap(\.exercise) })
        var slots: [ObjectIdentifier: Slot] = [:]
        var liftSlots: [String: Int] = [:]
        for workout in week.workouts {
            var occurrences: [String: Int] = [:]
            for workoutExercise in workout.workoutExercises {
                guard let exercise = workoutExercise.exercise else { continue }
                let key = StrengthLifts.key(for: exercise)
                let role = StrengthLifts.role(of: exercise, priorityKeys: priorityKeys)
                liftSlots[key, default: 0] += 1
                let zone: StrengthZone? = role == .primary
                    ? (liftSlots[key, default: 1].isMultiple(of: 2) ? .moderate : .heavy)
                    : nil
                slots[ObjectIdentifier(workoutExercise)] = Slot(key: key, role: role, zone: zone, occurrence: occurrences[key, default: 0])
                occurrences[key, default: 0] += 1
            }
        }
        return slots
    }

    /// The same slot in earlier weeks, newest first: same day, same exercise, same place among its repeats.
    private static func slotHistory(
        of workoutExercise: WorkoutExercise,
        in workout: Workout,
        weeks: [ProgramWeek],
        slots slot: Slot
    ) -> [StrengthSession] {
        weeks.compactMap { week in
            guard let earlierWorkout = week.workouts.first(where: { $0.order == workout.order }) else { return nil }
            let matches = earlierWorkout.workoutExercises.filter { $0.exercise === workoutExercise.exercise }
            guard matches.indices.contains(slot.occurrence) else { return nil }
            return session(of: matches[slot.occurrence], role: slot.role)
        }
    }

    private static func slotContext(_ slot: Slot, exercise: Exercise, history: [StrengthSession], state: StrengthState) -> StrengthSlotContext {
        let parent = exercise.catalogID.flatMap { StrengthLifts.variants[$0] }.map { variant in
            (record: state[variant.parentID], ratio: variant.ratio)
        }
        return StrengthSlotContext(
            key: slot.key,
            role: slot.role,
            zone: slot.zone,
            curve: StrengthLifts.curve(for: exercise),
            grid: LoadGrid(equipment: exercise.exerciseEquipment),
            needsSpotter: StrengthLifts.needsSpotter(exercise),
            repRange: exercise.repRange,
            history: history,
            parent: parent
        )
    }

    private static func closedWeek(_ week: ProgramWeek, at now: Date) -> StrengthClosedWeek {
        let slots = slotsByExercise(in: week)
        let entries = week.workouts.flatMap(\.workoutExercises).compactMap { workoutExercise -> StrengthClosedWeek.Entry? in
            guard let slot = slots[ObjectIdentifier(workoutExercise)], let exercise = workoutExercise.exercise else { return nil }
            return StrengthClosedWeek.Entry(
                key: slot.key,
                role: slot.role,
                zone: slot.zone,
                curve: StrengthLifts.curve(for: exercise),
                session: session(of: workoutExercise, role: slot.role)
            )
        }
        return StrengthClosedWeek(
            entries: entries,
            priorityKeys: StrengthLifts.priorityKeys(in: week.workouts.map { $0.workoutExercises.compactMap(\.exercise) }),
            kind: week.weekKind ?? .build,
            closedAt: now
        )
    }

    /// The plan written on a slot. Slots the planner never wrote (a swapped exercise) read as by-feel weeks.
    private static func storedPlan(of workoutExercise: WorkoutExercise, role: StrengthRole) -> StrengthSlotPlan {
        let parsed = StrengthSlotPlan.parse(code: workoutExercise.progressionCode)
        let sets = workoutExercise.workingSets.map {
            StrengthPlannedSet(reps: $0.repsPlanned, loadKg: $0.weightTenthsPlannedPounds.map { WeightUnit.kilograms(fromTenthsPounds: $0) })
        }
        return StrengthSlotPlan(
            kind: parsed?.kind ?? (role == .accessory ? .accessory : .calibration),
            reps: workoutExercise.targetReps ?? sets.first?.reps ?? StrengthRules.repsMinNormal,
            rir: workoutExercise.rirTarget ?? 2,
            sets: sets,
            repOffset: workoutExercise.repOffset ?? 0,
            intendedKg: workoutExercise.intendedLoadKg,
            returnBand: parsed?.returnBand ?? 0,
            rules: parsed?.rules ?? []
        )
    }

    private static func session(of workoutExercise: WorkoutExercise, role: StrengthRole) -> StrengthSession {
        let working = workoutExercise.workingSets
        return StrengthSession(
            plan: storedPlan(of: workoutExercise, role: role),
            sets: working.map {
                StrengthSession.LoggedSet(
                    loadKg: $0.weightTenthsPounds.map { WeightUnit.kilograms(fromTenthsPounds: $0) },
                    reps: $0.reps,
                    plannedLoadKg: $0.weightTenthsPlannedPounds.map { WeightUnit.kilograms(fromTenthsPounds: $0) },
                    completed: $0.status == .complete
                )
            },
            rir: workoutExercise.feedback?.repsInReserve?.rawValue,
            pain: workoutExercise.feedback?.levelOfPain.rawValue,
            date: working.filter { $0.status == .complete }.compactMap(\.completedAt).max()
        )
    }

    /// The break band (12.2) for a lift last trained at `lastTrained`, or `nil` when it isn't on a break.
    private static func returnBand(since lastTrained: Date?, at date: Date) -> Int? {
        StrengthSessionRules.daysOff(since: lastTrained, at: date).flatMap { StrengthSessionRules.returnBand(daysOff: $0) }
    }

    /// When the exercise last had a working set done, in any program, so training in other styles counts.
    private static func lastCompleted(_ exercise: Exercise, before workout: Workout) -> Date? {
        (exercise.workoutExercisesValue ?? [])
            .filter { $0.workoutValue !== workout }
            .flatMap(\.workingSets)
            .filter { $0.status == .complete }
            .compactMap(\.completedAt)
            .max()
    }

    // MARK: In session

    /// 6.2: a working set short of its target reps lowers the prefilled loads of the sets still to do.
    /// Sets the lifter already changed keep their weight.
    static func didComplete(_ workoutSet: WorkoutSet, in workoutExercise: WorkoutExercise) {
        guard
            workoutExercise.strengthRole != nil,
            !workoutSet.isWarmup,
            workoutSet.status == .complete,
            let planned = workoutSet.repsPlanned,
            let reps = workoutSet.reps, reps < planned,
            let load = workoutSet.weightTenthsPounds,
            let exercise = workoutExercise.exercise,
            let grid = LoadGrid(equipment: exercise.exerciseEquipment)
        else { return }

        for later in workoutExercise.workingSets where later.order > workoutSet.order && later.status == .active {
            // Weeks picked by feel have no planned load, so the short set's own load stands in for it.
            let plannedLoad = later.weightTenthsPlannedPounds ?? load
            guard [nil, plannedLoad, load].contains(later.weightTenthsPounds) else { continue }
            let cut = StrengthSessionRules.loadAfterMiss(
                setLoadKg: WeightUnit.kilograms(fromTenthsPounds: load),
                missingReps: planned - reps,
                plannedKg: WeightUnit.kilograms(fromTenthsPounds: plannedLoad),
                grid: grid
            )
            later.weightTenthsPounds = WeightUnit.tenthsPounds(fromKilograms: cut)
        }
    }
}

extension WorkoutExercise {
    /// Strengthen rests 3:00 after priority lift sets and 2:15 after their close variants (5.6), unless the
    /// exercise has its own rest. Keyed off the slot's role, which only StrengthPlanner sets, so the rest
    /// timer never reaches up to the Program.
    var strengthRestDuration: Duration? {
        guard exercise?.customRestTime == nil else { return nil }
        switch strengthRole {
        case .primary: return .seconds(StrengthRules.restPrimarySeconds)
        case .secondary: return .seconds(StrengthRules.restSecondarySeconds)
        case .accessory, nil: return nil
        }
    }
}
