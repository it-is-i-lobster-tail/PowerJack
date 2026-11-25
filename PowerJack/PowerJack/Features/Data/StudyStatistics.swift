import Foundation

extension StudyHistory {
    func statistics(_ id: TrainingStudy) -> StudyResult {
        let benchName = focusName(Self.bench, "Bench press")
        let squatName = focusName(Self.squat, "Back squat")
        switch id {
        case .repMix:
            let windows = comparisonWindows
            let slots = lift(focusKey(Self.bench)).filter {
                $0.date >= windows.previous.start && $0.date < windows.current.end
            }
            let baseline = slots.filter { $0.date < windows.current.start }.flatMap(\.done)
            let latest = slots.filter { $0.date >= windows.current.start }.flatMap(\.done)
            let shared = Set(baseline.compactMap(\.reps)).intersection(latest.compactMap(\.reps)).sorted()
            func mean(_ sets: [StudySet]) -> (Double, Int)? {
                let loads = sets.compactMap(\.load)
                guard !loads.isEmpty else { return nil }
                return (loads.map(weight).reduce(0, +) / Double(loads.count), loads.count)
            }
            var rows: [[String]] = []
            var marks: [StudyBar] = []
            for rep in shared.map(Optional.some) + [nil] {
                guard let a = mean(baseline.filter { rep == nil || $0.reps == rep }),
                    let b = mean(latest.filter { rep == nil || $0.reps == rep })
                else { continue }
                let label = rep.map { "\($0) reps" } ?? "All sets"
                marks.append(.init(label: label, value: a.0, group: "Prior"))
                marks.append(.init(label: label, value: b.0, group: "Selected"))
                rows.append([
                    rep.map { "\($0) reps" } ?? "All sets", "\(a.0.studyNumber) · \(a.1) sets",
                    "\(b.0.studyNumber) · \(b.1) sets", (b.0 - a.0).studyNumber,
                ])
            }
            var result = table(
                id, "\(benchName) · successive \(days(windows.current.start,windows.current.end))-day periods",
                ["Rep count", "Prior (\(unit.symbol))", "Latest (\(unit.symbol))", "Change"], rows,
                "Compare mean working weight within the same rep count. The overall average also reflects the mix of sets.")
            result.alternateBars = marks
            result.xLabel = "Rep count"
            result.yLabel = "Mean load (\(unit.symbol))"
            return result
        case .relationship:
            return liftRelationship()
        case .typicalBench:
            let values = estimatePoints(focusedLift(Self.bench, includeEarlier: true))
            guard let current = values.last, includes(Date(timeIntervalSince1970: current.x)), values.count >= 5 else {
                return StudyResult(
                    id: id, scope: "\(benchName) · recent estimated maxes",
                    emptyReason:
                        "Log at least five eligible sessions for this exercise to compare the latest estimate with earlier sessions."
                )
            }
            let prior = Array(values.dropLast().suffix(parameter(.lookback, 12)))
            let lower = Self.quantile(prior.map(\.y), 0.25)!
            let upper = Self.quantile(prior.map(\.y), 0.75)!
            let span = [prior[0].x, current.x]
            return traces(
                id, "\(benchName) · previous \(prior.count) eligible sessions", "Workout date",
                "Estimated max (\(unit.symbol))",
                [
                    .init(name: "Prior estimates", points: prior, style: .dots),
                    .init(name: "Latest", points: [current], style: .dots),
                    .init(name: "25th percentile", points: span.map { .init($0, lower) }, style: .fit),
                    .init(name: "75th percentile", points: span.map { .init($0, upper) }, style: .fit),
                ], dates: true,
                summary:
                    "Latest \(current.y.studyNumber) \(unit.symbol). The middle half of prior estimates spanned \(lower.studyNumber)–\(upper.studyNumber) \(unit.symbol)."
            )
        case .forecast:
            let values = estimatePoints(focusedLift(Self.bench, includeEarlier: true))
            let lookback = parameter(.lookback, 3)
            let eligible = values.indices.filter { $0 >= lookback && includes(Date(timeIntervalSince1970: values[$0].x)) }
                .suffix(parameter(.sessions, 12))
            guard values.count >= max(5, lookback + 1), !eligible.isEmpty else {
                return StudyResult(
                    id: id, scope: "\(benchName) · one session ahead",
                    emptyReason:
                        "An in-period estimate needs \(lookback) earlier eligible estimates. At least \(max(5, lookback + 1)) estimates are needed overall."
                )
            }
            var observed: [StudyPoint] = []
            var rolling: [StudyPoint] = []
            var previous: [StudyPoint] = []
            var medianError = 0.0
            var previousError = 0.0
            for i in eligible {
                let value = values[i]
                let last = values[i - 1].y
                let median = Self.quantile(values[(i - lookback)..<i].map(\.y))!
                observed.append(value)
                rolling.append(.init(value.x, median))
                previous.append(.init(value.x, last))
                medianError += abs(median - value.y)
                previousError += abs(last - value.y)
            }
            let n = Double(observed.count)
            return traces(
                id, "\(benchName) · latest \(observed.count) scored workouts", "Workout date",
                "Estimated max (\(unit.symbol))",
                [
                    .init(name: "Observed", points: observed), .init(name: "Prior \(lookback) median", points: rolling),
                    .init(name: "Prior session", points: previous),
                ], dates: true,
                summary:
                    "Mean absolute error was \((medianError/n).studyNumber) \(unit.symbol) for the median and \((previousError/n).studyNumber) \(unit.symbol) for the prior session."
            )
        case .squatSuccess:
            let repsTarget = parameter(.reps, 5)
            let openings = focusedLift(Self.squat).compactMap(\.opening).filter { $0.target == repsTarget && $0.reps != nil }
            let loads =
                options.exerciseKeys.isEmpty && options.parameters[.reps] == nil
                ? [2050, 2150, 2250] : Set(openings.compactMap(\.load)).sorted()
            let counts = loads.compactMap { load -> StudyCount? in
                let attempts = openings.filter { $0.load == load }
                guard !attempts.isEmpty else { return nil }
                let made = attempts.filter { ($0.reps ?? 0) >= repsTarget }.count
                return StudyCount(label: loadText(load), made: made, attempts: attempts.count)
            }
            return StudyResult(
                id: id, scope: "\(squatName) · first sets prescribed for \(repsTarget) reps",
                figure: counts.isEmpty ? nil : .attempts(counts),
                summary:
                    "Each filled dot is an opening set that reached \(repsTarget) reps. Each ring is a logged attempt that fell short."
            )
        default:
            let grouped = Dictionary(grouping: focusedLift(Self.squat), by: { week($0.date) })
            guard !grouped.isEmpty else { return StudyResult(id: id, scope: "\(squatName) · estimate eligibility") }
            var marks: [StudyBar] = []
            let rows = recentWeeks.map { date in
                let workouts = Dictionary(grouping: grouped[date] ?? [], by: \.workout)
                var eligible = 0
                var high = 0
                for s in workouts.values {
                    if s.contains(where: { $0.best != nil }) {
                        eligible += 1
                    } else if s.flatMap(\.done).allSatisfy({ ($0.reps ?? 0) > StrengthRules.e1rmMaxReps }) {
                        high += 1
                    }
                }
                let label = scopeDate(date)
                marks += [
                    StudyBar(label: label, value: Double(eligible), group: "Eligible"),
                    StudyBar(label: label, value: Double(high), group: "High reps only"),
                    StudyBar(label: label, value: Double(workouts.count - eligible - high), group: "Other / missing"),
                ]
                return [
                    label, String(eligible), String(high), String(workouts.count - eligible - high),
                    String(workouts.count),
                ]
            }
            var result = table(
                id, "\(squatName) · \(weeksLabel)", ["Week", "Eligible", "High reps only", "Other / missing", "Sessions"],
                rows,
                "An eligible set takes precedence. Zero sessions means no squat workout was logged that week.")
            result.alternateBars = marks
            result.xLabel = "Week"
            result.yLabel = "Sessions"
            return result
        }
    }

    func relationshipVerticalKey(for horizontal: String) -> String? {
        if let selected = options.secondExercise { return selected }
        let candidates = Dictionary(grouping: sessions.filter {
            $0.key != horizontal && $0.perLegLunge && includes($0.date) && $0.best != nil
        }, by: \.key)
        return candidates.values.sorted { left, right in
            left.count == right.count ? left[0].key < right[0].key : left.count > right.count
        }.first?.first?.key
    }

    private func liftRelationship() -> StudyResult {
        let id = TrainingStudy.relationship
        let xKey = focusKey(Self.squat)
        let xName = focusName(Self.squat, "Back squat")
        let xSlots = lift(xKey).filter { $0.loaded && includes($0.date) }
        let yKey = relationshipVerticalKey(for: xKey)
        let yName = yKey.map { exerciseName(for: $0) } ?? "Barbell reverse lunge"
        let scope = "\(xName) and \(yName) · changes over paired weeks"
        guard let yKey, yKey != xKey else {
            return StudyResult(
                id: id, scope: scope, emptyReason: "Choose two different loaded exercises with overlapping weekly estimates."
            )
        }
        let ySlots = lift(yKey).filter { $0.loaded && includes($0.date) }
        func weekly(_ slots: [StudySession]) -> [Date: Double] {
            Dictionary(grouping: estimatePoints(slots), by: { week(Date(timeIntervalSince1970: $0.x)) }).compactMapValues {
                Self.quantile($0.map(\.y))
            }
        }
        let a = weekly(xSlots)
        let b = weekly(ySlots)
        let weeks = Set(a.keys).intersection(b.keys).sorted()
        guard let first = weeks.first else { return StudyResult(id: id, scope: scope) }
        var pairs: [StudyPoint] = []
        var rows: [[String]] = []
        for start in weeks where (days(first, start) / 7).isMultiple(of: 2) {
            let end = offset(start, days: 7)
            if let range = selectedRange,
                start < range.start || offset(end, days: 7) > range.end
            {
                continue
            }
            guard let x0 = a[start], let x1 = a[end], let y0 = b[start], let y1 = b[end] else { continue }
            pairs.append(.init(x1 - x0, y1 - y0))
            rows.append([day(start), (x1 - x0).studyNumber, (y1 - y0).studyNumber])
        }
        let columns = ["Starting week", "\(xName) Δ (\(unit.symbol))", "\(yName) Δ (\(unit.symbol))"]
        guard pairs.count >= 8, let fit = StudyRegression.fit(pairs),
            let lo = pairs.map(\.x).min(), let hi = pairs.map(\.x).max()
        else {
            var result = table(
                id, scope, columns, rows,
                "Paired history only. A slope requires at least eight non-overlapping comparisons with variation in the horizontal exercise."
            )
            result.emptyReason = "Both lifts need eligible estimates in the same two consecutive weeks."
            return result
        }
        let increment = weight(50)
        let interval =
            StudyRegression.slopeInterval(pairs).map { bounds in
                " The approximate 95% interval is \((bounds.0*increment).studyNumber) to \((bounds.1*increment).studyNumber) \(unit.symbol)."
            } ?? ""
        return traces(
            id, scope, "\(xName) change (\(unit.symbol))", "\(yName) change (\(unit.symbol))",
            [
                .init(name: "Paired weeks", points: pairs, style: .dots),
                .init(
                    name: "Fitted average", points: [lo, hi].map { .init($0, fit.intercept + fit.slope * $0) }, style: .fit),
            ],
            summary:
                "Across \(pairs.count) periods, an additional \(increment.studyNumber) \(unit.symbol) of \(xName) progress was associated with \((fit.slope*increment).studyNumber) \(unit.symbol) of \(yName) change on average."
                + interval,
            detail: StudyTable(columns: columns, rows: rows))
    }
}

enum StudyRegression {
    static func fit(_ points: [StudyPoint]) -> (slope: Double, intercept: Double)? {
        guard points.count > 1 else { return nil }
        let n = Double(points.count)
        let x = points.map(\.x).reduce(0, +) / n
        let y = points.map(\.y).reduce(0, +) / n
        var variance = 0.0
        var covariance = 0.0
        for p in points {
            variance += (p.x - x) * (p.x - x)
            covariance += (p.x - x) * (p.y - y)
        }
        guard variance > 0.000001 else { return nil }
        let slope = covariance / variance
        return (slope, y - slope * x)
    }

    /// Circular moving blocks retain adjacent pairs. Use reproducible resampling for an unchanged chart.
    static func slopeInterval(_ points: [StudyPoint]) -> (Double, Double)? {
        var state: UInt64 = 71
        var slopes: [Double] = []
        for _ in 0..<1000 {
            var sample: [StudyPoint] = []
            while sample.count < points.count {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let start = Int((state >> 32) % UInt64(points.count))
                for j in 0..<min(3, points.count - sample.count) { sample.append(points[(start + j) % points.count]) }
            }
            if let result = fit(sample) { slopes.append(result.slope) }
        }
        guard slopes.count >= 950, let lo = StudyHistory.quantile(slopes, 0.025),
            let hi = StudyHistory.quantile(slopes, 0.975)
        else { return nil }
        return (lo, hi)
    }
}
