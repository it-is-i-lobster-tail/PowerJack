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
            var picked = [StrengthLifts.squatID, StrengthLifts.benchID, StrengthLifts.deadliftID].compactMap { candidates.byID[$0] }
            // Then the best of each other pattern, like the overhead press, up to four.
            for lift in mains where picked.count < 4 && !picked.contains(where: { $0.liftPattern == lift.liftPattern }) {
                picked.append(lift)
            }
            for lift in mains where picked.count < 2 && !picked.contains(lift) {
                picked.append(lift)
            }
            // Lower and upper body take turns, so each day pairs a squat or hinge with a press or row.
            let lower = picked.filter { $0.liftPattern == .squat || $0.liftPattern == .hinge }
            let upper = picked.filter { !lower.contains($0) }
            return (0..<max(lower.count, upper.count)).flatMap { index in
                [lower.indices.contains(index) ? lower[index] : nil, upper.indices.contains(index) ? upper[index] : nil].compactMap { $0 }
            }
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

    /// Fills a day from its split, focus muscles with one more slot each, in candidate rank order,
    /// while the session has time. Then makes sure it has the 3 exercises G4 asks for.
    private func fill(_ plan: inout TemplatePlan, day index: Int) {
        let base = TemplateSplit.days(for: request.workoutsPerWeek)[index].slots
        let all = base + request.focus.compactMap { muscle in base.first { $0.muscle == muscle } }
        // Each big muscle's first slot, then focus muscles, then the rest, so focus work never crowds out coverage.
        var seen = Set<Muscle>()
        var ranks: [Int] = []
        for slot in all {
            let first = TemplateRules.majorMuscles.contains(slot.muscle) && seen.insert(slot.muscle).inserted
            ranks.append(first ? 0 : request.focus.contains(slot.muscle) ? 1 : 2)
        }
        let slots = all.indices.sorted { ranks[$0] != ranks[$1] ? ranks[$0] < ranks[$1] : $0 < $1 }.map { all[$0] }

        let quickest = quickest(for: slots, day: index, in: plan)
        var wanted: [Muscle: Int] = [:]
        for (position, slot) in slots.enumerated() {
            wanted[slot.muscle, default: 0] += 1
            guard plan.days[index].exerciseIDs.count < TemplateRules.maximumExercises else { break }
            let have = rules.resolve(plan.days[index]).filter { $0.primary == slot.muscle }.count
            guard have < wanted[slot.muscle, default: 0] else { continue }
            let reserve = reserve(for: slots.dropFirst(position + 1), besides: slot.muscle, day: plan.days[index], quickest: quickest)
            addBest(where: slot.matches, toDay: index, in: &plan, fitting: true, reserve: reserve)
        }
        while plan.days[index].exerciseIDs.count < TemplateRules.minimumExercises {
            guard addBest(where: { _ in true }, toDay: index, in: &plan, fitting: true)
                || addBest(where: { _ in true }, toDay: index, in: &plan, fitting: false) else { break }
        }
    }

    /// Time kept back for the big and focus muscles later in the day that have nothing yet: the
    /// quickest exercise for each. So a tight day picks a quicker lift now rather than skip a muscle.
    private func reserve(for slots: ArraySlice<TemplateSplit.Slot>, besides muscle: Muscle, day: TemplatePlan.Day,
                         quickest: [TemplateSplit.Slot: Int]) -> Int {
        var trained = Set(rules.resolve(day).map(\.primary))
        trained.insert(muscle)
        return slots.reduce(0) { total, slot in
            guard TemplateRules.majorMuscles.contains(slot.muscle) || request.focus.contains(slot.muscle),
                  trained.insert(slot.muscle).inserted else { return total }
            return total + (quickest[slot] ?? 0)
        }
    }

    /// The quickest exercise that could fill each slot on a day, in seconds.
    private func quickest(for slots: [TemplateSplit.Slot], day index: Int, in plan: TemplatePlan) -> [TemplateSplit.Slot: Int] {
        let placement = rules.resolve(plan).placement
        var quickest: [TemplateSplit.Slot: Int] = [:]
        for slot in Set(slots) {
            quickest[slot] = candidates.ranked
                .filter { slot.matches($0) && placement.allows($0, onDay: index) }
                .map { TemplateRules.estimateSets * (TemplateRules.workSeconds + $0.restSeconds) + TemplateRules.setupSeconds }
                .min()
        }
        return quickest
    }

    @discardableResult
    private func addBest(where matches: (BuilderExercise) -> Bool, toDay index: Int, in plan: inout TemplatePlan,
                         fitting: Bool, reserve: Int = 0) -> Bool {
        let placement = rules.resolve(plan).placement
        for exercise in candidates.ranked where matches(exercise) && placement.allows(exercise, onDay: index) {
            let day = adding(exercise, to: plan.days[index])
            if !fitting || rules.seconds(day) + reserve <= request.sessionSeconds {
                plan.days[index] = ordered(day)
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

    /// Candidates an edit tries for one violation, best ranked first.
    private static let editCandidates = 8

    /// The first edit that helps with `violation`: dropping an exercise for rules about too much, adding
    /// or swapping one in for rules about too little.
    private func improvement(of plan: TemplatePlan, for violation: TemplateViolation, below current: Double) -> TemplatePlan? {
        let days = violation.day.map { [$0] } ?? Array(plan.days.indices)
        if violation.tooMuch {
            let removal = bestRemoval(from: plan, days: days, muscle: violation.rule == .g7 ? violation.muscle : nil)
            if let removal, removal.score < current { return removal.plan }
            return violation.rule == .g3 ? quickerSwap(in: plan, day: days[0], below: current) : nil
        }

        let wanted = wanted(for: violation)
        // Days with the most time left come first.
        let byTime = days.sorted { rules.seconds(plan.days[$0]) < rules.seconds(plan.days[$1]) }
        let placement = rules.resolve(plan).placement
        for exercise in candidates.ranked.lazy.filter(wanted).prefix(Self.editCandidates) {
            for index in byTime {
                if placement.allows(exercise, onDay: index) {
                    var added = plan
                    add(exercise, toDay: index, in: &added)
                    if score(added) < current { return added }
                }
                for removed in rules.resolve(plan.days[index]) where placement.allows(exercise, onDay: index, removing: removed) {
                    var swapped = plan
                    remove(removed.id, fromDay: index, in: &swapped)
                    add(exercise, toDay: index, in: &swapped)
                    if score(swapped) < current { return swapped }
                    // A bigger lift may need two to make room.
                    if rules.seconds(swapped.days[index]) > request.sessionSeconds,
                       let room = bestRemoval(from: swapped, days: [index], muscle: nil, keeping: exercise.id),
                       room.score < current {
                        return room.plan
                    }
                }
            }
        }
        return nil
    }

    /// Swaps an exercise for a quicker one for the same muscle, for a day that runs long.
    private func quickerSwap(in plan: TemplatePlan, day index: Int, below current: Double) -> TemplatePlan? {
        let placement = rules.resolve(plan).placement
        for exercise in rules.resolve(plan.days[index]).reversed() {
            for quicker in candidates.ranked where quicker.primary == exercise.primary && quicker.restSeconds < exercise.restSeconds
                && placement.allows(quicker, onDay: index, removing: exercise) {
                var swapped = plan
                remove(exercise.id, fromDay: index, in: &swapped)
                add(quicker, toDay: index, in: &swapped)
                if score(swapped) < current { return swapped }
            }
        }
        return nil
    }

    private func bestRemoval(from plan: TemplatePlan, days: [Int], muscle: Muscle?,
                             keeping kept: String? = nil) -> (plan: TemplatePlan, score: Double)? {
        var best: (plan: TemplatePlan, score: Double)?
        for index in days {
            for id in plan.days[index].exerciseIDs where id != kept && (muscle == nil || candidates.byID[id]?.primary == muscle) {
                var trial = plan
                remove(id, fromDay: index, in: &trial)
                let score = score(trial)
                if score < best?.score ?? .infinity { best = (trial, score) }
            }
        }
        return best
    }

    /// What an edit for `violation` may add.
    private func wanted(for violation: TemplateViolation) -> (BuilderExercise) -> Bool {
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

    /// Lower is better. What can't be traded away, like a day's opening lift or the big three, weighs
    /// most, then time and coverage, then focus, so no edit gives up a heavier rule for a lighter one.
    private func score(_ violations: [TemplateViolation]) -> Double {
        violations.reduce(0) { total, violation in
            let weight: Double = switch violation.rule {
            case .g1, .g2, .g4, .g9, .g10, .g11: 10
            case .g3, .g5, .g8: 3
            case .g6, .g7: 1
            }
            return total + weight * (1 + violation.amount)
        }
    }

    // MARK: - Editing a day

    /// Adds an exercise and keeps the day in order. With supersets on, an accessory joins the first
    /// accessory on its own that works another muscle.
    private func add(_ exercise: BuilderExercise, toDay index: Int, in plan: inout TemplatePlan) {
        plan.days[index] = ordered(adding(exercise, to: plan.days[index]))
    }

    /// The day with `exercise` at the end, not yet in order.
    private func adding(_ exercise: BuilderExercise, to day: TemplatePlan.Day) -> TemplatePlan.Day {
        var day = day
        day.exerciseIDs.append(exercise.id)
        if request.supersets, exercise.isAccessory, day.supersets.count < SupersetStyle.maxPerWorkout,
           let partner = day.exerciseIDs.dropLast().first(where: { id in
               !day.supersets.contains { $0.contains(id) } && rules.canSuperset(id, exercise.id)
           }) {
            day.supersets.append(.init(first: partner, second: exercise.id))
        }
        return day
    }

    private func remove(_ id: String, fromDay index: Int, in plan: inout TemplatePlan) {
        plan.days[index] = removing(id, from: plan.days[index])
    }

    /// Taking an exercise out keeps the rest in order, unless it opened a Strength or PowerJack day,
    /// which then needs a new opener.
    private func removing(_ id: String, from day: TemplatePlan.Day) -> TemplatePlan.Day {
        var day = day
        let opened = day.exerciseIDs.first == id
        day.exerciseIDs.removeAll { $0 == id }
        day.supersets.removeAll { $0.contains(id) }
        return opened && request.type != .hypertrophy ? ordered(day) : day
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
        let openers = blocks.indices.filter { blocks[$0].count == 1 && opens(blocks[$0][0]) }
        if let index = openers.first(where: { blocks[$0][0].fatigue == .high }) ?? openers.first {
            opener = blocks.remove(at: index)
        }
        // Ties keep their order.
        let sorted = blocks.enumerated().sorted { first, second in
            let firstKey = rules.orderKey(first.element), secondKey = rules.orderKey(second.element)
            return firstKey != secondKey ? firstKey < secondKey : first.offset < second.offset
        }.map(\.element)
        let ids = (opener + sorted.joined()).map(\.id)
        return TemplatePlan.Day(exerciseIDs: ids, supersets: day.supersets.filter { ids.contains($0.first) && ids.contains($0.second) })
    }
}
