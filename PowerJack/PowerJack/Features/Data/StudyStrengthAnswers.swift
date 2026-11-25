import Foundation

extension LoggedStudyQuestion {
    func strengthAnswer(_ history: StudyHistory) -> StudyResult? {
        let q = text
        let comparison = ["compare", "comparison", " versus ", " vs ", " against "].contains(where: q.contains)
        let sessions = sessions(history).filter { !$0.done.isEmpty }
        let title = liftNames.joined(separator: " / ")
        let records = Dictionary(grouping: sessions, by: \.key)
        let unit = history.unit.symbol
        func result(_ id: TrainingStudy, _ label: String, _ note: String, _ columns: [String], _ rows: [[String]], insufficient: Bool? = nil) -> StudyResult {
            let scope = title.isEmpty ? "the selected exercises" : title
            let message = rows.isEmpty && insufficient != false ? "No qualifying results for \(scope) in this period. " + note : note
            return answer(id, label, message, columns: columns, rows: rows, insufficient: insufficient)
        }
        func estimates(_ slots: [StudySession]) -> [(date: Date, value: Int)] {
            Dictionary(grouping: slots, by: \.workout).values.compactMap { group in
                guard let date = group.first?.date, let best = group.compactMap({ $0.best?.tenthsPounds }).max() else { return nil }
                return (date: date, value: best)
            }.sorted { $0.date < $1.date }
        }
        func delta(_ first: Int, _ last: Int) -> Double {
            100 * Double(last - first) / Double(first)
        }
        if (q.contains("heavier") || q.contains("working weight") || q.contains("working load"))
            && (q.contains("started") || q.contains("beginning") || q.contains("first to last")) {
            var rows: [[String]] = []
            for key in records.keys.sorted() {
                let slots = records[key] ?? []
                let workouts = Dictionary(grouping: slots, by: \.workout).values.compactMap { group -> (Date, Double)? in
                    guard let date = group.first?.date else { return nil }
                    let loads = group.filter { !$0.repsOnly }.flatMap(\.done).compactMap(\.load).filter { $0 > 0 }
                    guard !loads.isEmpty else { return nil }
                    return (date, loads.map { history.weight($0) }.reduce(0, +) / Double(loads.count))
                }.sorted { $0.0 < $1.0 }
                if let first = workouts.first, let last = workouts.last, first.0 < last.0 {
                    rows.append([slots[0].name, history.day(first.0), first.1.studyNumber,
                                 history.day(last.0), last.1.studyNumber, (last.1 - first.1).studyNumber])
                }
            }
            return result(.repMix, "Change in actual working weight",
                          "Mean external load per completed set with a positive recorded weight, comparing each lift’s first and latest workout.",
                          ["Lift", "First date", "First (" + unit + ")", "Latest date", "Latest (" + unit + ")", "Change (" + unit + ")"], rows)
        }
        if q.contains("powerlifting total") || (q.contains("total") && ["Back squat", "Bench press", "Deadlift"].allSatisfy(liftNames.contains)) {
            let lifts = ["Back squat", "Bench press", "Deadlift"]
            var total = 0
            var rows: [[String]] = []
            var missing = [String]()
            for name in lifts {
                guard let latest = estimates(history.sessions.filter { includes($0.date) && matchesLift($0, named: name) && ($0.equipment == .barbell || $0.equipment == nil) }).last else {
                    missing.append(name)
                    rows.append([name, "No qualifying set", "—"])
                    continue
                }
                total += latest.value
                rows.append([name, history.day(latest.date), history.loadText(latest.value)])
            }
            let summary = missing.isEmpty ? "Estimated total: \(history.loadText(total)), using each lift’s latest session estimate." : "A total requires all three lifts. Missing estimates: \(missing.joined(separator: ", "))."
            return result(.legMax, "Current estimated powerlifting total", summary, ["Lift", "Latest session", "Estimated max"], rows, insufficient: !missing.isEmpty)
        }
        if q.contains("relative to bodyweight") || q.contains("bodyweight") || q.contains("body weight") { return nil }
        if q.contains("stall") || q.contains("plateau") || q.contains("haven t progressed") || q.contains("haven't progressed") {
            var stalled: [(visits: Int, name: String, row: [String])] = []
            for (key, scoped) in records {
                let within = estimates(scoped)
                guard within.count >= 2, let latest = within.last else { continue }
                let series = estimates(history.sessions.filter { $0.key == key && $0.date <= latest.date })
                guard let peak = series.map(\.value).max(),
                      let index = series.firstIndex(where: { $0.value == peak }) else { continue }
                let since = series.count - index - 1
                if let interval {
                    // With an explicit period, an improvement anywhere in the period breaks the plateau.
                    if series[index].date > max(interval.start, series.first!.date) { continue }
                } else if since < 3 { continue }
                let name = scoped[0].name
                stalled.append((since, name, [name, history.loadText(peak), history.day(series[index].date),
                                               history.loadText(latest.value), history.day(latest.date), String(since)]))
            }
            stalled.sort { $0.visits == $1.visits ? $0.name < $1.name : $0.visits > $1.visits }
            let rule = interval == nil ? "At least three subsequent workouts without exceeding the previous best estimate." :
                "No new best estimate within the selected period, compared with the prior recorded peak or the first available session. Requires two measured workouts in the period."
            return result(.legMax, "Lifts without a new strength estimate record", "\(stalled.count) lifts matched. " + rule,
                          ["Lift", "Previous peak", "First reached", "Latest", "Last measured", "Workouts since peak"], stalled.map(\.row))
        }
        if q.contains("most improved") || q.contains("improved the most") || (q.contains("machine") && q.contains("free weight")) || q.contains("heavier am i lifting") {
            let equipment = (q.contains("machine") && q.contains("free weight"))
            var changes: [(name: String, change: Double, row: [String], group: String)] = []
            for slots in records.values {
                let series = estimates(slots)
                guard let a = series.first, let b = series.last, let name = slots.first?.name, b.date > a.date else { continue }
                let category: String
                switch slots.first?.equipment {
                case .machine, .cable, .legPress: category = "Machines and cables"
                case .barbell, .dumbbell, .kettlebell: category = "Free weights"
                default: category = ""
                }
                let change = delta(a.value, b.value)
                let elapsed = history.days(a.date, b.date)
                if equipment && elapsed == 0 { continue }
                let rate = equipment ? change * 7 / Double(elapsed) : change
                changes.append((name, rate, [name, history.loadText(a.value), history.loadText(b.value), change.studyNumber + "%", String(series.count)], category))
            }
            changes.sort { $0.change == $1.change ? $0.name < $1.name : $0.change > $1.change }
            if equipment {
                let rows = ["Machines and cables", "Free weights"].compactMap { group -> [String]? in
                    let rates = changes.filter { $0.group == group }.map(\.change)
                    guard let median = StudyHistory.quantile(rates) else { return nil }
                    return [group, median.studyNumber + "%", String(rates.count)]
                }
                let headline = rows.map { "\($0[0]): \($0[1])/week." }.joined(separator: " ")
                return result(.legMax, "Strength progression by equipment", headline + " Median weekly percentage change in each lift’s estimated max, first to latest session. Each lift counts once.", ["Equipment", "Change/week", "Lifts"], rows)
            }
            let headline = changes.first.map { "\($0.name) led with \($0.change.studyNumber)% change. " } ?? ""
            return result(.legMax, "First-to-latest strength change by lift",
                          headline + "Ranked by percentage change from first to latest session-best estimated max. Requires at least two sessions.",
                          ["Exercise", "First", "Latest", "Change", "Sessions"], changes.map(\.row))
        }
        if q.contains("personal records") && !q.contains("rep count") || q.contains(" prs") || q.contains(" pr ") || (q.contains("record") && (q.contains("when") || q.contains("recent") || q.contains("year old"))) || q.hasSuffix(" pr") || q.contains("last pr") {
            // Scan full history before filtering record dates, so earlier bests still count.
            let slots = history.sessions.filter { slot in liftNames.isEmpty || liftNames.contains { matchesLift(slot, named: $0) } }
            struct Record { let date: Date; let name: String; let reps: Int; let load: Int }
            var best = [String: Record]()
            var events = [Record]()
            for slot in slots {
                for set in slot.done {
                    guard let reps = set.reps, reps > 0 else { continue }
                    guard let load = set.load, load > 0 else {
                        if slot.repsOnly {
                            let key = slot.key + "/reps"
                            if reps > (best[key]?.reps ?? 0) {
                                let event = Record(date: slot.date, name: slot.name, reps: reps, load: 0)
                                events.append(event)
                                best[key] = event
                            }
                        }
                        continue
                    }
                    let key = slot.key + "/" + String(reps)
                    guard load > (best[key]?.load ?? 0) else { continue }
                    let event = Record(date: slot.date, name: slot.name, reps: reps, load: load)
                    events.append(event)
                    best[key] = event
                }
            }
            let old = q.contains("year old")
            let yearAgo = history.calendar.date(byAdding: .year, value: -1, to: history.today) ?? history.today
            let recent = q.contains("recent") && interval == nil
            let qualifying = (old ? Array(best.values) : events).filter {
                old ? $0.date < yearAgo : includes($0.date) && (!recent || history.days($0.date, history.today) < 28)
            }.sorted { ($0.date, $0.name, $0.load) > ($1.date, $1.name, $1.load) }
            let rows = qualifying.map { [history.day($0.date), $0.name, String($0.reps), $0.load > 0 ? history.loadText($0.load) : "Bodyweight"] }
            let headline = old ? "\(rows.count) current records are over a year old. " : rows.first.map { "Latest: \($0[1]), \($0[3]) × \($0[2]) on \($0[0]). " } ?? ""
            return result(.records, old ? "Current records set over a year ago" : "Personal record dates", headline + "Loaded records track the first time you exceed the previous load for that exact rep count. Bodyweight records track highest reps. First observations count. " + (recent ? "Showing the last 28 days." : ""), ["Date", "Exercise", "Reps", "Load"], rows, insufficient: old && !best.isEmpty ? false : nil)
        }
        if comparison && liftNames.count >= 2 {
            let rows = liftNames.map { lift -> [String] in
                let points = estimates(history.sessions.filter { includes($0.date) && matchesLift($0, named: lift) })
                guard let last = points.last else { return [lift, "No qualifying set", "—"] }
                return [lift, history.day(last.date), history.loadText(last.value)]
            }
            let headline = rows.map { "\($0[0]): \($0[2])." }.joined(separator: " ")
            return result(.legMax, "Latest strength comparison", headline + " Each lift uses its latest session-best estimated one-rep max.", ["Lift", "Session", "Estimated max"], rows, insufficient: rows.contains { $0.last == "—" })
        }
        let comeback = q.contains("bounce back") || q.contains("comeback") || q.contains("after a break") || q.contains("after time off")
        if !liftNames.isEmpty && (comeback || ((q.contains("break") || q.contains("rest days") || q.contains("days between")) && (q.contains("next") || q.contains("strength")))) {
            let points = estimates(sessions)
            let gaps = zip(points, points.dropFirst()).map { (previous, next) in
                (previous, next, history.days(previous.date, next.date))
            }
            if comeback {
                guard let pair = gaps.filter({ $0.2 >= 7 }).max(by: { $0.2 < $1.2 }) else {
                    return result(.returnToSquat, "Strength after a break · " + title, "No adjacent qualifying sessions at least seven days apart.", ["Session", "Estimated max"], [])
                }
                let followup = Array(points.filter { $0.date >= pair.1.date }.prefix(5))
                let recovery = followup.first { $0.value >= pair.0.value }.map { "Matched or exceeded the pre-break estimate on \(history.day($0.date)). " } ?? "The first \(followup.count) return visits stayed below the pre-break estimate. "
                let rows = ([pair.0] + followup).map {
                    [history.day($0.date), history.loadText($0.value), delta(pair.0.value, $0.value).studyNumber + "%"]
                }
                return result(.returnToSquat, "Strength after a break · " + title, recovery + "Longest break between qualifying sessions: \(pair.2) days. Changes compare with the last pre-break estimate.", ["Date", "Estimated max", "Change"], rows)
            }
            let medianGap = StudyHistory.quantile(gaps.map { Double($0.2) }) ?? 0
            let short = gaps.filter { Double($0.2) <= medianGap }, long = gaps.filter { Double($0.2) > medianGap }
            let first = StudyHistory.quantile(short.map { delta($0.0.value, $0.1.value) }), last = StudyHistory.quantile(long.map { delta($0.0.value, $0.1.value) })
            let comparison: String
            if let first, let last {
                comparison = "Median change after up to \(medianGap.studyNumber) days: \(first.studyNumber)% (\(short.count) gaps). After longer breaks: \(last.studyNumber)% (\(long.count) gaps). "
            } else { comparison = "The recorded gaps do not form two different length groups. " }
            return result(.relationship, "Days between sessions and next strength · " + title, comparison + "Each row compares the next session’s estimated max with the preceding one. Other training factors can also affect the change.", ["Days apart", "Next session", "Estimated max", "Change"], gaps.sorted { $0.2 < $1.2 }.map { [String($0.2), history.day($0.1.date), history.loadText($0.1.value), delta($0.0.value, $0.1.value).studyNumber + "%"] })
        }
        return strengthSetAnswer(history, sessions: sessions, title: title, unit: unit)
    }
}

private extension LoggedStudyQuestion {
    func strengthSetAnswer(_ h: StudyHistory, sessions: [StudySession], title: String, unit: String) -> StudyResult? {
        let q = text
        let all = sessions.flatMap { slot in slot.done.map { (slot, $0) } }
        let name = title.isEmpty ? "All exercises" : title
        func table(_ id: TrainingStudy, _ heading: String, _ summary: String, _ columns: [String], _ rows: [[String]]) -> StudyResult {
            let missing = "No completed sets meet this chart’s filters for \(name) in this period. "
            return answer(id, heading + " · " + name, rows.isEmpty ? missing + summary : summary, columns: columns, rows: rows)
        }
        func numeric(_ pattern: String) -> Double? {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: q, range: NSRange(q.startIndex..., in: q)),
                  let range = Range(match.range(at: 1), in: q) else { return nil }
            guard let value = Double(q[range]), value.isFinite, (0...100_000).contains(value) else { return nil }
            return value
        }
        let weights = all.filter { ($0.1.reps ?? 0) > 0 && ($0.1.load ?? 0) > 0 }
        if !liftNames.isEmpty && (q.contains("at least") || (q.contains("rep") && q.contains(" at "))) {
            guard let value = numeric(#"(?:at least|at)\s+([0-9]+(?:\.[0-9]+)?)"#) else { return nil }
            let input: WeightUnit = q.contains("kg") ? .kilograms : q.contains("lb") || q.contains("pound") ? .pounds : h.unit
            guard value.isFinite, value >= 0, value <= input.maxEntry else {
                return table(.records, "Matching load", "The requested load exceeds the supported range.", ["Date", "Reps"], [])
            }
            let load = input.tenthsPounds(from: value)
            let minimum = q.contains("at least")
            guard !weights.isEmpty else { return table(.records, "Sets at " + h.loadText(load), "No completed sets with recorded loads for this lift.", ["Date", "Reps"], []) }
            let qualifying = weights.filter { minimum ? $0.1.load! >= load : $0.1.load! == load }
            return table(.records, minimum ? "Sessions reaching " + h.loadText(load) : "Reps at " + h.loadText(load), "\(qualifying.count) matching completed sets in \(Set(qualifying.map { $0.0.workout }).count) workouts out of \(Set(weights.map { $0.0.workout }).count) with recorded loads.", ["Date", "Exercise", "Load", "Reps"], qualifying.reversed().map { [h.day($0.0.date), $0.0.name, h.loadText($0.1.load!), String($0.1.reps!)] })
        }
        if q.contains("rep record") || q.contains("in one set") || q.contains("single set") || q.contains("most reps") {
            let sorted = all.filter { ($0.1.reps ?? 0) > 0 }.sorted { ($0.1.reps!, $0.0.date) > ($1.1.reps!, $1.0.date) }
            return table(.records, "Most reps in one set", sorted.first.map { "Best completed set: \($0.1.reps!) reps." } ?? "No completed sets with recorded reps.", ["Date", "Exercise", "Reps"], sorted.prefix(10).map { [h.day($0.0.date), $0.0.name, String($0.1.reps!)] })
        }
        let numbers = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "twelve": 12]
        let exact = numeric(#"(?:set of |exactly )(\d+)"#).flatMap { Int(exactly: $0) }
            ?? numeric(#"(\d+) rep(?:s| |$)"#).flatMap { Int(exactly: $0) }
            ?? numbers.first { word, _ in q.contains("set of " + word) || q.contains(word + " rep") }?.value
        if q.contains("heaviest") || q.contains("best set") || q.contains("rep count") || (exact != nil && (q.contains("best") || q.contains("record") || q.contains("set of"))) {
            let monthly = q.contains("month")
            let repRecords = q.contains("rep count")
            let candidates = weights.filter { exact == nil || $0.1.reps == exact }
            let groups = Dictionary(grouping: candidates) { row in
                let month = monthly ? row.0.date.formatted(.dateTime.year().month(.twoDigits)) : ""
                return [row.0.key, month, repRecords ? String(row.1.reps!) : ""].joined(separator: "/")
            }
            let rows = groups.values.compactMap { group in group.max { ($0.1.load!, $0.1.reps!) < ($1.1.load!, $1.1.reps!) } }
                .sorted { ($0.0.date, $0.0.name, $0.1.reps ?? 0) > ($1.0.date, $1.0.name, $1.1.reps ?? 0) }
                .map { [h.day($0.0.date), $0.0.name, h.loadText($0.1.load!), String($0.1.reps!)] }
            let heading = exact.map { "Heaviest set of exactly \($0)" } ?? (monthly ? "Monthly heaviest sets" : repRecords ? "Load records by exact rep count" : "Heaviest completed set")
            return table(.records, heading, (rows.count == 1 ? "\(rows[0][1]): \(rows[0][2]) × \(rows[0][3]) on \(rows[0][0]). " : "") + "Actual completed working sets with a recorded external load. For weighted bodyweight lifts, the load is added weight.", ["Date", "Lift", "Load", "Reps"], rows)
        }
        let starting = ["starting weight", "opening weight", "opening load", "start with"].contains(where: q.contains)
        if starting || ((q.contains("common") || q.contains("usual")) && (q.contains("weight") || q.contains("load"))) {
            let loads = starting ? sessions.compactMap { $0.opening?.load }.filter { $0 > 0 } : weights.map { $0.1.load! }
            let groups = Dictionary(grouping: loads, by: { $0 }).sorted { $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count }
            return table(.repMix, starting ? "Usual opening working weight" : "Most common working weight", (groups.first.map { "\(h.loadText($0.key)) occurred \($0.value.count) times. " } ?? "") + "Ranked by the number of recorded occurrences.", ["Load", starting ? "Opening sets" : "Sets"], groups.map { [h.loadText($0.key), String($0.value.count)] })
        }
        if q.contains("set") && q.contains("rep") && ["fall off", "drop", "declin", "fatigue", "fall across"].contains(where: q.contains) {
            let groups = Dictionary(grouping: sessions, by: \.key)
            var rows = [[String]]()
            for key in groups.keys.sorted() {
                // Only compare sets at the same load within a single exercise slot.
                let slots = groups[key]!
                let pairs = slots.compactMap { slot -> (Int, Int)? in
                    guard slot.sets.count >= 2, let a = slot.opening, let b = slot.sets.last, b.status == .complete,
                          ((a.load != nil && a.load == b.load) || slot.repsOnly), let first = a.reps, let last = b.reps else { return nil }
                    return (first, last)
                }
                guard let first = StudyHistory.quantile(pairs.map { Double($0.0) }), let last = StudyHistory.quantile(pairs.map { Double($0.1) }) else { continue }
                rows.append([slots[0].name, String(pairs.count), first.studyNumber, last.studyNumber, String(pairs.filter { $0.1 < $0.0 }.count)])
            }
            let drops = rows.reduce(0) { $0 + (Int($1[4]) ?? 0) }
            let sample = rows.reduce(0) { $0 + (Int($1[1]) ?? 0) }
            let headline = sample == 0 ? "" : "Reps fell in \(drops) of \(sample) matched observations. "
            return table(.benchSets, "First and last working-set reps", headline + "Matched within a workout at the same load. Medians describe the first and final working sets. Drops counts sessions where the final set had fewer reps.", ["Lift", "Sessions", "First", "Last", "Drops"], rows)
        }
        let workoutCount = numeric(#"last (\d+) (?:logged )?(?:workouts|sessions)"#).flatMap { Int(exactly: $0) } ?? (q.contains("last ten") ? 10 : nil)
        if q.contains("weights i used") || q.contains("loads i used") || (!liftNames.isEmpty && workoutCount != nil) || q.contains("top set") {

            let groups = Dictionary(grouping: weights, by: { $0.0.workout }).values.sorted { $0[0].0.date > $1[0].0.date }
            var rows = [[String]]()
            for workout in groups.prefix(workoutCount ?? groups.count) {
                let slots = Dictionary(grouping: workout, by: { $0.0.key })
                for key in slots.keys.sorted() {
                    let sets = slots[key]!
                    if q.contains("top set") {
                        guard let top = sets.max(by: { ($0.1.load!, $0.1.reps!) < ($1.1.load!, $1.1.reps!) }) else { continue }
                        rows.append([h.day(top.0.date), top.0.name, h.loadText(top.1.load!) + " × " + String(top.1.reps!)])
                    } else {
                        rows.append([h.day(sets[0].0.date), sets[0].0.name, sets.map { h.loadText($0.1.load!) + " × " + String($0.1.reps!) }.joined(separator: ", ")])
                    }
                }
            }
            return table(.sessionLedger, q.contains("top set") ? "Heaviest set each session" : "Working loads and reps by workout", "Completed working sets, most recent workout first.", ["Session", "Exercise", "Load × reps"], rows)
        }
        let weekdays = (q.contains("weekday") || q.contains("days of the week")) && (q.contains("strong") || q.contains("best"))
        let bestDay = !liftNames.isEmpty && q.contains("best") && (q.contains(" day") || q.contains(" session"))
        if weekdays || bestDay || q.contains("stronger") || q.contains("estimated") || q.contains("progress") || (q.contains("max") && (q.contains("rate") || q.contains("fast") || q.contains("trend"))) || (!liftNames.isEmpty && (q.contains("weeks of") || q.contains("strength trend") || q.contains("getting stronger") || q.contains("strength gain"))) || q.contains("switched programs") {
            guard !liftNames.isEmpty, !q.contains("depth"), !q.contains("volume") else { return nil }
            let points = sessions.compactMap { slot in slot.best.map { (slot, $0.tenthsPounds) } }
            if weekdays {
                let weekdays = Dictionary(grouping: points) { h.calendar.component(.weekday, from: $0.0.date) }
                let medians = weekdays.compactMap { day, group -> (String, Double, Int)? in
                    guard let median = StudyHistory.quantile(group.map { h.weight($0.1) }) else { return nil }
                    return (h.calendar.weekdaySymbols[day-1], median, group.count)
                }.sorted { $0.1 > $1.1 }
                return table(.legMax, "Strength by weekday", (medians.first.map { "\($0.0) ranked highest at \($0.1.studyNumber) \(unit) across \($0.2) observations. " } ?? "") + "Ranked by median session-best estimated one-rep max.", ["Weekday", "Median (" + unit + ")", "Observations"], medians.map { [$0.0, $0.1.studyNumber, String($0.2)] })
            }
            if q.contains("switched programs") {
                let groups = Dictionary(grouping: points) { String($0.0.workout.split(separator: "/").first ?? "") }
                let ordered = groups.values.sorted { $0[0].0.date < $1[0].0.date }
                guard ordered.count >= 2 else { return table(.blocks, "Strength across programs", "At least two recorded programs with qualifying sets are required.", ["Program", "First", "Latest"], []) }
                return table(.blocks, "Strength across programs", "First and last session-best estimated max for each program in start-date order.", ["Program", "First session", "First estimate", "Last session", "Last estimate"], ordered.map { g in
                    let a = g.first!, b = g.last!
                    return [a.0.routine.components(separatedBy: " · day ").first ?? a.0.routine, h.day(a.0.date), h.loadText(a.1), h.day(b.0.date), h.loadText(b.1)]
                })
            }
            if bestDay {
                let top = points.max { $0.1 < $1.1 }
                return table(.legMax, "Best session by estimated one-rep max", (top.map { "\(h.day($0.0.date)): \(h.loadText($0.1)). " } ?? "") + "Based on the best qualifying working set in each session.", ["Date", "Lift", "Estimate"], top.map { [[h.day($0.0.date), $0.0.name, h.loadText($0.1)]] } ?? [])
            }
            let grouped = Dictionary(grouping: points, by: { $0.0.key })
            var series = [StudySeries]()
            var notes = [String]()
            for key in grouped.keys.sorted() {
                let entries = grouped[key]!
                let workoutGroups = Dictionary(grouping: entries, by: { $0.0.workout })
                let ordered = workoutGroups.values.compactMap { $0.max { $0.1 < $1.1 } }.sorted { $0.0.date < $1.0.date }
                guard let a = ordered.first, let b = ordered.last else { continue }
                let days = h.days(a.0.date, b.0.date)
                let change = h.weight(b.1) - h.weight(a.1)
                let rate = days > 0 ? " (\((change * 7 / Double(days)).studyNumber) \(unit)/week)" : ""
                notes.append("\(a.0.name): \(h.loadText(a.1)) to \(h.loadText(b.1))\(rate).")
                series.append(StudySeries(name: a.0.name, points: ordered.map { StudyPoint($0.0.date.timeIntervalSince1970, h.weight($0.1)) }))
            }
            let rows = points.sorted { $0.0.date < $1.0.date }.map { [h.day($0.0.date), $0.0.name, h.loadText($0.1)] }
            var answer = table(.legMax, "Session-best estimated one-rep max", notes.isEmpty ? "No qualifying completed working sets for this lift and period." : notes.joined(separator: " "), ["Date", "Lift", "Estimate"], rows)
            if !series.isEmpty {
                if series.allSatisfy({ $0.points.count < 2 }) && ["trend", "change", "stronger", "progress", "improv"].contains(where: q.contains) {
                    answer.summary = "Not enough data. A trend needs at least two measured workouts for the same lift. The chart shows the available estimates."
                }
                answer.detail = StudyTable(columns: ["Date", "Lift", "Estimate"], rows: rows)
                answer.figure = .traces(series, dates: true)
                answer.xLabel = "Workout date"
                answer.yLabel = "Estimated max (" + unit + ")"
            }
            return answer
        }
        return nil
    }
}
