import Foundation
import SwiftData

struct StudySet {
    var reps: Int?
    var load: Int?
    var target: Int?
    var targetLoad: Int?
    var status: Status
    var logged: Date?
    var rating: RepsInReserve?
    var started: Date?
    var seconds: Double?
}

struct StudySession {
    var date: Date
    var workout: String
    var routine: String
    var block: String?
    var blockWeek: Int?
    var seconds: Double?
    var finished: Bool
    var slot: Int
    var superset: Bool
    var key: String
    var name: String
    var planned: String?
    var primary: Muscle?
    var assisting: [Muscle]?
    var loaded: Bool
    var repsOnly = false
    var targetRIR: Int?
    var sets: [StudySet]
    var warmups: [StudySet] = []
    var movementPattern: MovementPattern?
    var equipment: Equipment?
    var isAccessory: Bool?

    var done: [StudySet] { sets.filter { $0.status == .complete } }
    var opening: StudySet? { sets.first.flatMap { $0.status == .complete ? $0 : nil } }
    var best: ProgramExerciseHistory.MaxEstimate? {
        guard loaded else { return nil }
        return .best(
            in: done.compactMap { ProgramExerciseHistory.estimate(load: $0.load, reps: $0.reps, rating: $0.rating) })
    }
    var perLegLunge: Bool {
        let text = name.lowercased()
        return loaded && text.contains("barbell") && text.contains("reverse") && text.contains("lunge")
            && text.contains("per leg")
    }
}

struct StudyWorkout {
    let key: String
    let program: String
    let template: String
    let activeProgram: Bool
    let weekNumber: Int
    let weekKind: String
    let block: String?
    let status: Status
    let began: Date?
    let ended: Date?
    let seconds: Double?
    let primaryMuscles: Set<Muscle>
    var date: Date? { began ?? ended }
}

struct StudyHistory {
    var options = StudyOptions()
    private(set) var selectedRange: DateInterval?
    private var exerciseMuscles: [Muscle] = []
    let sessions: [StudySession]
    let plansFromLivePrograms: Set<String>
    let workouts: [StudyWorkout]
    let credits: [(date: Date, muscle: Muscle, sets: Double)]
    let today: Date
    let firstDate: Date
    let calendar: Calendar
    let unit: WeightUnit
    static let legs: [Muscle] = [.quads, .glutes, .hamstrings, .calves]
    static let arms: [Muscle] = [.biceps, .triceps, .forearms]
    static let squat = "catalog:barbell-back-squat"
    static let bench = "catalog:barbell-bench-press"
    static let curl = "catalog:cable-curl"

    init(
        programs: [Program], archive: [HistoryRecord], logs: [WorkoutLog], unit: WeightUnit,
        today: Date = .now, calendar: Calendar = .current
    ) {
        self.unit = unit
        self.today = today
        self.calendar = calendar
        var sessions: [StudySession] = []
        var workouts: [String: StudyWorkout] = [:]
        let catalog = Dictionary(uniqueKeysWithValues: ExerciseCatalog.entries.map { ("catalog:" + $0.id, $0) })
        for program in programs {
            let pid = program.syncID?.uuidString ?? String(describing: program.persistentModelID)
            for week in program.programWeeks {
                for workout in week.workouts {
                    let key = "\(pid)/\(week.order)/\(workout.order)"
                    if let date = workout.startedAt ?? workout.endedAt, date > today { continue }
                    workouts[key] = StudyWorkout(key: key, program: pid, template: program.templateName,
                        activeProgram: program.status == .active, weekNumber: week.order + 1,
                        weekKind: week.weekKind?.rawValue ?? "", block: week.blockWeek > 0 ? "\(pid)/\(week.order + 1 - week.blockWeek)" : nil,
                        status: workout.status, began: workout.startedAt, ended: workout.endedAt,
                        seconds: workout.endedAt == nil ? nil : workout.duration(),
                        primaryMuscles: Set(workout.workoutExercises.compactMap { $0.shownExercise?.primaryMuscleFocus }))
                    guard workout.status != .planned else { continue }
                    guard let date = workout.endedAt ?? workout.startedAt, date <= today else { continue }
                    for slot in workout.workoutExercises {
                        guard let exercise = slot.shownExercise else { continue }
                        let working = slot.workingSets
                        let feedback = slot.feedback
                        let rated = feedback?.completedSets ?? working.filter { $0.status == .complete }.count
                        var completed = 0
                        let sets = working.map { set in
                            if set.status == .complete { completed += 1 }
                            return StudySet(
                                reps: set.reps, load: set.weightTenthsPounds, target: set.repsPlanned,
                                targetLoad: set.weightTenthsPlannedPounds, status: set.status, logged: set.completedAt,
                                rating: set.status == .complete && completed == rated ? feedback?.repsInReserve : nil,
                                started: set.startedAt, seconds: set.duration)
                        }
                        sessions.append(
                            StudySession(
                                date: date, workout: "\(pid)/\(week.order)/\(workout.order)",
                                routine: "\(program.templateName) · day \(workout.order + 1)",
                                block: week.blockWeek > 0 ? "\(pid)/\(week.order + 1 - week.blockWeek)" : nil,
                                blockWeek: week.blockWeek > 0 ? week.blockWeek : nil,
                                seconds: workout.endedAt == nil ? nil : workout.duration(),
                                finished: workout.status == .complete,
                                slot: slot.order, superset: slot.supersetID != nil,
                                key: exercise.syncKey ?? exercise.exerciseName,
                                name: exercise.exerciseName, planned: slot.exercise.map { $0.syncKey ?? $0.exerciseName },
                                primary: exercise.primaryMuscleFocus, assisting: exercise.secondaryMuscles,
                                loaded: !exercise.repsOnly && !exercise.addsToBodyweight,
                                repsOnly: exercise.repsOnly, targetRIR: slot.rirTarget,
                                sets: sets, warmups: slot.warmupSets.map { set in
                                    StudySet(reps: set.reps, load: set.weightTenthsPounds, target: set.repsPlanned,
                                        targetLoad: set.weightTenthsPlannedPounds, status: set.status, logged: set.completedAt,
                                        started: set.startedAt, seconds: set.duration)
                                }, movementPattern: exercise.movementPattern ?? exercise.syncKey.flatMap { catalog[$0]?.profile.pattern },
                                equipment: exercise.equipment,
                                isAccessory: slot.strengthRole.map { $0 == .accessory } ?? slot.powerJackRoleValue.map { $0 == "accessory" }))
                    }
                }
            }
        }

        // Prefer retained program objects for richer fields. Only recover archived programs once.
        let liveIDs = Set(programs.compactMap(\.syncID))
        let saved = HistoryArchive.uniqueBatchRecords(
            archive.filter { record in
                !(record.programID.map(liveIDs.contains) ?? false)
            })
        let archivedSlots = Dictionary(grouping: saved) { record in
            let pid = (record.programID ?? record.batchID)?.uuidString ?? record.programNameValue
            return "\(pid)/\(record.weekValue)/\(record.dayValue)/\(record.exerciseNumberValue)"
        }
        for entry in archivedSlots.values {
            let rows = entry.sorted { $0.order < $1.order }.map(\.row)
            guard let first = rows.first else { continue }
            if let date = first.workoutStarted ?? first.workoutEnded, date > today { continue }
            let pid = (entry.first?.programID ?? entry.first?.batchID)?.uuidString ?? first.programName
            let key = "\(pid)/\(first.week)/\(first.day)"
            let primary = Muscle(rawValue: first.primaryMuscle.lowercased())
            let muscles = (workouts[key]?.primaryMuscles ?? []).union([primary].compactMap { $0 })
            workouts[key] = StudyWorkout(key: key, program: pid, template: first.programName,
                activeProgram: false, weekNumber: first.week, weekKind: first.weekType.lowercased(), block: nil,
                status: Status(rawValue: first.workoutStatus.lowercased()) ?? .planned, began: first.workoutStarted,
                ended: first.workoutEnded, seconds: first.workoutSeconds, primaryMuscles: muscles)
            guard let date = first.workoutEnded ?? first.workoutStarted, date <= today else { continue }
            let working = rows.filter { $0.setType != "Warmup" }
            var sets = working.map { row in
                StudySet(
                    reps: row.reps, load: row.weightTenthsPounds, target: row.targetReps,
                    targetLoad: row.targetWeightTenthsPounds,
                    status: Status(rawValue: row.setStatus.lowercased()) ?? .planned,
                    logged: row.setLogged, started: row.setStarted, seconds: row.setSeconds.map(Double.init))
            }
            if let last = sets.lastIndex(where: { $0.status == .complete }) {
                sets[last].rating = RepsInReserve.allCases.first { $0.label == first.effort }
            }
            sessions.append(
                StudySession(
                    date: date, workout: "\(pid)/\(first.week)/\(first.day)",
                    routine: "\(first.programName) · day \(first.day)",
                    seconds: first.workoutSeconds, finished: first.workoutStatus == "Complete",
                    slot: first.exerciseNumber - 1, superset: !first.superset.isEmpty,
                    key: first.exerciseKey.isEmpty ? first.exerciseName : first.exerciseKey, name: first.exerciseName,
                    primary: Muscle(rawValue: first.primaryMuscle.lowercased()),
                    loaded: ![Equipment.bodyweight.displayName, Equipment.loadableBodyweight.displayName, ""].contains(
                        first.equipment),
                    repsOnly: first.equipment == Equipment.bodyweight.displayName,
                    targetRIR: Int(first.rirTarget), sets: sets,
                    warmups: rows.filter { $0.setType == "Warmup" }.map { row in
                        StudySet(reps: row.reps, load: row.weightTenthsPounds, target: row.targetReps,
                            targetLoad: row.targetWeightTenthsPounds, status: Status(rawValue: row.setStatus.lowercased()) ?? .planned,
                            logged: row.setLogged, started: row.setStarted, seconds: row.setSeconds.map(Double.init))
                    }, movementPattern: catalog[first.exerciseKey]?.profile.pattern,
                    equipment: Equipment.allCases.first { $0.displayName == first.equipment }))
        }
        self.plansFromLivePrograms = Set(programs.map { $0.syncID?.uuidString ?? String(describing: $0.persistentModelID) })
        self.workouts = workouts.values.sorted { ($0.date ?? .distantFuture, $0.key) < ($1.date ?? .distantFuture, $1.key) }
        self.sessions = sessions.sorted { ($0.date, $0.workout, $0.slot) < ($1.date, $1.workout, $1.slot) }
        let recordedLogs = logs.filter { $0.date <= today }
        self.firstDate = min(self.sessions.first?.date ?? today, recordedLogs.map(\.date).min() ?? today)
        self.credits = recordedLogs.flatMap { log in
            Muscle.allCases.map { muscle in (log.date, muscle, log.sets(for: muscle)) }
        }
    }

    func configured(for options: StudyOptions) -> Self {
        var history = self
        history.options = options
        history.exerciseMuscles = []
        if !options.exerciseKeys.isEmpty {
            let keys = Set(options.exerciseKeys)
            let represented = Set(sessions.filter { keys.contains($0.key) }.compactMap(\.primary))
            history.exerciseMuscles = Muscle.allCases.filter(represented.contains)
        }
        switch options.period {
        case .year(let year):
            history.selectedRange = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
                .flatMap { calendar.dateInterval(of: .year, for: $0) }
        case .month(let year, let month):
            history.selectedRange = calendar.date(from: DateComponents(year: year, month: month, day: 1))
                .flatMap { calendar.dateInterval(of: .month, for: $0) }
        case let .day(year, month, day):
            history.selectedRange = calendar.date(from: DateComponents(year: year, month: month, day: day))
                .flatMap { calendar.dateInterval(of: .day, for: $0) }
        case .original, .all: history.selectedRange = nil
        }
        return history
    }

    var originalPeriod: Bool {
        if case .original = options.period { return true }
        return false
    }
    var asOf: Date { min(today, selectedRange?.end.addingTimeInterval(-1) ?? today) }
    var rangeLabel: String {
        switch options.period {
        case .original: return ""
        case .all: return "All recorded history"
        case .year(let year): return String(year)
        case .day: return selectedRange?.start.formatted(.dateTime.month(.wide).day().year()) ?? ""
        case .month: return selectedRange?.start.formatted(.dateTime.month(.wide).year()) ?? ""
        }
    }
    func parameter(_ key: StudyParameter, _ fallback: Int) -> Int {
        min(key.range.upperBound, max(key.range.lowerBound, options.parameters[key] ?? fallback))
    }
    func includes(_ date: Date) -> Bool {
        guard let selectedRange else { return true }
        return date >= selectedRange.start && date < selectedRange.end
    }
    /// Historical baselines may cross the lower bound but still end at the exact calendar boundary.
    func throughRangeEnd(_ date: Date) -> Bool {
        date <= today && (selectedRange.map { date < $0.end } ?? true)
    }
    func exerciseMatches(_ session: StudySession) -> Bool {
        options.exerciseKeys.isEmpty || options.exerciseKeys.contains(session.key)
    }
    func muscles(_ fallback: [Muscle]) -> [Muscle] {
        if !options.muscles.isEmpty { return options.muscles }
        return exerciseMuscles.isEmpty ? fallback : exerciseMuscles
    }
    func muscleLabel(_ fallback: [Muscle], _ original: String) -> String {
        guard !options.muscles.isEmpty || !options.exerciseKeys.isEmpty else { return original }
        return muscles(fallback).map { $0.rawValue.capitalized }.joined(separator: ", ")
    }
    func focusKey(_ fallback: String) -> String { options.exerciseKeys.first ?? fallback }
    func exerciseName(for key: String) -> String {
        sessions.first { $0.key == key }?.name
            ?? key.replacingOccurrences(of: "catalog:", with: "").replacingOccurrences(of: "-", with: " ").capitalized
    }
    func focusName(_ fallback: String, _ original: String) -> String {
        options.exerciseKeys.first.map { exerciseName(for: $0) } ?? original
    }
    func lift(_ key: String) -> [StudySession] { sessions.filter { $0.key == key && !$0.done.isEmpty } }
    func focusedLift(_ fallback: String, includeEarlier: Bool = false) -> [StudySession] {
        lift(focusKey(fallback)).filter { includeEarlier ? throughRangeEnd($0.date) : includes($0.date) }
    }
    func weight(_ tenths: Int) -> Double { unit.value(fromTenthsPounds: tenths) }
    func loadText(_ tenths: Int) -> String { "\(unit.format(tenthsPounds: tenths)) \(unit.symbol)" }
    func day(_ date: Date) -> String { date.formatted(.dateTime.month(.abbreviated).day().year(.twoDigits)) }
    func week(_ date: Date) -> Date { calendar.dateInterval(of: .weekOfYear, for: date)!.start }
    func offset(_ date: Date, days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: date)! }
    func days(_ start: Date, _ end: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
    var recentWeeks: [Date] {
        let last = week(asOf)
        let count = parameter(.weeks, 6)
        let start = originalPeriod ? offset(last, days: -(count - 1) * 7) : week(selectedRange?.start ?? firstDate)
        guard start <= last else { return [] }
        return (0...max(0, days(start, last) / 7)).map { offset(start, days: $0 * 7) }
    }
    var yearStart: Date {
        selectedRange?.start
            ?? (originalPeriod
                ? calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))! : calendar.startOfDay(for: firstDate))
    }
    var yearEnd: Date {
        selectedRange?.end
            ?? (originalPeriod
                ? calendar.date(byAdding: .year, value: 1, to: yearStart)!
                : offset(calendar.startOfDay(for: today), days: 1))
    }
    var annualLabel: String { originalPeriod ? "2026" : rangeLabel }
    func inYear(_ date: Date) -> Bool { date >= yearStart && date < yearEnd }
    func recent(_ date: Date) -> Bool { originalPeriod ? days(date, today) < 28 : includes(date) }
    var recentLabel: String { originalPeriod ? "last 28 days" : rangeLabel }
    var weeksLabel: String { originalPeriod ? "last \(parameter(.weeks, 6)) weeks" : rangeLabel }

    /// Compare equally long observed intervals, including a partial current month or year only up to today.
    var comparisonWindows: (previous: DateInterval, current: DateInterval) {
        let until = offset(calendar.startOfDay(for: asOf), days: 1)
        let length: Int
        if originalPeriod {
            length = parameter(.comparisonDays, 28)
        } else if let selectedRange {
            length = max(1, days(selectedRange.start, until))
        } else {
            length = max(1, days(calendar.startOfDay(for: firstDate), until) / 2)
        }
        let start = selectedRange?.start ?? offset(until, days: -length)
        let upper = max(start, until)
        return (DateInterval(start: offset(start, days: -length), end: start), DateInterval(start: start, end: upper))
    }

    func isLeg(_ session: StudySession) -> Bool {
        let groups = muscles(Self.legs)
        return exerciseMatches(session)
            && (session.primary.map(groups.contains) == true || (session.assisting ?? []).contains(where: groups.contains))
    }

    static func quantile(_ values: [Double], _ p: Double = 0.5) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = Double(sorted.count - 1) * p
        let lower = Int(index)
        return sorted[lower] + (sorted[Int(ceil(index))] - sorted[lower]) * (index - Double(lower))
    }
}
