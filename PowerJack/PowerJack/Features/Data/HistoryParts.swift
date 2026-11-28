import Foundation
import SwiftData

/// What the Data tab and the exercise picker are built from, kept in pieces so a saved change
/// rebuilds only the pieces it touched. Nothing here depends on the day or the weight unit:
/// `StudyHistory(parts:unit:today:calendar:)` filters and sums them for a given day.
struct HistoryParts: Codable {
    /// One program workout.
    struct Workout: Codable, Equatable {
        var workout: StudyWorkout
        /// Empty while the workout is planned.
        var sessions: [StudySession]
        /// When a finished workout is dated, and the lifts it logged, for the picker's familiarity.
        var familiar: Familiar?
        /// Where its lifts sit in `exercises`, so editing a lift rebuilds only the workouts that show it.
        var lifts: [Int]
    }

    /// One exercise of a saved program that no longer exists.
    struct Archived: Codable, Equatable {
        var workout: StudyWorkout
        var session: StudySession?
    }

    struct Familiar: Codable, Equatable {
        var date: Date
        var keys: [String]
    }

    /// A finished workout's log: the sets it counted for each muscle, in `Muscle.allCases` order.
    struct Log: Codable, Equatable {
        var date: Date
        var sets: [Double]
    }

    /// A lift, or a program or week, as the pieces read it. A change elsewhere leaves the pieces alone.
    struct Print: Codable, Equatable {
        var id: String
        var text: String
    }

    /// Rows by `rowID(_:)`. A decoded `PersistentIdentifier` equals the store's but hashes
    /// differently, so it can't key a dictionary read back from the file.
    var workouts: [String: Workout] = [:]
    var exercises: [Print] = []
    var programPrints: [String: String] = [:]
    var weekPrints: [String: String] = [:]
    var archived: [Archived] = []
    var imported: [StudySession] = []
    var importedFamiliar: [Familiar] = []
    var logs: [Log] = []
    var movesLike: [String: String] = [:]
    /// The calendar and time zone the imported days were dated in.
    var calendar = ""

    /// The picker's familiarity: finished workouts and imported days, oldest first.
    var familiarity: ExerciseFamiliarity {
        let sessions = (workouts.values.compactMap(\.familiar) + importedFamiliar).sorted { a, b in
            a.date != b.date ? a.date < b.date : a.keys.lexicographicallyPrecedes(b.keys)
        }
        return ExerciseFamiliarity(sessions: sessions.map { Set($0.keys) })
    }
}

// MARK: Building the pieces

extension HistoryParts {
    private static let rowEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    /// A row's identifier as text that stays the same across launches.
    static func rowID(_ id: PersistentIdentifier) -> String {
        if let known = rowIDs[id] { return known }
        let text = (try? rowEncoder.encode(id)).map { String(decoding: $0, as: UTF8.self) } ?? "\(id)"
        rowIDs[id] = text
        return text
    }

    private static var rowIDs: [PersistentIdentifier: String] = [:]

    static func calendarStamp(_ calendar: Calendar) -> String {
        "\(calendar.identifier)|\(calendar.timeZone.identifier)|\(calendar.firstWeekday)"
    }

    /// Every piece, from models already fetched.
    init(programs: [Program], archive: [ArchivedRow], logs: [WorkoutLog], imported: [ImportedSet],
         exercises: [Exercise], calendar: Calendar) {
        for program in programs {
            programPrints[Self.rowID(program.persistentModelID)] = Self.print(of: program)
            for week in program.programWeeks {
                weekPrints[Self.rowID(week.persistentModelID)] = Self.print(of: week)
                for workout in week.workouts {
                    workouts[Self.rowID(workout.persistentModelID)] = part(of: workout, in: week, of: program)
                }
            }
        }
        archived = Self.archived(archive, live: Set(programs.compactMap(\.syncID)))
        setImported(imported, exercises: exercises, calendar: calendar)
        self.logs = Self.logs(logs)
    }

    /// The program or week fields a workout's sessions read.
    static func print(of program: Program) -> String {
        "\(program.syncID?.uuidString ?? "")|\(program.templateName)"
    }

    static func print(of week: ProgramWeek) -> String { "\(week.order)|\(week.blockWeek)" }

    static func print(of exercise: Exercise) -> String {
        let assisting = exercise.secondaryMuscles.map(\.rawValue).joined(separator: ",")
        return [exercise.syncKey ?? "", exercise.searchKey, exercise.exerciseName, exercise.primaryMuscleFocus.rawValue,
                assisting, "\(exercise.repsOnly)", "\(exercise.addsToBodyweight)"].joined(separator: "|")
    }

    /// Where `exercise` sits in `exercises`, adding it when it's new.
    mutating func lift(_ exercise: Exercise) -> Int {
        let id = Self.rowID(exercise.persistentModelID)
        if let index = exercises.firstIndex(where: { $0.id == id }) { return index }
        exercises.append(Print(id: id, text: Self.print(of: exercise)))
        return exercises.count - 1
    }

    /// One program workout's sessions, as `StudyHistory` reads them.
    mutating func part(of workout: PowerJack.Workout, in week: ProgramWeek, of program: Program) -> Workout {
        let pid = program.syncID?.uuidString ?? String(describing: program.persistentModelID)
        let key = "\(pid)/\(week.order)/\(workout.order)"
        let summary = StudyWorkout(key: key, status: workout.status, began: workout.startedAt,
            ended: workout.endedAt, seconds: workout.endedAt == nil ? nil : workout.duration())
        var lifts: [Int] = []
        var sessions: [StudySession] = []
        var familiarKeys: [String] = []
        for slot in workout.workoutExercises {
            if let exercise = slot.exercise { lifts.append(lift(exercise)) }
            if let substitute = slot.substituteValue { lifts.append(lift(substitute)) }
            let working = slot.workingSets
            if working.contains(where: { $0.status == .complete }), let searchKey = slot.shownExercise?.searchKey {
                familiarKeys.append(searchKey)
            }
            guard workout.status != .planned, let date = workout.endedAt ?? workout.startedAt,
                  let exercise = slot.shownExercise else { continue }
            let feedback = slot.feedback
            let rated = feedback?.completedSets ?? working.filter { $0.status == .complete }.count
            var completed = 0
            let sets = working.map { set in
                if set.status == .complete { completed += 1 }
                return StudySet(
                    reps: set.reps, load: set.weightTenthsPounds, target: set.repsPlanned,
                    targetLoad: set.weightTenthsPlannedPounds, status: set.status, logged: set.completedAt,
                    rating: set.status == .complete && completed == rated ? feedback?.repsInReserve : nil)
            }
            sessions.append(
                StudySession(
                    date: date, workout: key,
                    routine: "\(program.templateName) · day \(workout.order + 1)",
                    block: week.blockWeek > 0 ? "\(pid)/\(week.order + 1 - week.blockWeek)" : nil,
                    blockWeek: week.blockWeek > 0 ? week.blockWeek : nil,
                    seconds: summary.seconds,
                    finished: workout.status == .complete,
                    slot: slot.order, superset: slot.supersetID != nil,
                    key: exercise.syncKey ?? exercise.exerciseName,
                    name: exercise.exerciseName, planned: slot.exercise.map { $0.syncKey ?? $0.exerciseName },
                    primary: exercise.primaryMuscleFocus, assisting: exercise.secondaryMuscles,
                    loaded: !exercise.repsOnly && !exercise.addsToBodyweight,
                    repsOnly: exercise.repsOnly, targetRIR: slot.rirTarget,
                    sets: sets, warmups: slot.warmupSets.map { set in
                        StudySet(reps: set.reps, load: set.weightTenthsPounds, target: set.repsPlanned,
                            targetLoad: set.weightTenthsPlannedPounds, status: set.status, logged: set.completedAt)
                    }))
        }
        var familiar: Familiar?
        if workout.status == .complete, let date = workout.endedAt ?? workout.startedAt, !familiarKeys.isEmpty {
            familiar = Familiar(date: date, keys: Array(Set(familiarKeys)).sorted())
        }
        return Workout(workout: summary, sessions: sessions, familiar: familiar, lifts: lifts)
    }

    /// Saved rows of programs that no longer exist, one piece per exercise. A live program's rows
    /// would repeat what its own workouts show, so they're left out.
    static func archived(_ archive: [ArchivedRow], live: Set<UUID>) -> [Archived] {
        let saved = HistoryArchive.uniqueBatchRecords(
            archive.filter { record in
                !(record.programID.map(live.contains) ?? false)
            })
        let slots = Dictionary(grouping: saved) { record in
            let pid = (record.programID ?? record.batchID)?.uuidString ?? record.row.programName
            return "\(pid)/\(record.row.week)/\(record.row.day)/\(record.row.exerciseNumber)"
        }
        return slots.keys.sorted().compactMap { slot in
            let entry = slots[slot]!
            let rows = entry.sorted { $0.order < $1.order }.map(\.row)
            guard let first = rows.first else { return nil }
            let pid = (entry.first?.programID ?? entry.first?.batchID)?.uuidString ?? first.programName
            let key = "\(pid)/\(first.week)/\(first.day)"
            let workout = StudyWorkout(key: key, status: Status(rawValue: first.workoutStatus.lowercased()) ?? .planned,
                began: first.workoutStarted, ended: first.workoutEnded, seconds: first.workoutSeconds)
            guard let date = first.workoutEnded ?? first.workoutStarted else { return Archived(workout: workout) }
            let working = rows.filter { $0.setType != "Warmup" }
            var sets = working.map { row in
                StudySet(
                    reps: row.reps, load: row.weightTenthsPounds, target: row.targetReps,
                    targetLoad: row.targetWeightTenthsPounds,
                    status: Status(rawValue: row.setStatus.lowercased()) ?? .planned,
                    logged: row.setLogged)
            }
            if let last = sets.lastIndex(where: { $0.status == .complete }) {
                sets[last].rating = RepsInReserve.allCases.first { $0.label == first.effort }
            }
            let session = StudySession(
                date: date, workout: key,
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
                        logged: row.setLogged)
                })
            return Archived(workout: workout, session: session)
        }
    }

    /// Imported sets and the lifts' own-exercise links, which read the exercise list.
    mutating func setImported(_ imported: [ImportedSet], exercises: [Exercise], calendar: Calendar) {
        self.calendar = Self.calendarStamp(calendar)
        movesLike = Dictionary(exercises.compactMap { exercise in
            guard let key = exercise.syncKey, let built = MovesLike.key(of: exercise) else { return nil }
            return (key, built)
        }, uniquingKeysWith: { first, _ in first })
        self.imported = Self.sessions(from: imported, exercises: exercises, calendar: calendar)
        importedFamiliar = Dictionary(grouping: imported, by: \.trainingDay).compactMap { day, rows in
            guard let date = Self.noon(of: day, in: calendar) else { return nil }
            return Familiar(date: date, keys: Set(rows.map(\.exerciseKey).filter { !$0.isEmpty }).sorted())
        }
    }

    static func logs(_ logs: [WorkoutLog]) -> [Log] {
        logs.map { log in Log(date: log.date, sets: Muscle.allCases.map { log.sets(for: $0) }) }
    }

    private static func noon(of day: String, in calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// Imported sets grouped into one session per exercise per training day, dated at local noon.
    /// Rows without reps (cardio, timed holds) aren't strength sets, so they are left out.
    private static func sessions(from imported: [ImportedSet], exercises: [Exercise], calendar: Calendar) -> [StudySession] {
        let byKey = Dictionary(exercises.compactMap { e in e.syncKey.map { ($0, e) } }, uniquingKeysWith: { a, _ in a })
        let days = Dictionary(grouping: imported.filter { $0.reps != nil }, by: \.trainingDay)
        return days.keys.sorted().flatMap { day -> [StudySession] in
            guard let date = noon(of: day, in: calendar) else { return [] }
            let slots = Dictionary(grouping: days[day]!, by: \.exerciseKey).values
                .map { $0.sorted { $0.sourceOrder < $1.sourceOrder } }
                .sorted { $0[0].sourceOrder < $1[0].sourceOrder }
            return slots.enumerated().map { slot, rows in
                let first = rows[0]
                let exercise = byKey[first.exerciseKey]
                let loaded = exercise.map { !$0.repsOnly && !$0.addsToBodyweight }
                    ?? rows.contains { ($0.weightTenthsPounds ?? 0) > 0 }
                return StudySession(
                    date: date, workout: "imported/\(day)", routine: "Imported", seconds: nil, finished: true,
                    slot: slot, superset: false, key: first.exerciseKey.isEmpty ? first.exerciseName : first.exerciseKey,
                    name: exercise?.exerciseName ?? first.exerciseName,
                    primary: exercise?.primaryMuscleFocus ?? Muscle(rawValue: first.muscle),
                    assisting: exercise?.secondaryMuscles, loaded: loaded, repsOnly: exercise?.repsOnly ?? !loaded,
                    sets: rows.map { StudySet(reps: $0.reps, load: $0.weightTenthsPounds, status: .complete) })
            }
        }
    }
}

extension HistoryParts.Archived {
    init(workout: StudyWorkout) { self.init(workout: workout, session: nil) }
}
