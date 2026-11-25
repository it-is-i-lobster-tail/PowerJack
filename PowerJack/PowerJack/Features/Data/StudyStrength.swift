import Foundation

extension StudyHistory {
    func strength(_ id: TrainingStudy) -> StudyResult {
        let squats = focusedLift(Self.squat)
        let squatName = focusName(Self.squat, "Back squat")
        let benchName = focusName(Self.bench, "Bench press")
        let repsTarget = parameter(.reps, 5)
        let loadTarget = parameter(.load, 1850)
        switch id {
        case .legMax:
            let groups = muscles(Self.legs)
            let legs = sessions.filter {
                includes($0.date) && exerciseMatches($0) && $0.primary.map(groups.contains) == true && $0.loaded
            }
            let grouped = Dictionary(grouping: legs, by: \.key)
            let series = grouped.values.sorted { ($0.first?.name ?? "") < ($1.first?.name ?? "") }.map {
                StudySeries(name: $0[0].name, points: estimatePoints($0))
            }
            let rows = legs.compactMap { s -> [String]? in
                guard let best = s.best,
                    let set = s.done.first(where: {
                        let e = ProgramExerciseHistory.estimate(load: $0.load, reps: $0.reps, rating: $0.rating)
                        return e?.tenthsPounds == best.tenthsPounds && e?.hasRecordedRIR == best.hasRecordedRIR
                    })
                else { return nil }
                return [
                    day(s.date), s.name, set.load.map(loadText) ?? "—", set.reps.map(String.init) ?? "—",
                    set.rating?.valueText ?? "—", loadText(best.tenthsPounds),
                ]
            }
            var result = traces(
                id, "\(muscleLabel(Self.legs, "Leg")) lifts · session bests", "Workout date",
                "Estimated max (\(unit.symbol))", series, dates: true,
                summary:
                    "Each series is a different lift. The source set shows its recorded load, reps and available reps in reserve.",
                detail: StudyTable(columns: ["Date", "Lift", "Load", "Reps", "RIR", "Estimate"], rows: rows.reversed()))
            if case .traces(let eligible, _) = result.figure { result.figure = .liftPanels(eligible) }
            return result
        case .records:
            let byReps = Dictionary(
                grouping: squats.flatMap { s in
                    s.done.compactMap { set -> (Int, Int, Date, String)? in
                        guard let r = set.reps, options.parameters[.reps].map({ $0 == r }) ?? true, let load = set.load
                        else { return nil }
                        return (r, load, s.date, s.workout)
                    }
                }, by: { $0.0 })
            let rows = byReps.keys.sorted().compactMap { reps -> [String]? in
                guard let logged = byReps[reps], let best = logged.map(\.1).max() else { return nil }
                let ties = logged.filter { $0.1 == best }.sorted { $0.2 < $1.2 }
                return [
                    "\(reps)", loadText(best), day(ties[0].2), "\(Set(ties.map(\.3)).count)", day(ties[ties.count - 1].2),
                ]
            }
            var result = table(
                id, "\(squatName) · exact rep counts", ["Reps", "Best load", "First", "Sessions", "Latest"], rows)
            result.alternateBars = byReps.keys.sorted().compactMap { reps in
                byReps[reps]?.map(\.1).max().map { StudyBar(label: String(reps), value: weight($0)) }
            }
            result.xLabel = "Exact reps"
            result.yLabel = "Best load (\(unit.symbol))"
            return result
        case .fixedSquat:
            let points = squats.compactMap { s -> StudyPoint? in
                guard let first = s.opening, first.load == loadTarget, let reps = first.reps else { return nil }
                return StudyPoint(s.date.timeIntervalSince1970, Double(reps))
            }
            return traces(
                id, "\(squatName) · first working set at \(loadText(loadTarget))", "Workout date", "Reps",
                [.init(name: "First set", points: points)], dates: true)
        case .milestones:
            var best = Int.min
            var dates: [StudyPoint] = []
            var records: [StudyPoint] = []
            for s in focusedLift(Self.squat, includeEarlier: true) {
                guard let load = s.done.filter({ ($0.reps ?? 0) >= repsTarget }).compactMap(\.load).max() else { continue }
                best = max(best, load)
                guard includes(s.date) else { continue }
                let time = s.date.timeIntervalSince1970
                dates.append(.init(time, weight(load)))
                records.append(.init(time, weight(best)))
            }
            return traces(
                id, "\(squatName) · at least \(repsTarget) reps", "Workout date", "Load (\(unit.symbol))",
                [
                    .init(name: "Session best", points: dates, style: .dots),
                    .init(name: "Record", points: records, style: .step),
                ], dates: true)
        case .repeatBench:
            let setsTarget = parameter(.sets, 3)
            let slots = focusedLift(Self.bench).filter { s in
                s.sets.count == setsTarget && s.sets.allSatisfy { $0.target == repsTarget && $0.targetLoad == loadTarget }
            }
            let points = slots.map { s in
                StudyPoint(
                    s.date.timeIntervalSince1970,
                    Double(
                        s.done.filter { set in set.load.map { $0 >= loadTarget } == true && (set.reps ?? 0) >= repsTarget }
                            .count))
            }
            return traces(
                id, "\(benchName) · \(setsTarget) sets of \(repsTarget) at \(loadText(loadTarget))", "Workout date",
                "Qualifying sets",
                [.init(name: "Sets reaching target", points: points)], dates: true)
        case .yearlyRecords:
            let keys =
                options.exerciseKeys.isEmpty
                ? [Self.squat, Self.bench, "catalog:barbell-deadlift", "catalog:barbell-row"] : options.exerciseKeys
            var rows: [[String]] = []
            var marks: [StudyCategoryPoint] = []
            let comparesPeriod = options.period != .all
            for key in keys {
                let slots = lift(key)
                let observed = slots.flatMap { s in
                    s.done.compactMap { set -> (Int, Date)? in
                        guard set.reps == repsTarget, let load = set.load else { return nil }
                        return (load, s.date)
                    }
                }
                guard let all = observed.max(by: { $0.0 < $1.0 }) else { continue }
                let year = observed.filter { inYear($0.1) }.max(by: { $0.0 < $1.0 })
                let liftName = slots[0].name
                marks.append(.init(category: liftName, series: "Lifetime", value: weight(all.0)))
                if comparesPeriod {
                    if let year { marks.append(.init(category: liftName, series: annualLabel, value: weight(year.0))) }
                    rows.append([liftName, year.map { loadText($0.0) } ?? "—", loadText(all.0), day(all.1)])
                } else {
                    rows.append([liftName, loadText(all.0), day(all.1)])
                }
            }
            return StudyResult(
                id: id,
                scope: "Actual \(repsTarget)-rep sets · " + (comparesPeriod ? "\(annualLabel) and lifetime" : annualLabel),
                figure: marks.isEmpty ? nil : .comparison(marks, connected: comparesPeriod),
                xLabel: "Best load (\(unit.symbol))",
                yLabel: "Lift",
                detail: .init(
                    columns: comparesPeriod
                        ? ["Lift", annualLabel, "Lifetime", "Best date"] : ["Lift", "Lifetime", "Best date"], rows: rows))
        case .goal:
            let goalReps = parameter(.goalReps, 1000)
            var count = 0
            let grouped = Dictionary(grouping: squats.filter { inYear($0.date) }, by: { calendar.startOfDay(for: $0.date) })
            let points = grouped.keys.sorted().map { date in
                count += (grouped[date] ?? []).flatMap(\.done).compactMap(\.reps).reduce(0, +)
                return StudyPoint(date.timeIntervalSince1970, Double(count))
            }
            let goal = [
                StudyPoint(yearStart.timeIntervalSince1970, Double(goalReps)),
                StudyPoint(offset(yearEnd, days: -1).timeIntervalSince1970, Double(goalReps)),
            ]
            return traces(
                id, "\(goalReps.formatted()) \(squatName) reps · \(annualLabel)", "Date", "Reps",
                points.isEmpty
                    ? []
                    : [
                        .init(name: "Completed", points: points, style: .step),
                        .init(name: "Goal", points: goal, style: .fit),
                    ],
                dates: true, summary: "\(count) completed reps · \(max(0,goalReps-count)) remaining.")
        case .pushups:
            let setsTarget = parameter(.sets, 3)
            let slots = focusedLift("catalog:push-up").filter {
                $0.repsOnly && $0.sets.count == setsTarget && $0.done.compactMap(\.reps).count == setsTarget
            }
            let best = slots.map { StudyPoint($0.date.timeIntervalSince1970, Double($0.done.compactMap(\.reps).max() ?? 0)) }
            let totals = slots.map {
                StudyPoint($0.date.timeIntervalSince1970, Double($0.done.compactMap(\.reps).reduce(0, +)))
            }
            return traces(
                id, "\(focusName("catalog:push-up", "Push Up")) · \(setsTarget) completed working sets", "Workout date",
                "Reps",
                [.init(name: "Best set", points: best), .init(name: "Session total", points: totals)], dates: true)
        default:
            let latest = squats.filter { $0.loaded && $0.done.allSatisfy { $0.load != nil && $0.reps != nil } }.suffix(2)
            let rows = latest.map { s in
                let reps = s.done.compactMap(\.reps).reduce(0, +)
                let volume = s.done.reduce(0.0) { $0 + weight($1.load ?? 0) * Double($1.reps ?? 0) }
                let loads = Set(s.done.compactMap(\.load)).sorted().map(loadText).joined(separator: " / ")
                return [day(s.date), "\(s.done.count)", "\(reps)", loads, volume.studyNumber]
            }
            var result = table(
                id, "\(squatName) · latest two sessions", ["Session", "Sets", "Reps", "Loads", "\(unit.symbol)·reps"],
                rows.count == 2 ? rows : [],
                "Volume load sums external load × completed reps across working sets.")
            if rows.count == 2 {
                result.alternateBars = latest.map { slot in
                    StudyBar(
                        label: day(slot.date),
                        value: slot.done.reduce(0) { $0 + weight($1.load ?? 0) * Double($1.reps ?? 0) })
                }
                result.xLabel = "Session"
                result.yLabel = "Volume load (\(unit.symbol)·reps)"
            }
            return result
        }
    }
}
