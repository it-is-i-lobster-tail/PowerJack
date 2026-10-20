//
//  BuildSimDriver.swift
//  PowerJackTests
//
//  Runs one simulated lifter through the app for months or years, the way the UI does: programs started
//  from Build templates, workouts started, logged, rated, skipped and cut short, exercises swapped and
//  edited, and breaks in between. Every week the Build planner writes goes to `BuildSimChecker`.
//

import Foundation
import SwiftData
@testable import PowerJack

@MainActor
final class BuildSimDriver {
    /// Monday 4 January 2027, midnight UTC.
    static let firstDay = Date(timeIntervalSince1970: 1_799_020_800)

    let seed: UInt64
    let profile: BuildSimProfile
    let weeks: Int
    private let lifter: BuildSimLifter
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    /// Catalog exercises in catalog order, then the lifter's own.
    private let exercises: [Exercise]
    private let catalogTemplates: [TemplateProgram]
    private var checker = BuildSimChecker()
    private var report: BuildSimReport

    private var program: Program?
    private var programNumber = 0
    private var lastTemplate: TemplateProgram?
    private var customTemplates = 0
    private var nextProgramDay = 0
    private var breakEndsDay = 0
    private var trainingDays: Set<Int> = []
    private var lastTrained: Date?
    /// Trained build weeks in a row since the last deload, return week or break, across programs.
    private var buildRun = 0
    /// The pain tapped the last time each exercise was done, nil when it went unrated.
    private var lastPain: [String: LevelOfPain] = [:]

    init(seed: UInt64, profile: BuildSimProfile, weeks: Int, keepsTrace: Bool = false) throws {
        self.seed = seed
        self.profile = profile
        self.weeks = weeks
        lifter = BuildSimLifter(profile: profile, seed: seed)
        report = BuildSimReport(seed: seed, profile: profile.name, weeks: weeks)
        report.keepsTrace = keepsTrace
        container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        try TemplateCatalog.seed(in: context)

        let stored = try context.fetch(FetchDescriptor<Exercise>())
        let exercisesByID = Dictionary(stored.compactMap { exercise in exercise.catalogID.map { ($0, exercise) } }) { first, _ in first }
        var draw = BuildSimRandom(seed: seed ^ 0xC057_0E)
        let ownExercises = Self.makeOwnExercises(&draw)
        ownExercises.forEach(context.insert)
        exercises = ExerciseCatalog.entries.compactMap { exercisesByID[$0.id] } + ownExercises

        let templates = try context.fetch(FetchDescriptor<TemplateProgram>())
        let templatesByID = Dictionary(templates.compactMap { template in template.catalogID.map { ($0, template) } }) { first, _ in first }
        // Whatever Build templates the catalog holds, so new ones are covered as they land.
        catalogTemplates = TemplateCatalog.entries.filter { $0.type == .hypertrophy }.compactMap { templatesByID[$0.id] }
        try context.save()
    }

    /// Lives through `weeks` calendar weeks and reports what the checks found.
    func run() throws -> BuildSimReport {
        for day in 0..<(weeks * 7) {
            let date = Self.firstDay.addingTimeInterval(Double(day) * 86_400)
            if day.isMultiple(of: 7) {
                startCalendarWeek(day: day, at: date)
            }
            guard day >= breakEndsDay else { continue }
            if program?.status != .active {
                guard day >= nextProgramDay else { continue }
                startProgram(at: date)
            }
            guard let program, trainingDays.contains(day % 7), !lifter.decides(profile.missDay) else { continue }

            let start = date.addingTimeInterval(17 * 3_600 + Double(lifter.rng.int(0...120)) * 60)
            train(program, at: start)
            if program.status == .active, lifter.decides(profile.doubleSession) {
                train(program, at: start.addingTimeInterval(3 * 3_600))
            }
            if program.status != .active {
                report.programsFinished += 1
                nextProgramDay = day + 1 + lifter.rng.pick(profile.daysBetweenPrograms)
            }
        }
        report.violations = checker.violations
        report.weeksChecked = checker.weeksChecked
        report.programs = programNumber
        return report
    }
}

//
// Calendar
//
private extension BuildSimDriver {
    func startCalendarWeek(day: Int, at date: Date) {
        lifter.endWeek(at: date)
        guard day >= breakEndsDay else { return }
        if lifter.decides(profile.breakChance) {
            let days = lifter.rng.pick(profile.breakDays)
            breakEndsDay = day + days
            report.breaks += 1
            report.trace("\(Self.dayText(date)) break of \(days) days")
            return
        }
        guard let program, program.status == .active else { return }
        if lifter.decides(profile.editExercise) {
            editExercise(in: program)
        }
        if lifter.decides(profile.abandonProgram) {
            report.programsAbandoned += 1
            startProgram(at: date)
        }
    }

    /// Starts a new program the way Programs › New does, stopping the active one.
    func startProgram(at date: Date) {
        let template = chooseTemplate()
        let length = lifter.rng.int(profile.programWeeks)
        let program = BuildPlanner.$startDate.withValue(date) {
            Program(programLengthWeeks: length, templateProgram: template)
        }
        // The app saves here. One in-memory context needs no saves, and skipping them keeps years of logs fast.
        context.insert(program)
        if let lastTrained, date.timeIntervalSince(lastTrained) >= Double(BuildRules.returnBandsDays[0]) * 86_400 {
            buildRun = 0
        }
        countPainLeftBehind(by: program)
        if let previous = self.program, previous.status == .active {
            previous.stop()
            previous.stopAndCascade()
        }
        program.start()
        self.program = program
        lastTemplate = template
        programNumber += 1
        trainingDays = Self.trainingDays(count: program.workoutsPerWeek, shift: lifter.rng.int(0...6))
        checker.place = "program \(programNumber) (\(template.templateName), \(length) wk)"
        report.trace("\(Self.dayText(date)) start \(checker.place)")
        checker.checkFirstWeek(of: program)
        traceWeek(of: program, index: 0)
    }

    func chooseTemplate() -> TemplateProgram {
        if let lastTemplate, lifter.decides(profile.sameTemplate) {
            return lastTemplate
        }
        if lifter.decides(profile.customTemplate) || catalogTemplates.isEmpty {
            return makeOwnTemplate()
        }
        return lifter.rng.pick(catalogTemplates)
    }

    static func trainingDays(count: Int, shift: Int) -> Set<Int> {
        let pattern: [Int] = switch count {
        case ...1: [0]
        case 2: [0, 3]
        case 3: [0, 2, 4]
        case 4: [0, 1, 3, 4]
        case 5: [0, 1, 2, 3, 4]
        default: [0, 1, 2, 3, 4, 5]
        }
        return Set(pattern.map { ($0 + shift) % 7 })
    }

    static func dayText(_ date: Date) -> String {
        "day \(Int(date.timeIntervalSince(firstDay) / 86_400))"
    }
}

//
// Workouts
//
private extension BuildSimDriver {
    func train(_ program: Program, at start: Date) {
        guard let workout = program.nextWorkout else { return }
        if workout.status == .planned {
            if lifter.decides(profile.skipWorkout) {
                finish(workout, in: program, skip: true, at: start)
                return
            }
            prepare(workout, in: program, at: start)
            workout.startAndCascade()
        }
        lifter.startSession()
        var clock = start
        var lines: [String] = []
        for workoutExercise in workout.workoutExercises {
            if let line = perform(workoutExercise, clock: &clock) {
                lines.append(line)
            }
        }
        report.trace("\(Self.dayText(start)) workout \(workout.order + 1): " + lines.joined(separator: "; "))
        // Finish Workout skips whatever is left unlogged.
        workout.skipRemainingSets()
        finish(workout, in: program, skip: false, at: start)
    }

    /// The planner's chance to replan the week after a long break, checked when it does (CLOCK 0).
    func prepare(_ workout: Workout, in program: Program, at date: Date) {
        let weeks = program.programWeeks
        guard let index = weeks.firstIndex(where: { week in week.workouts.contains { $0 === workout } }) else { return }
        let week = weeks[index]
        let (bandBefore, kindBefore, blockWeekBefore) = (week.returnBand, week.weekKind, week.blockWeek)
        program.prepareToStart(workout, at: date)
        guard week.returnBand != bandBefore else { return }
        report.returns += 1
        // A break right at a block's start, or in week 1, only marks the week (BuildPlanner.prepareToStart).
        let replanned = index > 0 && !(week.returnBand == 1 && kindBefore == .build && blockWeekBefore == 1)
        checker.checkBreak(in: program, week: index, band: week.returnBand, replanned: replanned)
        report.trace("\(Self.dayText(date)) break handled: band \(week.returnBand)\(replanned ? ", replanned" : "")")
        if replanned {
            traceWeek(of: program, index: index)
        }
    }

    func finish(_ workout: Workout, in program: Program, skip: Bool, at date: Date) {
        let weeks = program.programWeeks
        let index = weeks.firstIndex { week in week.workouts.contains { $0 === workout } }
        let nextWasEmpty = index.map { $0 + 1 < weeks.count && weeks[$0 + 1].workouts.isEmpty } ?? false
        let weekWasOpen = index.map { weeks[$0].status != .complete } ?? false
        if skip {
            program.skipWorkout(workout)
            report.workoutsSkipped += 1
            report.trace("\(Self.dayText(date)) workout \(workout.order + 1) skipped")
        } else {
            program.finishWorkout(workout)
            report.workouts += 1
        }
        if let index, weekWasOpen, weeks[index].status == .complete {
            countRun(of: weeks[index])
        }
        if let index, nextWasEmpty, !weeks[index + 1].workouts.isEmpty {
            checker.checkBuild(of: program, week: index + 1)
            traceWeek(of: program, index: index + 1)
            recordSlack(in: weeks[index + 1])
        }
    }

    /// Counts trained build weeks in a row, across programs: a deload, a return week or a break of 15 days or
    /// more starts the count again.
    func countRun(of week: ProgramWeek) {
        guard week.workouts.contains(where: { $0.completedWorkingSets > 0 }) else { return }
        if week.weekKind == .build {
            buildRun = week.returnBand > 0 ? 1 : buildRun + 1
            report.longestBuildRun = max(report.longestBuildRun, buildRun)
        } else {
            buildRun = 0
        }
    }

    /// Exercises that start a new program with no check-in, though they were painful (Moderate or worse) the last
    /// time they were done. PAIN-03 asks for pain state to carry over to a new program.
    func countPainLeftBehind(by program: Program) {
        guard let week = program.programWeeks.first else { return }
        for slot in BuildSimSlot.all(in: week) where !slot.workoutExercise.checkInPending {
            if let pain = lastPain[slot.name], pain.rawValue >= BuildRules.holdAt.rawValue {
                report.painLeftBehind += 1
            }
        }
    }

    /// How far each new build-week target sits from what the lifter can really do: reps left on a fresh first set.
    func recordSlack(in week: ProgramWeek) {
        guard week.weekKind == .build else { return }
        for slot in BuildSimSlot.all(in: week) {
            guard
                let code = slot.code,
                Self.progressionCodes.contains(code),
                let reps = slot.reps,
                let slack = lifter.slack(slot.exercise, load: slot.load, reps: reps)
            else {
                continue
            }
            report.record(slack: slack)
        }
    }

    /// Codes that ask for more than last time, or set a new baseline: the targets that must stay within reach.
    static let progressionCodes: Set<BuildReason.Code> = [
        .repsUp, .loadUp, .unratedStep, .blockRebase, .calibrated, .volumeRamp, .volumeUp,
    ]

    /// Does one exercise: answers its check-in, maybe swaps or skips it, logs each set and rates it.
    /// Returns a trace line.
    func perform(_ workoutExercise: WorkoutExercise, clock: inout Date) -> String? {
        if workoutExercise.checkInPending {
            workoutExercise.resolveCheckIn(lifter.rng.pick(weighted: profile.checkIn))
        }
        guard workoutExercise.status == .active, var exercise = workoutExercise.exercise else { return nil }
        if lifter.decides(profile.swapExercise), let swap = replacement(for: exercise) {
            workoutExercise.changeExercise(newExercise: swap)
            exercise = swap
        }
        if lifter.decides(profile.skipExercise) || (lifter.isHurt(exercise) && lifter.decides(0.5)) {
            workoutExercise.skipRemainingSets()
            return "\(exercise.exerciseName) skipped"
        }
        if workoutExercise.workingSets.count > 1, lifter.decides(profile.removeSet) {
            workoutExercise.removeLastSet()
        }
        if lifter.decides(profile.addSet) {
            _ = workoutExercise.addSet()
        }

        let aim = workoutExercise.rirTarget ?? BuildRules.startRIR
        let sets = workoutExercise.workingSets.filter { $0.status == .active }
        var plannedReps: Int?
        var repsLeft: Double?
        var logged: [String] = []
        for (index, set) in sets.enumerated() {
            if index > 0, lifter.decides(profile.stopEarly) { break }
            plannedReps = set.repsPlanned ?? plannedReps
            let planned = set.weightTenthsPounds ?? set.weightTenthsPlannedPounds
            if let load = lifter.load(for: exercise, planned: planned, reps: plannedReps, aim: aim) {
                set.weightTenthsPounds = load
            }
            let capacity = lifter.repsToFailure(exercise, load: set.weightTenthsPounds, setIndex: index)
            guard let reps = lifter.reps(planned: plannedReps, repsToFailure: capacity, isLast: index == sets.count - 1, aim: aim) else { break }
            set.reps = reps
            guard set.reps != nil, exercise.repsOnly || set.weightTenthsPounds != nil else { break }
            clock.addTimeInterval(Double(lifter.rng.int(90...240)))
            workoutExercise.completeSet(set, at: clock)
            lastTrained = clock
            lifter.didSet(exercise, repsLeft: capacity - Double(reps), at: clock)
            repsLeft = capacity - Double(reps)
            logged.append("\(reps)@\(BuildSimText.pounds(set.weightTenthsPounds))")
        }
        if !workoutExercise.allSetsDone() {
            workoutExercise.skipRemainingSets()
        }
        clock.addTimeInterval(120)
        guard let repsLeft else { return "\(exercise.exerciseName) nothing logged" }

        let pain = lifter.pain(after: exercise)
        guard workoutExercise.needsFeedback, !lifter.decides(profile.noRating) else {
            lastPain[exercise.exerciseName] = nil
            return "\(exercise.exerciseName) \(logged.joined(separator: ",")) unrated"
        }
        lastPain[exercise.exerciseName] = pain
        let feedback: ExerciseFeedback
        if lifter.decides(profile.legacyRating) {
            feedback = ExerciseFeedback(levelOfEffort: lifter.legacyWord(repsLeft: repsLeft), levelOfPain: pain)
        } else {
            feedback = ExerciseFeedback(repsInReserve: lifter.rating(repsLeft: repsLeft), levelOfPain: pain)
        }
        workoutExercise.addFeedback(feedback: feedback)
        let rating = feedback.repsInReserve.map { "rir \($0.valueText)" } ?? "word \(feedback.levelOfEffort.label)"
        return "\(exercise.exerciseName) \(logged.joined(separator: ",")) \(rating) pain \(pain.rawValue)"
    }

    func replacement(for exercise: Exercise) -> Exercise? {
        let sameMuscle = exercises.filter { $0 !== exercise && $0.primaryMuscleFocus == exercise.primaryMuscleFocus }
        let others = exercises.filter { $0 !== exercise }
        return sameMuscle.isEmpty ? (others.isEmpty ? nil : lifter.rng.pick(others)) : lifter.rng.pick(sameMuscle)
    }

    /// Changes one of this week's exercises the way the exercise editor allows.
    func editExercise(in program: Program) {
        let candidates = (program.nextWorkout?.workoutExercises ?? []).compactMap(\.exercise)
        guard !candidates.isEmpty else { return }
        let exercise = lifter.rng.pick(candidates)
        switch lifter.rng.int(0...3) {
        case 0:
            let minReps = lifter.rng.int(Exercise.minRepsAllowed...20)
            exercise.minReps = minReps
            exercise.maxReps = lifter.rng.int(minReps...Exercise.maxRepsAllowed)
        case 1:
            exercise.fatigueLevel = lifter.rng.pick(FatigueLevel.allCases)
        case 2 where exercise.userCreated:
            // Only the lifter's own exercises can change equipment.
            exercise.exerciseEquipment = exercise.repsOnly ? .dumbbell : .bodyweight
        default:
            exercise.maxReps = lifter.rng.int(exercise.minReps...Exercise.maxRepsAllowed)
        }
        report.edits += 1
        report.trace("edit \(exercise.exerciseName): \(exercise.minReps)-\(exercise.maxReps) reps, \(exercise.fatigueLevel.name), \(exercise.exerciseEquipment.rawValue)")
    }
}

//
// The lifter's own exercises and templates
//
private extension BuildSimDriver {
    /// A few exercises of the lifter's own, with ranges anywhere the editor allows.
    static func makeOwnExercises(_ draw: inout BuildSimRandom) -> [Exercise] {
        (1...6).map { number in
            let equipment = number <= 2 ? Equipment.bodyweight : draw.pick(Equipment.allCases)
            let primary = draw.pick(Muscle.allCases)
            var secondary: [Muscle] = []
            for muscle in Muscle.allCases where muscle != primary && secondary.count < maxSecondaryMuscles && draw.chance(0.15) {
                secondary.append(muscle)
            }
            let minReps = draw.int(Exercise.minRepsAllowed...Exercise.maxRepsAllowed)
            let maxReps = draw.chance(0.2) ? minReps : draw.int(minReps...Exercise.maxRepsAllowed)
            return Exercise(
                exerciseName: "Own Lift \(number)",
                exerciseEquipment: equipment,
                primaryMuscleFocus: primary,
                secondaryMuscles: secondary,
                userCreated: true,
                minReps: minReps,
                maxReps: maxReps,
                fatigueLevel: draw.pick(FatigueLevel.allCases)
            )
        }
    }

    /// A template of the lifter's own: 2 to 6 days of any exercises, repeats included, as the editor allows.
    func makeOwnTemplate() -> TemplateProgram {
        customTemplates += 1
        let pool = profile.name == BuildSimProfile.bodyweight.name ? exercises.filter(\.repsOnly) : exercises
        let days = lifter.rng.int(TemplateProgramDraft.minimumWorkoutsPerWeek...TemplateProgramDraft.maximumWorkoutsPerWeek)
        var focus: [Muscle] = []
        for _ in 0..<lifter.rng.int(1...TemplateProgramDraft.maximumFocusMuscles) {
            let muscle = lifter.rng.pick(Muscle.allCases)
            if !focus.contains(muscle) { focus.append(muscle) }
        }
        let template = TemplateProgram(templateName: "Own \(customTemplates)", workoutsPerWeek: days, templateMuscleFocus: focus)
        for _ in 0..<days {
            let workout = template.addTemplateWorkout()
            for _ in 0..<lifter.rng.int(1...7) {
                workout.addTemplateExercise(exercise: lifter.rng.pick(pool))
            }
        }
        context.insert(template)
        return template
    }
}

//
// Trace
//
private extension BuildSimDriver {
    func traceWeek(of program: Program, index: Int) {
        let weeks = program.programWeeks
        guard weeks.indices.contains(index) else { return }
        let week = weeks[index]
        let slots = BuildSimSlot.all(in: week, plannedOnly: true)
        for slot in slots {
            report.count(slot.code)
        }
        report.countWeek(week.weekKind)
        report.trace("  plan p\(programNumber) w\(index + 1) \(BuildSimText.describe(week)): "
            + slots.map { "\($0.name) \(BuildSimText.describe($0))" }.joined(separator: "; "))
    }
}
