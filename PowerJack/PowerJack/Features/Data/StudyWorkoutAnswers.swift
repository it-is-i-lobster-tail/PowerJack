import Foundation

private enum WorkoutQuestion {
    case attendance, weekday, weekend, gaps, adjacent, frequency, streak, adherence, stopped, length, hours, start,
        template, programWeeks, block, deload, afterBreak, latest, exerciseMinutes, rest, muscleDates, programStrength

    init?(_ text: String) {
        func has(_ words: String...) -> Bool { words.contains(where: text.contains) }
        let workout = has("workout", "session", "training", "gym", "train", "lift")
        let count = has("how many", "how often", "frequency", "how frequently", "count", "attendance", "consisten")
        if has("rest time", "rest longer between sets", "rest between sets") { self = .rest }
        else if has("exercise takes", "exercises take") && has("time") { self = .exerciseMinutes }
        else if has("back-to-back", "back to back") { self = .adjacent }
        else if has("days between", "longer break between") { self = .gaps }
        else if has("after a week off", "after a week away") { self = .afterBreak }
        else if has("last upper body workout", "last lower body workout", "last workout") && has("log", "everything") { self = .latest }
        else if has("streak") { self = .streak }
        else if has("deload") { self = .deload }
        else if has("switched programs", "switching programs") { self = .programStrength }
        else if (has("current program", "this program") && has("volume", "first and last week"))
            || (has("compare", "comparison") && has("programs")) { self = .programWeeks }
        else if has("block") && has("compare", "last one") { self = .block }
        else if has("planned workouts", "scheduled workouts", "planned sessions", "scheduled sessions", "training days did i miss", "skip leg day") { self = .adherence }
        else if has("cut short", "stopped workouts") { self = .stopped }
        else if has("workout template") { self = .template }
        else if has("weekend") { self = .weekend }
        else if has("weekday", "which day do i lift the most") && !has("strongest", "strength") { self = .weekday }
        else if has("weekly training hours", "hours per week") { self = .hours }
        else if has("workout start", "sessions start") { self = .start }
        else if has("workout length", "workouts take", "sessions getting shorter", "session duration") || (workout && has("how long", "duration", "typical length") && !has("since", "break", "rest")) { self = .length }
        else if has("last time i hit", "since i trained", "muscles did i train", "muscles haven't i trained", "muscles have i neglected") { self = .muscleDates }
        else if has("days a week do i lift", "training consistency", "how often do i train", "how often did i actually train") { self = .frequency }
        else if has("workout", "session") && count && has("finish", "complete", "log", "attend") { self = .attendance }
        else if workout && count && !has("swap", "switch", "change", "pound", "heavy", "set", "rep", "skip", "strong", "volume") { self = .frequency }
        else { return nil }
    }
}

extension LoggedStudyQuestion {
    func workoutAnswer(_ h: StudyHistory) -> StudyResult? {
        guard let kind = WorkoutQuestion(text) else { return nil }
        let selected = sessions(h)
        let slots = Dictionary(grouping: selected, by: \.workout)
        let hasFocus = !muscles.isEmpty || !liftNames.isEmpty
        let scoped = h.workouts.filter { w in
            guard let date = w.date, includes(date) else { return false }
            return !hasFocus || slots[w.key]?.contains(where: { !$0.done.isEmpty }) == true
        }
        let visits = scoped.filter { $0.status == .complete || ($0.began != nil && $0.status != .skipped) }
        let days = Set(visits.compactMap { $0.date.map(h.calendar.startOfDay(for:)) }).sorted()
        func table(_ id: TrainingStudy, _ title: String, _ summary: String, _ columns: [String], _ rows: [[String]], insufficient: Bool? = nil) -> StudyResult {
            answer(id, title, summary, columns: columns, rows: rows, insufficient: insufficient)
        }
        func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0,+) / Double(values.count) }
        func counts(_ group: [StudyWorkout]) -> (sets: Int, reps: Int, volume: Double) {
            let sets = group.flatMap { slots[$0.key] ?? [] }.flatMap(\.done)
            let volume = sets.compactMap { set -> Double? in
                guard let load = set.load, let reps = set.reps, reps > 0 else { return nil }
                return h.weight(load) * Double(reps)
            }.reduce(0,+)
            return (sets.count, sets.compactMap(\.reps).reduce(0,+), volume)
        }
        func weekly(_ group: [StudyWorkout]) -> [[StudyWorkout]] {
            let buckets = Dictionary(grouping: group) { h.week($0.date!) }
            guard let first = group.first?.date, let last = group.last?.date else { return [] }
            let start = h.week(interval?.start ?? first)
            let end = h.week(min(h.today, interval?.end.addingTimeInterval(-1) ?? last))
            guard end >= start else { return [] }
            return (0...max(0, h.days(start, end) / 7)).map { buckets[h.offset(start, days: 7 * $0)] ?? [] }
        }
        func currentProgram() -> String? {
            let active = h.workouts.filter(\.activeProgram)
            return (active.last(where: { $0.date != nil }) ?? active.first)?.program
        }
        switch kind {
        case .attendance:
            let finished = text.contains("finish") || text.contains("complete")
            let list = finished ? visits.filter(\.status.isCompletedWorkout) : visits
            return table(.frequency, finished ? "Completed workouts" : "Logged workouts",
                "\(list.count) workouts across \(Set(list.compactMap { $0.date.map(h.calendar.startOfDay(for:)) }).count) calendar days.",
                ["Date", "Template", "Status"], list.reversed().map { [h.day($0.date!), $0.template, $0.status.rawValue.capitalized] })
        case .frequency:
            if !muscles.isEmpty && liftNames.isEmpty {
                let eligible = h.sessions.filter { includes($0.date) && !$0.done.isEmpty }
                let direct = Set(eligible.filter { $0.primary.map(muscles.contains) == true }
                    .map { h.calendar.startOfDay(for: $0.date) })
                let assisting = Set(eligible.filter { $0.assisting?.contains(where: muscles.contains) == true }
                    .map { h.calendar.startOfDay(for: $0.date) })
                let any = direct.union(assisting)
                let unknown = eligible.contains { $0.assisting == nil }
                let subject = muscles.map { $0.rawValue.capitalized }.sorted().joined(separator: ", ")
                let weeks = Set(eligible.map { h.week($0.date) }).sorted()
                let rows = weeks.map { week in
                    let end = h.offset(week, days: 7)
                    func count(_ days: Set<Date>) -> Int { days.filter { week <= $0 && $0 < end }.count }
                    return [h.day(week), String(count(direct)), String(count(assisting)), String(count(any))]
                }
                let periods = weekly(h.workouts.filter { $0.date.map(includes) == true && $0.status == .complete })
                let rate = periods.isEmpty ? "" : " Average: " + (Double(any.count) / Double(periods.count)).studyNumber + " days per calendar week."
                let note = "\(any.count) recorded training days: \(direct.count) with direct work and \(assisting.count) with known assisting work. Days with both roles count once." + rate
                return table(.frequency, "Training frequency · " + subject,
                             note + (unknown ? " Some archived exercises have no assisting-muscle tags." : ""),
                             ["Week of", "Direct days", "Assisting days", "Any matching work"], rows)
            }
            let weeks = weekly(visits)
            let firstWeek = (interval?.start ?? days.first).map(h.week)
            let rows = weeks.enumerated().map { index, group in
                [firstWeek.map { h.day(h.offset($0, days: index * 7)) } ?? "—",
                 String(Set(group.compactMap { $0.date.map(h.calendar.startOfDay(for:)) }).count), String(group.count)]
            }
            let average = weeks.isEmpty ? 0 : Double(days.count) / Double(weeks.count)
            let subject = muscles.map(\.rawValue).sorted().joined(separator: ", ")
            return table(.frequency, subject.isEmpty ? "Workout attendance by week" : "Training days for " + subject,
                "\(visits.count) logged workouts on \(days.count) distinct days. Average \(average.studyNumber) training days per calendar week, including partial boundary weeks.",
                ["Week of", "Days trained", "Workouts"], rows)
        case .weekday, .weekend:
            let weekend = kind == .weekend
            let buckets = Dictionary(grouping: visits) { w in
                weekend ? (h.calendar.isDateInWeekend(w.date!) ? 1 : 0) : h.calendar.component(.weekday, from: w.date!)
            }
            let order = weekend ? [0,1] : (0..<7).map { (h.calendar.firstWeekday - 1 + $0) % 7 + 1 }
            let start = interval?.start ?? days.first
            let end = min(h.today, interval?.end.addingTimeInterval(-1) ?? days.last ?? h.today)
            var opportunities: [Int:Int] = [:]
            if let start {
                for offset in 0...max(0, h.days(start, end)) {
                    let date = h.offset(start, days: offset)
                    let key = weekend ? (h.calendar.isDateInWeekend(date) ? 1 : 0) : h.calendar.component(.weekday, from: date)
                    opportunities[key, default: 0] += 1
                }
            }
            let rows = order.map { key -> [String] in
                let workouts = buckets[key] ?? []
                let label = weekend ? (key == 1 ? "Weekend" : "Weekday") : h.calendar.weekdaySymbols[key-1]
                let distinct = Set(workouts.map { h.calendar.startOfDay(for: $0.date!) }).count
                let rate = opportunities[key].flatMap { $0 > 0 ? (100 * Double(distinct) / Double($0)).studyNumber + "%" : nil }
                return [label, String(workouts.count), rate ?? "—", String(counts(workouts).sets)]
            }
            return table(.frequency, weekend ? "Weekend and weekday lifting" : "Workout attendance by weekday",
                "Training rate is the share of available calendar days with a logged workout. Working sets show the amount lifted.",
                ["Day", "Workouts", "Days trained", "Working sets"], visits.isEmpty ? [] : rows)
        case .gaps, .adjacent:
            if text.contains("help") { return breakPerformance(h, slots: selected) }
            let pairs = zip(days, days.dropFirst()).map { ($0, $1, h.days($0, $1)) }
            let adjacent = kind == .adjacent
            let used = pairs.filter { !adjacent || $0.2 == 1 }
            let average = mean(pairs.map { Double($0.2) })?.studyNumber ?? "—"
            let focus = muscles.map { $0.rawValue.capitalized }.sorted().joined(separator: ", ")
            let heading = adjacent ? "Consecutive training days" : "Days between training sessions"
            return table(.recency, focus.isEmpty ? heading : heading + " · " + focus,
                adjacent ? "\(used.count) pairs of consecutive calendar days." : "Average gap: \(average) calendar days across \(pairs.count) intervals.",
                ["Earlier day", "Next day", "Days apart"], used.reversed().map { [h.day($0.0),h.day($0.1),String($0.2)] }, insufficient: adjacent && !h.sessions.isEmpty ? false : nil)
        case .streak:
            let byWeek = text.contains("week")
            let threshold = text.contains("three") || text.contains("3 times") ? 3 : 1
            let grouped = Dictionary(grouping: days, by: h.week)
            let dates = byWeek ? grouped.filter { $0.value.count >= threshold }.keys.sorted() : days
            var runs: [[Date]] = []
            for date in dates {
                if let last = runs.last?.last, h.days(last, date) == (byWeek ? 7 : 1) { runs[runs.count-1].append(date) }
                else { runs.append([date]) }
            }
            runs.sort { $0.count == $1.count ? $0[0] > $1[0] : $0.count > $1.count }
            let unit = byWeek ? "weeks" : "days"
            return table(.frequency, "Longest training streak", "Longest streak: \(runs.first?.count ?? 0) consecutive \(unit)."
                + (byWeek ? " A week qualifies with at least \(threshold) distinct training days." : ""),
                ["Start", "End", "Consecutive " + unit], runs.map { [h.day($0.first!), h.day($0.last!), String($0.count)] })
        case .adherence:
            if interval != nil, h.workouts.contains(where: { $0.date == nil && $0.status.isOpen }) {
                return table(.skipped, "Workout plan completion", "Pending workouts have no scheduled dates. The planned count for this period is unknown.", [], [])
            }
            var plans = h.workouts.filter { w in
                (interval == nil || w.date.map(includes) == true) && (muscles.isEmpty || !w.primaryMuscles.isDisjoint(with: muscles))
            }
            if text.contains("this program") {
                guard let current = currentProgram() else {
                    return table(.skipped, "Missed days in current program", "There is no active program in this history.", ["Program"], [])
                }
                plans = plans.filter { $0.program == current }
            }
            // Completed-only archives do not establish how many sessions were planned.
            let archiveOnly = Set(plans.map(\.program)).subtracting(h.plansFromLivePrograms)
            if plans.isEmpty || archiveOnly.contains(where: { id in
                plans.filter { $0.program == id }.allSatisfy { $0.status == .complete }
            }) {
                return table(.skipped, "Workout plan completion", "The available records do not establish the original planned-workout count.", [], [])
            }
            let closed = plans.filter { !$0.status.isOpen }, finished = closed.filter { $0.status == .complete }.count
            let skipped = closed.filter { $0.status == .skipped }.count
            let stopped = closed.filter { $0.status == .stopped }.count
            let percent = closed.isEmpty ? "—" : (100 * Double(finished) / Double(closed.count)).studyNumber + "%"
            let plannedPercent = plans.isEmpty ? "—" : (100 * Double(finished) / Double(plans.count)).studyNumber + "%"
            let current = text.contains("this program")
            let heading = current ? "Workout plan completion · " + (plans.first?.template ?? "Current program") : "Workout plan completion"
            let due = current ? " The program records workout order without scheduled calendar dates, so pending workouts have no overdue date." : ""
            return table(.skipped, heading,
                "\(finished) of \(plans.count) planned workouts completed (\(plannedPercent)). Of \(closed.count) closed workouts, \(percent) completed, \(skipped) skipped and \(stopped) stopped. Open workouts are pending." + due,
                ["Status", "Workouts"], plans.isEmpty ? [] : Status.allCases.map { value in [value.rawValue.capitalized, String(plans.filter { $0.status == value }.count)] })
        case .stopped:
            let stopped = scoped.filter { $0.status == .stopped }
            return answer(.skipped, "Workouts stopped early", "\(stopped.count) workouts were recorded as stopped.",
                columns: ["Date","Template","Completed working sets"], rows: stopped.reversed().map { [h.day($0.date!), $0.template, String(counts([$0]).sets)] }, insufficient: scoped.isEmpty)
        case .length, .hours:
            let measured = visits.filter { ($0.seconds ?? 0) > 0 }
            if kind == .hours {
                let groups = weekly(visits)
                let firstWeek = (interval?.start ?? days.first).map(h.week)
                let rows = groups.enumerated().map { index, group in
                    [firstWeek.map { h.day(h.offset($0, days: 7 * index)) } ?? "—",
                     (group.compactMap(\.seconds).reduce(0,+) / 3600).studyNumber,
                     String(group.filter { ($0.seconds ?? 0) > 0 }.count)]
                }
                let avg = groups.isEmpty ? "—" : (measured.compactMap(\.seconds).reduce(0,+) / 3600 / Double(groups.count)).studyNumber
                return table(.duration,"Weekly training hours","Average \(avg) recorded hours per week. \(measured.count) workouts had durations.", ["Week of","Hours","Timed workouts"],rows)
            }
            let groups = Dictionary(grouping: measured) { h.calendar.dateInterval(of: .month, for: $0.date!)!.start }
            let rows = groups.keys.sorted().map { date in
                [date.formatted(.dateTime.month(.abbreviated).year()), (mean(groups[date]!.compactMap(\.seconds))! / 60).studyNumber, String(groups[date]!.count)]
            }
            let bounds = groups.keys.sorted()
            var trend = ""
            if let first = bounds.first, let last = bounds.last, first != last,
               let a = mean(groups[first]!.compactMap(\.seconds)), let b = mean(groups[last]!.compactMap(\.seconds)) {
                trend = " Average duration changed from " + (a/60).studyNumber + " to " + (b/60).studyNumber + " minutes."
            }
            let overall = mean(measured.compactMap(\.seconds)).map { ($0 / 60).studyNumber } ?? "—"
            return table(.duration, "Average workout length", "Average \(overall) minutes across \(measured.count) timed workouts." + trend, ["Month","Average minutes","Workouts"],rows)
        case .start:
            let starts = visits.compactMap(\.began)
            return table(.duration,"Recorded workout start times","\(starts.count) workouts have a recorded start time.",["Date","Start time"],starts.reversed().map { [h.day($0),$0.formatted(date: .omitted,time: .shortened)] })
        case .template:
            let totals = Dictionary(grouping: visits, by: \.template).mapValues(\.count)
            let groups: [(String, Int)] = totals.sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }.map { ($0.key, $0.value) }
            let summary: String
            if let highest = groups.first?.1 {
                let leaders = groups.filter { $0.1 == highest }.map { $0.0 }.joined(separator: ", ")
                summary = "\(leaders) · \(highest) logged workouts each (highest count)."
            } else { summary = "No logged workouts." }
            return table(.frequency,"Most-used workout templates",summary,["Template","Workouts"],groups.map { [$0.0,String($0.1)] })
        case .muscleDates:
            let ref = min(h.today, interval?.end.addingTimeInterval(-1) ?? h.today)
            let recency = text.contains("neglect") || text.contains("lately") || text.contains("since i trained") || text.contains("last time")
            let source = recency ? h.sessions.filter { $0.date <= ref } : selected
            let data = Dictionary(grouping: source.filter { $0.primary != nil && !$0.done.isEmpty }, by: { $0.primary! })
            let targets = muscles.isEmpty ? Muscle.allCases : Muscle.allCases.filter(muscles.contains)
            var entries: [[String]] = []
            for muscle in targets {
                let visits = data[muscle] ?? []
                if let last = visits.last {
                    let sets = visits.filter { includes($0.date) }.flatMap(\.done).count
                    entries.append([muscle.rawValue.capitalized,h.day(last.date),String(h.days(last.date,ref)),String(sets)])
                } else if recency {
                    entries.append([muscle.rawValue.capitalized,"No recorded direct set","—","0"])
                }
            }
            if recency { entries.sort { (Int($0[2]) ?? .max) > (Int($1[2]) ?? .max) } }
            let summary = entries.isEmpty ? "No completed direct working sets were recorded in this period." : entries.count == 1 && entries[0][2] != "—"
                ? entries[0][0] + " was last trained on " + entries[0][1] + ", " + entries[0][2] + " days ago."
                : "Only completed primary-muscle sets count. Days since training uses all records through the end of the selected period."
            return table(.recency,recency ? "Time since direct muscle training" : "Direct muscle training dates",summary,
                ["Muscle","Last trained","Days since","Sets in period"],entries, insufficient: !recency && !h.sessions.isEmpty ? false : nil)
        case .programWeeks, .block, .deload:
            var applicable = visits
            let comparingPrograms = kind == .programWeeks && text.contains("programs")
            if kind == .programWeeks && !comparingPrograms {
                guard let current = currentProgram() else { return table(.blocks,"Current program volume","There is no active program in this history.",["Program"],[]) }
                applicable = visits.filter { $0.program == current }
            }
            if kind == .block { applicable = applicable.filter { $0.block != nil } }
            let buckets = Dictionary(grouping: applicable) { comparingPrograms ? $0.program : kind == .block ? $0.block! : "\($0.program)/\($0.weekNumber)" }
            var groups = buckets.values.sorted { $0[0].date! < $1[0].date! }
            var summary = "Completed work in each recorded period. External volume sums load × reps."
            if kind == .deload {
                let indexed = groups.enumerated().filter { $0.element[0].weekKind.lowercased() == "deload" }
                var comparison: Set<Int> = []
                var paired: [(previous: Double, deload: Double)] = []
                for (i, group) in indexed {
                    comparison.insert(i)
                    if i > 0 && groups[i-1][0].program == group[0].program && groups[i-1][0].weekNumber + 1 == group[0].weekNumber {
                        comparison.insert(i-1)
                        paired.append((counts(groups[i-1]).volume, counts(group).volume))
                    }
                }
                groups = comparison.sorted().map { groups[$0] }
                summary = "\(indexed.count) recorded deload weeks. Each is shown with its preceding recorded week in the same program when available."
                let prior = paired.map(\.previous).reduce(0,+)
                let deload = paired.map(\.deload).reduce(0,+)
                if prior > 0 {
                    let difference = 100 * (deload - prior) / prior
                    summary += " Across \(paired.count) paired weeks, deload volume was \(abs(difference).studyNumber)% \(difference < 0 ? "lower" : "higher")."
                }
            } else if kind == .block { groups = Array(groups.suffix(2)) }
            else if text.contains("first and last"), groups.count > 1 { groups = [groups.first!,groups.last!] }
            let rows = groups.map { group in
                let n = counts(group), w = group[0]
                return [w.template, kind == .block || comparingPrograms ? h.day(w.date!) : "Week \(w.weekNumber)", w.weekKind.capitalized,
                        String(group.count), String(n.sets), String(n.reps), n.volume.studyNumber]
            }
            if groups.count >= 2 && kind != .deload {
                let a = counts(groups.first!), b = counts(groups.last!)
                summary += " First to last displayed: \(a.sets) → \(b.sets) completed sets and \(a.volume.studyNumber) → \(b.volume.studyNumber) \(h.unit.symbol)·reps."
            }
            return table(.blocks,kind == .deload ? "Deload weeks and preceding training" : kind == .block ? "Latest two training blocks" : comparingPrograms ? "Training volume across programs" : "Current program volume by week",
                         summary,["Program","Period","Week type","Workouts","Sets","Reps","Volume (" + h.unit.symbol + "·reps)"],rows)
        case .afterBreak:
            let pairs = zip(visits,visits.dropFirst()).filter { h.days($0.0.date!, $0.1.date!) >= 7 }
            let rows = pairs.map { a,b in
                [h.day(a.date!),h.day(b.date!),String(h.days(a.date!,b.date!)),counts([a]).volume.studyNumber,counts([b]).volume.studyNumber]
            }
            return table(.tonnage,"Workout volume after a week off","\(rows.count) returns after at least seven days between workouts. External load × reps before and after each gap.",["Prior date","Return date","Gap days","Prior " + h.unit.symbol + "·reps","Return " + h.unit.symbol + "·reps"],rows)
        case .programStrength:
            let groups = Dictionary(grouping: visits, by: \.program).values.sorted { $0[0].date! < $1[0].date! }
            guard groups.count >= 2 else { return table(.blocks,"Strength across programs","Two programs with matching logged lifts are needed to compare a switch.",["Program"],[]) }
            let rows = groups.suffix(2).map { group -> [String] in
                let estimates = group.compactMap { w in slots[w.key]?.compactMap(\.best).map(\.tenthsPounds).max() }
                return [group[0].template,h.day(group[0].date!),estimates.first.map(h.loadText) ?? "—",estimates.last.map(h.loadText) ?? "—",estimates.max().map(h.loadText) ?? "—"]
            }
            return table(.blocks,"Strength before and after changing programs","First, last and best session estimates in each of the two latest matching programs.",["Template","First workout","First estimate","Last estimate","Best estimate"],rows)
        case .latest:
            let wholeBodyRegion = text.contains("upper body") || text.contains("lower body")
            let applicable = visits.filter { workout in
                guard wholeBodyRegion else { return true }
                let region = text.contains("upper body") ? Set(StudyOptions.upperBody) : Set(StudyHistory.legs)
                let muscles = workout.primaryMuscles.subtracting([.abs,.obliques])
                return !muscles.isEmpty && muscles.isSubset(of: region)
            }
            guard let latest = applicable.last else {
                return table(.sessionLedger,"Last matching workout","No workout with all primary exercises in the requested body region was recorded.",["Date"],[])
            }
            let whole = h.sessions.filter { $0.workout == latest.key }.sorted { $0.slot < $1.slot }
            var rows: [[String]] = []
            for slot in whole {
                for (type, sets) in [("Warm-up", slot.warmups), ("Working", slot.sets)] {
                    for (index, set) in sets.enumerated() {
                        var row = [slot.name, type, String(index + 1), set.status.rawValue.capitalized,
                                   set.load.map(h.loadText) ?? "—", set.reps.map(String.init) ?? "—"]
                        row.append(set.rating?.valueText ?? "—")
                        row.append(set.targetLoad.map(h.loadText) ?? "—")
                        row.append(set.target.map(String.init) ?? "—")
                        row.append(slot.targetRIR.map(String.init) ?? "—")
                        row.append(set.logged?.formatted(date: .omitted, time: .standard) ?? "—")
                        row.append(set.seconds?.studyNumber ?? "—")
                        rows.append(row)
                    }
                }
            }
            var summary = latest.template + " · " + String(whole.count) + " exercise slots, " + String(rows.count) + " sets."
            if let start = latest.began { summary += " Started " + start.formatted(date: .omitted, time: .shortened) + "." }
            if let seconds = latest.seconds { summary += " Recorded duration: " + (seconds / 60).studyNumber + " min." }
            return table(.sessionLedger, "Last matching workout · " + h.day(latest.date!), summary,
                         ["Exercise", "Type", "Set", "Status", "Load", "Reps", "Reported RIR", "Target load", "Target reps", "Target RIR", "Logged at", "Seconds"], rows)
        case .exerciseMinutes:
            let groups = Dictionary(grouping: selected,by: \.name)
            let timed = groups.compactMap { key, list -> (String,Double,Int)? in
                let seconds = list.flatMap(\.done).compactMap(\.seconds)
                return seconds.isEmpty ? nil : (key,seconds.reduce(0,+),seconds.count)
            }.sorted { $0.1 > $1.1 }
            return table(.duration,"Recorded time by exercise","Sum of timed working sets, including their preceding rest. Untimed sets are excluded.",["Exercise","Total minutes","Timed sets"],timed.map { [$0.0,($0.1 / 60).studyNumber,String($0.2)] })
        case .rest:
            return table(.duration,"Rest between sets","The log combines rest and lifting in each set timer. Rest-only duration and its relationship to load cannot be measured from these timestamps.",["Rest duration"],[])
        }
    }

    private func breakPerformance(_ h: StudyHistory, slots: [StudySession]) -> StudyResult {
        let workouts = Dictionary(grouping: slots.filter { $0.best != nil }, by: \.key)
        var rows: [[String]] = []
        var observations: [(gap: Int, change: Double)] = []
        for list in workouts.values.sorted(by: { $0[0].name < $1[0].name }) {
            let byDate = Dictionary(grouping: list, by: { h.calendar.startOfDay(for: $0.date) })
            let dates = byDate.keys.sorted()
            for (earlier,later) in zip(dates,dates.dropFirst()) {
                guard let first = byDate[earlier]?.compactMap(\.best).map(\.tenthsPounds).max(),
                      let next = byDate[later]?.compactMap(\.best).map(\.tenthsPounds).max() else { continue }
                observations.append((h.days(earlier,later),h.weight(next-first)))
                rows.append([list[0].name,h.day(later),String(h.days(earlier,later)),h.loadText(first),h.loadText(next),h.weight(next-first).studyNumber])
            }
        }
        var summary = "Each row compares successive training days for the same lift."
        if let median = StudyHistory.quantile(observations.map { Double($0.gap) }) {
            let shorter = observations.filter { Double($0.gap) <= median }
            let longer = observations.filter { Double($0.gap) > median }
            if !longer.isEmpty {
                let a = shorter.map(\.change).reduce(0,+) / Double(shorter.count)
                let b = longer.map(\.change).reduce(0,+) / Double(longer.count)
                summary = "Mean next-session change was \(a.studyNumber) \(h.unit.symbol) after gaps up to \(median.studyNumber) days (n=\(shorter.count)), versus \(b.studyNumber) \(h.unit.symbol) after longer gaps (n=\(longer.count)). This comparison cannot establish cause."
            } else { summary += " Recorded intervals do not supply two distinct gap groups around the median." }
        }
        return answer(.returnToSquat,"Recovery interval and next-session strength",summary,columns:["Lift","Next date","Days apart","Prior estimate","Next estimate","Change (" + h.unit.symbol + ")"],rows:rows)
    }
}

private extension Status {
    var isCompletedWorkout: Bool { self == .complete }
}
