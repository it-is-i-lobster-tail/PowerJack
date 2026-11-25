import Foundation

struct StudyTitle: Equatable {
    let full: String
    let caption: String
}

extension StudyHistory {
    /// One name for the query, shared by the gallery, draft preview, detail and full-screen chart.
    func chartTitle(for id: TrainingStudy) -> StudyTitle? {
        let exerciseNames = options.exerciseKeys.map(exerciseName(for:))
        let muscles = options.muscles.map(\.rawValue)
        let parameters = id.parameters.compactMap { key, _ -> (StudyParameter, Int)? in
            guard let value = options.parameters[key],
                originalPeriod || (key != .weeks && key != .comparisonDays)
            else { return nil }
            return (key, value)
        }
        let dates: (full: String, short: String)?
        switch options.period {
        case .original: dates = nil
        case .all: dates = ("All history", "All history")
        case .year(let year): dates = (String(year), String(year))
        case .month(let year, _):
            if let date = selectedRange?.start {
                let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
                dates = (date.formatted(style.month(.wide).year()), date.formatted(style.month(.abbreviated).year()))
            } else { dates = (String(year), String(year)) }
        }
        guard dates != nil || !exerciseNames.isEmpty || !muscles.isEmpty || options.secondExercise != nil
            || !parameters.isEmpty else { return nil }

        let metric = id.titleMetric(period: options.period)
        var subjects: [String] = []
        var shortSubjects: [String] = []
        if id == .relationship {
            let x = exerciseNames.first ?? "Back squat"
            let y = relationshipVerticalKey(for: options.horizontalLift).map(exerciseName(for:)) ?? "Reverse lunge"
            subjects = [x + " and " + y]
            shortSubjects = [x, y]
        } else {
            if !exerciseNames.isEmpty {
                subjects.append(exerciseNames.formatted(.list(type: .and)))
                shortSubjects.append(shortList(exerciseNames))
            }
            if !muscles.isEmpty {
                subjects.append(muscles.formatted(.list(type: .and)))
                shortSubjects.append(shortList(muscles))
            }
            if subjects.isEmpty && !metric.subject.isEmpty {
                subjects = [metric.subject]
                shortSubjects = [metric.subject]
            }
        }

        let focus = subjects.joined(separator: " · ")
        var headline = metric.full
        if !focus.isEmpty { headline += " for " + focus }
        if !parameters.isEmpty {
            headline += " · " + parameters.map { titleParameter($0.0, value: $0.1, study: id) }.joined(separator: ", ")
        }
        if let dates {
            headline += (id == .recency && options.period != .all ? " · through " : " · ") + dates.full
        } else if id == .yearlyRecords || id == .armReps || id == .goal {
            headline += " · 2026"
        }
        if headline.split(whereSeparator: \.isWhitespace).count <= 6 { return StudyTitle(full: headline, caption: headline) }

        // Reserve room for the metric and the actual date before fitting a long exercise or muscle list.
        var compactMetric = metric.short
        if let (key, value) = parameters.first {
            switch key {
            case .reps: compactMetric = "\(value)-rep " + compactMetric
            case .load: compactMetric += " " + loadText(value).replacingOccurrences(of: " ", with: "")
            case .sets: compactMetric = "\(value)-set " + compactMetric
            case .goalReps: compactMetric = "\(value.formatted())-rep goal"
            case .sessions: compactMetric = "\(value)-\(id == .blocks ? "block" : "session") " + compactMetric
            case .gapDays, .comparisonDays: compactMetric = "\(value)-day " + compactMetric
            case .minutes: compactMetric = "\(value)-minute " + compactMetric
            case .lookback: compactMetric = "\(value)-session " + compactMetric
            case .weeks: compactMetric = "\(value)-week " + compactMetric
            }
        }
        let shortDate = dates?.short ?? ([.yearlyRecords, .armReps, .goal].contains(id) ? "2026" : "")
        let reserved = (compactMetric + " " + shortDate).split(whereSeparator: \.isWhitespace).count
        let room = max(0, 6 - reserved)
        var shortFocus = shortSubjects.joined(separator: "/")
        if shortFocus.split(whereSeparator: \.isWhitespace).count > room {
            shortFocus = shortSubjects.map(compactExercise).joined(separator: "/")
        }
        if shortFocus.split(whereSeparator: \.isWhitespace).count > room {
            if shortSubjects.count == 2 && room >= 2 {
                shortFocus = shortSubjects.compactMap { $0.split(separator: " ").last }.joined(separator: "/")
            } else {
                shortFocus = shortFocus.split(whereSeparator: \.isWhitespace).suffix(room).joined(separator: " ")
            }
        }
        var caption = compactMetric
        if !shortFocus.isEmpty {
            let focusWords = shortFocus.split(whereSeparator: \.isWhitespace).count
            caption += (reserved + focusWords < 6 ? " for " : ", ") + shortFocus
        }
        if !shortDate.isEmpty { caption += ", " + shortDate }
        return StudyTitle(full: headline, caption: caption.prefix(1).uppercased() + caption.dropFirst())
    }

    private func shortList(_ names: [String]) -> String {
        if names.count == 1 { return names[0] }
        let firstTwo = names.prefix(2).map(compactExercise).joined(separator: "/")
        return names.count == 2 ? firstTwo : firstTwo + "+\(names.count - 2)"
    }

    private func compactExercise(_ name: String) -> String {
        let equipment = ["barbell", "dumbbell", "machine", "cable", "kettlebell", "bodyweight"]
        let words = name.components(separatedBy: " (")[0].split(whereSeparator: \.isWhitespace)
        if words.count > 1, let first = words.first, equipment.contains(first.lowercased()) {
            return words.dropFirst().joined(separator: " ")
        }
        return words.joined(separator: " ")
    }

    private func titleParameter(_ key: StudyParameter, value: Int, study: TrainingStudy) -> String {
        let plural = value == 1 ? "" : "s"
        return switch key {
        case .load: loadText(value)
        case .reps: study == .milestones ? "at least \(value) rep\(plural)" : "\(value) rep\(plural)"
        case .sets: "\(value) working set\(plural)"
        case .sessions: study == .blocks ? "\(value) block\(plural)" : "\(value) session\(plural)"
        case .gapDays: "\(value)-day break"
        case .minutes: "\(value)-minute budget"
        case .goalReps: "\(value.formatted())-rep goal"
        case .lookback: "\(value)-session baseline"
        case .comparisonDays: "\(value)-day periods"
        case .weeks: "\(value) week\(plural)"
        }
    }
}

extension TrainingStudy {
    var genericName: String {
        switch self {
        case .armReps: "Rep totals over time"
        case .relationship: "Strength changes across two lifts"
        default: titleMetric(period: .original).full
        }
    }

    fileprivate func titleMetric(period: StudyPeriod) -> (full: String, short: String, subject: String) {
        switch self {
        case .legWork: ("Weekly set credits", "set credits", "legs")
        case .armReps:
            if case .month = period { ("Daily reps", "daily reps", "arms") }
            else { ("Monthly reps", "monthly reps", "arms") }
        case .gluteSources: ("Set credits by exercise", "set credits", "glutes")
        case .frequency: ("Working sets by weekday", "weekday sets", "legs")
        case .repRanges: ("Working sets by rep range", "rep ranges", "legs")
        case .repChanges: ("Change in direct reps", "rep changes", "arms")
        case .legMax: ("Estimated one-rep max trends", "estimated max", "legs")
        case .records: ("Load records by rep count", "rep records", "back squat")
        case .fixedSquat: ("Opening-set reps at a fixed load", "opening reps", "back squat")
        case .milestones: ("Load milestones by reps", "load milestones", "back squat")
        case .repeatBench: ("Sets reaching their target", "qualifying sets", "bench press")
        case .yearlyRecords:
            if period == .all { ("Lifetime load records", "lifetime records", "four barbell lifts") }
            else { ("Period and lifetime load records", "lifetime comparison", "four barbell lifts") }
        case .skipped: ("Planned and skipped sets", "skipped sets", "legs")
        case .effort: ("Target and reported effort", "effort ratings", "back squat")
        case .lastCurl: ("Reps across two matching sessions", "session comparison", "cable curl")
        case .benchSets: ("Reps across working sets", "set reps", "bench press")
        case .substitutions: ("Planned exercise substitutions", "exercise substitutions", "back squat")
        case .exerciseOrder: ("Opening reps by exercise order", "exercise order", "cable curl")
        case .returnToSquat: ("Performance after a break", "return performance", "back squat")
        case .blocks: ("Strength gains across blocks", "block gains", "back squat")
        case .duration: ("Workout completion times", "workout duration", "back squat")
        case .goal: ("Rep goal progress", "goal progress", "back squat")
        case .recency: ("Days since direct training", "training recency", "legs")
        case .repMix: ("Load by rep range", "rep-range loads", "bench press")
        case .relationship: ("Relationship between strength changes", "strength relationship", "")
        case .typicalBench: ("Strength versus recent range", "recent range", "bench press")
        case .forecast: ("Estimated max forecast errors", "forecast errors", "bench press")
        case .squatSuccess: ("Rep target success by load", "rep success", "back squat")
        case .missingEstimates: ("Gaps in estimated maxes", "estimate gaps", "back squat")
        case .pushups: ("Best set and total reps", "session reps", "push-ups")
        case .tonnage: ("Changes in volume load", "volume change", "back squat")
        case .sessionLedger: ("Sets in the first workout", "first workout", "legs")
        }
    }
}
