import Foundation

extension StudyHistory {
    func programming(_ id: TrainingStudy) -> StudyResult {
        let squatName = focusName(Self.squat, "Back squat")
        let curlName = focusName(Self.curl, "Cable curl")
        let benchName = focusName(Self.bench, "Bench press")
        let curlLoad = parameter(.load, 300)
        switch id {
        case .skipped:
            let slots = sessions.filter { $0.finished && recent($0.date) && isLeg($0) }
            let grouped = Dictionary(grouping: slots, by: \.name)
            var marks: [StudyBar] = []
            let rows = grouped.keys.sorted().compactMap { name -> [String]? in
                let sets = (grouped[name] ?? []).flatMap(\.sets).filter { $0.target != nil || $0.targetLoad != nil }
                guard !sets.isEmpty else { return nil }
                let done = sets.filter { $0.status == .complete }
                let skipped = sets.filter { $0.status == .skipped }.count
                marks += [
                    StudyBar(label: name, value: Double(sets.count), group: "Planned"),
                    StudyBar(label: name, value: Double(done.count), group: "Completed"),
                    StudyBar(label: name, value: Double(skipped), group: "Skipped"),
                ]
                return [
                    name, "\(sets.count)", "\(done.count)", "\(sets.filter { $0.status == .skipped }.count)",
                    "\(sets.compactMap(\.target).reduce(0,+))", "\(done.compactMap(\.reps).reduce(0,+))",
                ]
            }
            var result = table(
                id, "\(muscleLabel(Self.legs, "Leg")) work · finished workouts · \(recentLabel)",
                ["Exercise", "Planned", "Done", "Skipped", "Target reps", "Actual reps"], rows)
            result.alternateBars = marks
            result.xLabel = "Exercise"
            result.yLabel = "Working sets"
            return result
        case .effort:
            let slots = focusedLift(Self.squat).filter { $0.targetRIR != nil }.suffix(parameter(.sessions, 12))
            var targets: [StudyPoint] = []
            var ratings: [StudyPoint] = []
            var rows: [[String]] = []
            for s in slots {
                let t = s.date.timeIntervalSince1970
                let rating = s.done.compactMap(\.rating).last
                if let target = s.targetRIR { targets.append(.init(t, Double(target))) }
                if let rating { ratings.append(.init(t, Double(rating.rawValue))) }
                rows.append([day(s.date), s.targetRIR.map(String.init) ?? "—", rating?.valueText ?? "Unrated"])
            }
            return traces(
                id, "\(squatName) · latest \(parameter(.sessions, 12)) prescribed sessions", "Workout date",
                "Reps in reserve",
                [
                    .init(name: "Target", points: targets, style: .dots),
                    .init(name: "Reported", points: ratings, style: .dots),
                ], dates: true,
                summary: "Reported effort belongs to the rated last working set. A 5 is five or more reps left.",
                detail: StudyTable(columns: ["Date", "Target", "Reported"], rows: rows))
        case .lastCurl:
            let slots = focusedLift(Self.curl, includeEarlier: true).filter { $0.opening?.load == curlLoad }
            guard let current = slots.last(where: { includes($0.date) }),
                let prior = slots.last(where: {
                    $0.date < current.date && $0.routine == current.routine && $0.slot == current.slot
                        && $0.sets.map(\.target) == current.sets.map(\.target)
                })
            else { return StudyResult(id: id, scope: "\(curlName) · same routine at \(loadText(curlLoad))") }
            var marks: [StudyBar] = []
            let rows = (0..<max(current.sets.count, prior.sets.count)).map { i in
                func reps(_ s: StudySession) -> Int? {
                    guard s.sets.indices.contains(i), s.sets[i].status == .complete, s.sets[i].load == curlLoad else {
                        return nil
                    }
                    return s.sets[i].reps
                }
                let a = reps(prior)
                let b = reps(current)
                if let a { marks.append(.init(label: String(i + 1), value: Double(a), group: "Previous")) }
                if let b { marks.append(.init(label: String(i + 1), value: Double(b), group: "Selected")) }
                let delta = a.flatMap { first in b.map { String($0 - first) } }
                return ["\(i+1)", a.map(String.init) ?? "—", b.map(String.init) ?? "—", delta ?? "—"]
            }
            var result = table(
                id, "\(curlName) · matching slot at \(loadText(curlLoad))",
                ["Set", day(prior.date), day(current.date), "Change"],
                rows)
            result.alternateBars = marks
            result.xLabel = "Set position"
            result.yLabel = "Reps"
            return result
        case .benchSets:
            let setsTarget = parameter(.sets, 4)
            let benchLoad = parameter(.load, 1350)
            let candidates = focusedLift(Self.bench).filter { s in
                s.sets.count == setsTarget && s.done.allSatisfy { $0.load == benchLoad }
            }
            let prescription = candidates.last?.sets.map(\.target)
            let matched = candidates.filter { $0.sets.map(\.target) == prescription }.suffix(parameter(.sessions, 4))
            let series = matched.map { s in
                StudySeries(
                    name: day(s.date),
                    points: s.sets.enumerated().compactMap { i, set in
                        guard set.status == .complete, let r = set.reps else { return nil }
                        return .init(Double(i + 1), Double(r))
                    })
            }
            return traces(
                id, "\(benchName) · \(setsTarget) sets at \(loadText(benchLoad))", "Working-set position", "Reps", series)
        case .substitutions:
            let slots = sessions.filter { includes($0.date) && $0.planned == focusKey(Self.squat) && !$0.done.isEmpty }
            let grouped = Dictionary(grouping: slots, by: \.name)
            let rows = grouped.sorted {
                $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count
            }.map { name, group in
                [name, String(group.count), "\((100 * Double(group.count) / Double(slots.count)).studyNumber)%"]
            }
            var result = table(
                id, "Planned \(squatName) · completed slots", ["Performed exercise", "Slots", "Share"], rows,
                "Only slots retaining the original exercise are included.")
            result.alternateBars = grouped.keys.sorted().map { StudyBar(label: $0, value: Double(grouped[$0]?.count ?? 0)) }
            result.xLabel = "Performed exercise"
            result.yLabel = "Completed slots"
            return result
        case .exerciseOrder:
            let workouts = Dictionary(grouping: sessions, by: \.workout)
            let curls = focusedLift(Self.curl).filter { $0.opening?.load == curlLoad && $0.opening?.target != nil }
            let target = options.parameters[.reps] ?? curls.last?.opening?.target
            var early: [Int] = []
            var late: [Int] = []
            for s in curls where s.opening?.target == target {
                let slots = (workouts[s.workout] ?? []).filter { !$0.done.isEmpty }
                let times = slots.compactMap { $0.done.compactMap(\.logged).min() }
                guard !slots.contains(where: \.superset), times.count == slots.count, Set(times).count == times.count,
                    let t = s.opening?.logged, let rank = times.sorted().firstIndex(of: t), let reps = s.opening?.reps
                else { continue }
                if rank == 0 { early.append(reps) } else if rank >= 2 { late.append(reps) }
            }
            let groups = [("First", early), ("Third or later", late)].filter { !$0.1.isEmpty }
            let marks = groups.flatMap { name, reps -> [StudyCategoryPoint] in
                let observations = reps.map { StudyCategoryPoint(category: name, series: "Observed", value: Double($0)) }
                guard let median = Self.quantile(reps.map(Double.init)) else { return observations }
                return observations + [.init(category: name, series: "Median", value: median)]
            }
            let rows = groups.map { title, values in
                [
                    title, "\(values.count)", Self.quantile(values.map(Double.init))?.studyNumber ?? "—",
                    values.map(String.init).joined(separator: ", "),
                ]
            }
            return StudyResult(
                id: id, scope: "\(curlName) · opening set at \(loadText(curlLoad))",
                figure: marks.isEmpty ? nil : .comparison(marks, connected: false), xLabel: "Opening-set reps",
                yLabel: "Position",
                summary: "Order comes from the first working-set timestamps. Supersets and ambiguous orders are excluded.",
                detail: .init(columns: ["Position", "Sessions", "Median reps", "Observed reps"], rows: rows))
        case .returnToSquat:
            let matchLoad = parameter(.load, 1850)
            let minGap = parameter(.gapDays, 21)
            let slots = focusedLift(Self.squat, includeEarlier: true)
            let gap = slots.indices.dropFirst().last {
                includes(slots[$0].date) && days(slots[$0 - 1].date, slots[$0].date) >= minGap
            }
            guard let gap else {
                return StudyResult(
                    id: id, scope: "\(squatName) · after a \(minGap)-day logging gap",
                    emptyReason: "A gap of at least \(minGap) days and comparable sets on either side are needed.")
            }
            let before = slots[..<gap].filter { $0.opening?.load == matchLoad }.suffix(parameter(.lookback, 3)).compactMap {
                $0.opening?.reps
            }.map(
                Double.init)
            let after = slots[gap...].filter { $0.opening?.load == matchLoad }.prefix(parameter(.sessions, 6)).compactMap {
                $0.opening?.reps
            }
            guard let base = Self.quantile(before), !after.isEmpty else {
                return StudyResult(id: id, scope: "\(squatName) · \(loadText(matchLoad)) before and after a break")
            }
            let points = after.enumerated().map { StudyPoint(Double($0.offset + 1), Double($0.element)) }
            return traces(
                id, "\(squatName) · \(days(slots[gap-1].date,slots[gap].date)) days between logs", "Visit after return",
                "Reps at \(loadText(matchLoad))",
                [
                    .init(name: "Return visits", points: points),
                    .init(name: "Pre-gap median", points: [.init(1, base), .init(Double(after.count), base)], style: .fit),
                ],
                summary: "Baseline uses \(before.count) comparable pre-gap opening sets.")
        case .blocks:
            let slots = focusedLift(Self.squat, includeEarlier: true).filter { $0.block != nil && $0.best != nil }
            let grouped = Dictionary(grouping: slots, by: { $0.block! }).values.filter { group in
                group.contains { includes($0.date) }
            }.sorted { $0[0].date < $1[0].date }.suffix(parameter(.sessions, 3))
            let series = grouped.compactMap { group -> StudySeries? in
                let weeks = Dictionary(grouping: group, by: { $0.blockWeek ?? 0 })
                guard let first = weeks[1],
                    let base = Self.quantile(first.compactMap { $0.best.map { Double($0.tenthsPounds) } }), base > 0
                else { return nil }
                let points = weeks.keys.sorted().compactMap { week -> StudyPoint? in
                    guard let visits = weeks[week]?.filter({ includes($0.date) }),
                        let median = Self.quantile(visits.compactMap { $0.best.map { Double($0.tenthsPounds) } })
                    else { return nil }
                    return .init(Double(week), 100 * (median / base - 1))
                }
                return .init(name: "\(day(first[0].date)) · \(loadText(Int(base.rounded())))", points: points)
            }
            return traces(
                id, "\(squatName) · latest \(parameter(.sessions, 3)) recorded blocks", "Block week",
                "Change from week one (%)", series)
        default:
            let minutes = parameter(.minutes, 50)
            let lower = sessions.filter {
                includes($0.date) && $0.key == focusKey(Self.squat) && $0.finished && $0.seconds != nil && !$0.done.isEmpty
            }
            guard let routine = lower.last?.routine else {
                return StudyResult(id: id, scope: "\(squatName) workouts · \(minutes)-minute budget")
            }
            let workouts = Dictionary(grouping: lower.filter { $0.routine == routine }, by: \.workout)
            let mins = workouts.values.compactMap { $0[0].seconds.map { $0 / 60 } }.sorted()
            let points = mins.enumerated().map { StudyPoint($0.element, 100 * Double($0.offset + 1) / Double(mins.count)) }
            return traces(
                id, routine, "Workout minutes", "Sessions finished (%)",
                [.init(name: "Completed", points: points, style: .step)],
                summary:
                    "\(mins.filter { $0 <= Double(minutes) }.count) of \(mins.count) finished within \(minutes) minutes, excluding pauses."
            )
        }
    }
}
