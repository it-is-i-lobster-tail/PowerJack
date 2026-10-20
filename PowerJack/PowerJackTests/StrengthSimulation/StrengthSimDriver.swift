//
//  StrengthSimDriver.swift
//  PowerJackTests
//
//  Runs one simulated lifter through the app for months or years, the way the UI does: programs started
//  from Strengthen templates (and now and then Build or PowerJack ones), workouts started, logged, rated,
//  skipped and cut short, pain check-ins answered, exercises swapped and edited, units and plates changed in
//  Settings, and breaks in between. Every week and workout the Strengthen planner writes goes to
//  `StrengthSimChecker`.
//

import Foundation
import SwiftData
@testable import PowerJack

@MainActor
final class StrengthSimDriver {
    /// Monday 4 January 2027, midnight UTC.
    static let firstDay = Date(timeIntervalSince1970: 1_799_020_800)

    /// The unit and smallest steps set in Settings (1.5).
    struct Settings {
        var unit: WeightUnit
        var steps: [Equipment: Double]
    }

    let seed: UInt64
    let profile: StrengthSimProfile
    let weeks: Int
    private let lifter: StrengthSimLifter
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    /// Catalog exercises in catalog order, then the lifter's own.
    private let exercises: [Exercise]
    private let exercisesByKey: [String: Exercise]
    private let strengthTemplates: [TemplateProgram]
    private let otherTemplates: [TemplateProgram]
    private var settings: Settings
    private var checker = StrengthSimChecker()
    private var report: StrengthSimReport

    private var program: Program?
    private var programNumber = 0
    private var lastTemplate: TemplateProgram?
    private var customTemplates = 0
    private var nextProgramDay = 0
    private var breakEndsDay = 0
    private var trainingDays: Set<Int> = []
    /// What really happened to each lift, by record key.
    private var truth: [String: StrengthSimTruth] = [:]

    init(seed: UInt64, profile: StrengthSimProfile, weeks: Int, keepsTrace: Bool = false) throws {
        self.seed = seed
        self.profile = profile
        self.weeks = weeks
        lifter = StrengthSimLifter(profile: profile, seed: seed)
        report = StrengthSimReport(seed: seed, profile: profile.name, weeks: weeks)
        report.keepsTrace = keepsTrace
        report.habits = profile.habits
        var draw = StrengthSimRandom(seed: seed ^ 0x5E77_1265)
        settings = Settings(unit: profile.unit, steps: Self.steps(profile.steps, unit: profile.unit, draw: &draw))

        container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        try TemplateCatalog.seed(in: context)

        let stored = try context.fetch(FetchDescriptor<Exercise>())
        let exercisesByID = Dictionary(stored.compactMap { exercise in exercise.catalogID.map { ($0, exercise) } }) { first, _ in first }
        let ownExercises = Self.makeOwnExercises(&draw)
        ownExercises.forEach(context.insert)
        exercises = ExerciseCatalog.entries.compactMap { exercisesByID[$0.id] } + ownExercises
        exercisesByKey = Dictionary(exercises.map { (StrengthLifts.key(for: $0), $0) }) { first, _ in first }

        let templates = try context.fetch(FetchDescriptor<TemplateProgram>())
        let templatesByID = Dictionary(templates.compactMap { template in template.catalogID.map { ($0, template) } }) { first, _ in first }
        // Whatever templates the catalog holds, so new ones are covered as they land.
        strengthTemplates = TemplateCatalog.entries.filter { $0.type == .strength }.compactMap { templatesByID[$0.id] }
        otherTemplates = TemplateCatalog.entries.filter { $0.type != .strength }.compactMap { templatesByID[$0.id] }

        if profile.trainedWeeksBefore > 0 {
            var state = StrengthState()
            state.clock.trainedWeeks = profile.trainedWeeksBefore
            context.insert(StrengthLog(date: Self.firstDay.addingTimeInterval(-86_400), state: state))
        }
        try context.save()
        checker.gridFor = Self.grids(settings)
    }

    /// Lives through `weeks` calendar weeks and reports what the checks found.
    func run() throws -> StrengthSimReport {
        for day in 0..<(weeks * 7) {
            let date = Self.firstDay.addingTimeInterval(Double(day) * 86_400)
            if day.isMultiple(of: 7) {
                try startCalendarWeek(day: day, at: date)
            }
            guard day >= breakEndsDay else { continue }
            if program?.status != .active {
                guard day >= nextProgramDay else { continue }
                try startProgram(at: date.addingTimeInterval(8 * 3_600))
            }
            guard let program, trainingDays.contains(day % 7), !lifter.decides(profile.missDay) else { continue }

            let start = date.addingTimeInterval(17 * 3_600 + Double(lifter.rng.int(0...120)) * 60)
            try train(program, at: start)
            if program.status == .active, lifter.decides(profile.doubleSession) {
                try train(program, at: start.addingTimeInterval(3 * 3_600))
            }
            if program.status != .active {
                report.programsFinished += 1
                nextProgramDay = day + 1 + lifter.rng.pick(profile.daysBetweenPrograms)
            }
        }
        finishRun(at: Self.firstDay.addingTimeInterval(Double(weeks * 7) * 86_400))
        report.violations = checker.violations
        report.weeksChecked = checker.weeksChecked
        report.workoutsChecked = checker.workoutsChecked
        report.programs = programNumber
        return report
    }

    /// Runs `body` as the app would at `date`, with the lifter's unit and steps in Settings.
    private func act<Result>(at date: Date, _ body: () throws -> Result) rethrows -> Result {
        try StrengthPlanner.$currentDate.withValue(date) {
            try WeightUnit.$pinned.withValue(settings.unit) {
                try StrengthLoadSteps.$pinned.withValue(settings.steps) {
                    try body()
                }
            }
        }
    }
}

//
// Calendar and Settings
//
private extension StrengthSimDriver {
    func startCalendarWeek(day: Int, at date: Date) throws {
        lifter.endWeek(at: date)
        guard day >= breakEndsDay else { return }
        changeSettings(on: date)
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
            try startProgram(at: date.addingTimeInterval(8 * 3_600))
        }
    }

    /// Switches kg and lb or picks new smallest steps, as Settings allows (1.4).
    func changeSettings(on date: Date) {
        var changed = false
        if lifter.decides(profile.unitSwitch) {
            let unit: WeightUnit = settings.unit == .kilograms ? .pounds : .kilograms
            settings = Settings(unit: unit, steps: Self.steps(profile.steps, unit: unit, draw: &lifter.rng))
            report.unitSwitches += 1
            changed = true
        }
        if lifter.decides(profile.stepChange) {
            settings.steps = Self.steps(.mixed, unit: settings.unit, draw: &lifter.rng)
            report.stepChanges += 1
            changed = true
        }
        guard changed else { return }
        checker.gridFor = Self.grids(settings)
        report.trace("\(Self.dayText(date)) settings \(settings.unit.symbol), steps "
            + Equipment.allCases.compactMap { equipment in settings.steps[equipment].map { "\(equipment.rawValue) \($0)" } }.joined(separator: ", "))
    }

    static func steps(_ choice: StrengthSimProfile.Steps, unit: WeightUnit, draw: inout StrengthSimRandom) -> [Equipment: Double] {
        var steps: [Equipment: Double] = [:]
        for equipment in Equipment.allCases where equipment != .bodyweight {
            let options = StrengthLoadSteps.options(for: equipment, in: unit)
            guard !options.isEmpty else { continue }
            steps[equipment] = switch choice {
            case .defaults: StrengthLoadSteps.defaultStep(for: equipment, in: unit) ?? options[0]
            case .smallest: options[0]
            case .largest: options[options.count - 1]
            case .mixed: draw.pick(options)
            }
        }
        return steps
    }

    static func grids(_ settings: Settings) -> (Equipment) -> LoadGrid? {
        { equipment in
            settings.steps[equipment].map { LoadGrid(unit: settings.unit, step: $0, isBarbell: equipment == .barbell) }
        }
    }

    var gridFor: (Equipment) -> LoadGrid? { Self.grids(settings) }

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
// Programs
//
private extension StrengthSimDriver {
    /// Starts a new program the way Programs › New does: the new one is saved, then the active one stops.
    func startProgram(at date: Date) throws {
        let template = chooseTemplate()
        let length = lifter.rng.int(profile.programWeeks)
        let program = act(at: date) { Program(programLengthWeeks: length, templateProgram: template) }
        // The app saves here. One in-memory context needs no saves, and skipping them keeps years of logs fast.
        context.insert(program)
        if let previous = self.program, previous.status == .active {
            stop(previous, at: date)
        }
        program.start()
        self.program = program
        lastTemplate = template
        programNumber += 1
        if template.templateType != .strength {
            report.otherStylePrograms += 1
        }
        trainingDays = Self.trainingDays(count: program.workoutsPerWeek, shift: lifter.rng.int(0...6))
        checker.place = "program \(programNumber) (\(template.templateName), \(template.templateType.rawValue), \(length) wk)"
        report.trace("\(Self.dayText(date)) start \(checker.place)")
        traceWeek(of: program, index: 0)
    }

    /// Stops a program partway through. A Strengthen week left partway through still counts toward the records.
    func stop(_ previous: Program, at date: Date) {
        let isStrength = previous.templateType == .strength
        let week = previous.nextWorkout.flatMap(previous.programWeek(containing:))
        let trained = week?.workouts.contains { workout in workout.workoutExercises.contains { $0.completedWorkingSets > 0 } } ?? false
        let logsBefore = strengthLogCount()
        let recordsBefore = latestRecords()
        act(at: date) {
            previous.stop()
            previous.stopAndCascade()
        }
        report.trace("\(Self.dayText(date)) stop \(checker.place)")
        guard isStrength else { return }
        let here = "\(checker.place) stopped"
        checker.checkClose(logsBefore: logsBefore, logsAfter: strengthLogCount(), expected: trained ? 1 : 0, at: here)
        if trained {
            checkRecords(after: recordsBefore, closed: week?.weekKind, at: here)
        }
    }

    func chooseTemplate() -> TemplateProgram {
        if let lastTemplate, lifter.decides(profile.sameTemplate) {
            return lastTemplate
        }
        if !otherTemplates.isEmpty, lifter.decides(profile.otherStyles) {
            return lifter.rng.pick(otherTemplates)
        }
        if lifter.decides(profile.customTemplate) || strengthTemplates.isEmpty {
            return makeOwnTemplate()
        }
        return lifter.rng.pick(strengthTemplates)
    }

    func strengthLogCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<StrengthLog>())) ?? 0
    }

    func latestRecords() -> StrengthState {
        StrengthLog.latestState(in: context)
    }

    func checkRecords(after previous: StrengthState, closed: WeekKind?, at here: String) {
        let records = latestRecords()
        checker.checkRecords(
            records, previous: previous, closed: closed, lifter: lifter, honest: profile.rating == .honest,
            exercises: exercisesByKey, at: here
        )
        report.trainedWeeks = records.clock.trainedWeeks
        report.experience = records.clock.experience
    }

    /// Each priority lift's final e1RM against the lifter's true max, for lifts trained in the last 8 weeks.
    func finishRun(at end: Date) {
        let records = latestRecords()
        for key in records.lifts.keys.sorted() {
            guard
                let e1rm = records[key].e1rmKg,
                let exercise = exercisesByKey[key], !exercise.repsOnly,
                let trained = truth[key]?.lastTrained, end.timeIntervalSince(trained) < 56 * 86_400
            else { continue }
            report.record(e1rmRatio: e1rm / lifter.trueMax(exercise))
        }
    }
}

//
// Workouts
//
private extension StrengthSimDriver {
    func train(_ program: Program, at start: Date) throws {
        guard let workout = program.nextWorkout else { return }
        if workout.status == .planned {
            if lifter.decides(profile.skipWorkout) {
                try finish(workout, in: program, skip: true, at: start)
                return
            }
            prepare(workout, in: program, at: start)
            workout.startAndCascade()
        }
        lifter.startSession()
        var clock = start
        var lines: [String] = []
        for workoutExercise in workout.workoutExercises {
            if let line = perform(workoutExercise, in: program, clock: &clock) {
                lines.append(line)
            }
        }
        report.trace("\(Self.dayText(start)) workout \(workout.order + 1): " + lines.joined(separator: "; "))
        // Finish Workout skips whatever is left unlogged.
        workout.skipRemainingSets()
        try finish(workout, in: program, skip: false, at: clock.addingTimeInterval(60))
    }

    /// The planner's chance to replan the workout for a break, pain or the lift records, checked when it does.
    func prepare(_ workout: Workout, in program: Program, at date: Date) {
        let before = Dictionary(StrengthSimSlot.all(in: workout).map { (ObjectIdentifier($0.workoutExercise), StrengthSimChecker.signature(of: $0)) }) { first, _ in first }
        act(at: date) { program.prepareToStart(workout, at: date) }
        guard program.templateType == .strength else { return }
        checker.checkStart(of: workout, in: program, at: date, records: latestRecords(), truth: truth, before: before)
        let changed = StrengthSimSlot.all(in: workout).filter { before[ObjectIdentifier($0.workoutExercise)] != StrengthSimChecker.signature(of: $0) }
        for slot in changed {
            report.count(kind: slot.kind, rules: slot.rules)
        }
        if !changed.isEmpty {
            report.trace("  start w\((program.weekNumber(containing: workout) ?? 0)) workout \(workout.order + 1): "
                + changed.map { "\($0.name) \(describe($0))" }.joined(separator: "; "))
        }
    }

    func finish(_ workout: Workout, in program: Program, skip: Bool, at date: Date) throws {
        let isStrength = program.templateType == .strength
        let weeks = program.programWeeks
        let index = weeks.firstIndex { week in week.workouts.contains { $0 === workout } }
        let nextWasEmpty = index.map { $0 + 1 < weeks.count && weeks[$0 + 1].workouts.isEmpty } ?? false
        let weekWasOpen = index.map { weeks[$0].status != .complete } ?? false
        let logsBefore = strengthLogCount()
        let recordsBefore = latestRecords()
        _ = act(at: date) {
            skip ? program.skipWorkout(workout) : program.finishWorkout(workout)
        }
        if skip {
            report.workoutsSkipped += 1
            report.trace("\(Self.dayText(date)) workout \(workout.order + 1) skipped")
        } else {
            report.workouts += 1
        }
        guard isStrength, let index else { return }
        if weekWasOpen, weeks[index].status == .complete {
            let here = "\(checker.place) week \(index + 1) closed"
            checker.checkClose(logsBefore: logsBefore, logsAfter: strengthLogCount(), expected: 1, at: here)
            checkRecords(after: recordsBefore, closed: weeks[index].weekKind, at: here)
        }
        if nextWasEmpty, !weeks[index + 1].workouts.isEmpty {
            checker.checkBuild(of: program, week: index + 1, records: latestRecords())
            traceWeek(of: program, index: index + 1)
            recordSlack(in: weeks[index + 1])
        }
    }

    /// How far each new normal-week priority target sits from what the lifter can really do: reps left on a
    /// fresh first set.
    func recordSlack(in week: ProgramWeek) {
        guard week.weekKind == .build else { return }
        for slot in StrengthSimSlot.all(in: week) where slot.role == .primary && slot.kind == .normal {
            guard let reps = slot.reps, let slack = lifter.slack(slot.exercise, loadKg: slot.loadKg, reps: reps) else { continue }
            report.record(slack: slack)
        }
    }

    /// Does one exercise: answers its check-in, maybe swaps or skips it, logs its warm-ups and each set, and rates
    /// it. Returns a trace line.
    func perform(_ workoutExercise: WorkoutExercise, in program: Program, clock: inout Date) -> String? {
        let isStrength = program.templateType == .strength
        if workoutExercise.checkInPending {
            // Strengthen has already planned the lighter sets, so its sheet offers only Lighter or Skip (15.4).
            let options = workoutExercise.strengthRole != nil ? profile.checkIn.filter { $0.0 != .reset } : profile.checkIn
            workoutExercise.resolveCheckIn(lifter.rng.pick(weighted: options))
            report.checkIns += 1
        }
        guard workoutExercise.status == .active, var exercise = workoutExercise.exercise else { return nil }
        if lifter.decides(profile.swapExercise), let swap = replacement(for: exercise) {
            workoutExercise.changeExercise(newExercise: swap)
            exercise = swap
            report.swaps += 1
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
        if lifter.decides(profile.disableWarmups) {
            workoutExercise.disableWarmups()
        }

        let key = StrengthLifts.key(for: exercise)
        let grid = gridFor(exercise.exerciseEquipment)
        let aim = workoutExercise.rirTarget ?? 2
        let sets = workoutExercise.workingSets.filter { $0.status == .active }
        if workoutExercise.showsWarmups, lifter.decides(profile.logWarmups) {
            logWarmups(of: workoutExercise, exercise: exercise, working: sets.first, grid: grid, clock: &clock)
        }

        var plannedReps: Int?
        var repsLeft: Double?
        var logged: [String] = []
        for (index, set) in sets.enumerated() {
            if index > 0, lifter.decides(profile.stopEarly) { break }
            plannedReps = set.repsPlanned ?? plannedReps
            if let load = lifter.load(for: exercise, prefilled: set.weightTenthsPounds, reps: plannedReps, aim: aim, grid: grid),
               load != set.weightTenthsPounds {
                // A weight typed on a set carries to the sets after it, as the workout screen does.
                set.weightTenthsPounds = load
                workoutExercise.applyWeight(load, after: set)
            }
            let loadKg = set.weightTenthsPounds.map { WeightUnit.kilograms(fromTenthsPounds: $0) }
            let capacity = lifter.repsToFailure(exercise, loadKg: loadKg, setIndex: index)
            guard let reps = lifter.reps(planned: plannedReps, repsToFailure: capacity, isLast: index == sets.count - 1, aim: aim) else { break }
            set.reps = reps
            guard set.reps != nil, exercise.repsOnly || set.weightTenthsPounds != nil else { break }
            clock.addTimeInterval(Double(lifter.rng.int(90...240)))
            let nextBefore = sets.dropFirst(index + 1).first?.weightTenthsPounds
            let at = clock
            act(at: at) { workoutExercise.completeSet(set, at: at) }
            if isStrength, let planned = set.repsPlanned, reps < planned {
                checker.checkMiss(StrengthSimSlot(workoutExercise: workoutExercise, exercise: exercise), short: set,
                                  nextWeightBefore: nextBefore, at: "\(checker.place) \(Self.dayText(at))")
            }
            lifter.didSet(exercise, loadKg: loadKg, repsLeft: capacity - Double(reps), at: clock)
            truth[key, default: StrengthSimTruth()].lastTrained = clock
            repsLeft = capacity - Double(reps)
            logged.append("\(reps)@\(text(set.weightTenthsPounds))")
        }
        if !workoutExercise.allSetsDone() {
            workoutExercise.skipRemainingSets()
        }
        clock.addTimeInterval(120)
        guard let repsLeft else { return "\(exercise.exerciseName) nothing logged" }

        let pain = lifter.pain(after: exercise)
        guard workoutExercise.needsFeedback, !lifter.decides(profile.noRating) else {
            // A trained session uses up any pain action, and without a rating sets none (15.1).
            if isStrength { truth[key, default: StrengthSimTruth()].painAction = nil }
            return "\(exercise.exerciseName) \(logged.joined(separator: ",")) unrated"
        }
        let rating = lifter.rating(repsLeft: repsLeft)
        workoutExercise.addFeedback(feedback: ExerciseFeedback(repsInReserve: rating, levelOfPain: pain))
        if isStrength {
            truth[key, default: StrengthSimTruth()].painAction = pain.rawValue >= StrengthRules.painStop.rawValue ? .lighter
                : pain.rawValue >= StrengthRules.painHold.rawValue ? .cut : nil
        }
        return "\(exercise.exerciseName) \(logged.joined(separator: ",")) rir \(rating.valueText) pain \(pain.rawValue)"
    }

    /// Logs the warm-ups at their planned weights, or about half the working weight when none is planned.
    func logWarmups(of workoutExercise: WorkoutExercise, exercise: Exercise, working: WorkoutSet?, grid: LoadGrid?, clock: inout Date) {
        let workingLoad = working.flatMap { $0.weightTenthsPounds ?? $0.weightTenthsPlannedPounds }
        for warmup in workoutExercise.warmupSets where warmup.status == .active {
            if !exercise.repsOnly, let load = lifter.warmupLoad(prefilled: warmup.weightTenthsPounds, working: workingLoad, grid: grid) {
                warmup.weightTenthsPounds = load
            }
            warmup.reps = warmup.reps ?? warmup.repsPlanned ?? 5
            guard warmup.reps != nil, exercise.repsOnly || warmup.weightTenthsPounds != nil else { continue }
            clock.addTimeInterval(Double(lifter.rng.int(60...120)))
            let at = clock
            act(at: at) { workoutExercise.completeSet(warmup, at: at) }
        }
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
private extension StrengthSimDriver {
    /// A few exercises of the lifter's own, with ranges anywhere the editor allows.
    static func makeOwnExercises(_ draw: inout StrengthSimRandom) -> [Exercise] {
        (1...6).map { number in
            let equipment = number <= 2 ? Equipment.bodyweight : draw.pick(Equipment.allCases)
            let primary = draw.pick(Muscle.allCases)
            var secondary: [Muscle] = []
            for muscle in Muscle.allCases where muscle != primary && secondary.count < maxSecondaryMuscles && draw.chance(0.2) {
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

    /// Catalog lifts a strength lifter builds days around.
    static let mainLiftIDs = [
        "barbell-back-squat", "barbell-bench-press", "barbell-deadlift", "barbell-overhead-press", "barbell-row",
        "barbell-front-squat", "incline-barbell-bench-press", "barbell-romanian-deadlift", "leg-press", "barbell-hip-thrust",
    ]

    /// A Strengthen template of the lifter's own: 2 to 6 days, each mostly opening with a main lift, then any
    /// exercises, repeats included, as the editor allows.
    func makeOwnTemplate() -> TemplateProgram {
        customTemplates += 1
        let mainLifts = Self.mainLiftIDs.compactMap { id in exercises.first { $0.catalogID == id } }
        let days = lifter.rng.int(TemplateProgramDraft.minimumWorkoutsPerWeek...TemplateProgramDraft.maximumWorkoutsPerWeek)
        var focus: [Muscle] = []
        for _ in 0..<lifter.rng.int(1...TemplateProgramDraft.maximumFocusMuscles) {
            let muscle = lifter.rng.pick(Muscle.allCases)
            if !focus.contains(muscle) { focus.append(muscle) }
        }
        let template = TemplateProgram(templateName: "Own \(customTemplates)", workoutsPerWeek: days, templateMuscleFocus: focus, templateType: .strength)
        for _ in 0..<days {
            let workout = template.addTemplateWorkout()
            if !mainLifts.isEmpty, lifter.decides(0.75) {
                workout.addTemplateExercise(exercise: lifter.rng.pick(mainLifts))
            }
            for _ in 0..<lifter.rng.int(0...5) {
                workout.addTemplateExercise(exercise: lifter.decides(0.3) && !mainLifts.isEmpty ? lifter.rng.pick(mainLifts) : lifter.rng.pick(exercises))
            }
            if workout.templateExercises.isEmpty {
                workout.addTemplateExercise(exercise: lifter.rng.pick(exercises))
            }
        }
        context.insert(template)
        return template
    }
}

//
// Trace
//
private extension StrengthSimDriver {
    func traceWeek(of program: Program, index: Int) {
        let weeks = program.programWeeks
        guard weeks.indices.contains(index) else { return }
        let week = weeks[index]
        guard program.templateType == .strength else { return }
        let slots = StrengthSimSlot.all(in: week, plannedOnly: true)
        for slot in slots {
            report.count(kind: slot.kind, rules: slot.rules)
        }
        report.countWeek(week.weekKind)
        report.trace("  plan p\(programNumber) w\(index + 1) \(week.weekKind?.rawValue ?? "none") b\(week.blockWeek): "
            + slots.map { "\($0.name) \(describe($0))" }.joined(separator: "; "))
    }

    func describe(_ slot: StrengthSimSlot) -> String {
        let load = slot.load.map(text) ?? "feel"
        let target = slot.target.map { " R\($0)" } ?? ""
        let rir = slot.rir.map { "@\($0)" } ?? ""
        let checkIn = slot.workoutExercise.checkInPending ? " check-in" : ""
        return "\(slot.sets.count)×\(slot.reps.map(String.init) ?? "-") \(load)\(target)\(rir) \(slot.workoutExercise.progressionCode ?? "-")\(checkIn)"
    }

    /// A weight in the lifter's unit.
    func text(_ tenths: Int?) -> String {
        guard let tenths else { return "-" }
        return settings.unit.format(tenthsPounds: tenths) + settings.unit.symbol
    }
}
