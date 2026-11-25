import Foundation

/// A projected opportunity. Only its deterministic inputs, never generated prose, establish a record.
struct WorkoutAchievement: Codable, Hashable {
    enum Kind: String, Codable, Hashable, CaseIterable {
        // Selection priority. Within a kind, workout order wins.
        case firstProgram, fourWeekStreak, returnToBest, strengthPR, sessionVolume, heavierDumbbells, repPR, extraSet
    }

    let kind: Kind
    var exerciseName: String?
    var weight: Int?
    var reps: Int?
    var previous: Int?
    var target: Int?
    var lastBest: Date?

    var title: String {
        switch kind {
        case .firstProgram: "First program finish"
        case .fourWeekStreak: "Four-week training streak"
        case .returnToBest: "Return to your best on \(exerciseName ?? "this lift")"
        case .strengthPR: "\(exerciseName ?? "Strength") PR in play"
        case .sessionVolume: "Session volume record in play"
        case .heavierDumbbells: "Heavier dumbbells on \(exerciseName ?? "this lift")"
        case .repPR: "\(exerciseName ?? "Exercise") rep PR in play"
        case .extraSet: "An extra set on \(exerciseName ?? "this lift")"
        }
    }

    func detail(unit: WeightUnit) -> String {
        func load(_ value: Int) -> String { "\(unit.format(tenthsPounds: value)) \(unit.symbol)" }
        let name = exerciseName ?? "this exercise"
        let effort = [reps.map { "\($0) reps" }, weight.map { "at \(load($0))" }].compactMap { $0 }.joined(separator: " ")
        switch kind {
        case .firstProgram: return "Finish this workout to complete every scheduled session in your first full program."
        case .fourWeekStreak: return "Finish this workout to complete four consecutive program weeks with every scheduled session logged."
        case .returnToBest: return "\(name): \(effort) would match your previous best after time away from that mark."
        case .strengthPR: return "\(name): \(effort) would put your strength estimate above your recorded best."
        case .sessionVolume:
            return "Completing the planned working sets would total \(load(target ?? 0)) lifted, above your previous session best of \(load(previous ?? 0))."
        case .heavierDumbbells:
            return "\(name) calls for \(load(weight ?? 0)), above your previous heaviest dumbbell load of \(load(previous ?? 0))."
        case .repPR: return "\(name): \(effort) would beat your best of \(previous ?? 0) reps at the same load."
        case .extraSet: return "\(name) goes from \(previous ?? 0) to \(target ?? 0) planned working sets."
        }
    }

    static func selected(preview: WorkoutPreview, program: Program, workout: Workout,
                         history: WorkoutPreviewHistory, at date: Date) -> Self? {
        guard workout.status == .planned, !preview.lifts.isEmpty else { return nil }
        if let milestone = attendance(program: program, workout: workout, history: history) { return milestone }
        let stable = preview.type == .strength ? StrengthPlanner.previewStability(workout, in: program, at: date) : nil
        let eligible = preview.lifts.filter { $0.allowsPR && (stable?.targets.contains($0.order) ?? true) }
        var candidates: [Kind: Self] = [:]
        for lift in eligible {
            let benchPRAllowed = preview.weekKind != .deload && preview.weekKind != .return &&
                (stable?.normalBench.contains(lift.order) ?? true)
            for opportunity in liftOpportunities(lift, history: history, at: date, benchPRAllowed: benchPRAllowed) where candidates[opportunity.kind] == nil {
                candidates[opportunity.kind] = opportunity
            }
        }
        for lift in preview.lifts where lift.allowsPR && (stable?.counts.contains(lift.order) ?? true) {
            let previousCount = history.previousSets(for: lift, before: date).count
            let count = lift.sets.reduce(0) { $0 + $1.count }
            if previousCount > 0, count > previousCount {
                candidates[.extraSet] = Self(kind: .extraSet, exerciseName: lift.name, previous: previousCount, target: count)
                break
            }
        }
        if eligible.count == preview.lifts.count, let volume = sessionVolume(lifts: eligible, history: history, at: date) {
            candidates[.sessionVolume] = volume
        }
        return Kind.allCases.lazy.compactMap { candidates[$0] }.first
    }

    private static func attendance(program: Program, workout: Workout, history: WorkoutPreviewHistory) -> Self? {
        let weeks = program.programWeeks
        guard program.status == .active, let index = weeks.firstIndex(where: { $0.workouts.contains { $0 === workout } }),
              weeks[index].workouts.last === workout else { return nil }
        func fullyTrained(_ week: ProgramWeek) -> Bool {
            week.workouts.count == program.workoutsPerWeek && !week.workouts.isEmpty && week.workouts.allSatisfy { $0 === workout || $0.status == .complete }
        }
        guard fullyTrained(weeks[index]) else { return nil }
        if index == weeks.count - 1, weeks.count == program.programLengthWeeks, weeks.allSatisfy(fullyTrained), !history.precludesFirstProgram {
            return Self(kind: .firstProgram)
        }
        let streak = weeks[...index].reversed().prefix(while: fullyTrained).count
        return streak == 4 ? Self(kind: .fourWeekStreak) : nil
    }

    private struct Result {
        let date: Date
        let reps: Int
        let weight: Int
    }

    private static func liftOpportunities(_ lift: WorkoutPreview.Lift, history: WorkoutPreviewHistory, at date: Date, benchPRAllowed: Bool) -> [Self] {
        let prior = history.sessions.filter { $0.ended <= date }.flatMap { session in
            session.matching(lift, in: session.logged).compactMap { row -> Result? in
                guard let reps = row.reps, let weight = comparableLoad(row.weightTenthsPounds, for: lift.equipment) else { return nil }
                return Result(date: session.ended, reps: reps, weight: weight)
            }
        }
        var result: [Self] = []
        let sets = lift.sets.compactMap { set -> Result? in
            guard let reps = set.reps, reps > 0, let weight = comparableLoad(set.weight, for: lift.equipment) else { return nil }
            return Result(date: date, reps: reps, weight: weight)
        }

        func candidate(_ kind: Kind, set: Result) -> Self {
            Self(kind: kind, exerciseName: lift.name, weight: lift.equipment == .bodyweight ? nil : set.weight, reps: set.reps)
        }
        // Compare each session's best on this measure. A lighter back-off in a record session
        // cannot establish the intervening dip, and a stronger planned top set takes precedence over a match.
        func comeback(planned: [(Result, Double)], previous: [(Result, Double)]) -> Self? {
            guard let top = planned.max(by: { $0.1 < $1.1 }), let best = previous.map(\.1).max(),
                  top.1 == best, let last = previous.filter({ $0.1 == best }).map({ $0.0.date }).max() else { return nil }
            let calendar = Calendar.current
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: date)).day ?? 0
            guard days >= 30, previous.contains(where: { $0.0.date > last && $0.1 < best }) else { return nil }
            var match = candidate(.returnToBest, set: top.0)
            match.lastBest = last
            return match
        }

        if let curve = lift.curve {
            func scored(_ set: Result) -> (Result, Double)? {
                WorkoutPreviewHistory.estimate(curve: curve, reps: set.reps, weight: set.weight).map { (set, $0) }
            }
            let planned = sets.compactMap(scored)
            let previous = prior.compactMap(scored)
            if let match = comeback(planned: planned, previous: previous) { result.append(match) }
            if let top = planned.max(by: { $0.1 < $1.1 }), let best = previous.map(\.1).max(), top.1 > best,
               lift.catalogID != StrengthLifts.benchID || (benchPRAllowed && top.1 >= best * 1.02) {
                result.append(candidate(.strengthPR, set: top.0))
            }
        }

        for set in sets {
            let sameWeight = prior.filter { $0.weight == set.weight }
            if let best = sameWeight.map(\.reps).max(), set.reps > best {
                var record = candidate(.repPR, set: set)
                record.previous = best
                result.append(record)
            }
            if lift.curve == nil {
                let plans = sets.filter { $0.weight == set.weight }.map { ($0, Double($0.reps)) }
                let logs = sameWeight.map { ($0, Double($0.reps)) }
                if let match = comeback(planned: plans, previous: logs) { result.append(match) }
                if lift.equipment != .bodyweight {
                    let plans = sets.filter { $0.reps == set.reps }.map { ($0, Double($0.weight)) }
                    let logs = prior.filter { $0.reps == set.reps }.map { ($0, Double($0.weight)) }
                    if let match = comeback(planned: plans, previous: logs) { result.append(match) }
                }
            }
        }
        if lift.equipment == .dumbbell, let heaviest = lift.sets.compactMap(\.weight).max(),
           let best = prior.map(\.weight).max(), heaviest > best {
            result.append(Self(kind: .heavierDumbbells, exerciseName: lift.name, weight: heaviest, previous: best))
        }
        // A set surpassing the old mark is a record, even when another set in this lift matches it.
        if result.contains(where: { [.strengthPR, .heavierDumbbells, .repPR].contains($0.kind) }) {
            result.removeAll { $0.kind == .returnToBest }
        }
        return result
    }

    private static func comparableLoad(_ weight: Int?, for equipment: Equipment) -> Int? {
        if equipment == .bodyweight { return weight == nil || weight == 0 ? 0 : nil }
        guard let weight, weight > 0 || (equipment == .loadableBodyweight && weight == 0) else { return nil }
        return weight
    }

    private static func sessionVolume(lifts: [WorkoutPreview.Lift], history: WorkoutPreviewHistory, at date: Date) -> Self? {
        var planned = 0
        for lift in lifts where lift.equipment != .bodyweight {
            for set in lift.sets {
                guard let weight = comparableLoad(set.weight, for: lift.equipment), let reps = set.reps, reps > 0 else { return nil }
                planned += weight * reps * set.count
            }
        }
        guard planned > 0 else { return nil }
        var best = 0
        for session in history.sessions where session.ended <= date {
            var total = 0
            for row in session.logged {
                guard let equipment = Equipment.allCases.first(where: { $0.displayName == row.equipment }) else { return nil }
                // For weighted bodyweight movements, only the recorded external load counts.
                if equipment == .bodyweight { continue }
                guard let weight = comparableLoad(row.weightTenthsPounds, for: equipment), let reps = row.reps else { return nil }
                total += weight * reps
            }
            best = max(best, total)
        }
        return best > 0 && planned > best ? Self(kind: .sessionVolume, previous: best, target: planned) : nil
    }
}
