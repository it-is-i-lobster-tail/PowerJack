import Foundation

extension StudyHistory {
    func result(for id: TrainingStudy, options: StudyOptions = StudyOptions()) -> StudyResult {
        let history = configured(for: options)
        var result = history.makeResult(for: id)
        result.title = history.chartTitle(for: id)
        if !history.originalPeriod && !result.scope.contains(history.rangeLabel) {
            result.scope += " · " + history.rangeLabel
        }
        return result
    }

    private func makeResult(for id: TrainingStudy) -> StudyResult {
        switch id {
        case .legWork, .armReps, .gluteSources, .frequency, .repRanges, .repChanges, .recency, .sessionLedger:
            workload(id)
        case .legMax, .records, .fixedSquat, .milestones, .repeatBench, .yearlyRecords, .goal, .pushups, .tonnage:
            strength(id)
        case .skipped, .effort, .lastCurl, .benchSets, .substitutions, .exerciseOrder, .returnToSquat, .blocks, .duration:
            programming(id)
        case .repMix, .relationship, .typicalBench, .forecast, .squatSuccess, .missingEstimates:
            statistics(id)
        }
    }

    func table(_ id: TrainingStudy, _ scope: String, _ columns: [String], _ rows: [[String]], _ summary: String = "")
        -> StudyResult
    {
        let data = StudyTable(columns: columns, rows: rows)
        return StudyResult(id: id, scope: scope, figure: rows.isEmpty ? nil : .table(data), summary: summary)
    }

    func bars(
        _ id: TrainingStudy, _ scope: String, _ x: String, _ y: String, _ data: [StudyBar],
        summary: String = "", detail: StudyTable? = nil
    ) -> StudyResult {
        StudyResult(
            id: id, scope: scope, figure: data.isEmpty ? nil : .bars(data),
            xLabel: x, yLabel: y, summary: summary, detail: detail)
    }

    func traces(
        _ id: TrainingStudy, _ scope: String, _ x: String, _ y: String, _ series: [StudySeries],
        dates: Bool = false, summary: String = "", detail: StudyTable? = nil
    ) -> StudyResult {
        let visible = series.filter { !$0.points.isEmpty }
        return StudyResult(
            id: id, scope: scope, figure: visible.isEmpty ? nil : .traces(visible, dates: dates),
            xLabel: x, yLabel: y, summary: summary, detail: detail)
    }

    func matrix(
        _ id: TrainingStudy, _ scope: String, _ cols: [String], _ rows: [String], _ values: [[Double?]],
        _ summary: String
    ) -> StudyResult {
        let hasData = values.joined().contains { $0 != nil }
        return StudyResult(
            id: id, scope: scope, figure: hasData ? .matrix(columns: cols, rows: rows, values: values) : nil,
            summary: summary)
    }

    func estimatePoints(_ slots: [StudySession]) -> [StudyPoint] {
        Dictionary(grouping: slots, by: \.workout).values.compactMap { appearances in
            guard let date = appearances.first?.date,
                let best = ProgramExerciseHistory.MaxEstimate.best(in: appearances.compactMap(\.best))
            else { return nil }
            return StudyPoint(date.timeIntervalSince1970, weight(best.tenthsPounds))
        }.sorted { $0.x < $1.x }
    }

    func scopeDate(_ date: Date) -> String {
        if case .all = options.period { return day(date) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

extension StudyHistory {
    fileprivate func workload(_ id: TrainingStudy) -> StudyResult {
        let legMuscles = muscles(Self.legs)
        let armMuscles = muscles(Self.arms)
        let legName = muscleLabel(Self.legs, "Leg")
        let armName = muscleLabel(Self.arms, "Arms")
        let legSessions = sessions.filter { includes($0.date) && isLeg($0) }
        let weeks = recentWeeks
        let labels = legMuscles.map { $0.rawValue.capitalized }
        switch id {
        case .legWork:
            let byWeek = Dictionary(grouping: credits.filter { includes($0.date) }, by: { week($0.date) })
            let values = legMuscles.map { muscle in
                weeks.map { date in
                    byWeek[date].map { $0.filter { $0.muscle == muscle }.reduce(0) { $0 + $1.sets } }
                }
            }
            return matrix(
                id, "\(legName) muscles · \(weeksLabel)", weeks.map(scopeDate), labels, values,
                "Completed working sets earn one credit for the primary muscle and half for each assisting muscle. A dash means no workout log."
            )
        case .armReps:
            let matches = sessions.filter { inYear($0.date) && exerciseMatches($0) && !$0.done.isEmpty }
            let grain: Calendar.Component
            if options.period.usesDailyBuckets { grain = .day } else { grain = .month }
            let bucket = { (date: Date) in calendar.dateInterval(of: grain, for: date)!.start }
            let counts = Dictionary(grouping: matches, by: { bucket($0.date) })
            let grainLabel = grain == .day ? "Day" : "Month"
            var data: [StudyBar] = []
            var rows: [[String]] = []
            var allDirect = 0
            var allAssisting = 0
            var partial = false
            var date = bucket(yearStart)
            while date < yearEnd, date <= today {
                let label: String
                if grain == .day {
                    label = date.formatted(.dateTime.month(.abbreviated).day())
                } else if case .all = options.period {
                    label = date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
                } else {
                    label = date.formatted(.dateTime.month(.abbreviated))
                }
                let month = counts[date] ?? []
                date = calendar.date(byAdding: grain, value: 1, to: date)!
                for muscle in armMuscles {
                    let total = month.filter { $0.primary == muscle }.flatMap(\.done).compactMap(\.reps).reduce(0, +)
                    allDirect += total
                    data.append(StudyBar(label: label, value: Double(total), group: muscle.rawValue.capitalized))
                }
                for (name, slots) in Dictionary(grouping: month, by: \.name).sorted(by: { $0.key < $1.key }) {
                    let direct = slots.filter { $0.primary.map(armMuscles.contains) == true }
                    let assisting = slots.filter {
                        $0.primary.map(armMuscles.contains) != true
                            && ($0.assisting ?? []).contains(where: armMuscles.contains)
                    }
                    partial =
                        partial || slots.contains { $0.primary.map(armMuscles.contains) != true && $0.assisting == nil }
                    for (role, group) in [("Direct", direct), ("Assisting", assisting)] where !group.isEmpty {
                        let reps = group.flatMap(\.done).compactMap(\.reps).reduce(0, +)
                        if role == "Assisting" { allAssisting += reps }
                        rows.append([label, name, role, String(reps)])
                    }
                }
            }
            return bars(
                id, "\(armName) · \(originalPeriod ? "January–December 2026" : rangeLabel)", grainLabel, "Direct reps",
                matches.isEmpty ? [] : data,
                summary: "\(allDirect) direct reps and \(allAssisting) known assisting reps. Each set is counted once."
                    + (partial ? " Some archived sessions lack assisting-muscle tags." : ""),
                detail: StudyTable(columns: [grainLabel, "Exercise", "Role", "Reps"], rows: rows))
        case .gluteSources:
            let groups = muscles([.glutes])
            let slots = sessions.filter {
                recent($0.date) && exerciseMatches($0) && !$0.done.isEmpty
                    && ($0.primary.map(groups.contains) == true || $0.assisting?.contains(where: groups.contains) == true)
            }
            var rows: [(name: String, direct: Int, assisted: Int, credits: Double)] = []
            for (name, group) in Dictionary(grouping: slots, by: \.name) {
                let direct = group.filter { $0.primary.map(groups.contains) == true }.flatMap(\.done).count
                let assisted = group.flatMap(\.done).count - direct
                rows.append((name, direct, assisted, Double(direct) + Double(assisted) / 2))
            }
            rows.sort { $0.credits == $1.credits ? $0.name < $1.name : $0.credits > $1.credits }
            var result = table(
                id, "\(muscleLabel([.glutes], "Glutes")) · \(recentLabel)", ["Exercise", "Primary", "Assisting", "Credits"],
                rows.map { [$0.name, String($0.direct), String($0.assisted), $0.credits.studyNumber] },
                "Working sets from identifiable exercises. Assisting sets contribute half a credit when their muscle tags are available."
            )
            result.alternateBars = rows.map { StudyBar(label: $0.name, value: $0.credits) }
            result.xLabel = "Exercise"
            result.yLabel = "Set credits"
            return result
        case .frequency:
            let byDay = Dictionary(
                grouping: sessions.filter { includes($0.date) && !$0.done.isEmpty },
                by: { calendar.startOfDay(for: $0.date) })
            let cols = (0..<7).map {
                offset(weeks.first ?? week(today), days: $0).formatted(.dateTime.weekday(.abbreviated))
            }
            let values = weeks.map { w in
                (0..<7).map { d in
                    byDay[offset(w, days: d)].map { Double($0.filter(isLeg).flatMap(\.done).count) }
                }
            }
            return matrix(
                id, "\(legName) working sets · \(weeksLabel)", cols, weeks.map(scopeDate), values,
                "A zero means other work was logged that day. A dash means no logged workout.")
        case .repRanges:
            let grouped = Dictionary(grouping: legSessions.filter { recent($0.date) && !$0.done.isEmpty }, by: \.name)
            let names = grouped.keys.sorted()
            let ranges = [1..<4, 4..<7, 7..<12, 12..<16, 16..<Int.max]
            let values = names.map { name in
                ranges.map { band in
                    Double((grouped[name] ?? []).flatMap(\.done).compactMap(\.reps).filter(band.contains).count) as Double?
                }
            }
            let bands = ["1–3", "4–6", "7–11", "12–15", "16+"]
            let totals = bands.indices.map { col in Int(values.compactMap { $0[col] }.reduce(0, +)) }
            let breakdown = zip(bands, totals).map { "\($0) reps: \($1)" }.joined(separator: " · ")
            return matrix(
                id, "\(legName) exercises · \(recentLabel)", bands, names, values,
                names.isEmpty ? "" : "Completed working sets by rep range. \(breakdown).")
        case .repChanges:
            let windows = comparisonWindows
            guard windows.current.duration > 0 else { return StudyResult(id: id, scope: rangeLabel) }
            let grouped = Dictionary(
                grouping: sessions.filter {
                    $0.date >= windows.previous.start && $0.date < windows.current.end && exerciseMatches($0)
                        && $0.primary.map(armMuscles.contains) == true && !$0.done.isEmpty
                }, by: \.name)
            var data: [StudyBar] = []
            for (name, group) in grouped {
                var delta = 0
                for session in group {
                    let reps = session.done.compactMap(\.reps).reduce(0, +)
                    delta += session.date >= windows.current.start ? reps : -reps
                }
                data.append(StudyBar(label: name, value: Double(delta)))
            }
            data.sort { $0.value == $1.value ? $0.label < $1.label : $0.value > $1.value }
            return bars(
                id, "\(armName) · two \(days(windows.current.start, windows.current.end))-day periods", "Exercise",
                "Change in reps", data,
                summary:
                    "Each value subtracts reps in the preceding period from reps in the selected period. New and removed exercises count."
            )
        case .recency:
            if let range = selectedRange, range.start > today {
                return StudyResult(
                    id: id, scope: rangeLabel, emptyReason: "Choose a date up to today to measure days since training.")
            }
            let data = legMuscles.compactMap { muscle -> StudyBar? in
                guard
                    let s = sessions.last(where: {
                        throughRangeEnd($0.date) && exerciseMatches($0) && $0.primary == muscle && !$0.done.isEmpty
                    })
                else { return nil }
                return StudyBar(label: muscle.rawValue.capitalized, value: Double(days(s.date, asOf)))
            }.sorted { $0.value > $1.value }
            return bars(
                id, "\(legName) · primary working sets through \(scopeDate(asOf))", "Muscle", "Days since training", data,
                summary:
                    "Measured from the latest logged direct work. Muscles without a recorded exposure have no numerical age."
            )
        default:
            guard let first = legSessions.first(where: { !$0.done.isEmpty }) else {
                return StudyResult(id: id, scope: "First logged workout · \(legName)")
            }
            let slots = legSessions.filter { $0.workout == first.workout && !$0.done.isEmpty }
            let count = slots.map { $0.sets.count }.max() ?? 0
            let columns = ["Exercise"] + (0..<count).map { "Set \($0 + 1)" }
            let rows = slots.map { slot in
                [slot.name]
                    + (0..<count).map { index in
                        guard slot.sets.indices.contains(index) else { return "—" }
                        let set = slot.sets[index]
                        guard set.status == .complete, let reps = set.reps else { return "—" }
                        return set.load.map { "\(loadText($0)) × \(reps)" } ?? "\(reps) reps"
                    }
            }
            let total = slots.flatMap(\.done)
            let observedReps = total.compactMap(\.reps)
            return table(
                id, "\(legName) workout · \(day(first.date))", columns, rows,
                "\(total.count) completed working sets and \(observedReps.reduce(0, +)) recorded reps.")
        }
    }
}
