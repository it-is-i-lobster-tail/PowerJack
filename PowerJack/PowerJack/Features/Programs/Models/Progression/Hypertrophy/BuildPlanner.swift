//
//  BuildPlanner.swift
//  PowerJack
//
//  Runs the Build engine on a program: reads its weeks into the engine's inputs and writes the plan back.
//

import Foundation
import OSLog

enum BuildPlanner: WeekPlanner {
    /// When a new program starts, for reading how recent its seed sets are. Nil is now; tests set it to
    /// replay programs on a simulated calendar.
    @TaskLocal static var startDate: Date?

    /// Week 1 is block week 1. Exercises lifted recently in another program start from those sets; the rest
    /// calibrate, leaving the weight to the lifter (START-03, START-04).
    static func setUpFirstWeek(_ week: ProgramWeek, in program: Program) {
        week.setBlock(kind: .build, blockWeek: 1)
        let weekOne = BuildWeek(kind: .build, blockWeek: 1)
        for workout in week.workouts {
            for workoutExercise in workout.workoutExercises {
                guard let exercise = workoutExercise.exercise else { continue }
                let info = exerciseInfo(exercise)
                let recent = seed(for: exercise, outside: program, at: startDate ?? .now)
                if let recent {
                    workoutExercise.replacePlannedWorkingSets(
                        Array(repeating: (recent.reps, recent.load), count: max(1, workoutExercise.workingSets.count))
                    )
                }
                let reason: BuildReason = recent.map { $0.calibrate ? .calibrate(repsOnly: info.repsOnly) : .startHistory }
                    ?? .calibrate(repsOnly: info.repsOnly)
                let aim = BuildEngine.aim(
                    for: weekOne,
                    exercise: info,
                    reps: recent?.reps,
                    failureBlocked: true,
                    calibrating: reason.code == .calibrate
                )
                workoutExercise.setProgression(rirTarget: aim, code: reason.code.rawValue, note: reason.message)
            }
        }
    }

    /// Fills an empty week once the week before it is finished (CLOCK 2).
    static func build(_ week: ProgramWeek, in program: Program) {
        let weeks = program.programWeeks
        guard
            week.workouts.isEmpty,
            let weekIndex = weeks.firstIndex(where: { $0 === week }),
            weekIndex > 0
        else {
            Logger.program.warning("Can only build an empty ProgramWeek that follows another week.")
            return
        }
        let sourceWeek = weeks[weekIndex - 1]
        let entries = sourceWeek.workouts.flatMap { workout in
            workout.workoutExercises.filter { $0.exercise != nil }.map { (workout, $0) }
        }
        let plan = BuildEngine.plan(input(for: program, through: weekIndex - 1, slots: entries))

        var plans = plan.slots.makeIterator()
        for sourceWorkout in sourceWeek.workouts {
            guard let workout = week.addWorkout() else { continue }
            for sourceExercise in sourceWorkout.workoutExercises {
                guard let exercise = sourceExercise.exercise, let slotPlan = plans.next() else { continue }
                guard let workoutExercise = workout.addWorkoutExercise(exercise: exercise) else { continue }
                // Warmups repeat what was logged last week, including how many. They never progress.
                workoutExercise.inheritWarmupsDisabled(from: sourceExercise)
                let sourceWarmups = sourceExercise.warmupSets
                let warmupCount = sourceWarmups.isEmpty ? WorkoutExercise.initialWarmupSets : sourceWarmups.count
                for index in 0..<warmupCount {
                    let warmup = sourceWarmups.indices.contains(index) ? sourceWarmups[index] : nil
                    workoutExercise.addPlannedSet(
                        type: .warmup,
                        plannedReps: warmup.flatMap { $0.reps ?? $0.repsPlanned },
                        plannedWeightTenthsPounds: warmup.flatMap { $0.weightTenthsPounds ?? $0.weightTenthsPlannedPounds }
                    )
                }
                write(slotPlan, to: workoutExercise)
            }
        }
        week.setBlock(kind: plan.week.kind, blockWeek: plan.week.blockWeek, returnBand: plan.week.returnBand)
        Logger.program.info("Built Build week \(weekIndex + 1): \(plan.week.kind.rawValue) \(plan.week.blockWeek)")
    }

    /// The first workout after 15 or more days off replans the week's unstarted workouts, once a week (CLOCK 0).
    static func prepareToStart(_ workout: Workout, in program: Program, at date: Date) {
        let weeks = program.programWeeks
        guard
            let weekIndex = weeks.firstIndex(where: { week in week.workouts.contains { $0 === workout } }),
            // A week that handled a break became week 1 of a block or of a return. Later return weeks keep the
            // band but handled no break, so they still catch the next one.
            !(weeks[weekIndex].returnBand > 0 && weeks[weekIndex].blockWeek == 1),
            let lastSet = lastCompletedSetAt(in: program)
        else {
            return
        }
        let days = date.timeIntervalSince(lastSet) / 86_400
        guard let bandIndex = BuildRules.returnBandsDays.lastIndex(where: { days >= Double($0) }) else { return }
        let band = bandIndex + 1
        let week = weeks[weekIndex]

        // A break right at a block's start needs nothing new, and week 1 has nothing earlier to plan from.
        guard weekIndex > 0, !(band == 1 && week.weekKind == .build && week.blockWeek == 1) else {
            week.setBlock(kind: week.weekKind ?? .build, blockWeek: max(week.blockWeek, 1), returnBand: band)
            return
        }
        let entries = week.workouts
            .filter { $0.status == .planned }
            .flatMap { workout in workout.workoutExercises.filter { $0.exercise != nil }.map { (workout, $0) } }
        let plan = BuildEngine.planAfterBreak(input(for: program, through: weekIndex - 1, slots: entries), band: band)
        for ((_, workoutExercise), slotPlan) in zip(entries, plan.slots) {
            workoutExercise.replacePlannedWorkingSets(
                Array(repeating: (slotPlan.reps, slotPlan.load), count: slotPlan.sets)
            )
            write(progressionOf: slotPlan, to: workoutExercise)
        }
        week.setBlock(kind: plan.week.kind, blockWeek: plan.week.blockWeek, returnBand: band)
        Logger.program.info("Replanned Build week \(weekIndex + 1) after \(Int(days)) days off (band \(band))")
    }
}

//
// Reading the program
//
extension BuildPlanner {
    /// The engine's input for planning after week `lastWeek`, with one slot per `(workout, exercise)` entry.
    static func input(
        for program: Program,
        through lastWeek: Int,
        slots entries: [(workout: Workout, exercise: WorkoutExercise)]
    ) -> BuildInput {
        let weeks = Array(program.programWeeks.prefix(lastWeek + 1))
        let shortGaps = ShortGaps(weeks: weeks)
        // Entries without an exercise have no slot, so callers leave them out.
        let slots = entries.compactMap { workout, workoutExercise -> BuildSlot? in
            guard let exercise = workoutExercise.exercise else { return nil }
            let occurrence = workout.workoutExercises
                .prefix { $0 !== workoutExercise }
                .count(where: { $0.exercise === exercise })
            let history = weeks.enumerated().compactMap { weekIndex, week -> BuildExposure? in
                guard
                    let pastWorkout = week.workouts.first(where: { $0.order == workout.order }),
                    let past = pastWorkout.workoutExercises.filter({ $0.exercise === exercise }).dropFirst(occurrence).first
                else {
                    return nil
                }
                var exposure = self.exposure(past, weekIndex: weekIndex)
                exposure.shortGap = shortGaps.isShort(exposure, muscle: exercise.primaryMuscleFocus)
                return exposure
            }
            return BuildSlot(workout: workout.order, exercise: exerciseInfo(exercise), history: history)
        }
        return BuildInput(
            weeks: weeks.enumerated().map { buildWeek($1, index: $0) },
            slots: slots,
            focus: Set(program.templateMuscleFocus)
        )
    }

    static func exerciseInfo(_ exercise: Exercise) -> BuildExercise {
        BuildExercise(
            minReps: exercise.repRange.lowerBound,
            maxReps: exercise.repRange.upperBound,
            primary: exercise.primaryMuscleFocus,
            secondary: exercise.secondaryMuscles,
            repsOnly: exercise.repsOnly,
            fatigueLevel: exercise.fatigueLevel
        )
    }

    static func exposure(_ workoutExercise: WorkoutExercise, weekIndex: Int) -> BuildExposure {
        let feedback = workoutExercise.feedback
        let effort: BuildEffort = if let rir = feedback?.repsInReserve {
            .tapped(rir.rawValue)
        } else if let feedback {
            BuildEffort(legacy: feedback.levelOfEffort)
        } else {
            .missing
        }
        return BuildExposure(
            weekIndex: weekIndex,
            sets: workoutExercise.workingSets.map {
                BuildSet(
                    plannedReps: $0.repsPlanned,
                    plannedLoad: $0.weightTenthsPlannedPounds,
                    reps: $0.reps,
                    load: $0.weightTenthsPounds,
                    completed: $0.status == .complete,
                    completedAt: $0.completedAt
                )
            },
            effort: effort,
            pain: feedback?.levelOfPain,
            rirTarget: workoutExercise.rirTarget,
            code: workoutExercise.progressionCode.flatMap(BuildReason.Code.init(rawValue:)),
            checkIn: workoutExercise.checkIn,
            checkInSourcePain: workoutExercise.checkInSourcePain
        )
    }

    /// Weeks written before blocks were stored read as build weeks, four to a block.
    static func buildWeek(_ week: ProgramWeek, index: Int) -> BuildWeek {
        guard let kind = week.weekKind, week.blockWeek > 0 else {
            return BuildWeek(kind: .build, blockWeek: index % BuildRules.buildWeeks + 1)
        }
        return BuildWeek(kind: kind, blockWeek: week.blockWeek, returnBand: week.returnBand)
    }

    /// When the program's last working set was completed. Skipping never moves it, so a skip can't hide a break.
    static func lastCompletedSetAt(in program: Program) -> Date? {
        program.programWeeks
            .flatMap(\.workouts)
            .flatMap(\.workoutExercises)
            .flatMap(\.workingSets)
            .filter { $0.status == .complete }
            .compactMap(\.completedAt)
            .max()
    }
}

//
// Writing the plan
//
private extension BuildPlanner {
    static func write(_ plan: BuildSlotPlan, to workoutExercise: WorkoutExercise) {
        for _ in 0..<plan.sets {
            workoutExercise.addPlannedSet(plannedReps: plan.reps, plannedWeightTenthsPounds: plan.load)
        }
        write(progressionOf: plan, to: workoutExercise)
    }

    static func write(progressionOf plan: BuildSlotPlan, to workoutExercise: WorkoutExercise) {
        workoutExercise.setProgression(
            rirTarget: plan.rirTarget,
            code: plan.reason.code.rawValue,
            note: plan.reason.message
        )
        if let pain = plan.checkInPain, !workoutExercise.checkInPending {
            workoutExercise.requireCheckIn(sourcePain: pain)
        }
    }
}

//
// Starting from history (START-04)
//
extension BuildPlanner {
    struct Seed: Equatable {
        var reps: Int?
        var load: Int?
        /// Old enough to need a cut, so the first week still checks it.
        var calibrate: Bool
    }

    /// The exercise's most recent rated sets from another program in the last 26 weeks, solved for 3 reps left.
    static func seed(for exercise: Exercise, outside program: Program, at date: Date) -> Seed? {
        let maxAge: TimeInterval = 26 * 7 * 86_400
        let candidates = (exercise.workoutExercisesValue ?? []).compactMap { past -> (Int, Int?, Int, Date)? in
            guard
                past.workoutValue?.programWeekValue?.programValue !== program,
                let rir = past.feedback?.repsInReserve?.rawValue,
                let last = past.workingSets.last(where: { $0.status == .complete }),
                let reps = last.reps,
                let completedAt = last.completedAt,
                date.timeIntervalSince(completedAt) <= maxAge
            else {
                return nil
            }
            return (reps, last.weightTenthsPounds, rir, completedAt)
        }
        .sorted { $0.3 > $1.3 }
        // Short sets estimate the max best (AUTO-14).
        guard let (reps, load, rir, completedAt) = candidates.first(where: { $0.0 + $0.2 <= 10 }) ?? candidates.first else {
            return nil
        }
        let info = exerciseInfo(exercise)
        let days = Int(date.timeIntervalSince(completedAt) / 86_400)
        let band = BuildRules.returnBandsDays.lastIndex { days >= $0 }.map { $0 + 1 } ?? 0
        let keep = band == 0 ? 1 : (100 - BuildRules.returnLoadCutPct[band - 1]) / 100
        let calibrate = keep < 1
        if info.repsOnly {
            let target = min(max(reps + rir - BuildRules.startRIR, info.minReps), BuildRules.bodyweightRepCap)
            return Seed(reps: target, load: nil, calibrate: calibrate)
        }
        guard
            let load,
            let estimatedMax = EstimatedMax(loadTenths: load, reps: reps, repsInReserve: rir),
            !estimatedMax.isLowerBound
        else {
            return nil
        }
        let target = min(max(reps, info.minReps), info.maxReps)
        guard let solved = estimatedMax.loadTenths(forReps: target, leaving: BuildRules.startRIR) else { return nil }
        let seeded = min(max(BuildRules.stepTenths, BuildEngine.floorToStep(solved * keep)), BuildRules.maxLoad)
        return Seed(reps: target, load: seeded, calibrate: calibrate)
    }
}

/// Which exposures came within 48 hours of a hard session for the same muscle that ended at 0 reps left or short (FREQ-05).
private struct ShortGaps {
    private struct Session {
        var start: Date
        var end: Date
        /// Muscles the workout trained as a primary.
        var trained: Set<Muscle>
        /// Muscles with a slot that ended at 0 reps left or missed reps.
        var endedHard: Set<Muscle>
    }

    private let sessions: [Session]

    init(weeks: [ProgramWeek]) {
        sessions = weeks.flatMap(\.workouts).compactMap { workout in
            var start: Date?
            var end: Date?
            var trained: Set<Muscle> = []
            var endedHard: Set<Muscle> = []
            for workoutExercise in workout.workoutExercises {
                let done = workoutExercise.workingSets.filter { $0.status == .complete }
                guard let muscle = workoutExercise.exercise?.primaryMuscleFocus, !done.isEmpty else { continue }
                for date in done.compactMap(\.completedAt) {
                    start = min(start ?? date, date)
                    end = max(end ?? date, date)
                }
                trained.insert(muscle)
                let missed = done.contains { set in set.repsPlanned.map { (set.reps ?? $0) < $0 } ?? false }
                if missed || workoutExercise.feedback?.repsInReserve == .zero {
                    endedHard.insert(muscle)
                }
            }
            guard let start, let end else { return nil }
            return Session(start: start, end: end, trained: trained, endedHard: endedHard)
        }
    }

    func isShort(_ exposure: BuildExposure, muscle: Muscle) -> Bool {
        guard let start = exposure.startedAt else { return false }
        let previous = sessions
            .filter { $0.trained.contains(muscle) && $0.end < start }
            .max { $0.end < $1.end }
        guard let previous, previous.endedHard.contains(muscle) else { return false }
        return start.timeIntervalSince(previous.end) < BuildRules.minHoursBetweenHardSessions * 3_600
    }
}
