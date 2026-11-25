import Foundation

extension LoggedStudyQuestion {
    /// Direct questions about recorded work use completed working sets, excluding warm-ups.
    /// Keep these routes narrow so a comparison or an extra condition cannot become an unfiltered total.
    func loggedMetricAnswer(_ h: StudyHistory) -> StudyResult? {
        guard (!text.contains(" than ") || text.contains("more than eight reps on one set")), !text.contains(" versus "), !text.contains(" change "),
              !text.contains("compared"), liftNames.count <= 1 else { return nil }

        let selected = sessions(h).filter { !$0.done.isEmpty }
        let sets = selected.flatMap(\.done)
        let ranked = selected.sorted { ($0.date, $0.slot) < ($1.date, $1.slot) }
        let dates = Set(selected.map { h.calendar.startOfDay(for: $0.date) }).sorted()
        let visits = h.workouts.filter { $0.status == .complete && $0.date.map(includes) == true }
        let scope = liftNames.first ?? muscles.map(\.rawValue).sorted().joined(separator: ", ")
        func has(_ phrase: String) -> Bool { text.contains(phrase) }
        func table(_ title: String, _ columns: [String], _ rows: [[String]], _ detail: String) -> StudyResult {
            answer(.sessionLedger, title, detail, columns: columns, rows: rows, scope: scope.isEmpty ? nil : scope)
        }
        func number(_ title: String, _ value: String, _ detail: String) -> StudyResult {
            table(title, [title], [[value]], detail)
        }
        func missing(_ title: String, _ detail: String) -> StudyResult {
            table(title, [], [], detail)
        }
        if has("longest stretch") && (has("whole days off between two") || has("no workouts inside"))
            || has("most widely spaced consecutive workouts") {
            let wholeDays = !has("days apart")
            var bounds = Set(visits.compactMap { $0.date.map { h.calendar.startOfDay(for: $0) } }).sorted()
            if has("no workouts inside"), let interval {
                bounds.insert(h.offset(interval.start, days: -1), at: 0)
                bounds.append(min(interval.end, h.offset(h.calendar.startOfDay(for: h.today), days: 1)))
                if bounds.last! <= bounds.first! {
                    return missing("Days without a workout", "The requested period has no observed days.")
                }
            }
            let pairs = zip(bounds,bounds.dropFirst()).map { ($0, $1, h.days($0,$1) - (wholeDays ? 1 : 0)) }
            guard let best = pairs.map(\.2).max() else { return missing("Longest gap", "Two workout dates are needed to measure an interval.") }
            let title = wholeDays ? "Whole days off" : "Calendar days apart"
            let rows = pairs.filter { $0.2 == best }.map { pair in
                [h.day(wholeDays && best > 0 ? h.offset(pair.0, days: 1) : pair.0),
                 h.day(wholeDays && best > 0 ? h.offset(pair.1, days: -1) : pair.1), String(best)]
            }
            return table(title, ["Start", "End", title], rows, "\(best) \(title.lowercased()) in the longest recorded gap.")
        }
        if has("separate") && has("dates did i log") || has("how many days did i train") && !liftNames.isEmpty
            || has("how many days have i trained") && !liftNames.isEmpty {
            return number("Training dates", String(dates.count), "\(dates.count) distinct dates with completed working sets.")
        }
        if has("which date was my first") || has("what was the first") && has("workout where i did")
            || has("when did i last train") {
            guard let date = has("last") ? dates.last : dates.first else { return missing("Training date", "No matching completed sets were recorded.") }
            return number(has("last") ? "Last training date" : "First training date", h.day(date), "Date of a matching completed working set.")
        }
        if has("how many different exercises") {
            let names = Dictionary(grouping: selected, by: \.key).values.compactMap { $0.first?.name }.sorted()
            return number("Distinct exercises", String(names.count), names.joined(separator: ", "))
        }
        if has("workouts fell on a ") || has("training dates fell on a ") {
            guard let weekday = h.calendar.weekdaySymbols.firstIndex(where: { has($0.lowercased()) }) else { return nil }
            let fraction = has("fraction")
            let sample = fraction ? Set(visits.compactMap { $0.date.map { h.calendar.startOfDay(for: $0) } }).sorted() : visits.compactMap(\.date)
            let count = sample.filter { h.calendar.component(.weekday, from: $0) == weekday + 1 }.count
            guard !fraction || !sample.isEmpty else { return missing("Training dates", "No training dates in the selected period.") }
            return number(h.calendar.weekdaySymbols[weekday], fraction ? "\(count)/\(sample.count)" : String(count), "\(count) of \(sample.count) recorded \(fraction ? "training dates" : "workouts").")
        }
        if has("which days of the week did i lift") {
            let counts = Dictionary(grouping: Set(visits.compactMap { $0.date.map { h.calendar.startOfDay(for: $0) } })) { h.calendar.component(.weekday, from: $0) }
            return table("Training dates by weekday", ["Weekday", "Dates"], counts.keys.sorted().map { [h.calendar.weekdaySymbols[$0-1], String(counts[$0]!.count)] }, "Each calendar date counts once.")
        }
        if has("median number of working sets per workout") || has("median number of sets per workout") {
            let byWorkout = Dictionary(grouping: selected, by: \.workout)
            let counts = visits.map { Double(byWorkout[$0.key, default: []].flatMap(\.done).count) }
            guard let median = StudyHistory.quantile(counts) else { return missing("Median working sets", "No completed workouts in this period.") }
            return number("Median working sets per workout", median.studyNumber, "\(visits.count) completed workouts.")
        }
        if has("which dates did i log at least ten working sets") || has("workout dates tied for the most total reps") {
            let byDay = Dictionary(grouping: selected) { h.calendar.startOfDay(for: $0.date) }
            let reps = has("total reps")
            let counts = byDay.mapValues { slots in
                reps ? slots.flatMap(\.done).compactMap(\.reps).reduce(0,+) : slots.flatMap(\.done).count
            }
            let threshold = reps ? counts.values.max() ?? 0 : 10
            let rows = counts.keys.sorted().filter { counts[$0]! >= threshold }.map { [h.day($0), String(counts[$0]!)] }
            return answer(.sessionLedger, reps ? "Most reps in one day" : "Dates with ten or more working sets", "\(rows.count) matching dates.", columns: ["Date", reps ? "Reps" : "Sets"], rows: rows, insufficient: false)
        }
        if has("most working sets") && has("primary muscle groups") {
            let counts = Dictionary(grouping: selected.filter { $0.primary != nil }, by: { $0.primary! }).mapValues { $0.flatMap(\.done).count }
            let maxCount = counts.values.max()
            let rows = counts.keys.filter { counts[$0] == maxCount }.sorted { $0.rawValue < $1.rawValue }.map { [$0.rawValue.capitalized, String(counts[$0]!)] }
            return table("Most direct working sets", ["Primary muscle", "Sets"], rows, "Each completed set counts toward its primary muscle.")
        }
        if has("how much time did i spend training") || has("length of my longest") && has("workout in minutes") || has("how long did my") && has("workouts take") {
            let timed = visits.compactMap(\.seconds).filter { $0 > 0 }
            guard let longest = timed.max() else { return missing("Workout duration", "No completed workouts have a recorded duration in this period.") }
            if has("workouts take") {
                let rows = visits.compactMap { visit -> [String]? in
                    guard let seconds = visit.seconds, seconds > 0, let date = visit.date else { return nil }
                    return [h.day(date), visit.template, (seconds / 60).studyNumber]
                }
                return table("Workout durations", ["Date", "Workout", "Minutes"], rows, "\(timed.count) completed workouts have recorded durations.")
            }
            return number(has("longest") ? "Longest workout (min)" : "Total recorded minutes", ((has("longest") ? longest : timed.reduce(0,+))/60).studyNumber, "\(timed.count) of \(visits.count) completed workouts have a duration.")
        }
        if !["planned", "scheduled", "percent", "fraction", "share", "%"].contains(where: has),
           (has("workouts") || has("sessions")) && (has("did i finish") || has("did i actually finish") || has("have i completed since january") || has("had i logged this year") || has("had i logged since january")) && scope.isEmpty && !has(" per ") {
            return answer(.frequency, "Completed workouts", "\(visits.count) completed workouts.", columns: ["Date", "Template", "Status"], rows: visits.reversed().compactMap { visit in
                visit.date.map { [h.day($0), visit.template, visit.status.rawValue.capitalized] }
            }, insufficient: false)
        }

        if has("best rep count at my heaviest") || has("heaviest load i used for") || has("heaviest") && has("each time i hit it") {
            guard let maxLoad = sets.compactMap(\.load).max() else { return missing("Heaviest logged load", "No completed set has a recorded external load.") }
            let top = ranked.flatMap { slot in slot.done.filter { $0.load == maxLoad }.map { (slot.date, $0.reps) } }
            let best = top.compactMap(\.1).max().map(String.init) ?? "Unrecorded"
            return table("Heaviest logged load", ["Date", "Load", "Reps"], top.map { [h.day($0.0), h.loadText(maxLoad), $0.1.map(String.init) ?? "—"] }, "Heaviest external load: \(h.loadText(maxLoad)). Best rep count at this load: \(best).")
        }
        if has("highest rep count on a single") || has("most reps i got on one set") {
            guard let best = sets.compactMap(\.reps).max() else { return missing("Most reps on one set", "No recorded working-set reps.") }
            return number("Most reps on one set", String(best), "Highest rep count among completed working sets.")
        }
        if has("very last set of"), has("how many reps") {
            guard let last = ranked.last, let reps = last.done.last?.reps else { return missing("Latest set", "No rep count on a matching final set.") }
            return number("Last set reps", String(reps), "\(last.name) · \(h.day(last.date))")
        }
        if has("what was my last"), has("what loads and reps"), let last = ranked.last {
            let rows = ranked.filter { $0.workout == last.workout }.flatMap(\.done).enumerated().map { index, set in
                [String(index+1), set.load.map(h.loadText) ?? "—", set.reps.map(String.init) ?? "—"]
            }
            return table("Last matching session", ["Set","Load","Reps"], rows, "\(last.name) · \(h.day(last.date))")
        }
        if has("reps did i accumulate") || has("reps did i do across all of") || has("push up reps did i log") {
            let reps = sets.compactMap(\.reps)
            return number("Total recorded reps", String(reps.reduce(0,+)), "\(reps.count) sets with recorded reps.")
        }
        if has("sets did i complete") || has("how many working sets for") && has("did i complete") || has("training sets had i completed this year") {
            return number("Completed working sets", String(sets.count), "Excludes warm-up sets.")
        }
        if has("total external volume") || has("how much external volume did i log") || has("volume came from") && has("exact pounds") || has("total logged volume") && has("zero added pounds") {
            let volume = sets.compactMap { set -> Double? in
                guard let load = set.load, let reps = set.reps else { return nil }
                return Double(load) * Double(reps) / 10
            }
            guard !volume.isEmpty else { return missing("External volume", "No completed sets have both a recorded load and reps.") }
            return number("External volume (lb·reps)", volume.reduce(0,+).studyNumber, "Logged pounds × reps across \(volume.count) sets with both measurements.")
        }
        let ratings = sets.compactMap(\.rating)
        if has("sets actually have a reps in reserve entry") || has("sets had an effort rating recorded") {
            return number("Sets with reported RIR", String(ratings.count), "\(ratings.count) of \(sets.count) completed working sets have a rating.")
        }
        if has("lowest rir i recorded") {
            guard let low = ratings.min(by: { $0.rawValue < $1.rawValue }) else { return missing("Lowest recorded RIR", "No reported RIR in the selected records.") }
            return number("Lowest recorded RIR", low.valueText, "Lowest of \(ratings.count) reported ratings.")
        }
        let finals = selected.compactMap { $0.done.last?.rating }
        if has("average last set rir") {
            guard !finals.isEmpty else { return missing("Average last-set RIR", "No last-set RIR was recorded.") }
            let average = Double(finals.reduce(0) { $0 + $1.rawValue }) / Double(finals.count)
            return number("Average last-set RIR", average.studyNumber, "\(finals.count) rated final sets. Ratings of 5+ count as five.")
        }
        if has("one rir or lower") || has("rated sets") && has("at most one rep in reserve") {
            let sample = has("final sets") ? finals : ratings
            guard !sample.isEmpty else { return missing("Sets at 0–1 RIR", "No applicable ratings were recorded.") }
            let low = sample.filter { $0.rawValue <= 1 }.count
            return number("Sets at 0–1 RIR", has("percentage") ? (100*Double(low)/Double(sample.count)).studyNumber + "%" : String(low), "\(low) of \(sample.count) rated sets.")
        }
        if has("no rir recorded") && has("ended on a set") || has("final") && has("set missing an effort rating") {
            let unrated = ranked.filter { $0.done.last?.rating == nil }
            return answer(.sessionLedger, "Missing last-set RIR", "\(unrated.count) exercise sessions ended without a reported RIR.", columns: ["Date","Exercise"], rows: unrated.map { [h.day($0.date),$0.name] }, scope: scope, insufficient: false)
        }
        if has("load did i accumulate the most"), !liftNames.isEmpty {
            var repsByLoad: [Int: Int] = [:]
            for set in sets {
                if let load = set.load, let reps = set.reps { repsByLoad[load, default: 0] += reps }
            }
            guard let best = repsByLoad.values.max() else { return missing("Reps by load", "No sets have both load and reps.") }
            let rows = repsByLoad.keys.sorted().filter { repsByLoad[$0] == best }.map { [h.loadText($0), String(best)] }
            return table("Loads with the most total reps", ["Load", "Total reps"], rows, "Each listed load accumulated \(best) reps.")
        }
        if has("ended with at most one rep in reserve") {
            let qualifying = ranked.filter { ($0.done.last?.rating?.rawValue ?? Int.max) <= 1 }
            return answer(.effort, "Final set at 0–1 RIR", "\(qualifying.count) qualifying sessions.", columns: ["Date", "Exercise", "RIR"], rows: qualifying.map { [h.day($0.date), $0.name, $0.done.last?.rating?.valueText ?? "—"] }, scope: scope, insufficient: false)
        }
        if has("drop between the first and last") || has("drop in reps between the first and last") {
            let qualifying = ranked.filter { slot in
                guard let first = slot.done.first?.reps, let last = slot.done.last?.reps else { return false }
                return first > last
            }
            return number("Sessions with a rep drop", String(qualifying.count), "Compares the first and last completed set of the exercise.")
        }
        if has("more than eight reps on one set") {
            return number("Sets above eight reps", String(sets.filter { ($0.reps ?? 0) > 8 }.count), "Counts completed working sets with nine or more recorded reps.")
        }
        if has("sets were bodyweight sets with no added load") {
            let bodyweight = selected.filter { $0.equipment == .bodyweight }.flatMap(\.done)
            return number("Unweighted bodyweight sets", String(bodyweight.filter { $0.load == 0 }.count), "Completed sets on bodyweight exercises with zero recorded added load.")
        }
        if has("share of my reps") && has("came from"), !liftNames.isEmpty {
            let total = h.sessions.filter { includes($0.date) }.flatMap(\.done).compactMap(\.reps).reduce(0,+)
            guard total > 0 else { return missing("Share of reps", "No recorded reps in the selected period.") }
            let count = sets.compactMap(\.reps).reduce(0,+)
            return number("Share of recorded reps", (100 * Double(count) / Double(total)).studyNumber + "%", "\(count) of \(total) reps.")
        }
        if has("did i do any"), !liftNames.isEmpty {
            return number("Matching working sets", String(sets.count), "\(sets.count) completed matching sets.")
        }
        if has("workout had the most pounds times reps") {
            let grouped = Dictionary(grouping: selected, by: \.workout)
            let totals = grouped.mapValues { slots in
                slots.flatMap(\.done).compactMap { set -> Double? in
                    guard let load = set.load, let reps = set.reps else { return nil }
                    return Double(load) * Double(reps) / 10
                }
            }.filter { !$0.value.isEmpty }.mapValues { $0.reduce(0,+) }
            guard let best = totals.values.max() else { return missing("Highest workout volume", "No recorded working-set volume.") }
            let leaders = visits.filter { totals[$0.key] == best }
            return table("Highest workout volume", ["Date", "Workout", "lb·reps"], leaders.compactMap { visit in
                visit.date.map { [h.day($0), visit.template, best.studyNumber] }
            }, "Maximum recorded external volume: \(best.studyNumber) lb·reps.")
        }
        if has("exercises did i try for the first time"), let interval {
            let previous = Set(h.sessions.filter { $0.date < interval.start && !$0.done.isEmpty }.map(\.key))
            let firsts = Dictionary(grouping: selected.filter { !previous.contains($0.key) }, by: \.key)
            let rows = firsts.values.compactMap { slots in slots.min(by: { $0.date < $1.date }) }.sorted { $0.name < $1.name }.map { [$0.name, h.day($0.date)] }
            return answer(.sessionLedger, "First recorded exercises", "\(rows.count) exercises first appeared in the selected period.", columns: ["Exercise", "First date"], rows: rows, insufficient: false)
        }
        return nil
    }
}
