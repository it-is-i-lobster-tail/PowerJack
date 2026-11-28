//
//  PlanBuilder.swift
//  PowerJack
//
//  Builds a template with code alone, and repairs any plan, such as the model's picks, until it
//  passes every rule. Main lifts go in first, then each day fills from its split in candidate rank
//  order, then small edits fix whatever a rule still finds. Sets, reps and rest are never touched.
//

import Foundation

struct PlanBuilder: Sendable {
    enum Result: Hashable, Sendable {
        case plan(TemplatePlan)
        /// The equipment can't fill 3 exercises a day, or has no lift to open a Strength or PowerJack day.
        case notEnoughEquipment
    }

    /// Edits tried before a repair gives up and falls back to the code-only plan.
    private static let maximumEdits = 60

    let request: TemplateRequest
    let candidates: BuilderCandidates
    let rules: TemplateRules

    init(request: TemplateRequest, exercises: [BuilderExercise]) {
        self.request = request
        candidates = BuilderCandidates(exercises, for: request)
        rules = TemplateRules(request: request, candidates: candidates)
    }

    // MARK: - Building and repairing

    func build() -> Result {
        guard mainLiftOrder.count > 0 || request.type == .hypertrophy else { return .notEnoughEquipment }
        var plan = TemplatePlan(
            name: TemplateSplit.name(for: request.workoutsPerWeek),
            days: Array(repeating: TemplatePlan.Day(), count: request.workoutsPerWeek)
        )
        placeMainLifts(in: &plan)
        complete(&plan)
        guard plan.days.allSatisfy({ $0.exerciseIDs.count >= TemplateRules.minimumExercises }) else {
            return .notEnoughEquipment
        }
        return .plan(plan)
    }

    /// Keeps what it can of `plan`: drops IDs that aren't candidates or repeat, trims extras from the end
    /// (accessories first), fills gaps with the best candidate that passes, fixes the order, then edits
    /// until every rule passes. A day that still fails comes from the code-only plan, and if the whole
    /// plan still fails, it's the code-only plan.
    func repair(_ plan: TemplatePlan) -> TemplatePlan {
        var repaired = cleaned(plan)
        complete(&repaired)
        guard !rules.violations(repaired).isEmpty, case .plan(let built) = build() else { return repaired }

        for index in repaired.days.indices {
            var trial = repaired
            trial.days[index] = built.days[index]
            if score(trial) < score(repaired) { repaired = trial }
        }
        return rules.violations(repaired).isEmpty ? repaired : built
    }

    private func complete(_ plan: inout TemplatePlan) {
        for index in plan.days.indices { fill(&plan, day: index) }
        fix(&plan)
    }

    // MARK: - Cleaning

    private func cleaned(_ plan: TemplatePlan) -> TemplatePlan {
        let name = plan.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var cleaned = TemplatePlan(
            name: name.isEmpty || name.count > TemplatePlan.maximumNameLength ? TemplateSplit.name(for: request.workoutsPerWeek) : name,
            days: []
        )
        var weekly: [Muscle: Int] = [:]
        for index in 0..<request.workoutsPerWeek {
            let given = plan.days.indices.contains(index) ? plan.days[index] : TemplatePlan.Day()
            var ids: [String] = []
            var high = 0
            for id in given.exerciseIDs {
                guard let exercise = candidates.byID[id], !ids.contains(id) else { continue }
                if !rules.canRepeatDaily(exercise), cleaned.days.last?.exerciseIDs.contains(id) == true { continue }
                if exercise.fatigue == .high {
                    guard high < TemplateRules.maximumHighFatigue else { continue }
                    high += 1
                }
                guard weekly[exercise.primary, default: 0] < TemplateRules.maximumWeeklyDirect else { continue }
                weekly[exercise.primary, default: 0] += 1
                ids.append(id)
            }
            // Too many: accessories go first, from the end.
            while ids.count > TemplateRules.maximumExercises {
                let index = ids.lastIndex { candidates.byID[$0]?.isAccessory == true } ?? ids.count - 1
                weekly[candidates.byID[ids[index]]!.primary, default: 0] -= 1
                ids.remove(at: index)
            }
            var day = TemplatePlan.Day(exerciseIDs: ids)
            if request.supersets {
                for superset in given.supersets where day.supersets.count < SupersetStyle.maxPerWorkout
                    && ids.contains(superset.first) && ids.contains(superset.second)
                    && !day.supersets.contains(where: { $0.contains(superset.first) || $0.contains(superset.second) })
                    && rules.canSuperset(superset.first, superset.second) {
                    day.supersets.append(superset)
                }
            }
            cleaned.days.append(ordered(day))
        }
        return cleaned
    }

    // MARK: - Main lifts

    /// The lifts that open Strength and PowerJack days, in the order days take them. Empty for Hypertrophy.
    private var mainLiftOrder: [BuilderExercise] {
        switch request.type {
        case .hypertrophy:
            return []
        case .strength:
            let mains = candidates.ranked.filter(\.isStrengthMainLift)
            let bigThree = [StrengthLifts.squatID, StrengthLifts.benchID, StrengthLifts.deadliftID].compactMap { candidates.byID[$0] }
            var order = bigThree
            // Then the best of each other muscle, like the overhead press, up to four.
            for lift in mains where order.count < 4 && !order.contains(where: { $0.primary == lift.primary }) {
                order.append(lift)
            }
            for lift in mains where order.count < 2 && !order.contains(lift) {
                order.append(lift)
            }
            return order
        case .powerJack:
            return TemplateRules.powerJackPatterns.compactMap { pattern in
                candidates.ranked.first { $0.powerJackMainPattern == pattern }
            }
        }
    }

    /// Two main lifts open each day, taking turns through `mainLiftOrder`, so each comes as often as the
    /// week allows: squat and bench, then deadlift and overhead press, and so on.
    private func placeMainLifts(in plan: inout TemplatePlan) {
        let order = mainLiftOrder
        guard !order.isEmpty else { return }
        var next = 0
        for index in plan.days.indices {
            for _ in 0..<2 {
                let lift = order[next % order.count]
                next += 1
                if rules.canAdd(lift, toDay: index, in: rules.resolve(plan)) {
                    add(lift, toDay: index, in: &plan)
                }
            }
        }
    }

    // MARK: - Filling

    /// Fills a day from its split, focus muscles first with one more slot each, in candidate rank order,
    /// while the session has time. Then makes sure it has the 3 exercises G4 asks for.
    private func fill(_ plan: inout TemplatePlan, day index: Int) {
        let base = TemplateSplit.days(for: request.workoutsPerWeek)[index].slots
        let extra = request.focus.compactMap { muscle in base.first { $0.muscle == muscle } }
        let slots = (base + extra).enumerated().sorted { first, second in
            let firstFocus = request.focus.contains(first.element.muscle)
            let secondFocus = request.focus.contains(second.element.muscle)
            return firstFocus != secondFocus ? firstFocus : first.offset < second.offset
        }.map(\.element)

        var wanted: [Muscle: Int] = [:]
        for slot in slots {
            wanted[slot.muscle, default: 0] += 1
            guard plan.days[index].exerciseIDs.count < TemplateRules.maximumExercises else { break }
            let have = rules.resolve(plan.days[index]).filter { $0.primary == slot.muscle }.count
            guard have < wanted[slot.muscle, default: 0] else { continue }
            addBest(where: slot.matches, toDay: index, in: &plan, fitting: true)
        }
        while plan.days[index].exerciseIDs.count < TemplateRules.minimumExercises {
            guard addBest(where: { _ in true }, toDay: index, in: &plan, fitting: true)
                || addBest(where: { _ in true }, toDay: index, in: &plan, fitting: false) else { break }
        }
    }

    @discardableResult
    private func addBest(where matches: (BuilderExercise) -> Bool, toDay index: Int, in plan: inout TemplatePlan,
                         fitting: Bool) -> Bool {
        let week = rules.resolve(plan)
        for exercise in candidates.ranked where matches(exercise) && rules.canAdd(exercise, toDay: index, in: week) {
            var trial = plan
            add(exercise, toDay: index, in: &trial)
            if !fitting || rules.seconds(trial.days[index]) <= request.sessionSeconds {
                plan = trial
                return true
            }
        }
        return false
    }

    // MARK: - Fixing

    /// Small edits, each kept only when it leaves the plan better by `score`, until every rule passes.
    private func fix(_ plan: inout TemplatePlan) {
        for _ in 0..<Self.maximumEdits {
            let violations = rules.violations(plan)
            guard !violations.isEmpty else { return }
            let current = score(violations)
            let snapshot = plan
            guard let better = violations.lazy.compactMap({ improvement(of: snapshot, for: $0, below: current) }).first else { return }
            plan = better
        }
    }

    /// The first edit that helps with `violation`: dropping an exercise for rules about too much, adding
    /// or swapping one in for rules about too little.
    private func improvement(of plan: TemplatePlan, for violation: TemplateViolation, below current: Double) -> TemplatePlan? {
        let days = violation.day.map { [$0] } ?? Array(plan.days.indices)
        let removal = bestRemoval(from: plan, days: days, muscle: violation.rule == .g7 ? violation.muscle : nil)
        if let removal, removal.score < current, removesFirst(violation) { return removal.plan }

        let wanted = wanted(for: violation, in: plan)
        // Days with the most time left come first.
        let byTime = days.sorted { rules.seconds(plan.days[$0]) < rules.seconds(plan.days[$1]) }
        for exercise in candidates.ranked where wanted(exercise) {
            for index in byTime {
                var added = plan
                add(exercise, toDay: index, in: &added)
                if rules.canAdd(exercise, toDay: index, in: rules.resolve(plan)), score(added) < current { return added }

                for id in plan.days[index].exerciseIDs where id != exercise.id {
                    var swapped = plan
                    remove(id, fromDay: index, in: &swapped)
                    guard rules.canAdd(exercise, toDay: index, in: rules.resolve(swapped)) else { continue }
                    add(exercise, toDay: index, in: &swapped)
                    if score(swapped) < current { return swapped }
                }
            }
        }
        if let removal, removal.score < current { return removal.plan }
        return nil
    }

    private func removesFirst(_ violation: TemplateViolation) -> Bool {
        switch violation.rule {
        case .g1, .g2, .g3, .g7, .g9: true
        case .g4: violation.detail.contains("High") || violation.detail.contains("at most")
        default: false
        }
    }

    private func bestRemoval(from plan: TemplatePlan, days: [Int], muscle: Muscle?) -> (plan: TemplatePlan, score: Double)? {
        var best: (plan: TemplatePlan, score: Double)?
        for index in days {
            for id in plan.days[index].exerciseIDs where muscle == nil || candidates.byID[id]?.primary == muscle {
                var trial = plan
                remove(id, fromDay: index, in: &trial)
                let score = score(trial)
                if score < best?.score ?? .infinity { best = (trial, score) }
            }
        }
        return best
    }

    /// What an edit for `violation` may add.
    private func wanted(for violation: TemplateViolation, in plan: TemplatePlan) -> (BuilderExercise) -> Bool {
        if let id = violation.exerciseID, violation.rule == .g10 || violation.rule == .g11 { return { $0.id == id } }
        if let pattern = violation.pattern { return { $0.powerJackMainPattern == pattern } }
        if let muscle = violation.muscle { return { $0.primary == muscle } }
        switch violation.rule {
        case .g8: return { $0.direction == .pull }
        case .g10: return \.isStrengthMainLift
        case .g11: return { $0.powerJackMainPattern != nil }
        default: return { _ in true }
        }
    }

    private func score(_ plan: TemplatePlan) -> Double { score(rules.violations(plan)) }

    private func score(_ violations: [TemplateViolation]) -> Double {
        violations.reduce(0) { $0 + 1 + $1.amount }
    }

    // MARK: - Editing a day

    /// Adds an exercise and keeps the day in order. With supersets on, an accessory joins the first
    /// accessory on its own that works another muscle.
    private func add(_ exercise: BuilderExercise, toDay index: Int, in plan: inout TemplatePlan) {
        var day = plan.days[index]
        day.exerciseIDs.append(exercise.id)
        if request.supersets, exercise.isAccessory, day.supersets.count < SupersetStyle.maxPerWorkout,
           let partner = day.exerciseIDs.dropLast().first(where: { id in
               !day.supersets.contains { $0.contains(id) } && rules.canSuperset(id, exercise.id)
           }) {
            day.supersets.append(.init(first: partner, second: exercise.id))
        }
        plan.days[index] = ordered(day)
    }

    private func remove(_ id: String, fromDay index: Int, in plan: inout TemplatePlan) {
        var day = plan.days[index]
        day.exerciseIDs.removeAll { $0 == id }
        day.supersets.removeAll { $0.contains(id) }
        plan.days[index] = ordered(day)
    }

    /// The day in G9's order, each superset's two together. A Strength or PowerJack day opens with its
    /// heaviest lift that can open it, best ranked first.
    private func ordered(_ day: TemplatePlan.Day) -> TemplatePlan.Day {
        var blocks: [[BuilderExercise]] = []
        var placed = Set<String>()
        for exercise in rules.resolve(day) where !placed.contains(exercise.id) {
            if let superset = day.supersets.first(where: { $0.contains(exercise.id) }),
               let first = candidates.byID[superset.first], let second = candidates.byID[superset.second] {
                blocks.append([first, second])
                placed.formUnion([first.id, second.id])
            } else {
                blocks.append([exercise])
                placed.insert(exercise.id)
            }
        }

        var opener: [BuilderExercise] = []
        let opens: (BuilderExercise) -> Bool = switch request.type {
        case .strength: \.isStrengthMainLift
        case .powerJack: { $0.powerJackMainPattern != nil }
        case .hypertrophy: { _ in false }
        }
        if let index = blocks.indices.filter({ blocks[$0].count == 1 && opens(blocks[$0][0]) })
            .min(by: { (blocks[$0][0].fatigue == .high ? 0 : 1) < (blocks[$1][0].fatigue == .high ? 0 : 1) }) {
            opener = blocks.remove(at: index)
        }
        // Ties keep their order.
        let sorted = blocks.enumerated().sorted { first, second in
            let firstKey = rules.orderKey(first.element), secondKey = rules.orderKey(second.element)
            return firstKey != secondKey ? firstKey < secondKey : first.offset < second.offset
        }.map(\.element)
        let ids = (opener + sorted.joined()).map(\.id)
        let kept = day.exerciseIDs.filter { candidates.byID[$0] == nil }
        return TemplatePlan.Day(exerciseIDs: ids + kept, supersets: day.supersets.filter { ids.contains($0.first) && ids.contains($0.second) })
    }
}
