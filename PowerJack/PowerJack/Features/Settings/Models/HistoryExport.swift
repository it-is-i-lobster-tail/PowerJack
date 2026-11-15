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
            "Program #", "Program", "Program Type", "Program Weeks", "Days Per Week", "Program Status",
            "Week", "Week Type", "Day", "Workout Status", "Workout Started", "Workout Ended", "Workout Minutes",
            "Exercise #", "Exercise", "Equipment", "Primary Muscle", "Exercise Source", "Superset", "Exercise Status",
            "Effort", "Pain", "Top Set RIR", "RIR Target", "Progression",
            "Set Type", "Set #", "Set Status", "Target Reps", "Reps",
            "Target Weight (\(unit.symbol))", "Weight (\(unit.symbol))", "Set Started", "Set Logged", "Set Seconds",
        ]
    }

    /// The whole history as CSV text, oldest program first.
    static func csv(for programs: [Program], unit: WeightUnit = .current) -> String {
        var lines = [row(columns(unit: unit))]
        var names = Names()
        for (index, program) in programs.sorted(by: { firstActivity(of: $0) < firstActivity(of: $1) }).enumerated() {
            lines += rows(for: program, number: index + 1, unit: unit, names: &names)
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Writes the history to a temporary file named for today, ready to share.
    static func writeFile(from context: ModelContext, unit: WeightUnit = .current) throws -> URL {
        let programs = try context.fetch(FetchDescriptor<Program>())
        let url = URL.temporaryDirectory.appending(path: "PowerJack History \(Date.now.formatted(Self.day)).csv")
        try csv(for: programs, unit: unit).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func rows(for program: Program, number: Int, unit: WeightUnit, names: inout Names) -> [String] {
        var lines: [String] = []
        let programName = names.template(program.templateName)
        for (weekIndex, week) in program.programWeeks.enumerated() {
            for (dayIndex, workout) in week.workouts.enumerated() {
                let supersets = supersetLetters(in: workout)
                for (exerciseIndex, workoutExercise) in workout.workoutExercises.enumerated() {
                    let exercise = workoutExercise.exercise
                    let exerciseName = exercise.map { names.exercise($0) } ?? ""
                    let feedback = workoutExercise.feedback
                    for workoutSet in workoutExercise.workoutSets {
                        lines.append(row([
                            "\(number)",
                            programName,
                            program.templateType.name,
                            "\(program.programLengthWeeks)",
                            "\(program.workoutsPerWeek)",
                            program.status.label,
                            "\(weekIndex + 1)",
                            week.weekKind?.rawValue.capitalized ?? "",
                            "\(dayIndex + 1)",
                            workout.status.label,
                            date(workout.startedAt),
                            date(workout.endedAt),
                            workout.endedAt == nil ? "" : decimal(workout.duration().map { $0 / 60 }),
                            "\(exerciseIndex + 1)",
                            exerciseName,
                            exercise?.equipment.displayName ?? "",
                            exercise?.primaryMuscleFocus.rawValue.capitalized ?? "",
                            exercise.map { $0.userCreated ? "Custom" : "Built-in" } ?? "",
                            supersets[ObjectIdentifier(workoutExercise)] ?? "",
                            workoutExercise.status.label,
                            feedback.map(effort) ?? "",
                            feedback?.levelOfPain.label ?? "",
                            workoutExercise.topSetRepsInReserve?.valueText ?? "",
                            workoutExercise.rirTarget.map(String.init) ?? "",
                            workoutExercise.progressionNote ?? workoutExercise.progressionCode ?? "",
                            setType(of: workoutSet, in: workoutExercise),
                            "\(workoutExercise.number(of: workoutSet))",
                            workoutSet.status.label,
                            workoutSet.repsPlanned.map(String.init) ?? "",
                            workoutSet.reps.map(String.init) ?? "",
                            weight(workoutSet.weightTenthsPlannedPounds, in: unit),
                            weight(workoutSet.weightTenthsPounds, in: unit),
                            date(workoutSet.startedAt),
                            date(workoutSet.completedAt),
                            workoutSet.duration.map { "\(Int($0.rounded()))" } ?? "",
                        ]))
                    }
                }
            }
        }
        return lines
    }

    /// Programs are numbered by when they started. One never started goes after the rest.
    private static func firstActivity(of program: Program) -> Date {
        program.programWeeks.flatMap(\.workouts).compactMap { $0.startedAt ?? $0.createdAt }.min() ?? .distantFuture
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

    private static func setType(of workoutSet: WorkoutSet, in workoutExercise: WorkoutExercise) -> String {
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
    private var exercises: [ObjectIdentifier: String] = [:]

    /// A built-in template's name, even for a program made from an edited copy, as long as the name is unchanged.
    mutating func template(_ name: String) -> String {
        if Self.builtInTemplates.contains(name) { return name }
        if let label = templates[name] { return label }
        let label = "Custom Template \(templates.count + 1)"
        templates[name] = label
        return label
    }

    /// Built-in exercises can't be renamed, so only the lifter's own get a stand-in.
    mutating func exercise(_ exercise: Exercise) -> String {
        guard exercise.userCreated else { return exercise.exerciseName }
        if let label = exercises[ObjectIdentifier(exercise)] { return label }
        let label = "Custom Exercise \(exercises.count + 1)"
        exercises[ObjectIdentifier(exercise)] = label
        return label
    }
}

private extension Status {
    var label: String { rawValue.capitalized }
}
