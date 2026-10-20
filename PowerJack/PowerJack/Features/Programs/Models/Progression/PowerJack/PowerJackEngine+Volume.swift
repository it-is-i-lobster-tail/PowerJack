//
//  PowerJackEngine+Volume.swift
//  PowerJack
//
//  Working sets: weekly lift sets per main lift (R3.3), each muscle's hard-set target filled on its
//  S and A slots (R3.2, R3.4, R3.7), sets added after clean weeks (R3.5) and cut after fatigued ones
//  (R3.3, R3.6). It changes only set counts, never the template's exercises.
//

import Foundation

extension PowerJackWeekBuilder {
    // MARK: Muscles

    /// Muscles that are the primary muscle of an exercise in the week: focus ones and standard ones (R3.2).
    var targetedMuscles: Set<Muscle> { Set(structure.joined().map(\.primary)) }

    func isFocus(_ muscle: Muscle) -> Bool { context.focusMuscles.contains(muscle) }

    func cap(_ muscle: Muscle) -> Int {
        isFocus(muscle) ? PowerJackRules.focusCap(goal) : PowerJackRules.muscleCap(goal)
    }

    private func band(_ muscle: Muscle) -> Int {
        PowerJackRules.muscleStart(goal) + (isFocus(muscle) ? PowerJackRules.focusStartBonus : 0)
    }

    private func clampStart(_ value: Int, _ muscle: Muscle) -> Int {
        min(max(value, PowerJackRules.maintenanceSets), cap(muscle) - 1)
    }

    /// R3.7: each block starts a muscle 1 set lower after a cut, 1 higher after an add, else the same.
    func blockStart(_ muscle: Muscle) -> Int {
        var start = clampStart(band(muscle), muscle)
        let blocks = Set(weeks.map(\.blockNumber)).sorted()
        let open = blocks.last.map { number in weeks.last?.type == .deload ? number + 1 : number }
        for number in blocks where number != open {
            let builds = weeks.filter { $0.blockNumber == number && $0.type == .build }
            guard builds.count >= PowerJackRules.minBuildWeeks else { continue }
            let changes = setChanges(muscle, in: builds)
            if changes.removals > 0 {
                start -= PowerJackRules.blockStepSets
            } else if changes.adds > 0 {
                start += PowerJackRules.blockStepSets
            }
            start = clampStart(start, muscle)
        }
        return start
    }

    /// Sets added and removed on a muscle's S and A slots between consecutive BUILD weeks.
    func setChanges(_ muscle: Muscle, in builds: [PowerJackWeekLog]) -> (adds: Int, removals: Int) {
        var adds = 0
        var removals = 0
        for (earlier, later) in zip(builds, builds.dropFirst()) {
            for slot in slots where role(slot).role != .main && exercise(slot).primary == muscle {
                guard let before = log(slot, in: earlier)?.sets.count, let after = log(slot, in: later)?.sets.count else { continue }
                adds += max(0, after - before)
                removals += max(0, before - after)
            }
        }
        return (adds, removals)
    }

    /// Planned hard-set credit per muscle, for the whole week or one workout (R3.1).
    func credits(_ counts: [SlotRef: Int], workout: Int? = nil) -> [Muscle: Double] {
        var credits: [Muscle: Double] = [:]
        for slot in slots where workout == nil || slot.workout == workout {
            let exercise = exercise(slot)
            for reps in plannedReps(slot, sets: counts[slot] ?? 0) {
                let factor = reps < PowerJackRules.minRepsForCredit ? PowerJackRules.lowRepFactor : 1
                credits[exercise.primary, default: 0] += factor
                for muscle in Set(exercise.secondaries) where muscle != exercise.primary {
                    credits[muscle, default: 0] += PowerJackRules.secondaryCredit * factor
                }
            }
        }
        return credits
    }

    private func plannedReps(_ slot: SlotRef, sets: Int) -> [Int] {
        guard sets > 0 else { return [] }
        switch role(slot).tag {
        case .heavy: return Array(repeating: heavyReps, count: sets)
        case .volume: return Array(repeating: volumeReps, count: sets)
        case .topAndBack: return [heavyReps] + Array(repeating: volumeReps, count: max(0, sets - 1))
        case nil: return Array(repeating: repRange(slot).lowerBound, count: sets)
        }
    }

    /// Keeps every credited muscle within its cap and 10 credits a session after adding a set to `slot`.
    func hasRoom(_ counts: [SlotRef: Int], adding slot: SlotRef) -> Bool {
        var next = counts
        next[slot, default: 0] += 1
        let week = credits(next)
        let session = credits(next, workout: slot.workout)
        let exercise = exercise(slot)
        return ([exercise.primary] + exercise.secondaries).allSatisfy { muscle in
            week[muscle, default: 0] <= Double(cap(muscle))
                && session[muscle, default: 0] <= PowerJackRules.maxCreditsPerSessionPerMuscle
        }
    }

    // MARK: Block start

    /// R3.3 and R3.4: each slot's working sets at a block start.
    func blockStartSetCounts() -> [SlotRef: Int] {
        var counts = liftSetCounts()
        for slot in slots where role(slot).role != .main {
            counts[slot] = role(slot).role == .secondary ? PowerJackRules.secondaryStartSets : PowerJackRules.accessoryStartSets
        }

        let direct = Dictionary(grouping: slots, by: { exercise($0).primary }).mapValues { Set($0.map(\.workout)).count }
        let targets = Dictionary(uniqueKeysWithValues: targetedMuscles.map { muscle in
            (muscle, min(Double(blockStart(muscle)), PowerJackRules.maxCreditsPerSessionPerMuscle * Double(direct[muscle] ?? 0)))
        })
        let adjustable = { (muscle: Muscle) in
            slots.filter { role($0).role != .main && exercise($0).primary == muscle }
        }

        for _ in 0..<200 {
            var changed = false
            let current = credits(counts)
            // Trim: over target by more than the tolerance.
            for (muscle, target) in targets where current[muscle, default: 0] > target + PowerJackRules.creditTolerance {
                let candidate = adjustable(muscle)
                    .filter { counts[$0, default: 0] > PowerJackRules.minSetsPerExposure }
                    .max { a, b in
                        (counts[a]!, fatigueRank(a), a.workout, a.entry) < (counts[b]!, fatigueRank(b), b.workout, b.entry)
                    }
                if let candidate {
                    counts[candidate]! -= 1
                    changed = true
                }
            }
            // Fill: short by the tolerance or more, focus muscles first, then the largest gap.
            let refreshed = credits(counts)
            let short = targets
                .filter { $0.value - refreshed[$0.key, default: 0] >= PowerJackRules.creditTolerance }
                .sorted { a, b in
                    (isFocus(a.key) ? 1 : 0, a.value - refreshed[a.key, default: 0])
                        > (isFocus(b.key) ? 1 : 0, b.value - refreshed[b.key, default: 0])
                }
            for (muscle, _) in short {
                if let candidate = fillCandidate(adjustable(muscle), counts: counts) {
                    counts[candidate]! += 1
                    changed = true
                }
            }
            if !changed { break }
        }
        return counts
    }

    /// R3.4's fill order: fewest sets, accessories before secondaries, then earlier in the week.
    func fillCandidate(_ candidates: [SlotRef], counts: [SlotRef: Int]) -> SlotRef? {
        candidates
            .filter { counts[$0, default: 0] < PowerJackRules.maxSetsPerSlot && hasRoom(counts, adding: $0) }
            .min { a, b in
                (counts[a, default: 0], role(a).role == .accessory ? 0 : 1, a.workout, a.entry)
                    < (counts[b, default: 0], role(b).role == .accessory ? 0 : 1, b.workout, b.entry)
            }
    }

    private func fatigueRank(_ slot: SlotRef) -> Int {
        switch exercise(slot).fatigue {
        case .low: 0
        case .moderate: 1
        case .high: 2
        }
    }

    /// R3.3: weekly lift sets spread over each main lift's exposures, 2 to 5 each.
    func liftSetCounts() -> [SlotRef: Int] {
        var counts: [SlotRef: Int] = [:]
        let mainSlots = slots.filter { role($0).role == .main }
        let lifts = Dictionary(grouping: mainSlots, by: { exercise($0).id })
        for (_, liftSlots) in lifts {
            let lift = exercise(liftSlots[0])
            var total = PowerJackRules.liftSets(goal)
            if lift.pattern == .hinge {
                total = max(PowerJackRules.liftSetsFloor, Int((PowerJackRules.hingeFactor * Double(total)).rounded(.up)))
            }
            total = min(max(total, PowerJackRules.liftSetsFloor), PowerJackRules.liftSetsCap)
            // An exposure is all of the lift's entries in one workout.
            let exposures = Dictionary(grouping: liftSlots, by: \.workout).sorted { $0.key < $1.key }.map(\.value)
            total = min(total, PowerJackRules.maxSetsPerSlot * exposures.count)

            var perExposure = Array(repeating: total / exposures.count, count: exposures.count)
            let extraFirst: PowerJackTag = goal == .bigger ? .volume : .heavy
            let order = exposures.indices.sorted { a, b in
                let aFirst = role(exposures[a][0]).tag == extraFirst || role(exposures[a][0]).tag == .topAndBack
                let bFirst = role(exposures[b][0]).tag == extraFirst || role(exposures[b][0]).tag == .topAndBack
                return aFirst != bFirst ? aFirst : a < b
            }
            for index in order.prefix(total % exposures.count) { perExposure[index] += 1 }

            for (index, exposure) in exposures.enumerated() {
                let sets = min(max(perExposure[index], PowerJackRules.minSetsPerExposure), PowerJackRules.maxSetsPerSlot)
                if exposure.count == 1 {
                    counts[exposure[0]] = sets
                } else {
                    // A TOP entry, then the BACK sets spread over the BACK entries, earlier first.
                    counts[exposure[0]] = PowerJackRules.topSets
                    let back = max(exposure.count - 1, sets - PowerJackRules.topSets)
                    for (offset, slot) in exposure.dropFirst().enumerated() {
                        counts[slot] = back / (exposure.count - 1) + (offset < back % (exposure.count - 1) ? 1 : 0)
                    }
                }
            }
        }
        return counts
    }

    // MARK: Within a block

    /// R3.6 (a) and R3.3: slots that lose a set for the rest of the block after 2 fatigued BUILD weeks.
    /// Their load holds this week instead of a cut (decision 25).
    func setCuts(header: PowerJackWeekPlanHeader) -> Set<SlotRef> {
        let counted = currentBlockBuildWeeks.filter { !$0.isPartial }
        guard counted.count >= PowerJackRules.strainWeeks else { return [] }
        let recent = Array(counted.suffix(PowerJackRules.strainWeeks))
        guard let last = recent.last else { return [] }
        var cuts: Set<SlotRef> = []

        // Muscles: S and A slots only.
        for muscle in targetedMuscles {
            let muscleSlots = slots.filter { role($0).role != .main && exercise($0).primary == muscle }
            guard recent.allSatisfy({ fatigued(muscleSlots, in: $0) }),
                  setChanges(muscle, in: currentBlockBuildWeeks).removals == 0
            else { continue }
            let candidate = muscleSlots
                .filter { strainSign($0, in: last) && (log($0, in: last)?.sets.count ?? 0) >= 2 && !painState(exercise($0)).inEpisode }
                .max { a, b in
                    ((log(a, in: last)?.sets.count ?? 0), a.workout, a.entry) < ((log(b, in: last)?.sets.count ?? 0), b.workout, b.entry)
                }
            if let candidate { cuts.insert(candidate) }
        }

        // Main lifts: once a block, from the strained exposure with the most sets.
        let lifts = Dictionary(grouping: slots.filter { role($0).role == .main }, by: { exercise($0).id })
        for (_, liftSlots) in lifts {
            guard recent.allSatisfy({ fatigued(liftSlots, in: $0) }) else { continue }
            let liftSets = currentBlockBuildWeeks.map { week in liftSlots.compactMap { log($0, in: week)?.sets.count }.reduce(0, +) }
            guard !zip(liftSets, liftSets.dropFirst()).contains(where: { $1 < $0 }) else { continue }
            let total = liftSets.last ?? 0
            let candidate = liftSlots
                .filter { strainSign($0, in: last) && (log($0, in: last)?.sets.count ?? 0) > PowerJackRules.minSetsPerExposure }
                .max { a, b in
                    ((log(a, in: last)?.sets.count ?? 0), role(a).tag == .volume ? 1 : 0, a.workout, a.entry)
                        < ((log(b, in: last)?.sets.count ?? 0), role(b).tag == .volume ? 1 : 0, b.workout, b.entry)
                }
            if let candidate, total - 1 >= PowerJackRules.liftSetsFloor { cuts.insert(candidate) }
        }
        return cuts
    }

    /// Strain on at least half of the assessable exposures of these slots.
    private func fatigued(_ group: [SlotRef], in week: PowerJackWeekLog) -> Bool {
        let assessable = group.filter { classes($0, in: week)?.contains { $0 != .none } ?? false }
        guard !assessable.isEmpty else { return false }
        return Double(assessable.filter { strainSign($0, in: week) }.count) >= Double(assessable.count) / 2
    }

    /// Drops one working set, a BACK set in a TOP + BACK entry, never the last one.
    func removeSet(_ plan: inout PowerJackEntryPlan) {
        guard plan.sets.count > max(1, plan.topSets + (plan.topSets > 0 ? 1 : 0)) else { return }
        plan.sets.removeLast()
        plan.reasons.append(.setCut)
    }

    /// R3.5: one set on one S or A slot for a muscle whose last BUILD weeks were clean.
    func addSets(_ plans: inout [SlotRef: PowerJackEntryPlan], header: PowerJackWeekPlanHeader) {
        guard header.type == .build, !header.caution, !header.isLastBuildWeek else { return }
        let counted = currentBlockBuildWeeks.filter { !$0.isPartial }
        var counts = plans.mapValues(\.sets.count)
        let current = credits(counts)
        var added = 0

        let eligible = targetedMuscles.filter { muscle in
            let needed = isFocus(muscle) ? PowerJackRules.focusAddEligibleWeeks : PowerJackRules.addEligibleWeeks
            let changes = setChanges(muscle, in: currentBlockBuildWeeks)
            let limit = max(1, (PowerJackRules.blockAddPct / 100 * Double(blockStart(muscle))).roundedHalfUp)
            return counted.count >= needed
                && counted.suffix(needed).allSatisfy { isClean(muscle, in: $0) }
                && changes.removals == 0
                && changes.adds < limit
        }
        .sorted { a, b in
            (isFocus(a) ? 1 : 0, Double(cap(a)) - current[a, default: 0]) > (isFocus(b) ? 1 : 0, Double(cap(b)) - current[b, default: 0])
        }

        for muscle in eligible where added < PowerJackRules.maxAddsPerWeek {
            let candidates = slots.filter { slot in
                guard role(slot).role != .main, exercise(slot).primary == muscle, let plan = plans[slot] else { return false }
                let unchangedLoad = plan.reasons.allSatisfy { [.repStep, .hold, .widenRange].contains($0) }
                return unchangedLoad && !plan.reasons.contains(.addedSet) && !painState(exercise(slot)).inEpisode
            }
            guard let slot = fillCandidate(candidates, counts: counts), var plan = plans[slot], let last = plan.sets.last else { continue }
            let low = repRange(slot).lowerBound
            plan.sets.append(PowerJackSetPlan(reps: last.reps.map { max(low, $0 + PowerJackRules.newSetRepsOffset) }, load: last.load))
            plan.reasons.append(.addedSet)
            plans[slot] = plan
            counts[slot, default: 0] += 1
            added += 1
        }
    }

    /// R3.5: every exposure of the muscle's exercises MET or EASY from a tap, not calibrating, and
    /// pain at most Mild and not rising.
    private func isClean(_ muscle: Muscle, in week: PowerJackWeekLog) -> Bool {
        let exposures = slots.filter { exercise($0).primary == muscle && !workoutSkipped($0, in: week) }
            .compactMap { slot in log(slot, in: week).map { (slot, $0) } }
            .filter { $0.1.hasCompletedSets }
        guard !exposures.isEmpty else { return false }
        return exposures.allSatisfy { slot, entry in
            guard !entry.calibrating,
                  let classes = classes(slot, in: week),
                  classes.allSatisfy(\.rises),
                  entry.parts.allSatisfy({ $0.source == .tapped }),
                  let pain = entry.pain, pain.rawValue <= PowerJackRules.addMaxPain.rawValue
            else { return false }
            let previous = previousBuildWeek(before: week).flatMap { log(slot, in: $0)?.pain }
            return pain.rawValue <= (previous?.rawValue ?? pain.rawValue)
        }
    }
}
