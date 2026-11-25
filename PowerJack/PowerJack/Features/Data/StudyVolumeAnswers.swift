import Foundation

private struct WorkingVolume {
    var sets = 0
    var reps = 0
    var repSets = 0
    var externalSets = 0
    var externalReps = 0
    var tonnage = 0.0

    init(_ slots: [StudySession], _ history: StudyHistory) {
        for slot in slots {
            for set in slot.done {
                sets += 1
                guard let count = set.reps else { continue }
                repSets += 1
                reps += count
                guard !slot.repsOnly, let load = set.load else { continue }
                externalSets += 1
                externalReps += count
                tonnage += history.weight(load) * Double(count)
            }
        }
    }

    var fields: [String] {
        [String(sets), repSets > 0 ? String(reps) : "—", externalSets > 0 ? tonnage.studyNumber : "—"]
    }
    var meanLoad: String { externalReps > 0 ? (tonnage / Double(externalReps)).studyNumber : "—" }
}

private let volumePatterns = Dictionary(uniqueKeysWithValues: ExerciseCatalog.entries.map { ("catalog:" + $0.id, $0.profile.pattern) })

extension LoggedStudyQuestion {
    func volumeAnswer(_ history: StudyHistory) -> StudyResult? {
        let tokens = Set(text.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        func has(_ words: String...) -> Bool { words.contains(where: tokens.contains) }
        let all = history.sessions.filter { includes($0.date) }
        let selected = sessions(history)
        let subject = liftNames.isEmpty ? muscles.map { $0.rawValue.capitalized }.sorted().joined(separator: ", ") : liftNames.joined(separator: ", ")
        let focus = subject.isEmpty ? "" : " · " + subject
        let pushPull = has("push", "pushing", "pressing") && has("pull", "pulling")
        let upperLower = has("upper") && has("lower")
        let ratio = has("ratio") && has("quad", "quads", "quadriceps") && has("hamstring", "hamstrings")
        if pushPull || upperLower || ratio || (has("single") && has("leg") && has("work", "training", "sets")) {
            return balanceAnswer(history, all, pushPull: pushPull, upperLower: upperLower, ratio: ratio)
        }
        let hard = has("hard") && has("set", "sets")
        if hard || has("failure", "rpe", "rir") {
            return effortAnswer(history, selected, focus: focus, hard: hard, weekly: has("weekly", "week", "weeks"))
        }
        if has("switch", "swap", "swaps", "swapping", "change", "substitutions") && has("exercises") {
            return usageAnswer(history, all, swapping: true, skipped: false)
        }
        if (has("skip", "skipped") && has("exercises")) || (has("most") && has("exercise", "exercises") && has("do", "used", "use")) {
            return usageAnswer(history, selected, swapping: false, skipped: has("skip", "skipped"))
        }
        if has("range", "ranges", "bands") && has("rep", "reps") {
            let ranges = [1...3, 4...6, 7...11, 12...15, 16...Int.max]
            let reps = selected.flatMap(\.done).compactMap(\.reps)
            let rows = zip(ranges, ["1–3", "4–6", "7–11", "12–15", "16+"]).map { range, label in
                [label, String(reps.filter(range.contains).count)]
            }
            return answer(.repRanges, "Working sets by rep range" + focus, "Counts across \(reps.count) working sets with recorded reps.",
                          columns: ["Reps", "Sets"], rows: reps.isEmpty ? [] : rows)
        }
        if has("volume") && has("strength", "gains") {
            return volumeStrengthAnswer(history, selected)
        }
        if has("adding", "added", "increased", "increasing") && has("weight", "load") && has("sets", "reps") {
            return loadChangeAnswer(history, selected, focus: focus)
        }
        let averageReps = has("average", "mean") && has("reps", "repetitions") && has("set", "sets")
        let averageLoad = has("average", "mean") && has("load", "weight") && has("rep", "reps")
        if averageReps || averageLoad {
            let volume = WorkingVolume(selected, history)
            let title = (averageReps ? "Average reps per set" : "Average external load per rep") + focus
            let value = averageReps ? (volume.repSets > 0 ? (Double(volume.reps) / Double(volume.repSets)).studyNumber : "—") : volume.meanLoad
            let count = averageReps ? volume.repSets : volume.externalReps
            let basis = averageReps ? "working sets with reps" : "reps with external load"
            return answer(averageReps ? .armReps : .tonnage, title, "\(value) \(averageReps ? "reps per set" : history.unit.symbol + " per rep") across \(count) \(basis).",
                          columns: ["Average", "Eligible observations"], rows: count == 0 ? [] : [[value, String(count)]])
        }
        let byWorkout = has("workout", "workouts", "session", "sessions") && (has("sets", "reps") && has("per", "by", "each"))
        let muscleVolume = has("volume", "sets") && has("muscle", "muscles") && has("group", "groups")
        if muscleVolume {
            let groups = Dictionary(grouping: selected, by: { $0.primary?.rawValue.capitalized ?? "Unknown" })
            var counts: [(name: String, count: Int)] = []
            for (name, group) in groups {
                let count = group.reduce(0) { $0 + $1.done.count }
                if count > 0 { counts.append((name, count)) }
            }
            counts.sort { a, b in a.count == b.count ? a.name < b.name : a.count > b.count }
            let total = counts.reduce(0) { $0 + $1.count }
            return answer(.legWork, "Working sets by primary muscle" + focus, "Each of \(total) completed working sets counts once, under its primary muscle.",
                          columns: ["Primary muscle", "Sets"], rows: counts.map { [$0.name, String($0.count)] })
        }
        let counting = has("sets", "reps", "repetitions", "chin") && has("many", "total", "weekly", "monthly", "week", "month")
        let external = has("tonnage", "volume") || (has("much") && has("lift", "lifted", "weight", "move", "train"))
        guard byWorkout || counting || external else { return nil }
        guard !has("deload", "program", "break", "off", "cardio", "streak", "consistency", "often", "days", "hours", "times") else { return nil }
        guard !text.contains("in one set"), !text.contains("single set") else { return nil }
        guard !has("record", "best", "pr", "heaviest", "max", "failure", "reserve", "warm", "warmups") else { return nil }
        let sideDelt = has("side", "lateral") && has("delt", "delts", "deltoids")
        let slots = sideDelt ? all.filter { ($0.movementPattern ?? volumePatterns[$0.key]) == .lateralRaise } : selected
        return amountAnswer(history, slots, focus: sideDelt ? " · lateral raises (side-delt proxy)" : focus, byWorkout: byWorkout,
                            week: has("week", "weeks", "weekly"), month: has("month", "months", "monthly"),
                            peak: has("highest", "strongest", "peak"), kind: external ? "Volume load" : (has("rep", "reps", "repetitions", "chin") ? "Reps" : "Working sets"))
    }

    private func amountAnswer(_ h: StudyHistory, _ slots: [StudySession], focus: String, byWorkout: Bool, week: Bool,
                              month: Bool, peak: Bool, kind: String) -> StudyResult {
        let done = slots.filter { !$0.done.isEmpty }
        // Relative periods set the scope; only an explicit grouping asks for a time series.
        let relativeOnly = ["last week", "last month", "this week", "this month"].contains(where: text.contains)
        let groupWeek = week && (!relativeOnly || text.contains("weekly"))
        let groupMonth = month && (!relativeOnly || text.contains("monthly"))
        let unit = h.unit.symbol + "·reps"
        let grain = byWorkout ? "Workout" : groupWeek ? "Week beginning" : groupMonth ? "Month" : "Period"
        let grouped = Dictionary(grouping: done) { s in
            if byWorkout { return s.workout }
            if groupWeek { return String(h.week(s.date).timeIntervalSince1970) }
            if groupMonth { return String(h.calendar.dateInterval(of: .month, for: s.date)!.start.timeIntervalSince1970) }
            return "all"
        }
        let bins = grouped.values.sorted { ($0[0].date, $0[0].workout) < ($1[0].date, $1[0].workout) }.map { bin in
            let date = bin[0].date
            let label = byWorkout ? h.day(date) + " · " + bin[0].routine : groupWeek ? h.day(h.week(date)) :
                groupMonth ? date.formatted(.dateTime.month(.abbreviated).year()) : periodLabel
            let x = groupWeek ? h.week(date) : groupMonth ? h.calendar.dateInterval(of: .month, for: date)!.start : date
            return (label, WorkingVolume(bin, h), x)
        }
        let total = WorkingVolume(done, h)
        func value(_ v: WorkingVolume) -> String {
            if kind == "Working sets" { return "\(v.sets) working sets" }
            if kind == "Reps" { return "\(v.reps) recorded reps in \(v.repSets) sets" }
            guard v.externalSets > 0 else { return "No completed sets have both recorded external load and reps" }
            return "\(v.tonnage.studyNumber) \(unit) across \(v.externalSets) sets with recorded external load and reps"
        }
        let title = kind + (byWorkout ? " by workout" : groupWeek ? " by week" : groupMonth ? " by month" : "") + focus
        var summary = done.isEmpty ? "0 matching working sets were logged in this period." : value(total) + "."
        if done.isEmpty && kind == "Reps" { summary += " Recorded reps: 0." }

        if peak, let top = bins.filter({ $0.1.externalSets > 0 }).max(by: { $0.1.tonnage < $1.1.tonnage }) {
            let tied = bins.filter { $0.1.externalSets > 0 && $0.1.tonnage == top.1.tonnage }.map(\.0)
            summary = "Highest volume: \(tied.joined(separator: ", ")) with \(value(top.1))."
        }
        var rows = bins.map { [$0.0] + $0.1.fields }
        if rows.isEmpty, groupWeek, kind == "Reps" || kind == "Working sets", !h.workouts.isEmpty {
            // The absence of a matching lift establishes a logged count in each observed week.
            // Do not manufacture load or performance observations for that lift.
            let first = h.week(max(interval?.start ?? h.firstDate, h.firstDate))
            let last = h.week(min(interval?.end.addingTimeInterval(-1) ?? h.today, h.today))
            var date = first
            while date <= last {
                rows.append([h.day(date), "0", "0", "—"])
                date = h.offset(date, days: 7)
            }
        }
        if rows.isEmpty && !groupWeek && !groupMonth && !byWorkout {
            rows = [[periodLabel, "0", "0", "0"]]
        }
        var result = answer(kind == "Volume load" ? .tonnage : .armReps, title, summary, columns: [grain, "Sets", "Reps", unit], rows: rows)
        if (groupWeek || groupMonth || byWorkout) && bins.count > 1 {
            let points = bins.compactMap { _, v, date -> StudyPoint? in
                let value: Double
                switch kind {
                case "Volume load":
                    guard v.externalSets > 0 else { return nil }
                    value = v.tonnage
                case "Reps":
                    guard v.repSets > 0 else { return nil }
                    value = Double(v.reps)
                default: value = Double(v.sets)
                }
                return StudyPoint(date.timeIntervalSince1970, value)
            }
            if !points.isEmpty {
                result.detail = StudyTable(columns: [grain, "Sets", "Reps", unit], rows: rows)
                result.figure = .traces([StudySeries(name: kind, points: points, style: .bars)], dates: true)
                result.xLabel = grain
                result.yLabel = kind == "Volume load" ? unit : kind
            }
        }
        return result
    }

    private func balanceAnswer(_ h: StudyHistory, _ slots: [StudySession], pushPull: Bool, upperLower: Bool, ratio: Bool) -> StudyResult {
        var counts: [String: Int] = [:]
        let pair = pushPull ? ["Push", "Pull"] : upperLower ? ["Upper", "Lower"] : ratio ? ["Quads", "Hamstrings"] : ["Single-leg", "Other"]
        for s in slots {
            let group: String
            if pushPull {
                switch s.movementPattern ?? volumePatterns[s.key] {
                case .horizontalPress, .overheadPress, .dip, .elbowExtension, .chestFly: group = pair[0]
                case .horizontalPull, .verticalPull, .elbowFlexion, .facePull, .reverseFly: group = pair[1]
                default: group = "Other / unclassified"
                }
            } else if upperLower {
                switch s.movementPattern ?? volumePatterns[s.key] {
                case .hipHinge, .squat, .splitSquatLunge, .legPress, .hipThrustBridge, .kneeExtension, .kneeFlexion, .hipExtension, .hipAbduction, .calfRaise:
                    group = pair[1]
                default:
                    if let primary = s.primary, StudyOptions.upperBody.contains(primary) { group = pair[0] }
                    else if let primary = s.primary, StudyHistory.legs.contains(primary) { group = pair[1] }
                    else { group = "Core / unclassified" }
                }
            } else if ratio {
                if s.primary == .quads { group = pair[0] }
                else if s.primary == .hamstrings { group = pair[1] }
                else { continue }
            } else {
                let name = (s.name + " " + s.key).lowercased().replacingOccurrences(of: "-", with: " ")
                let named = ["single leg", "one leg", "per leg", "split squat", "lunge", "step up"].contains(where: name.contains)
                group = (s.movementPattern ?? volumePatterns[s.key]) == .splitSquatLunge || named ? pair[0] : pair[1]
            }
            counts[group, default: 0] += s.done.count
        }
        let a = counts[pair[0], default: 0], b = counts[pair[1], default: 0]
        let extra = counts.keys.filter { !pair.contains($0) }.sorted()
        let total = counts.values.reduce(0,+)
        let comparison = b > 0 ? "\((Double(a) / Double(b)).studyNumber):1" : "undefined (zero \(pair[1].lowercased()) sets)"
        let basis = pushPull ? "Catalog press, fly and triceps patterns count as push; row, vertical pull, reverse fly, face pull and curl patterns count as pull." :
            upperLower ? "Lower-body movement patterns, including hip hinges, count as lower. Other lifts use their primary muscle." :
            ratio ? "Sets are assigned once by primary muscle." : "Single-leg includes identified unilateral leg exercises, lunges, split squats and step-ups."
        let summary = "\(pair[0]) \(a) sets; \(pair[1]) \(b) sets. Ratio \(comparison). \(basis)"
        let rows = (pair + extra).map { key in
            let n = counts[key, default: 0]
            return [key, String(n), total > 0 ? "\((100 * Double(n) / Double(total)).studyNumber)%" : "—"]
        }
        return answer(.legWork, pair.joined(separator: " vs ") + " working sets", summary, columns: ["Group", "Working sets", "Share"], rows: total > 0 ? rows : [])
    }

    private func effortAnswer(_ h: StudyHistory, _ slots: [StudySession], focus: String, hard: Bool, weekly: Bool) -> StudyResult {
        let accessories = text.contains("accessor")
        let selected = accessories ? slots.filter { $0.isAccessory == true } : slots
        let title = (hard ? "Recorded hard sets" : text.contains("rpe") ? "Estimated lifting RPE" : "Reported proximity to failure")
            + (accessories ? " · accessory slots" : focus)
        let sets = selected.flatMap(\.done)
        let ratings = sets.compactMap(\.rating)
        var coverage = "\(ratings.count) of \(sets.count) completed working sets have an effort rating."
        if accessories {
            let unknown = slots.filter { $0.isAccessory == nil }.reduce(0) { $0 + $1.done.count }
            coverage += " \(unknown) working sets lack a recorded program role."
        }
        if hard {
            let grouped = Dictionary(grouping: selected) { s in
                (weekly ? h.day(h.week(s.date)) + " · " : "") + (s.primary?.rawValue.capitalized ?? "Unknown muscle")
            }
            let rows = grouped.sorted { ($0.value[0].date, $0.key) < ($1.value[0].date, $1.key) }.map { name, group in
                let done = group.flatMap(\.done)
                let rated = done.compactMap(\.rating)
                return [name, rated.isEmpty ? "—" : String(rated.filter { $0.rawValue <= 3 }.count), String(rated.count), String(done.count)]
            }
            let n = ratings.filter { $0.rawValue <= 3 }.count
            return answer(.effort, title + (weekly ? " by week" : " by primary muscle"),
                          "\(n) confirmed hard sets at 0–3 reported reps in reserve. \(coverage) Unrated sets have unknown effort.",
                          columns: [weekly ? "Week · muscle" : "Primary muscle", "Confirmed hard", "Rated", "Completed"], rows: rows)
        }
        let fields = ["Date", "Exercise", "Working set", "RIR", "Estimated RPE"]
        guard !ratings.isEmpty else {
            return answer(.effort, title, "No rated working sets matched this scope. \(coverage)" + (accessories ? " Only slots identified as accessories are included." : ""), columns: fields, rows: [])
        }
        var observations: [(Date, String, Int, RepsInReserve)] = []
        for s in selected {
            for (i, set) in s.sets.enumerated() where set.status == .complete {
                if let rating = set.rating { observations.append((s.date, s.name, i + 1, rating)) }
            }
        }
        observations.sort {
            if $0.3 != $1.3 { return $0.3.rawValue < $1.3.rawValue }
            if $0.0 != $1.0 { return $0.0 > $1.0 }
            return ($0.1, $0.2) < ($1.1, $1.2)
        }
        let first = observations[0]
        let upper = ratings.map { 10 - $0.rawValue }.reduce(0,+)
        let openEnded = ratings.contains(.fiveOrMore)
        let average = Double(upper) / Double(ratings.count)
        let rir = (10 - average).studyNumber
        let summary = text.contains("rpe")
            ? "Mean estimated RPE \(openEnded ? "at most " : "")\(average.studyNumber) using 10 minus reported RIR. \(coverage)"
            : "Closest reported effort: \(first.3.valueText) RIR on \(first.1), \(h.day(first.0)). Average \(openEnded ? "at least " : "")\(rir) RIR. \(coverage)"
        let rows = observations.map { date, name, index, rating in
            [h.day(date), name, String(index), rating.valueText, rating == .fiveOrMore ? "≤5" : String(10 - rating.rawValue)]
        }
        return answer(.effort, title, summary, columns: fields, rows: rows)
    }

    private func usageAnswer(_ h: StudyHistory, _ slots: [StudySession], swapping: Bool, skipped: Bool) -> StudyResult {
        if swapping {
            let done = slots.filter { !$0.done.isEmpty }
            let known = done.filter { $0.planned != nil }
            let swaps = known.filter { $0.planned != $0.key }
            let pairs = Dictionary(grouping: swaps) { h.exerciseName(for: $0.planned!) + " → " + $0.name }
            let ratio = known.isEmpty ? "—" : (100 * Double(swaps.count) / Double(known.count)).studyNumber + "%"
            let pairNames = pairs.keys.sorted { first, second in
                let a = pairs[first]?.count ?? 0
                let b = pairs[second]?.count ?? 0
                return a == b ? first < second : a > b
            }
            var rows = pairNames.map { [$0, String(pairs[$0]?.count ?? 0)] }
            if !known.isEmpty { rows.append(["Performed as planned", String(known.count - swaps.count)]) }
            return answer(.substitutions, "Programmed exercise swaps", "\(swaps.count) of \(known.count) comparable completed exercise slots were substitutions (\(ratio)). \(done.count - known.count) slots have no recorded planned exercise.",
                          columns: ["Planned → performed", "Slots"], rows: rows)
        }
        let grouped = Dictionary(grouping: slots, by: { skipped ? ($0.planned ?? $0.key) : $0.key })
        var entries: [(name: String, count: Int, observed: Int)] = []
        for (key, values) in grouped {
            let count: Int
            let observed: Int
            if skipped {
                count = values.filter { slot in !slot.sets.isEmpty && slot.sets.allSatisfy { $0.status == .skipped } }.count
                observed = values.filter { slot in slot.sets.contains { $0.status == .complete || $0.status == .skipped } }.count
            } else {
                count = Set(values.filter { !$0.done.isEmpty }.map(\.workout)).count
                observed = values.reduce(0) { $0 + $1.done.count }
            }
            if observed > 0 { entries.append((h.exerciseName(for: key), count, observed)) }
        }
        entries.sort { a, b in a.count == b.count ? a.name < b.name : a.count > b.count }
        let metric = skipped ? "fully skipped slots" : "workouts"
        let summary = entries.first.map { top in
            let names = entries.filter { $0.1 == top.1 }.map(\.0)
            if top.1 == 0 { return "No exercise slots had every working set marked skipped." }
            return "\(names.joined(separator: ", ")) led with \(top.1) \(metric)."
        } ?? "No matching exercise slots were recorded."
        return answer(skipped ? .skipped : .frequency, skipped ? "Most frequently skipped exercises" : "Most frequently trained exercises",
                      summary, columns: ["Exercise", metric.capitalized, skipped ? "Observed slots" : "Working sets"], rows: entries.map { [$0.0, String($0.1), String($0.2)] })
    }

    private func loadChangeAnswer(_ h: StudyHistory, _ slots: [StudySession], focus: String) -> StudyResult {
        let groups = Dictionary(grouping: slots.filter { !$0.done.isEmpty }, by: \.key)
        var rows: [[String]] = []
        for group in groups.values.sorted(by: { $0[0].name < $1[0].name }) {
            let visits = Dictionary(grouping: group, by: \.workout).values.sorted { ($0[0].date, $0[0].workout) < ($1[0].date, $1[0].workout) }
            guard visits.count > 1, let first = visits.first, let last = visits.last else { continue }
            let a = WorkingVolume(first, h), b = WorkingVolume(last, h)
            rows.append([group[0].name, h.day(first[0].date), h.day(last[0].date), "\(a.sets) → \(b.sets)",
                         "\(a.fields[1]) → \(b.fields[1])", "\(a.meanLoad) → \(b.meanLoad)"])
        }
        let summary: String
        if rows.count == 1, let row = rows.first {
            summary = "\(row[0]): sets \(row[3]), reps \(row[4]), external load per rep \(row[5]) \(h.unit.symbol), from \(row[1]) to \(row[2])."
        } else {
            summary = rows.isEmpty ? "Two workouts for the same exercise are needed." : "First and latest matching workouts for each of \(rows.count) exercises. Load is weighted by reps."
        }
        return answer(.tonnage, "Changes in sets, reps and load" + focus, summary,
                      columns: ["Exercise", "First", "Latest", "Sets", "Total reps", "Load/rep (\(h.unit.symbol))"], rows: rows)
    }

    private func volumeStrengthAnswer(_ h: StudyHistory, _ slots: [StudySession]) -> StudyResult {
        var rows: [[String]] = []
        var rising = 0
        var increasingVolume = 0
        for group in Dictionary(grouping: slots, by: \.key).values.sorted(by: { $0[0].name < $1[0].name }) {
            let weeks = Dictionary(grouping: group, by: { h.week($0.date) }).sorted { $0.key < $1.key }
            for (earlier, later) in zip(weeks, weeks.dropFirst()) {
                guard h.days(earlier.key, later.key) == 7,
                      let maxA = earlier.value.compactMap(\.best).map(\.tenthsPounds).max(),
                      let maxB = later.value.compactMap(\.best).map(\.tenthsPounds).max() else { continue }
                let a = WorkingVolume(earlier.value, h), b = WorkingVolume(later.value, h)
                guard a.externalSets > 0, b.externalSets > 0 else { continue }
                let volumeDelta = b.tonnage - a.tonnage
                if volumeDelta > 0 {
                    increasingVolume += 1
                    if maxB > maxA { rising += 1 }
                }
                rows.append([group[0].name, h.day(later.key), a.tonnage.studyNumber, b.tonnage.studyNumber,
                             volumeDelta.studyNumber, h.weight(maxB - maxA).studyNumber])
            }
        }
        return answer(.relationship, "Weekly volume change and estimated strength gains",
                      rows.isEmpty ? "No consecutive weeks had eligible load and strength estimates for the same exercise." :
                        "Estimated strength rose in \(rising) of \(increasingVolume) same-exercise week pairs with higher volume. \(rows.count) consecutive week pairs qualify.",
                      columns: ["Exercise", "Week beginning", "Prior volume", "Volume (\(h.unit.symbol)·reps)", "Volume change", "Best e1RM change (\(h.unit.symbol))"], rows: rows)
    }
}
