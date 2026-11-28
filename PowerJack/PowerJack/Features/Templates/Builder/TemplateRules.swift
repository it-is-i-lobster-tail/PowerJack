//
//  TemplateRules.swift
//  PowerJack
//
//  The guardrails every Build for Me template passes (G1-G12). Each rule is a pure function of the
//  plan, the request and the candidates, returning what it found wrong. The builder and its repair
//  rely on these alone, never on the model following them.
//

import Foundation

struct TemplateViolation: Hashable, Sendable, CustomStringConvertible {
    enum Rule: Int, Hashable, Sendable {
        case g1 = 1, g2, g3, g4, g5, g6, g7, g8, g9, g10, g11
    }

    let rule: Rule
    /// The day it's on, as an index, when it's about one day.
    var day: Int? = nil
    var muscle: Muscle? = nil
    var exerciseID: String? = nil
    var pattern: PowerJackPattern? = nil
    let detail: String
    /// How far off a counted rule is, so a repair that gets closer counts as better.
    var amount: Double = 0
    /// True when taking something out fixes it, false when something has to go in.
    var tooMuch = false

    var description: String {
        "G\(rule.rawValue)\(day.map { " day \($0 + 1)" } ?? ""): \(detail)"
    }
}

struct TemplateRules: Sendable {
    static let minimumExercises = 3
    static let maximumExercises = 8
    static let maximumHighFatigue = 2
    static let maximumWeeklyDirect = 6
    // G3's estimate. Three sets, as the engines start at 2 and add more, so the day still fits weeks in.
    static let estimateSets = 3
    static let workSeconds = 40
    static let setupSeconds = 60
    static let warmupSeconds = 300
    /// G6 asks less of sessions this short.
    static let shortSessionMinutes = 45
    static let majorMuscles: [Muscle] = [.chest, .back, .shoulders, .quads, .hamstrings, .glutes]
    static let bigThree: Set<String> = [StrengthLifts.squatID, StrengthLifts.benchID, StrengthLifts.deadliftID]
    static let powerJackPatterns: [PowerJackPattern] = [.squat, .hinge, .horizontalPush, .verticalPush]

    let request: TemplateRequest
    let candidates: BuilderCandidates

    /// The plan's exercises, counted once for the rules that read the whole week.
    struct Week {
        let days: [[BuilderExercise]]
        /// 1 for each exercise a muscle leads, half for each it assists.
        let exposures: [Muscle: Double]
        /// Exercises each muscle leads.
        let direct: [Muscle: Int]
        let placement: Placement

        init(_ days: [[BuilderExercise]], rules: TemplateRules) {
            self.days = days
            var exposures: [Muscle: Double] = [:]
            var direct: [Muscle: Int] = [:]
            for exercise in days.joined() {
                exposures[exercise.primary, default: 0] += 1
                direct[exercise.primary, default: 0] += 1
                for muscle in exercise.secondaries { exposures[muscle, default: 0] += 0.5 }
            }
            self.exposures = exposures
            self.direct = direct
            placement = Placement(days, direct: direct, rules: rules)
        }
    }

    func violations(_ plan: TemplatePlan) -> [TemplateViolation] {
        let week = resolve(plan)
        return g1(plan) + g2(plan) + g3(plan) + g4(plan, week) + g5(week) + g6(plan, week)
            + g7(week) + g8(week) + g9(plan) + g10(week) + g11(week)
    }

    // MARK: - What can be picked

    /// G1. Only candidates.
    func g1(_ plan: TemplatePlan) -> [TemplateViolation] {
        plan.days.enumerated().flatMap { index, day in
            day.exerciseIDs.filter { !candidates.contains($0) }.map {
                TemplateViolation(rule: .g1, day: index, exerciseID: $0, detail: "\($0) isn't a candidate", tooMuch: true)
            }
        }
    }

    /// G2. No exercise twice in a day, nor on back-to-back days unless it's a Strength or PowerJack main lift.
    func g2(_ plan: TemplatePlan) -> [TemplateViolation] {
        var found: [TemplateViolation] = []
        for (index, day) in plan.days.enumerated() {
            var seen = Set<String>()
            for id in day.exerciseIDs where !seen.insert(id).inserted {
                found.append(TemplateViolation(rule: .g2, day: index, exerciseID: id, detail: "\(id) twice in one day", tooMuch: true))
            }
            guard index > 0 else { continue }
            let yesterday = Set(plan.days[index - 1].exerciseIDs)
            for id in Set(day.exerciseIDs).intersection(yesterday).sorted() where !(candidates.byID[id].map(canRepeatDaily) ?? false) {
                found.append(TemplateViolation(rule: .g2, day: index, exerciseID: id, detail: "\(id) on back-to-back days", tooMuch: true))
            }
        }
        return found
    }

    // MARK: - How much fits

    /// G3. The day's time estimate fits the session. A day at G4's minimum always passes.
    func g3(_ plan: TemplatePlan) -> [TemplateViolation] {
        plan.days.enumerated().compactMap { index, day in
            let over = seconds(day) - request.sessionSeconds
            guard over > 0, day.exerciseIDs.count > Self.minimumExercises else { return nil }
            return TemplateViolation(rule: .g3, day: index, detail: "\(over / 60 + 1) min over", amount: Double(over) / 60, tooMuch: true)
        }
    }

    /// G4. One day per workout, 3 to 8 exercises each, at most 2 High fatigue.
    func g4(_ plan: TemplatePlan, _ week: Week) -> [TemplateViolation] {
        var found: [TemplateViolation] = []
        if plan.days.count != request.workoutsPerWeek {
            found.append(TemplateViolation(rule: .g4, detail: "\(plan.days.count) days for \(request.workoutsPerWeek) workouts",
                                           amount: Double(abs(plan.days.count - request.workoutsPerWeek))))
        }
        for (index, day) in plan.days.enumerated() {
            let count = day.exerciseIDs.count
            if count < Self.minimumExercises || count > Self.maximumExercises {
                let few = count < Self.minimumExercises
                found.append(TemplateViolation(
                    rule: .g4, day: index,
                    detail: few ? "\(count) exercises, at least \(Self.minimumExercises)" : "\(count) exercises, at most \(Self.maximumExercises)",
                    amount: Double(few ? Self.minimumExercises - count : count - Self.maximumExercises),
                    tooMuch: !few
                ))
            }
            let high = week.placement.high[index]
            if high > Self.maximumHighFatigue {
                found.append(TemplateViolation(rule: .g4, day: index, detail: "\(high) High fatigue lifts",
                                               amount: Double(high - Self.maximumHighFatigue), tooMuch: true))
            }
        }
        return found
    }

    // MARK: - Weekly balance

    /// G5. Chest, back, shoulders, quads, hamstrings and glutes twice a week with 3+ days, once with 2.
    /// A muscle with no candidate can't be trained, so it's left out.
    func g5(_ week: Week) -> [TemplateViolation] {
        let needed: Double = request.workoutsPerWeek >= 3 ? 2 : 1
        return Self.majorMuscles.compactMap { muscle in
            let exposure = exposure(of: muscle, in: week)
            guard exposure < needed, hasCandidate(for: muscle) else { return nil }
            return TemplateViolation(rule: .g5, muscle: muscle, detail: "\(muscle.rawValue) under \(Int(needed))x a week",
                                     amount: needed - exposure)
        }
    }

    /// G6. Each focus muscle gets at least one more exercise a week than the average non-focus muscle,
    /// unless no more of it can go anywhere, and isn't last on its day while its tier has other work.
    /// Only direct exercises count here: abs and forearms get half of nearly every squat and row, which
    /// would put the average out of reach. 45-minute sessions can't fit the extra beside G5's coverage,
    /// so there it's at least the average in whole exercises.
    func g6(_ plan: TemplatePlan, _ week: Week) -> [TemplateViolation] {
        let others = Muscle.allCases.filter { !request.focus.contains($0) && hasCandidate(for: $0) }
        let total = others.reduce(0) { $0 + week.direct[$1, default: 0] }
        let average = others.isEmpty ? 0 : Double(total) / Double(others.count)
        let needed = request.sessionMinutes > Self.shortSessionMinutes ? average + 1 : average.rounded(.down)
        var found: [TemplateViolation] = request.focus.compactMap { muscle in
            let count = Double(week.direct[muscle, default: 0])
            guard count < needed, hasCandidate(for: muscle), !isSaturated(muscle, in: week) else { return nil }
            return TemplateViolation(rule: .g6, muscle: muscle, detail: "focus \(muscle.rawValue) not above the rest",
                                     amount: needed - count)
        }
        for (index, day) in plan.days.enumerated() {
            let blocks = orderedBlocks(day)
            guard let last = blocks.last, isFocus(last) else { continue }
            let tier = tier(of: last)
            if blocks.dropLast().contains(where: { self.tier(of: $0) == tier && !isFocus($0) }) {
                found.append(TemplateViolation(rule: .g6, day: index, detail: "a focus muscle is last"))
            }
        }
        return found
    }

    /// G7. At most 6 direct exercises per muscle a week.
    func g7(_ week: Week) -> [TemplateViolation] {
        Muscle.allCases.compactMap { muscle in
            let count = week.direct[muscle, default: 0]
            guard count > Self.maximumWeeklyDirect else { return nil }
            return TemplateViolation(rule: .g7, muscle: muscle, detail: "\(count) \(muscle.rawValue) exercises",
                                     amount: Double(count - Self.maximumWeeklyDirect), tooMuch: true)
        }
    }

    /// G8. At least as much pulling as pushing each week, unless no more pulling fits anywhere, as with
    /// a barbell and bench alone, where rows are the only pull.
    func g8(_ week: Week) -> [TemplateViolation] {
        let exercises = week.days.joined()
        let pushes = exercises.filter { $0.direction == .push }.count
        let pulls = exercises.filter { $0.direction == .pull }.count
        guard pulls < pushes else { return [] }
        let canPullMore = candidates.ranked.contains { exercise in
            exercise.direction == .pull && week.days.indices.contains { week.placement.allows(exercise, onDay: $0) }
        }
        guard canPullMore else { return [] }
        return [TemplateViolation(rule: .g8, detail: "\(pushes) pushes, \(pulls) pulls", amount: Double(pushes - pulls))]
    }

    // MARK: - Order and type

    /// G9. High fatigue, then compounds, then isolation, focus muscles first in each (a Strength or
    /// PowerJack day's opening lift is G10's and G11's). Supersets pair two neighboring Low or Moderate
    /// accessories on different muscles, within the day's cap.
    func g9(_ plan: TemplatePlan) -> [TemplateViolation] {
        var found: [TemplateViolation] = []
        for (index, day) in plan.days.enumerated() {
            let keys = orderedBlocks(day).map(orderKey)
            if zip(keys, keys.dropFirst()).contains(where: { $0 > $1 }) {
                found.append(TemplateViolation(rule: .g9, day: index, detail: "out of order", tooMuch: true))
            }
            if !day.supersets.isEmpty && !request.supersets {
                found.append(TemplateViolation(rule: .g9, day: index, detail: "supersets weren't asked for", tooMuch: true))
            }
            if day.supersets.count > SupersetStyle.maxPerWorkout {
                found.append(TemplateViolation(rule: .g9, day: index, detail: "\(day.supersets.count) supersets", tooMuch: true))
            }
            var paired = Set<String>()
            for superset in day.supersets {
                let valid = paired.insert(superset.first).inserted && paired.insert(superset.second).inserted
                    && isNextTo(superset, in: day) && canSuperset(superset.first, superset.second)
                if !valid {
                    found.append(TemplateViolation(rule: .g9, day: index, exerciseID: superset.second,
                                                   detail: "\(superset.first) + \(superset.second) can't be a superset", tooMuch: true))
                }
            }
        }
        return found
    }

    /// G10. Strength: every day opens with a loaded compound, and with a barbell and bench the squat,
    /// bench press and deadlift each come at least once a week.
    func g10(_ week: Week) -> [TemplateViolation] {
        guard request.type == .strength else { return [] }
        var found = week.days.enumerated().compactMap { index, day in
            day.first?.isStrengthMainLift == true ? nil
                : TemplateViolation(rule: .g10, day: index, detail: "doesn't open with a loaded compound")
        }
        if request.equipment.contains(.barbell), request.setups.contains(.bench) {
            let used = Set(week.days.joined().map(\.id))
            for id in Self.bigThree.sorted() where candidates.contains(id) && !used.contains(id) {
                found.append(TemplateViolation(rule: .g10, exerciseID: id, detail: "no \(id)"))
            }
        }
        return found
    }

    /// G11. PowerJack: every day opens with a lift that can be a main lift, and with 4+ days each main
    /// pattern's main lift comes twice a week, for its heavy and volume slots.
    func g11(_ week: Week) -> [TemplateViolation] {
        guard request.type == .powerJack else { return [] }
        var found = week.days.enumerated().compactMap { index, day in
            day.first?.powerJackMainPattern != nil ? nil
                : TemplateViolation(rule: .g11, day: index, detail: "doesn't open with a main lift")
        }
        guard request.workoutsPerWeek >= 4 else { return found }
        for pattern in Self.powerJackPatterns where candidates.ranked.contains(where: { $0.powerJackMainPattern == pattern }) {
            let main = mainLift(for: pattern, in: week)
            let days = main.map { main in week.days.filter { $0.contains { $0.id == main.id } }.count } ?? 0
            if days < 2 {
                found.append(TemplateViolation(rule: .g11, exerciseID: main?.id, pattern: pattern,
                                               detail: "a main lift on \(days) days", amount: Double(2 - days)))
            }
        }
        return found
    }

    // G12. Hypertrophy has nothing beyond G1-G9.

    // MARK: - Shared readings

    func resolve(_ plan: TemplatePlan) -> Week {
        Week(plan.days.map { resolve($0) }, rules: self)
    }

    func resolve(_ day: TemplatePlan.Day) -> [BuilderExercise] {
        day.exerciseIDs.compactMap { candidates.byID[$0] }
    }

    func exposure(of muscle: Muscle, in week: Week) -> Double {
        week.exposures[muscle, default: 0]
    }

    func hasCandidate(for muscle: Muscle) -> Bool {
        candidates.primaries.contains(muscle)
    }

    /// Main lifts may come back the next day, as a Strength or PowerJack week trains them often.
    func canRepeatDaily(_ exercise: BuilderExercise) -> Bool {
        switch request.type {
        case .strength: exercise.isStrengthMainLift
        case .powerJack: exercise.powerJackMainPattern != nil
        case .hypertrophy: false
        }
    }

    /// What G2, G4's fatigue cap and G7 allow, leaving time and day length to G3 and G4.
    func canAdd(_ exercise: BuilderExercise, toDay index: Int, in week: Week) -> Bool {
        week.placement.allows(exercise, onDay: index)
    }

    /// True when no more exercises for `muscle` can go on any day.
    func isSaturated(_ muscle: Muscle, in week: Week) -> Bool {
        !candidates.ranked.contains { exercise in
            exercise.primary == muscle && week.days.indices.contains { week.placement.allows(exercise, onDay: $0) }
        }
    }

    /// What G2, G4's fatigue cap and G7 allow on each day, for checking many placements at once.
    struct Placement {
        let rules: TemplateRules
        let ids: [Set<String>]
        let high: [Int]
        let weekly: [Muscle: Int]

        init(_ days: [[BuilderExercise]], direct: [Muscle: Int], rules: TemplateRules) {
            self.rules = rules
            ids = days.map { Set($0.map(\.id)) }
            high = days.map { $0.count { $0.fatigue == .high } }
            weekly = direct
        }

        /// Whether `exercise` can go on the day, after `removed` comes off it when it's a swap.
        func allows(_ exercise: BuilderExercise, onDay index: Int, removing removed: BuilderExercise? = nil) -> Bool {
            guard exercise.id != removed?.id, !ids[index].contains(exercise.id) else { return false }
            if !rules.canRepeatDaily(exercise),
               (index > 0 && ids[index - 1].contains(exercise.id)) || (index + 1 < ids.count && ids[index + 1].contains(exercise.id)) {
                return false
            }
            let high = high[index] - (removed?.fatigue == .high ? 1 : 0)
            if exercise.fatigue == .high && high >= TemplateRules.maximumHighFatigue { return false }
            let weekly = weekly[exercise.primary, default: 0] - (removed?.primary == exercise.primary ? 1 : 0)
            return weekly < TemplateRules.maximumWeeklyDirect
        }
    }

    /// The PowerJack engine's main lift for a pattern: the first lift of it that can be one, in week order.
    func mainLift(for pattern: PowerJackPattern, in week: Week) -> BuilderExercise? {
        week.days.joined().first { $0.powerJackMainPattern == pattern }
    }

    /// The time estimate: 3 sets of 40 s plus rest, and a minute to set up, per exercise. A superset's
    /// two share one rest. A day with a big lift adds its warmups.
    func seconds(_ day: TemplatePlan.Day) -> Int {
        let exercises = resolve(day)
        let byID = candidates.byID
        var paired = Set<String>()
        var total = 0
        for superset in day.supersets {
            guard let first = byID[superset.first], let second = byID[superset.second],
                  !paired.contains(first.id), !paired.contains(second.id) else { continue }
            paired.formUnion([first.id, second.id])
            total += Self.estimateSets * (2 * Self.workSeconds + max(first.restSeconds, second.restSeconds)) + 2 * Self.setupSeconds
        }
        for exercise in exercises where !paired.contains(exercise.id) {
            total += Self.estimateSets * (Self.workSeconds + exercise.restSeconds) + Self.setupSeconds
        }
        if exercises.contains(where: \.isBigLift) { total += Self.warmupSeconds }
        return total
    }

    func canSuperset(_ first: String, _ second: String) -> Bool {
        guard let first = candidates.byID[first], let second = candidates.byID[second] else { return false }
        return first.isAccessory && second.isAccessory && first.primary != second.primary
    }

    private func isNextTo(_ superset: TemplatePlan.Superset, in day: TemplatePlan.Day) -> Bool {
        guard let index = day.exerciseIDs.firstIndex(of: superset.first) else { return false }
        return day.exerciseIDs.indices.contains(index + 1) && day.exerciseIDs[index + 1] == superset.second
    }

    // MARK: - Order

    /// The day as G9 orders it: one block per exercise or superset, leaving out a Strength or
    /// PowerJack day's opening lift.
    func orderedBlocks(_ day: TemplatePlan.Day) -> [[BuilderExercise]] {
        let exercises = resolve(day)
        var blocks: [[BuilderExercise]] = []
        var index = 0
        while index < exercises.count {
            let exercise = exercises[index]
            if index + 1 < exercises.count, day.supersets.contains(.init(first: exercise.id, second: exercises[index + 1].id)) {
                blocks.append([exercise, exercises[index + 1]])
                index += 2
            } else {
                blocks.append([exercise])
                index += 1
            }
        }
        return request.type == .hypertrophy ? blocks : Array(blocks.dropFirst())
    }

    /// 0 for High fatigue, 1 for compounds, 2 for isolation.
    func tier(of block: [BuilderExercise]) -> Int {
        block.map { $0.fatigue == .high ? 0 : $0.isCompound ? 1 : 2 }.min() ?? 2
    }

    func isFocus(_ block: [BuilderExercise]) -> Bool {
        block.contains { request.focus.contains($0.primary) }
    }

    /// Sorts the way G9 reads a day: tier first, focus muscles first within it.
    func orderKey(_ block: [BuilderExercise]) -> Int {
        tier(of: block) * 2 + (isFocus(block) ? 0 : 1)
    }
}
