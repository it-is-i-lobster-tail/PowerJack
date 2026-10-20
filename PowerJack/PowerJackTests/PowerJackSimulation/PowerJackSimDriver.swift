//
//  PowerJackSimDriver.swift
//  PowerJackTests
//
//  Runs one simulated lifter through the app for months or years, the way the UI does: programs started
//  from PowerJack templates (and now and then another style's), workouts started, logged, rated, skipped
//  and cut short, TOP sets rated, check-ins answered, exercises swapped and edited, and breaks in between.
//  Every week the PowerJack planner writes goes to `PowerJackSimChecker`.
//

import Foundation
import SwiftData
@testable import PowerJack

@MainActor
final class PowerJackSimDriver {
    /// Monday 4 January 2027, midnight UTC.
    static let firstDay = Date(timeIntervalSince1970: 1_799_020_800)

    let seed: UInt64
    let profile: PowerJackSimProfile
    let weeks: Int
    private let lifter: PowerJackSimLifter
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    /// Catalog exercises in catalog order, then the lifter's own.
    private let exercises: [Exercise]
    /// The same exercises by the id `PowerJackPlanner` gives the engine.
    private let exercisesByEngineID: [AnyHashable: Exercise]
    private let catalogTemplates: [TemplateProgram]
    private let otherStyleTemplates: [TemplateProgram]
    private var checker = PowerJackSimChecker()
    private var report: PowerJackSimReport

    private var program: Program?
    private var programNumber = 0
    private var lastTemplate: TemplateProgram?
    private var customTemplates = 0
    private var nextProgramDay = 0
    private var breakEndsDay = 0
    private var trainingDays: Set<Int> = []
    private var lastTrained: Date?
    /// Counted BUILD weeks in a row since the last deload or break, across programs.
    private var buildRun = 0

    init(seed: UInt64, profile: PowerJackSimProfile, weeks: Int, keepsTrace: Bool = false) throws {
        self.seed = seed
        self.profile = profile
        self.weeks = weeks
        lifter = PowerJackSimLifter(profile: profile, seed: seed)
        report = PowerJackSimReport(seed: seed, profile: profile.name, weeks: weeks)
        report.keepsTrace = keepsTrace
        container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        try TemplateCatalog.seed(in: context)

        let stored = try context.fetch(FetchDescriptor<Exercise>())
        let exercisesByID = Dictionary(stored.compactMap { exercise in exercise.catalogID.map { ($0, exercise) } }) { first, _ in first }
        var draw = PowerJackSimRandom(seed: seed ^ 0xC057_0E)
        let ownExercises = Self.makeOwnExercises(&draw)
        ownExercises.forEach(context.insert)
        exercises = ExerciseCatalog.entries.compactMap { exercisesByID[$0.id] } + ownExercises
        exercisesByEngineID = Dictionary(exercises.map { (AnyHashable(ObjectIdentifier($0)), $0) }) { first, _ in first }

        let templates = try context.fetch(FetchDescriptor<TemplateProgram>())
        let templatesByID = Dictionary(templates.compactMap { template in template.catalogID.map { ($0, template) } }) { first, _ in first }
        // Whatever the catalog holds, so new templates are covered as they land.
        catalogTemplates = TemplateCatalog.entries.filter { $0.type == .powerJack }.compactMap { templatesByID[$0.id] }
        otherStyleTemplates = TemplateCatalog.entries.filter { $0.type != .powerJack }.compactMap { templatesByID[$0.id] }
        try context.save()
        checker.names = exercisesByEngineID.mapValues(\.exerciseName)
    }

    /// Lives through `weeks` calendar weeks and reports what the checks found.
    func run() throws -> PowerJackSimReport {
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
        report.mainLiftTrend = mainLiftTrend
        return report
    }

    /// Each main lift's first and last planned heavy load, and how much stronger the lifter got.
    private var mainLiftLoads: [String: (first: Double, last: Double, exercise: Exercise)] = [:]
    private var mainLiftTrend: [String: (first: Double, last: Double, growth: Double)] {
        mainLiftLoads.mapValues { ($0.first, $0.last, lifter.growth(of: $0.exercise)) }
    }
}

//
// Calendar
//
private extension PowerJackSimDriver {
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
        let program = PowerJackPlanner.$now.withValue(date) {
            Program(programLengthWeeks: length, templateProgram: template)
        }
        // The app saves here. One in-memory context needs no saves, and skipping them keeps years of logs fast.
        context.insert(program)
        if let lastTrained, date.timeIntervalSince(lastTrained) >= 15 * 86_400 {
            buildRun = 0
        }
        if let previous = self.program, previous.status == .active {
            previous.stop()
            previous.stopAndCascade()
        }
        program.start()
        self.program = program
        lastTemplate = template
        programNumber += 1
        trainingDays = Self.trainingDays(count: program.workoutsPerWeek, shift: lifter.rng.int(0...6))
        let style = template.templateType == .powerJack ? "" : ", \(template.templateType.name)"
        checker.place = "program \(programNumber) (\(template.templateName)\(style), \(length) wk)"
        report.trace("\(Self.dayText(date)) start \(checker.place)")
        guard template.templateType == .powerJack else {
            report.otherStylePrograms += 1
            return
        }
        let plan = PowerJackPlanner.$now.withValue(date) {
            checker.checkFirstWeek(of: program)
        }
        traceWeek(of: program, index: 0, plan: plan)
    }

    func chooseTemplate() -> TemplateProgram {
        if let lastTemplate, lifter.decides(profile.sameTemplate) {
            return lastTemplate
        }
        if lifter.decides(profile.otherStyle), !otherStyleTemplates.isEmpty {
            return lifter.rng.pick(otherStyleTemplates)
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
private extension PowerJackSimDriver {
    func train(_ program: Program, at start: Date) {
        guard let workout = program.nextWorkout else { return }
        if workout.status == .planned {
            if lifter.decides(profile.skipWorkout) {
                finish(workout, in: program, skip: true, at: start)
                return
            }
            program.prepareToStart(workout, at: start)
            workout.startAndCascade()
        }
        lifter.startSession()
        var clock = start
        var lines: [String] = []
        var walkedOut = false
        for workoutExercise in workout.workoutExercises where !walkedOut {
            let outcome = perform(workoutExercise, in: workout, clock: &clock)
            if let line = outcome.line {
                lines.append(line)
            }
            walkedOut = outcome.walkedOut
        }
        report.trace("\(Self.dayText(start)) workout \(workout.order + 1)\(walkedOut ? " (walked out)" : ""): " + lines.joined(separator: "; "))
        if walkedOut {
            // Skip Workout keeps the sets already done and skips the rest.
            finish(workout, in: program, skip: true, at: clock)
            return
        }
        // Finish Workout skips whatever is left unlogged.
        workout.skipRemainingSets()
        finish(workout, in: program, skip: false, at: clock)
    }

    func finish(_ workout: Workout, in program: Program, skip: Bool, at date: Date) {
        let weeks = program.programWeeks
        let index = weeks.firstIndex { week in week.workouts.contains { $0 === workout } }
        let nextWasEmpty = index.map { $0 + 1 < weeks.count && weeks[$0 + 1].workouts.isEmpty } ?? false
        let weekWasOpen = index.map { weeks[$0].status != .complete } ?? false
        let started = Date()
        PowerJackPlanner.$now.withValue(date) {
            if skip {
                program.skipWorkout(workout)
            } else {
                program.finishWorkout(workout)
            }
        }
        let seconds = Date().timeIntervalSince(started)
        if skip {
            report.workoutsSkipped += 1
            if workout.completedWorkingSets == 0 {
                report.trace("\(Self.dayText(date)) workout \(workout.order + 1) skipped")
            }
        } else {
            report.workouts += 1
        }
        if let index, weekWasOpen, weeks[index].status == .complete {
            countRun(of: weeks[index], in: program)
        }
        guard let index, nextWasEmpty, !weeks[index + 1].workouts.isEmpty else { return }
        guard program.templateType == .powerJack else { return }
        report.slowestBuild = max(report.slowestBuild, seconds)
        let plan = PowerJackPlanner.$now.withValue(date) {
            checker.checkBuild(of: program, week: index + 1)
        }
        traceWeek(of: program, index: index + 1, plan: plan)
        recordSlack(in: weeks[index + 1])
    }

    /// Counts counted BUILD weeks in a row, across programs: a deload or a break of 15 days or more starts
    /// the count again.
    func countRun(of week: ProgramWeek, in program: Program) {
        guard program.templateType == .powerJack else { return }
        let trained = week.workouts.filter { $0.completedWorkingSets > 0 }.count
        guard trained > 0 else { return }
        if week.weekKind == .deload {
            buildRun = 0
        } else if Double(week.workouts.count - trained) / Double(max(1, week.workouts.count)) < PowerJackRules.partialShare {
            buildRun += 1
            report.longestBuildRun = max(report.longestBuildRun, buildRun)
        }
    }

    /// How far each new BUILD-week target sits from what the lifter can really do: reps left on a fresh
    /// set at the planned load. Holds, cuts and pain changes react to a bad week and aren't counted.
    func recordSlack(in week: ProgramWeek) {
        guard week.weekKind == .build else { return }
        for workoutExercise in week.workouts.flatMap(\.workoutExercises) {
            guard
                let exercise = workoutExercise.exercise,
                !workoutExercise.calibrating,
                let code = workoutExercise.progressionCode.flatMap(PowerJackReason.init(rawValue:)),
                Self.progressionReasons.contains(code)
            else {
                continue
            }
            let sets = workoutExercise.workingSets
            let firsts = workoutExercise.topSets > 0 ? [sets.first, sets.dropFirst(workoutExercise.topSets).first] : [sets.first]
            for set in firsts.compactMap({ $0 }) {
                guard let reps = set.repsPlanned, let slack = lifter.slack(exercise, pounds: set.weightInPoundsPlanned, reps: reps) else { continue }
                report.record(slack: slack)
            }
        }
    }

    /// Reasons that ask for more than last time, or set a new baseline: the targets that must stay within reach.
    static let progressionReasons: Set<PowerJackReason> = [
        .blockStart, .calibrate, .ramp, .easyStep, .repStep, .loadJump, .widenRange, .addedSet, .painReturn,
    ]

    /// Does one exercise: answers its check-in, maybe swaps or skips it, logs each set, rates the TOP sets
    /// and the exercise. Returns a trace line, and whether the lifter walked out of the workout.
    func perform(_ workoutExercise: WorkoutExercise, in workout: Workout, clock: inout Date) -> (line: String?, walkedOut: Bool) {
        let planned = workoutExercise.exercise?.exerciseName ?? "?"
        if workoutExercise.checkInPending {
            if lifter.decides(profile.ignoreCheckIn) {
                return ("\(planned) check-in left open", false)
            }
            let decision = lifter.rng.pick(weighted: profile.checkIn)
            workoutExercise.resolveCheckIn(decision)
            report.checkIns += 1
            report.trace("  check-in \(planned): \(decision)")
        }
        guard workoutExercise.status == .active, var exercise = workoutExercise.exercise else { return (nil, false) }
        if lifter.decides(profile.swapExercise), let swap = replacement(for: exercise) {
            workoutExercise.changeExercise(newExercise: swap)
            exercise = swap
            report.swaps += 1
            report.trace("  swap \(planned) for \(swap.exerciseName)")
        }
        if lifter.decides(profile.disableWarmups) {
            workoutExercise.disableWarmups()
        }
        if lifter.decides(profile.skipExercise) || (lifter.isHurt(exercise) && lifter.decides(0.5)) {
            workoutExercise.skipRemainingSets()
            return ("\(exercise.exerciseName) skipped", false)
        }
        if workoutExercise.workingSets.count > 1, lifter.decides(profile.removeSet) {
            workoutExercise.removeLastSet()
        }
        if lifter.decides(profile.addSet) {
            _ = workoutExercise.addSet()
        }

        let aim = workoutExercise.rirTarget ?? PowerJackRules.calibrationRIR
        let sets = workoutExercise.workingSets.filter { $0.status == .active }
        var plannedReps: Int?
        var typed: Int?
        var repsLeft: Double?
        var topRepsLeft: Double?
        var logged: [String] = []
        for (index, set) in sets.enumerated() {
            if index > 0, lifter.decides(profile.stopEarly) { break }
            let isTop = workoutExercise.isTopSet(set)
            if index == workoutExercise.topSets, workoutExercise.topSets > 0 {
                // The first BACK set: its own planned reps and weight, not the TOP set's.
                plannedReps = nil
                typed = nil
            }
            plannedReps = set.repsPlanned ?? plannedReps
            // An empty weight field shows what was typed on the set before it (`applyWeight`).
            let plannedLoad = set.weightTenthsPlannedPounds ?? typed
            if let load = lifter.load(for: exercise, planned: plannedLoad, reps: plannedReps, aim: aim) {
                set.weightTenthsPounds = load
                if !isTop { typed = load }
            }
            var capacity = lifter.repsToFailure(exercise, pounds: set.weightInPounds, setIndex: index)
            // Not even one rep: the lifter strips the bar a little and tries again, twice at most.
            for _ in 0..<2 where capacity < 1 && !exercise.repsOnly {
                guard let load = set.weightTenthsPounds else { break }
                set.weightTenthsPounds = lifter.lighter(load)
                if !isTop { typed = set.weightTenthsPounds }
                capacity = lifter.repsToFailure(exercise, pounds: set.weightInPounds, setIndex: index)
            }
            guard let reps = lifter.reps(planned: plannedReps, repsToFailure: capacity, isLast: index == sets.count - 1, aim: aim) else { break }
            set.reps = reps
            guard set.reps != nil, exercise.repsOnly || set.weightTenthsPounds != nil else { break }
            clock.addTimeInterval(Double(lifter.rng.int(90...240)))
            workoutExercise.completeSet(set, at: clock)
            // The rest timer reads the set just done, as the workout screen does.
            _ = workout.currentRest
            lastTrained = clock
            lifter.didSet(exercise, repsLeft: capacity - Double(reps), at: clock)
            repsLeft = capacity - Double(reps)
            if isTop {
                topRepsLeft = repsLeft
            }
            logged.append("\(reps)@\(PowerJackSimText.pounds(tenths: set.weightTenthsPounds))")
            if workoutExercise.needsTopSetRating, workoutExercise.isLastTopSet(set), lifter.decides(profile.inlineTopRating) {
                workoutExercise.rateTopSets(lifter.rating(repsLeft: topRepsLeft ?? 0))
                logged.append("top rir \(workoutExercise.topSetRepsInReserve?.valueText ?? "?")")
            }
        }
        if !workoutExercise.allSetsDone() {
            workoutExercise.skipRemainingSets()
        }
        clock.addTimeInterval(120)
        guard let repsLeft else { return ("\(exercise.exerciseName) nothing logged", false) }

        let pain = lifter.pain(after: exercise)
        guard workoutExercise.needsFeedback else { return ("\(exercise.exerciseName) \(logged.joined(separator: ","))", false) }
        if lifter.decides(profile.noRating) {
            // The feedback can't be dismissed, so an exercise goes unrated only when the lifter skips the workout.
            return ("\(exercise.exerciseName) \(logged.joined(separator: ",")) unrated", true)
        }
        // The feedback asks for the TOP sets too when they weren't rated after them.
        if workoutExercise.topSetsNeedRating {
            workoutExercise.rateTopSets(lifter.rating(repsLeft: topRepsLeft ?? repsLeft))
            logged.append("top rir \(workoutExercise.topSetRepsInReserve?.valueText ?? "?")")
        }
        let feedback: ExerciseFeedback
        if lifter.decides(profile.legacyRating) {
            feedback = ExerciseFeedback(levelOfEffort: lifter.legacyWord(repsLeft: repsLeft), levelOfPain: pain)
        } else {
            feedback = ExerciseFeedback(repsInReserve: lifter.rating(repsLeft: repsLeft), levelOfPain: pain)
        }
        workoutExercise.addFeedback(feedback: feedback)
        let rating = feedback.repsInReserve.map { "rir \($0.valueText)" } ?? "word \(feedback.levelOfEffort.label)"
        return ("\(exercise.exerciseName) \(logged.joined(separator: ",")) \(rating) pain \(pain.rawValue)", false)
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
        case 1, 3:
            exercise.fatigueLevel = lifter.rng.pick(FatigueLevel.allCases)
        default:
            // Only the lifter's own exercises can change equipment.
            guard exercise.userCreated else { return }
            exercise.exerciseEquipment = exercise.repsOnly ? .dumbbell : .bodyweight
        }
        report.edits += 1
        report.trace("edit \(exercise.exerciseName): \(exercise.fatigueLevel.name), \(exercise.exerciseEquipment.rawValue)")
    }
}

//
// The lifter's own exercises and templates
//
private extension PowerJackSimDriver {
    /// A few exercises of the lifter's own, which PowerJack reads by primary muscle and fatigue level (R1.1).
    static func makeOwnExercises(_ draw: inout PowerJackSimRandom) -> [Exercise] {
        (1...6).map { number in
            let equipment = number <= 2 ? Equipment.bodyweight : draw.pick(Equipment.allCases)
            let primary = draw.pick(Muscle.allCases)
            var secondary: [Muscle] = []
            for muscle in Muscle.allCases where muscle != primary && secondary.count < maxSecondaryMuscles && draw.chance(0.15) {
                secondary.append(muscle)
            }
            return Exercise(
                exerciseName: "Own Lift \(number)",
                exerciseEquipment: equipment,
                primaryMuscleFocus: primary,
                secondaryMuscles: secondary,
                userCreated: true,
                fatigueLevel: draw.pick(FatigueLevel.allCases)
            )
        }
    }

    /// A PowerJack template of the lifter's own: 2 to 6 days of any exercises, as the editor allows,
    /// with the shapes R1 has to read: a main lift entered twice in one workout, bodyweight or dumbbell
    /// presses ahead of the barbell, days with no main lift.
    func makeOwnTemplate() -> TemplateProgram {
        customTemplates += 1
        let days = lifter.rng.int(TemplateProgramDraft.minimumWorkoutsPerWeek...TemplateProgramDraft.maximumWorkoutsPerWeek)
        var focus: [Muscle] = []
        for _ in 0..<lifter.rng.int(1...TemplateProgramDraft.maximumFocusMuscles) {
            let muscle = lifter.rng.pick(Muscle.allCases)
            if !focus.contains(muscle) { focus.append(muscle) }
        }
        let template = TemplateProgram(templateName: "Own \(customTemplates)", workoutsPerWeek: days, templateMuscleFocus: focus, templateType: .powerJack)
        let barbells = exercises.filter { $0.exerciseEquipment == .barbell && $0.fatigueLevel == .high }
        for day in 0..<days {
            let workout = template.addTemplateWorkout()
            if day == 0, profile.name == PowerJackSimProfile.heavy.name, let legPress = exercises.first(where: { $0.catalogID == "leg-press" }) {
                workout.addTemplateExercise(exercise: legPress)
            }
            for slot in 0..<lifter.rng.int(1...7) {
                let exercise = slot == 0 && !barbells.isEmpty && lifter.decides(0.6) ? lifter.rng.pick(barbells) : lifter.rng.pick(exercises)
                workout.addTemplateExercise(exercise: exercise)
                // A second entry of the same lift: a TOP entry and a BACK entry (R1.2).
                if exercise.exerciseEquipment == .barbell, lifter.decides(0.15) {
                    workout.addTemplateExercise(exercise: exercise)
                }
            }
        }
        context.insert(template)
        return template
    }
}

//
// Trace
//
private extension PowerJackSimDriver {
    func traceWeek(of program: Program, index: Int, plan: PowerJackWeekPlan?) {
        let weeks = program.programWeeks
        guard weeks.indices.contains(index), let plan else { return }
        report.count(plan)
        recordMainLifts(plan)
        let entries = plan.workouts.joined().map { "\(PowerJackSimText.name($0, in: checker.names)) \(PowerJackSimText.describe($0))" }
        report.trace("  plan p\(programNumber) w\(index + 1) \(PowerJackSimText.describe(plan.header)): " + entries.joined(separator: "; "))
    }

    /// Keeps each main lift's first and latest planned heavy load (an H slot or a TOP set).
    func recordMainLifts(_ plan: PowerJackWeekPlan) {
        guard plan.header.type == .build else { return }
        for entry in plan.workouts.joined() where entry.role.role == .main && !entry.calibrating {
            guard entry.role.tag == .heavy || entry.topSets > 0, let load = entry.sets.first?.load,
                  let exercise = exercisesByEngineID[entry.exercise.id]
            else { continue }
            let name = exercise.exerciseName
            mainLiftLoads[name] = (mainLiftLoads[name]?.first ?? load, load, exercise)
        }
    }
}
