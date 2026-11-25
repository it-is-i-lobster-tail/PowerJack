import SwiftUI

struct StudyReadingGuide: View {
    let study: StudyResult

    @State private var isExpanded = false

    var body: some View {
        ControlGroup {
            VStack(alignment: .leading, spacing: 7) {
                Text(study.id.reading).font(.subheadline)
                if let example = study.readingExample {
                    Text("For example, \(example)").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text(study.id.emptyExample).font(.subheadline).foregroundStyle(.secondary)
                }
            }
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
            "Each value adds up working-set credits for one muscle and week. A primary muscle earns one credit and an assisting muscle earns half a credit."
        case .armReps:
            "Reps are grouped by date and by the primary muscle of the exercise. Assisting reps are reported separately in the totals."
        case .gluteSources:
            "Compare exercises to see how many sets trained the muscle directly or as an assistant. The credit total gives assisting sets half weight."
        case .frequency:
            "Each date counts completed working sets involving the selected muscles. Zero means a workout was logged with no matching sets. A dash means there is no logged workout."
        case .repRanges:
            "Compare each exercise’s counts to see which rep ranges you used. Each completed set belongs to one range."
        case .repChanges:
            "A positive change means you logged more reps in the later period. A negative change means you logged fewer."
        case .legMax:
            "Read each exercise separately. A point is the best eligible one-rep-max estimate from that workout, calculated from recorded load, reps and available effort ratings."
        case .records:
            "Each rep count has its own record. The best load is the heaviest weight logged for exactly that many reps."
        case .fixedSquat:
            "Compare opening sets at the same actual weight. A higher value means you did more reps at that weight."
        case .milestones:
            "A session qualifies when you reach the rep minimum. Its best load can fall between sessions while the running record only rises."
        case .repeatBench:
            "Each session shows how many prescribed working sets met both the rep and load targets. Compare this count across workouts with the same prescription."
        case .yearlyRecords:
            "The lifetime value is the best logged set at the selected rep count. When a period is shown, equal values mean that period matched the lifetime record."
        case .skipped:
            "Read the planned, completed and explicitly skipped sets together. Compare the rep totals to see how much of the prescribed work you logged."
        case .effort:
            "Compare the target with the lifter’s recorded reps in reserve. A higher reported value means the lifter felt they could do more reps."
        case .lastCurl:
            "Compare the same set position in two comparable sessions. The change gives the difference in completed reps."
        case .benchSets:
            "Each series follows a session from its first working set to its last. A downward series means reps fell across sets at the same load."
        case .substitutions:
            "Each row names the exercise actually performed in the selected planned slot. Its share is the fraction of completed slots using that exercise."
        case .exerciseOrder:
            "Compare opening-set reps when the lift came first with sessions when it came third or later. The median describes the middle observation in each group."
        case .returnToSquat:
            "Return visits are counted from the first matching session after a logging break. Compare their reps with the median of comparable sets before the break."
        case .blocks:
            "Each block starts at its own week-one baseline. A positive percentage means its estimated max exceeded that starting value."
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
            "Read each exercise across its working sets in the selected workout. Loaded sets show weight and reps. A dash marks an unlogged position."
        }
    }

    fileprivate var emptyExample: String {
        switch self {
        case .relationship: "For example, a point at +5 lb and +2 lb represents paired increases in the two lifts."
        case .duration:
            "For example, 75% at 45 minutes would mean three quarters of the matching workouts finished within 45 minutes."
        case .effort: "For example, two reps in reserve means the lifter estimated two more reps were possible."
        case .legWork, .gluteSources: "For example, two primary sets and two assisting sets would contribute three credits."
        case .repChanges, .lastCurl: "For example, a change of +3 would mean three more completed reps."
        case .blocks: "For example, +5% would mean an estimate five percent above the block’s starting value."
        case .recency: "For example, seven days would place the latest matching workout one week earlier."
        case .armReps: "For example, three direct sets of ten reps would add 30 reps to that date bucket."
        case .frequency: "For example, a value of four on Tuesday would mean four matching working sets that day."
        case .repRanges: "For example, two sets of eight would add two to the 7–11 rep range."
        case .legMax: "For example, estimates of 160 and 165 lb in one session would put the session point at 165 lb."
        case .records: "For example, lifting 100 lb for exactly eight reps would compete with other eight-rep sets."
        case .fixedSquat: "For example, going from five to six reps at the selected load would raise the next point by one."
        case .milestones: "For example, a qualifying 105 lb set after a 100 lb record would move the record up by 5 lb."
        case .repeatBench:
            "For example, meeting both targets on two of three prescribed sets would give the session a value of two."
        case .yearlyRecords:
            "For example, 95 lb for the period and 100 lb for lifetime would place the period best 5 lb below the record."
        case .skipped:
            "For example, a workout with four planned sets, three completed and one explicitly skipped would show all three counts."
        case .benchSets: "For example, eight reps followed by seven at the same load would show a one-rep drop."
        case .substitutions: "For example, performing a substitute in one of four completed slots would give it a 25% share."
        case .exerciseOrder:
            "For example, medians of ten reps first and eight later would show a two-rep difference between groups."
        case .returnToSquat:
            "For example, returning with four reps after a six-rep baseline would put the return two reps below baseline."
        case .goal: "For example, 250 completed reps toward a 1,000-rep goal would leave 750 reps."
        case .repMix:
            "For example, compare the mean load for sets of eight in both periods before comparing their overall averages."
        case .typicalBench: "For example, an estimate of 120 lb would sit above a prior middle range of 105–115 lb."
        case .forecast:
            "For example, forecasting 150 lb before a recorded 145 lb estimate would produce a 5 lb absolute error."
        case .squatSuccess: "For example, reaching the target on three of four opening sets would give a 75% success rate."
        case .missingEstimates:
            "For example, a week with two logged sessions and one eligible estimate would support one point."
        case .pushups: "For example, sets of ten, nine and eight reps would give a best set of ten and a total of 27."
        case .tonnage: "For example, two sets of five at 100 lb would total 1,000 lb·reps."
        case .sessionLedger: "For example, 50 lb × 8 would mean eight completed reps with 50 lb for that set."
        }
    }
}

extension StudyResult {
    fileprivate var readingExample: String? {
        guard let figure else { return nil }
        switch figure {
        case .bars(let bars):
            guard let bar = bars.first(where: { $0.value != 0 }) ?? bars.first else { return nil }
            let series = bar.group.isEmpty ? "" : " for \(bar.group)"
            let measure = horizontalCategories ? xLabel : yLabel
            return "\(bar.label)\(series) shows \(bar.value.studyNumber) \(measure.lowercased())."
        case .traces(let series, let dates):
            guard let track = series.first, let point = track.points.first else { return nil }
            if id == .relationship {
                return
                    "one paired period had a \(point.x.studyNumber) \(xLabel.lowercased()) and a \(point.y.studyNumber) \(yLabel.lowercased())."
            }
            let position =
                dates
                ? Date(timeIntervalSince1970: point.x).formatted(.dateTime.month(.abbreviated).day())
                : "\(xLabel.lowercased()) \(point.x.studyNumber)"
            return "\(track.name) shows \(point.y.studyNumber) at \(position)."
        case .liftPanels(let series):
            guard let line = series.first, let point = line.points.first else { return nil }
            return
                "\(line.name) had an estimated maximum of \(point.y.studyNumber) on \(Date(timeIntervalSince1970: point.x).formatted(date: .abbreviated, time: .omitted))."
        case .comparison(let points, _):
            guard let point = points.first else { return nil }
            return "\(point.category) shows \(point.value.studyNumber) for \(point.series.lowercased())."
        case .attempts(let counts):
            guard let count = counts.first else { return nil }
            return "\(count.made) of \(count.attempts) opening sets at \(count.label) reached the target."
        case .matrix(let columns, let rows, let values):
            for r in rows.indices {
                if let c = values[r].firstIndex(where: { ($0 ?? 0) > 0 }), let value = values[r][c] {
                    return "the entry for \(rows[r]) and \(columns[c]) is \(value.studyNumber)."
                }
            }
            return "a recorded zero means there were no matching sets in that cell."
        case .table(let table):
            guard let row = table.rows.first, let name = row.first, row.count > 1 else { return nil }
            if id == .lastCurl, row.count >= 3, table.columns.count >= 3 {
                if row[1] == row[2], let reps = Int(row[1]) {
                    return "set \(name) had \(reps) \(reps == 1 ? "rep" : "reps") on both \(table.columns[1]) and \(table.columns[2])."
                }
                let observations = (1...2).compactMap { index -> String? in
                    guard let reps = Int(row[index]) else { return nil }
                    return "\(reps) \(reps == 1 ? "rep" : "reps") on \(table.columns[index])"
                }
                if observations.count == 2 {
                    return "set \(name) went from \(observations[0]) to \(observations[1])."
                }
                if let only = observations.first {
                    return "set \(name) had \(only). The other session has no matching rep count."
                }
                return nil
            }
            let fields = zip(table.columns.dropFirst(), row.dropFirst()).filter { $0.1 != "—" }.prefix(2)
            guard !fields.isEmpty else { return nil }
            return "the row for \(name) shows \(fields.map { "\($0.0.lowercased()) \($0.1)" }.joined(separator: " and "))."
        }
    }
}
