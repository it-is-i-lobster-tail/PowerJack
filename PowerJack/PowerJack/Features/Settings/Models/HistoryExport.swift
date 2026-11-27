//
//  HistoryExport.swift
//  PowerJack
//
//  Every set of every program as one CSV file, so a lifter can keep their history, study it in a
//  spreadsheet, or rebuild it somewhere else. One row per set, in program, week, day, exercise and
//  set order, with the program, workout and exercise it belongs to repeated on each row.
//
//  Nothing personal goes in. Names the lifter typed (their own templates and exercises) could say
//  anything, so they become "Custom Template 1" or "Custom Exercise 2", numbered in the order they
//  first appear. Built-in names stay. Times are in UTC, so they don't give away where the lifter is.
//

import Foundation
import SwiftData

enum HistoryExport {
    /// The header row. Weights are in `unit`, so the weight headers name it.
    static func columns(unit: WeightUnit) -> [String] {
        [
            "Program #", "Program ID", "Program", "Program Type", "Program Weeks", "Days Per Week", "Program Status",
            "Week", "Week Type", "Day", "Workout Status", "Workout Started", "Workout Ended", "Workout Minutes",
            "Exercise #", "Exercise", "Equipment", "Primary Muscle", "Exercise Source", "Superset", "Exercise Status",
            "Effort", "Pain", "Top Set RIR", "RIR Target", "Progression",
            "Set Type", "Set #", "Set Status", "Target Reps", "Reps",
            "Target Weight (\(unit.symbol))", "Weight (\(unit.symbol))", "Set Started", "Set Logged", "Set Seconds",
        ]
    }

    /// The whole history as CSV text, oldest program first: the saved rows of programs that
    /// ended (see `HistoryArchive`), then each of `programs` not among them, read as it is now.
    static func csv(for programs: [Program], saved: [ArchivedRow] = [], unit: WeightUnit = .current) -> String {
        let savedIDs = Set(saved.compactMap(\.programID))
        let savedPrograms = Dictionary(grouping: saved) { $0.programID ?? $0.batchID }.values.map { records in
            (started: records.first?.programStarted ?? .distantFuture, rows: records.sorted { $0.order < $1.order }.map(\.row))
        }
        let livePrograms = programs
            .filter { program in program.syncID.map { !savedIDs.contains($0) } ?? true }
            .map { (started: firstActivity(of: $0) ?? .distantFuture, rows: rows(for: $0)) }
        let ordered = (savedPrograms + livePrograms).enumerated()
            .sorted { ($0.element.started, $0.offset) < ($1.element.started, $1.offset) }
            .map(\.element.rows)

        var lines = [row(columns(unit: unit))]
        var names = Names()
        for (index, rows) in ordered.enumerated() {
            lines += rows.map { line(for: $0, number: index + 1, unit: unit, names: &names) }
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Writes the history to a temporary file named for today, ready to share.
    static func writeFile(from context: ModelContext, unit: WeightUnit = .current) throws -> URL {
        try HistoryArchive.saveEndedPrograms(in: context)
        let saved = try HistoryArchive.records(in: context)
        let programs = try context.fetch(FetchDescriptor<Program>())
        let url = URL.temporaryDirectory.appending(path: "PowerJack History \(Date.now.formatted(Self.day)).csv")
        try csv(for: programs, saved: saved, unit: unit).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Every set of `program`, in week, day, exercise and set order. `status` stands in for the
    /// program's own, such as when it is about to be deleted.
    static func rows(for program: Program, status: HistoryProgramStatus? = nil) -> [HistoryRow] {
        var rows: [HistoryRow] = []
        for (weekIndex, week) in program.programWeeks.enumerated() {
            for (dayIndex, workout) in week.workouts.enumerated() {
                let supersets = supersetLetters(in: workout)
                for (exerciseIndex, workoutExercise) in workout.workoutExercises.enumerated() {
                    // What was actually done, so a one-time substitute shows as itself.
                    let exercise = workoutExercise.shownExercise
                    let feedback = workoutExercise.feedback
                    for workoutSet in workoutExercise.workoutSets {
                        rows.append(HistoryRow(
                            programID: program.syncID,
                            programName: program.templateName,
                            programType: program.templateType.name,
                            programWeeks: program.programLengthWeeks,
                            daysPerWeek: program.workoutsPerWeek,
                            programStatus: status ?? HistoryProgramStatus(program.status),
                            week: weekIndex + 1,
                            weekType: week.weekKind?.rawValue.capitalized ?? "",
                            day: dayIndex + 1,
                            workoutStatus: workout.status.label,
                            workoutStarted: workout.startedAt,
                            workoutEnded: workout.endedAt,
                            workoutSeconds: workout.endedAt == nil ? nil : workout.duration(),
                            exerciseNumber: exerciseIndex + 1,
                            exerciseName: exercise?.exerciseName ?? "",
                            exerciseKey: exercise.map { $0.syncKey ?? $0.exerciseName } ?? "",
                            exerciseSource: exercise.map { $0.userCreated ? "Custom" : "Built-in" } ?? "",
                            equipment: exercise?.equipment.displayName ?? "",
                            primaryMuscle: exercise?.primaryMuscleFocus.rawValue.capitalized ?? "",
                            superset: supersets[ObjectIdentifier(workoutExercise)] ?? "",
                            exerciseStatus: workoutExercise.status.label,
                            effort: feedback.map(effort) ?? "",
                            pain: feedback?.levelOfPain.label ?? "",
                            topSetRIR: workoutExercise.topSetRepsInReserve?.valueText ?? "",
                            rirTarget: workoutExercise.rirTarget.map(String.init) ?? "",
                            progression: workoutExercise.progressionNote ?? workoutExercise.progressionCode ?? "",
                            setType: setType(of: workoutSet, in: workoutExercise),
                            setNumber: workoutExercise.number(of: workoutSet),
                            setStatus: workoutSet.status.label,
                            targetReps: workoutSet.repsPlanned,
                            reps: workoutSet.reps,
                            targetWeightTenthsPounds: workoutSet.weightTenthsPlannedPounds,
                            weightTenthsPounds: workoutSet.weightTenthsPounds,
                            setStarted: workoutSet.startedAt,
                            setLogged: workoutSet.completedAt,
                            setSeconds: workoutSet.duration.map { Int($0.rounded()) }
                        ))
                    }
                }
            }
        }
        return rows
    }

    private static func line(for row: HistoryRow, number: Int, unit: WeightUnit, names: inout Names) -> String {
        Self.row([
            "\(number)",
            row.programID?.uuidString ?? "",
            names.template(row.programName),
            row.programType,
            "\(row.programWeeks)",
            "\(row.daysPerWeek)",
            row.programStatus.rawValue,
            "\(row.week)",
            row.weekType,
            "\(row.day)",
            row.workoutStatus,
            date(row.workoutStarted),
            date(row.workoutEnded),
            decimal(row.workoutSeconds.map { $0 / 60 }),
            "\(row.exerciseNumber)",
            names.exercise(row),
            row.equipment,
            row.primaryMuscle,
            row.exerciseSource,
            row.superset,
            row.exerciseStatus,
            row.effort,
            row.pain,
            row.topSetRIR,
            row.rirTarget,
            row.progression,
            row.setType,
            "\(row.setNumber)",
            row.setStatus,
            row.targetReps.map(String.init) ?? "",
            row.reps.map(String.init) ?? "",
            weight(row.targetWeightTenthsPounds, in: unit),
            weight(row.weightTenthsPounds, in: unit),
            date(row.setStarted),
            date(row.setLogged),
            row.setSeconds.map(String.init) ?? "",
        ])
    }

    /// Programs are numbered by when they started. One never started has none and goes after the rest.
    static func firstActivity(of program: Program) -> Date? {
        program.programWeeks.flatMap(\.workouts).compactMap { $0.startedAt ?? $0.createdAt }.min()
    }

    /// Supersets get letters by their place in the day, as in the template. An exercise on its own gets none.
    private static func supersetLetters(in workout: Workout) -> [ObjectIdentifier: String] {
        let letters = TemplateWorkoutDraft.supersetLetters
        var lettered: [ObjectIdentifier: String] = [:]
        for (index, group) in workout.exerciseGroups.filter({ $0.count > 1 }).enumerated() {
            for workoutExercise in group {
                lettered[ObjectIdentifier(workoutExercise)] = letters[min(index, letters.count - 1)]
            }
        }
        return lettered
    }

    static func setType(of workoutSet: WorkoutSet, in workoutExercise: WorkoutExercise) -> String {
        if workoutSet.isWarmup { return "Warmup" }
        return workoutExercise.isTopSet(workoutSet) ? "Top" : "Working"
    }

    /// Reps left when the effort was rated that way, or the older effort word.
    private static func effort(_ feedback: ExerciseFeedback) -> String {
        feedback.repsInReserve?.label ?? feedback.levelOfEffort.label
    }

    // Fixed formats, so the file reads the same in any region: "2026-11-15T02:03:22Z", "102.5".
    private static let time = Date.ISO8601FormatStyle()
    private static let day = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()

    private static func date(_ date: Date?) -> String {
        date?.formatted(time) ?? ""
    }

    private static func weight(_ tenthsPounds: Int?, in unit: WeightUnit) -> String {
        decimal(tenthsPounds.map(unit.value(fromTenthsPounds:)))
    }

    private static func decimal(_ value: Double?) -> String {
        value?.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))) ?? ""
    }

    /// Quotes a field only when it holds a comma, quote or line break, doubling any quotes inside.
    private static func row(_ fields: [String]) -> String {
        fields.map { field in
            guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        .joined(separator: ",")
    }
}

/// Stands in for names the lifter typed, so the file holds only names PowerJack ships with.
private struct Names {
    private static let builtInTemplates = Set(TemplateCatalog.entries.map(\.name))
    private var templates: [String: String] = [:]
    private var exercises: [String: String] = [:]

    /// A built-in template's name, even for a program made from an edited copy, as long as the name is unchanged.
    mutating func template(_ name: String) -> String {
        if Self.builtInTemplates.contains(name) { return name }
        if let label = templates[name] { return label }
        let label = "Custom Template \(templates.count + 1)"
        templates[name] = label
        return label
    }

    /// Built-in exercises can't be renamed, so only the lifter's own get a stand-in.
    mutating func exercise(_ row: HistoryRow) -> String {
        guard row.isCustomExercise else { return row.exerciseName }
        if let label = exercises[row.exerciseKey] { return label }
        let label = "Custom Exercise \(exercises.count + 1)"
        exercises[row.exerciseKey] = label
        return label
    }
}

private extension Status {
    var label: String { rawValue.capitalized }
}
