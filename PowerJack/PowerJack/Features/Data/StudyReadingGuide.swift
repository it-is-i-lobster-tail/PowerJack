import SwiftUI

struct StudyReadingGuide: View {
    let study: StudyResult

    @State private var isExpanded = false

    var body: some View {
        ControlGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text(study.question ?? study.id.readingCopy.question)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                Text(study.scope)
                    .foregroundStyle(.secondary)
                if study.figure == nil {
                    Text(study.emptyReason)
                } else {
                    if let example = study.readingExample {
                        Text(example)
                    }
                    if study.question == nil { Text(study.id.readingCopy.practice) }
                }
                if study.question == nil {
                    DisclosureGroup("How it’s calculated") {
                        Text(study.readingMethod)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        } label: {
            Text("How to Read")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
        }
        .controlGroupStyle(ReadingGuideStyle(isExpanded: $isExpanded))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .padding(.bottom, 12)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct ReadingGuideStyle: ControlGroupStyle {
    @Binding var isExpanded: Bool

    func makeBody(configuration: Configuration) -> some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            configuration.content
        } label: {
            configuration.label
        }
        .accessibilityIdentifier("data.readingGuide")
    }
}

extension TrainingStudy {
    fileprivate var reading: String {
        switch self {
        case .legWork:
            "A completed working set earns one credit for the primary muscle and half a credit for each assisting muscle. A blank week has no workout log."
        case .armReps:
            "Reps are grouped by date and by the primary muscle of the exercise. Assisting reps are reported separately in the totals."
        case .gluteSources:
            "Compare exercises to see how many sets trained the muscle directly or as an assistant. The credit total gives assisting sets half weight."
        case .frequency:
            "Each date counts completed working sets involving the selected muscles. Zero means a workout was logged with no matching sets. A dash means there is no logged workout."
        case .repRanges:
            "Each completed working set with a recorded positive rep count goes in one rep range."
        case .repChanges:
            "A positive change means you logged more reps in the later period. A negative change means you logged fewer."
        case .legMax:
            "Each workout contributes its best eligible estimate for that lift. The formula is load × 36 ÷ (37 − completed reps − reps in reserve). A set needs a positive load and rep count, at most \(StrengthRules.e1rmMaxRIR) reps in reserve, and at most \(StrengthRules.e1rmMaxReps) completed plus remaining reps. An unrated set uses zero remaining reps."
        case .records:
            "Each rep count has its own record. The best load is the heaviest weight logged for exactly that many reps."
        case .fixedSquat:
            "Compare opening sets at the same actual weight. A higher value means you did more reps at that weight."
        case .milestones:
            "The session best is the heaviest set that reached the rep minimum. The running record can include workouts before the selected dates."
        case .repeatBench:
            "Each session shows how many prescribed working sets met both the rep and load targets. Compare this count across workouts with the same prescription."
        case .yearlyRecords:
            "The lifetime value is the best logged set at the selected rep count. When a period is shown, equal values mean that period matched the lifetime record."
        case .skipped:
            "Read the planned, completed and explicitly skipped sets together. Compare the rep totals to see how much of the prescribed work you logged."
        case .effort:
            "Reps in reserve are the extra reps you felt you could do. The chart uses your last available rating for the exercise that day. A 5 means five or more."
        case .lastCurl:
            "Compare the same set position in two comparable sessions. The change gives the difference in completed reps."
        case .benchSets:
            "Each series follows a session from its first working set to its last. A downward series means reps fell across sets at the same load."
        case .substitutions:
            "Each row names the exercise actually performed in the selected planned slot. Its share is the fraction of completed slots using that exercise."
        case .exerciseOrder:
            "Compare opening-set reps when the lift came first with sessions when it came third or later. The median describes the middle observation in each group."
        case .returnToSquat:
            "The gap is between logged visits for this lift. The baseline is the middle rep count of comparable opening sets before the gap."
        case .blocks:
            "Each week’s middle estimate is compared with the middle estimate from week one of the same block."
        case .duration:
            "Find a duration and read the share of comparable workouts completed within that time. Logged pauses are excluded."
        case .goal:
            "Follow cumulative completed reps through the goal period. The goal marks the rep total you are aiming for."
        case .recency:
            "A larger day count means a longer interval since the muscle’s most recent direct working set at the selected date."
        case .repMix:
            "Compare mean load at the same rep count in both periods. The overall mean can also change when the mix of rep counts changes."
        case .relationship:
            "Each point pairs changes in the two lifts over the same weeks. The fitted average summarizes their association in your history. Individual workouts can vary."
        case .typicalBench:
            "Compare the latest estimate with the middle half of earlier estimates. Values outside that range are above or below what was typical in those sessions."
        case .forecast:
            "Compare each forecast with the estimate subsequently logged. A smaller mean absolute error means the forecasts landed closer on average."
        case .squatSuccess:
            "Read the number of opening sets that reached the rep target alongside the total attempts at that load. Small counts give a less stable percentage."
        case .missingEstimates:
            "Compare logged and eligible sessions for each period. High-rep sets or missing measurements can leave a period without a strength estimate."
        case .pushups:
            "Compare the most reps in one working set with the sum across the session. The sessions shown have the same number of completed sets."
        case .tonnage:
            "Multiply each working set’s external load by its reps, then add the sets. Compare total reps and load to understand the change between sessions."
        case .sessionLedger:
            "This is the first matching logged workout. A dash can mean the set was absent, incomplete, skipped, or missing its rep count."
        }
    }

    fileprivate var readingCopy: (question: String, practice: String) {
        switch self {
        case .legWork:
            (
                "Which muscles got the most work each week?",
                "If a muscle you meant to prioritize keeps getting fewer set credits, look for a place for it in your next workout."
            )
        case .armReps:
            (
                "Where did your direct reps go?",
                "When you plan your next session, check which muscles got direct work and which mostly helped on other lifts."
            )
        case .gluteSources:
            (
                "Which exercises gave this muscle the most work?",
                "When you swap an exercise, look for one that gives the muscle a similar amount of direct work."
            )
        case .frequency:
            (
                "How far apart were the days you trained these muscles?",
                "If your sets bunch up on consecutive days, check whether another workout has room for some of them."
            )
        case .repRanges:
            (
                "What rep ranges do you usually train in?",
                "Find the range you meant to train, then check which exercises actually landed there."
            )
        case .repChanges:
            (
                "Which exercises account for the change in your reps?",
                "Start with the biggest change. Check whether your reps changed on an exercise you kept, or whether you added or dropped that exercise."
            )
        case .legMax:
            (
                "How has your estimated max changed for each lift?",
                "Pick one lift and compare its recent estimates when you review your working weight."
            )
        case .records:
            (
                "What’s the most you’ve lifted for exactly this many reps?",
                "Look up the reps you plan to do and use your best logged set as a reference."
            )
        case .fixedSquat:
            (
                "Are you getting more opening-set reps at the same weight?",
                "Repeat the load when you want a direct comparison with your last opening set."
            )
        case .milestones:
            (
                "When did you last raise your best load for at least this many reps?",
                "Find the last time you matched the record when you’re choosing a benchmark for your next session."
            )
        case .repeatBench:
            (
                "How often did you hit every set you planned?",
                "Check whether you’ve been hitting the full prescription consistently before you change it."
            )
        case .yearlyRecords:
            (
                "How close did you get to your best at this rep count?",
                "Use your best at this rep count as a benchmark for the next time you try it."
            )
        case .skipped:
            (
                "Which planned sets did you finish or skip?",
                "If you regularly skip the same exercise, check where it falls in your workout and how many sets you planned."
            )
        case .effort:
            (
                "Did your set feel as hard as planned?",
                "If you repeatedly finish with more reps left than planned, review the load you’re using."
            )
        case .lastCurl:
            (
                "Which set changed since your last comparable session?",
                "Look at the same set number both times to see where you gained or lost reps."
            )
        case .benchSets:
            (
                "Where do your reps start to fall off?",
                "If your reps keep dropping at the same set, check your rest time before that set."
            )
        case .substitutions:
            (
                "What did you actually do in this exercise slot?",
                "If you keep choosing the same substitute, consider putting it in the plan."
            )
        case .exerciseOrder:
            (
                "Do you get different opening-set reps when you do this lift first?",
                "If the difference matters to you, try the lift earlier and track what happens at the same weight."
            )
        case .returnToSquat:
            (
                "How do your reps after the break compare with before?",
                "Use your usual opening set from before the gap as a reference for your next few visits."
            )
        case .blocks:
            (
                "How did your progress compare at the same week in each block?",
                "Compare weeks you reached in both blocks when you decide which block to revisit."
            )
        case .duration:
            (
                "How often did this workout fit the time you have?",
                "Check your usual time budget before you schedule this routine on a busy day."
            )
        case .goal:
            (
                "How many reps do you have left to reach your goal?",
                "Divide any remaining reps across the workouts you still plan to do."
            )
        case .recency:
            (
                "How long has it been since you trained each muscle directly?",
                "Check the longest gap against your plan when you choose what to train next."
            )
        case .repMix:
            (
                "Did you lift more weight for the same number of reps?",
                "Compare sets at the rep count you plan to use before drawing conclusions from your overall average."
            )
        case .relationship:
            (
                "When one lift improved, what happened to the other?",
                "If you track the lifts together, check how often they actually moved in the same direction."
            )
        case .typicalBench:
            (
                "Where does your latest estimate sit compared with your usual range?",
                "If this session stands out, see whether your next comparable session lands in the same range."
            )
        case .forecast:
            (
                "Which forecast came closer to what you actually logged?",
                "When you want a starting estimate for the next session, check which method missed by less across your logged workouts."
            )
        case .squatSuccess:
            (
                "How often did you get the reps you planned at this weight?",
                "When you choose an opening weight, check how many attempts sit behind its success rate."
            )
        case .missingEstimates:
            (
                "Why do some weeks have no strength estimate?",
                "Look at a week with logged work to see whether your sets were too high in reps or whether the set details need a closer look."
            )
        case .pushups:
            (
                "Are you gaining reps in your best set, across the whole workout, or both?",
                "Track the best set if you’re aiming for a single-set record, or the total if you’re building reps across sets."
            )
        case .tonnage:
            (
                "How did the work you lifted change between these sessions?",
                "Look at your reps and weights together to see what went into the change in your total."
            )
        case .sessionLedger:
            (
                "What did you log, set by set, in this workout?",
                "Pick the exercise and set number you want to repeat, then look up the weight and reps you used."
            )
        }
    }
}

extension StudyResult {
    fileprivate var readingMethod: String {
        if id == .relationship {
            if case .traces(let series, _) = figure, series.contains(where: { $0.style == .fit }) {
                return "Each point compares changes in the two lifts over the same weeks. The fitted line summarizes how they moved together in your history."
            }
            return "Each observation pairs changes in the two lifts over the same weeks. A fit needs at least eight non-overlapping pairs and variation in the first lift."
        }
        if id == .squatSuccess, case .bars = figure {
            return "Divide the opening sets that met the prescribed reps by all logged opening attempts at the same actual load."
        }
        return id.reading
    }

    var readingExample: String? {
        if question != nil {
            guard let table = detail ?? plottedValues, let row = table.rows.first else { return nil }
            return zip(table.columns, row).map { "\($0): \($1)" }.joined(separator: " · ")
        }
        guard let figure = readingFigure ?? figure else { return nil }
        switch figure {
        case .bars(let bars):
            guard let bar = exampleBar(in: bars) else { return nil }
            if id == .tonnage { return volumeExample(bars) }
            let axis = horizontalCategories ? xLabel : yLabel
            let measure = axis.components(separatedBy: " (")[0].lowercased()
            let related = bars.filter { $0.label == bar.label && !$0.group.isEmpty }
            if id == .armReps, !related.isEmpty {
                let values = related.map { "\($0.value.studyNumber) direct reps for \($0.group)" }
                return "For \(bar.label), you logged \(values.formatted(.list(type: .and)))."
            }
            if id == .records {
                return "Your heaviest set of \(bar.label) reps was \(measurement(bar.value, axis: axis))."
            }
            if id == .recency {
                let muscles = bars.filter { $0.value == bar.value }.map(\.label).formatted(.list(type: .and))
                let interval = bar.value == 1 ? "1 day" : "\(bar.value.studyNumber) days"
                return "Your last direct work for \(muscles) was \(interval) before the date shown."
            }
            if related.count > 1 {
                let values = related.map { "\($0.group) at \(measurement($0.value, axis: axis))" }
                    .formatted(.list(type: .and))
                return "For \(bar.label), \(measure) breaks down as \(values)."
            }
            return "For \(bar.label), \(bar.group.isEmpty ? measure : bar.group) was \(measurement(bar.value, axis: axis))."
        case .traces(let series, let dates):
            return traceExample(series, dates: dates)
        case .liftPanels(let series):
            guard let lift = series.max(by: { ($0.points.last?.x ?? 0) < ($1.points.last?.x ?? 0) }),
                let point = lift.points.last else { return nil }
            let current = "Your estimated max for \(lift.name) was \(measurement(point.y)) on \(dateLabel(point.x))."
            guard let prior = lift.points.dropLast().last else { return current }
            return "\(current) It was \(measurement(prior.y)) on \(dateLabel(prior.x))."
        case .comparison(let points, _):
            if id == .exerciseOrder {
                let medians = points.filter { $0.series == "Median" }
                let values = medians.map { median in
                    let count = points.count { $0.category == median.category && $0.series == "Observed" }
                    return "\(median.category): \(median.value.studyNumber) median reps across \(count) sessions"
                }
                return values.isEmpty ? nil : "\(values.formatted(.list(type: .and)))."
            }
            let categories = points.map(\.category).studyUnique
            guard let lift = categories.first(where: { category in points.count { $0.category == category } > 1 })
                ?? categories.first else { return nil }
            let values = points.filter { $0.category == lift }.map {
                "\($0.series): \(measurement($0.value, axis: xLabel))"
            }
            return "For \(lift), \(values.formatted(.list(type: .and)))."
        case .attempts(let counts):
            guard let count = counts.max(by: { $0.attempts < $1.attempts }), count.attempts > 0 else { return nil }
            let rate = 100 * Double(count.made) / Double(count.attempts)
            return "\(count.made) of \(count.attempts) opening sets at \(count.label) reached the target (\(rate.studyNumber)%)."
        case .matrix(let columns, let rows, let values):
            if id == .legWork {
                return weeklyCreditExample(columns: columns, rows: rows, values: values)
            }
            for (row, cells) in zip(rows, values).reversed() {
                if let (column, value) = zip(columns, cells).first(where: { ($0.1 ?? 0) > 0 }),
                    let value {
                    return "The cell for \(row) and \(column) shows \(value.studyNumber) working sets."
                }
            }
            for (row, cells) in zip(rows, values).reversed() {
                if let (column, _) = zip(columns, cells).first(where: { $0.1 == 0 }) {
                    return "The cell for \(row) and \(column) shows zero matching sets."
                }
            }
            return nil
        case .table(let table):
            return tableExample(table)
        }
    }

    private func weeklyCreditExample(columns: [String], rows: [String], values: [[Double?]]) -> String? {
        let transposed = yLabel == "Week"
        let weeks = transposed ? rows : columns
        let muscles = transposed ? columns : rows
        for week in weeks.indices.reversed() {
            let credits = muscles.indices.compactMap { muscle -> (name: String, value: Double)? in
                let value = transposed ? values[week][muscle] : values[muscle][week]
                return value.map { (muscles[muscle], $0) }
            }
            guard let most = credits.max(by: { $0.value < $1.value }) else { continue }
            if most.value == 0 { return "The week of \(weeks[week]) had no matching set credits." }
            let leaders = credits.filter { $0.value == most.value }.map(\.name).formatted(.list(type: .and))
            return "The most recent week with a log starts \(weeks[week]). \(leaders) led with \(most.value.studyNumber) set credits\(credits.count { $0.value == most.value } > 1 ? " each" : "")."
        }
        return nil
    }

    private func exampleBar(in bars: [StudyBar]) -> StudyBar? {
        switch id {
        case .repChanges:
            bars.max { abs($0.value) < abs($1.value) }
        case .recency:
            bars.max { $0.value < $1.value }
        case .armReps, .tonnage, .missingEstimates:
            bars.last(where: { $0.value != 0 }) ?? bars.last
        default:
            bars.first(where: { $0.value != 0 }) ?? bars.first
        }
    }

    private func traceExample(_ series: [StudySeries], dates: Bool) -> String? {
        guard let track = series.first, let point = track.points.last else { return nil }
        let position = dates ? dateLabel(point.x) : "\(xLabel.lowercased()) \(point.x.studyNumber)"
        switch id {
        case .forecast:
            let predictions = series.dropFirst().compactMap { prediction -> String? in
                guard let value = prediction.points.first(where: { $0.x == point.x })?.y else { return nil }
                return "\(prediction.name) predicted \(measurement(value)), off by \(measurement(abs(value - point.y)))."
            }
            return (["On \(position), your estimate was \(measurement(point.y))."] + predictions).joined(separator: " ")
        case .typicalBench:
            guard series.count >= 4, let latest = series[1].points.last, let lower = series[2].points.last,
                let upper = series[3].points.last else { return nil }
            let comparison = latest.y < lower.y ? "below" : latest.y > upper.y ? "above" : "within"
            return "On \(dateLabel(latest.x)), your estimate of \(measurement(latest.y)) was \(comparison) the middle half of your prior \(track.points.count) estimates (\(lower.y.studyNumber)–\(measurement(upper.y)))."
        case .goal:
            guard let goal = series.dropFirst().first?.points.first else { return nil }
            let difference = goal.y - point.y
            if difference < 0 {
                return "By \(position), you’d logged \(point.y.studyNumber) reps, \(abs(difference).studyNumber) past your \(goal.y.studyNumber)-rep goal."
            }
            let progress = "By \(position), you’d logged \(point.y.studyNumber) of \(goal.y.studyNumber) reps"
            return difference == 0 ? "\(progress) and reached your goal." : "\(progress), with \(difference.studyNumber) to go."
        case .relationship:
            let period = detail?.rows.last?.first.map { "For the comparison starting \($0)" } ?? "In one paired period"
            let sameDirection = track.points.count { $0.x * $0.y > 0 }
            let paired = "\(period), \(changeDescription(point.x, axis: xLabel)) and \(changeDescription(point.y, axis: yLabel))."
            return "\(paired) The lifts moved in the same direction in \(sameDirection) of \(track.points.count) comparisons."
        case .duration:
            return summary.isEmpty
                ? "At \(point.x.studyNumber) minutes, \(point.y.studyNumber)% of matching workouts had finished."
                : summary
        case .effort:
            let ratings = series.dropFirst().first?.points ?? []
            if let rated = ratings.last, let target = track.points.last(where: { $0.x == rated.x }) {
                return "On \(dateLabel(rated.x)), you reported \(rated.y >= 5 ? "5+" : rated.y.studyNumber) reps left against a target of \(target.y.studyNumber)."
            }
            return "On \(position), your target was \(point.y.studyNumber) reps left. There’s no reported rating for that example."
        case .milestones, .pushups, .returnToSquat:
            let related = series.dropFirst().compactMap { series in
                series.points.first(where: { $0.x == point.x }).map { "\(series.name): \(measurement($0.y))" }
            }
            let values = (["\(track.name): \(measurement(point.y))"] + related).formatted(.list(type: .and))
            return "At \(position), \(values)."
        case .fixedSquat, .repeatBench, .benchSets:
            guard let prior = track.points.dropLast().last else { break }
            let priorPosition = dates ? dateLabel(prior.x) : "\(xLabel.lowercased()) \(prior.x.studyNumber)"
            return "At \(priorPosition), you logged \(prior.y.studyNumber) \(yLabel.lowercased()). At \(position), you logged \(point.y.studyNumber)."
        default:
            break
        }
        return "\(track.name) shows \(measurement(point.y)) at \(position)."
    }

    private func tableExample(_ table: StudyTable) -> String? {
        if id == .tonnage, let example = volumeExample(alternateBars) { return example }
        if id == .exerciseOrder, table.columns == ["Position", "Sessions", "Median reps", "Observed reps"] {
            let medians = table.rows.filter { $0.count == 4 }.map { "\($0[2]) median reps when you trained \($0[0].lowercased()) across \($0[1]) sessions" }
            return medians.isEmpty ? nil : "You logged \(medians.formatted(.list(type: .and)))."
        }
        if id == .tonnage, table.rows.count == 2, let unit = table.columns.last {
            let first = table.rows[0]
            let second = table.rows[1]
            if first.count == 5, second.count == 5 {
                return "On \(first[0]), you logged \(first[4]) \(unit) across \(first[2]) reps. On \(second[0]), you logged \(second[4]) \(unit) across \(second[2]) reps."
            }
        }
        let rows = id == .missingEstimates ? table.rows.reversed().filter { $0.last != "0" } : table.rows
        guard let row = rows.first(where: { !$0.dropFirst().allSatisfy { $0 == "—" } }),
            let name = row.first else { return nil }
        switch id {
        case .gluteSources where row.count == 4:
            return "Your \(name) sets earned \(row[3]) credits from \(row[1]) primary and \(row[2]) assisting sets."
        case .records where row.count == 5:
            return "Your heaviest set of \(name) reps was \(row[1]). You first logged it on \(row[2]) and matched that weight across \(row[3]) sessions."
        case .missingEstimates where row.count == 5:
            return "The week of \(name) had \(row[4]) logged sessions. \(row[1]) supported an estimate, \(row[2]) had only high-rep sets, and \(row[3]) fell under Other / missing."
        case .substitutions where row.count == 3:
            return "You performed \(name) in \(row[1]) slots, \(row[2]) of the completed slots shown."
        case .skipped where row.count == 6:
            return "You finished \(row[2]) of \(row[1]) planned sets for \(name) and marked \(row[3]) skipped. You logged \(row[5]) of \(row[4]) target reps."
        case .relationship where row.count == 3 && table.columns.count == 3:
            return "For the comparison starting \(name), the table shows \(row[1]) for \(table.columns[1]) and \(row[2]) for \(table.columns[2])."
        case .yearlyRecords where row.count == 4 && table.columns.count == 4:
            guard row[1] != "—" else {
                return "Your lifetime best for \(name) is \(row[2]). This period has no matching set."
            }
            return "For \(name), you lifted \(row[1]) in \(table.columns[1]) compared with your lifetime best of \(row[2])."
        default:
            break
        }
        if id == .sessionLedger, let (set, value) = zip(table.columns.dropFirst(), row.dropFirst()).first(where: { $0.1 != "—" }) {
            return "For \(name), \(set.lowercased()) shows \(value)."
        }
        if id == .lastCurl, row.count >= 3, table.columns.count >= 3 {
            let observations = (1...2).compactMap { index -> String? in
                guard row[index] != "—" else { return nil }
                return "\(row[index]) reps on \(table.columns[index])"
            }
            if !observations.isEmpty {
                return "For set \(name), you logged \(observations.formatted(.list(type: .and)))."
            }
        }
        let fields = zip(table.columns.dropFirst(), row.dropFirst()).filter { $0.1 != "—" }.prefix(3)
        guard !fields.isEmpty else { return nil }
        return "For \(name), the table shows \(fields.map { "\($0.0.lowercased()): \($0.1)" }.formatted(.list(type: .and)))."
    }

    private func volumeExample(_ bars: [StudyBar]) -> String? {
        guard bars.count == 2 else { return nil }
        let first = bars[0]
        let second = bars[1]
        let change = second.value - first.value
        let comparison = change == 0 ? "the same total" : "\(measurement(abs(change))) \(change > 0 ? "more" : "less")"
        return "On \(first.label), your sets added up to \(measurement(first.value)). On \(second.label), they added up to \(measurement(second.value)), \(comparison)."
    }

    private func dateLabel(_ timestamp: Double) -> String {
        Date(timeIntervalSince1970: timestamp).formatted(date: .abbreviated, time: .omitted)
    }

    private func measurement(_ value: Double, axis: String? = nil) -> String {
        let label = axis ?? yLabel
        guard label.hasSuffix(")"), let unitStart = label.lastIndex(of: "(") else {
            return value.studyNumber
        }
        let unit = label[label.index(after: unitStart)..<label.index(before: label.endIndex)]
        return unit == "%" ? "\(value.studyNumber)%" : "\(value.studyNumber) \(unit)"
    }

    private func changeDescription(_ value: Double, axis: String) -> String {
        let exercise = axis.components(separatedBy: " change")[0]
        if value == 0 { return "your \(exercise) estimate stayed the same" }
        return "your \(exercise) estimate \(value > 0 ? "rose" : "fell") by \(measurement(abs(value), axis: axis))"
    }
}
