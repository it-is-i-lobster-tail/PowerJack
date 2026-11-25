import Foundation

extension LoggedStudyQuestion {
    /// Keep both operands of a calendar-month comparison visible in the answer.
    func monthComparison(_ h: StudyHistory) -> StudyResult? {
        let calendar = h.calendar
        let named = Self.months(in: text)
        let previous = text.contains("last month") || text.contains("previous month")
        let compares = ["than", "compared", "compare", "change", "difference", "from", "versus", " vs ", "since"]
        guard compares.contains(where: text.contains), named.count == 2 || previous else { return nil }
        let words = Set(text.split(separator: " ").map(String.init))
        let years = words.compactMap(Int.init).filter { (1900...2199).contains($0) }
        guard years.count <= 1 else { return nil }
        let year = years.first ?? calendar.component(.year, from: h.today)
        let anchor = named.max() ?? calendar.component(.month, from: h.today)
        guard let date = calendar.date(from: DateComponents(year: year, month: anchor)),
              let later = calendar.dateInterval(of: .month, for: date) else { return nil }
        let earlierDate = named.count == 2
            ? calendar.date(from: DateComponents(year: year, month: named.min()))
            : calendar.date(byAdding: .month, value: -1, to: date)
        guard let earlierDate, let earlier = calendar.dateInterval(of: .month, for: earlierDate) else { return nil }

        let label: String
        let study: TrainingStudy
        if words.contains("sessions") || words.contains("workouts") {
            guard liftNames.isEmpty, muscles.isEmpty,
                  words.isDisjoint(with: ["duration", "longer", "sets", "volume", "average", "skipped", "minutes", "hours", "shorter"]) else { return nil }
            label = "Completed workouts"
            study = .frequency
        } else if text.contains("working set") || text.contains("set count") {
            guard words.isDisjoint(with: ["average", "hard", "rated", "skipped", "failure", "heaviest"]) else { return nil }
            label = "Completed working sets"
            study = .sessionLedger
        } else if words.contains("volume") && words.contains("total") {
            label = "External volume (" + h.unit.symbol + " × reps)"
            study = .tonnage
        } else { return nil }

        var values: [Double] = []
        var rows: [[String]] = []
        for period in [earlier, later] {
            let workouts = h.workouts.filter { $0.date.map { period.start <= $0 && $0 < period.end } == true }
            var recorded = !workouts.isEmpty
            let count: Double
            if study == .frequency {
                count = Double(workouts.filter { $0.status == .complete }.count)
            } else {
                let matching = h.sessions.filter { slot in
                    period.start <= slot.date && slot.date < period.end
                        && (liftNames.isEmpty || liftNames.contains { matchesLift(slot, named: $0) })
                        && (muscles.isEmpty || slot.primary.map(muscles.contains) == true)
                }
                let sets = matching.flatMap(\.done)
                if study == .tonnage {
                    let external = matching.filter { !$0.repsOnly }.flatMap(\.done)
                    let volumes = external.compactMap { set -> Double? in
                        guard let reps = set.reps, let load = set.load else { return nil }
                        return h.weight(load) * Double(reps)
                    }
                    recorded = recorded && !sets.isEmpty && external.count == volumes.count
                    count = volumes.reduce(0, +)
                } else {
                    count = Double(sets.count)
                }
            }
            if recorded { values.append(count) }
            rows.append([calendar.monthSymbols[calendar.component(.month, from: period.start) - 1] + " " +
                         String(calendar.component(.year, from: period.start)), recorded ? count.studyNumber : "Insufficient records"])
        }
        let summary: String
        if values.count == 2 {
            let change = values[1] - values[0]
            summary = "\(rows[1][0]) had \(values[1].studyNumber) and \(rows[0][0]) had \(values[0].studyNumber). " +
                (change == 0 ? "Both months had the same total." : "\(abs(change).studyNumber) \(change > 0 ? "more" : "fewer") in \(rows[1][0]).")
        } else {
            summary = "A comparison needs workout history in both months."
        }
        var result = answer(study, label + " by month", summary, columns: ["Month", label], rows: rows, insufficient: values.count != 2)
        result.scope = rows.map { $0[0] }.joined(separator: " and ")
        return result
    }
}
