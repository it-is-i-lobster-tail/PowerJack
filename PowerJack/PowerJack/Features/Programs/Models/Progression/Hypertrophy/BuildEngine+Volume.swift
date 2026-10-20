//
//  BuildEngine+Volume.swift
//  PowerJack
//
//  Weekly sets per muscle: fatigue flags and cuts (L3), ramp-in to the weekly floor (L4) and the
//  block review that steps volume up, holds it or steps it down.
//

import Foundation

//
// Credits
//
extension BuildEngine {
    /// Planned credits per muscle for the week being drafted (VOL-01).
    static func plannedCredits(_ context: BuildContext, _ drafts: [Draft], workout: Int? = nil) -> [Muscle: Double] {
        var credits: [Muscle: Double] = [:]
        for (index, draft) in drafts.enumerated() where workout == nil || context.slots[index].workout == workout {
            for (muscle, credit) in context.slots[index].exercise.credits {
                credits[muscle, default: 0] += credit * Double(draft.sets)
            }
        }
        return credits
    }

    /// Planned or hard logged credits per muscle in one finished week (VOL-01, VOL-04).
    static func weekCredits(_ context: BuildContext, weekIndex: Int, logged: Bool) -> [Muscle: Double] {
        var credits: [Muscle: Double] = [:]
        for index in context.slots.indices {
            guard let exposure = context.exposure(index, inWeek: weekIndex) else { continue }
            let sets = logged ? hardSets(exposure) : exposure.plannedSets
            for (muscle, credit) in context.slots[index].exercise.credits {
                credits[muscle, default: 0] += credit * Double(sets)
            }
        }
        return credits
    }

    /// Completed sets of at least 5 reps, rated 4 reps left or fewer. Unrated sets count (VOL-01, EFF-07).
    static func hardSets(_ exposure: BuildExposure) -> Int {
        guard (exposure.tappedRIR ?? 0) <= BuildRules.hardSetMaxRIR else { return 0 }
        return exposure.done.count(where: { ($0.reps ?? $0.plannedReps ?? 0) >= BuildRules.minRepsForCredit })
    }

    static func ceiling(for muscle: Muscle, _ context: BuildContext) -> Double {
        context.input.focus.contains(muscle) ? BuildRules.focusCeiling : BuildRules.ceiling
    }

    /// Muscles that are the primary of at least one slot. Only they get a floor.
    static func targetMuscles(_ context: BuildContext) -> [Muscle] {
        Muscle.allCases.filter { muscle in context.slots.contains { $0.exercise.primary == muscle } }
    }

    static func primarySlots(_ context: BuildContext, _ muscle: Muscle) -> [Int] {
        context.slots.indices.filter { context.slots[$0].exercise.primary == muscle }
    }

    /// A primary slot of `muscle` was planned with `code` in `block`.
    static func primarySlot(
        of muscle: Muscle,
        had code: BuildReason.Code,
        inBlock block: Int,
        _ context: BuildContext
    ) -> Bool {
        primarySlots(context, muscle).contains { index in
            context.slots[index].history.contains { context.blocks[$0.weekIndex] == block && $0.code == code }
        }
    }
}

//
// Fatigue (L3)
//
extension BuildEngine {
    struct FatigueFlag {
        /// A set fell short at the planned load or lighter.
        var miss: Bool
        /// The estimated max fell past the noise band.
        var drop: Bool
        var any: Bool { miss || drop }
    }

    /// Flags a fatigued exposure, or nil when it can't be judged: not trained, not a build week, or calibrating (FAT-01).
    static func fatigueFlag(_ context: BuildContext, _ index: Int, weekIndex: Int) -> FatigueFlag? {
        guard
            context.weeks[weekIndex].kind == .build,
            let exposure = context.exposure(index, inWeek: weekIndex),
            exposure.isDone,
            !context.isCalibration(index, exposure)
        else {
            return nil
        }
        let miss = exposure.done.contains { set in
            guard let planned = set.plannedReps else { return false }
            return (set.reps ?? planned) < planned && (set.load ?? 0) <= (set.plannedLoad ?? .max)
        }
        var drop = false
        if let estimatedMax = exposure.estimatedMax, (exposure.tappedRIR ?? 5) <= 4 {
            let earlier = context.slots[index].history
                .filter { earlier in
                    earlier.weekIndex < weekIndex
                        && context.weeks[earlier.weekIndex].kind == .build
                        && (earlier.tappedRIR ?? 5) <= 4
                        && !context.isCalibration(index, earlier)
                }
                .compactMap(\.estimatedMax)
                .suffix(2)
            if earlier.count == 2 {
                let mean = earlier.map(\.tenths).reduce(0, +) / 2
                let band = BuildRules.dropBandPct(for: context.slots[index].exercise.primary)
                drop = estimatedMax.tenths < mean * (1 - band / 100)
            }
        }
        return FatigueFlag(miss: miss, drop: drop)
    }

    /// At least half the muscle's judged primary slots were flagged. A muscle with one primary slot needs a
    /// miss or two drops in a row (FAT-01, FAT-02).
    static func isFatigued(_ muscle: Muscle, weekIndex: Int, _ context: BuildContext) -> Bool {
        let slots = primarySlots(context, muscle)
        let flags = slots.compactMap { index in fatigueFlag(context, index, weekIndex: weekIndex).map { (index, $0) } }
        guard !flags.isEmpty else { return false }
        if slots.count == 1, let (index, flag) = flags.first {
            if flag.miss { return true }
            guard flag.drop, let previous = previousBuildWeek(context, before: weekIndex) else { return false }
            return fatigueFlag(context, index, weekIndex: previous)?.drop == true
        }
        return flags.count(where: { $0.1.any }) * 2 >= flags.count
    }

    /// At least 40% of the judged slots, and at least 2, were flagged (FAT-03).
    static func manyFlagged(weekIndex: Int, _ context: BuildContext) -> Bool {
        let flags = context.slots.indices.compactMap { fatigueFlag(context, $0, weekIndex: weekIndex) }
        let flagged = flags.count(where: \.any)
        return flagged >= 2 && Double(flagged) >= BuildRules.weekShare * Double(flags.count)
    }

    /// The build week right before `weekIndex` in the same block.
    static func previousBuildWeek(_ context: BuildContext, before weekIndex: Int) -> Int? {
        let previous = weekIndex - 1
        guard
            previous >= 0,
            context.blocks[previous] == context.blocks[weekIndex],
            context.weeks[previous].kind == .build
        else {
            return nil
        }
        return previous
    }

    /// Many lifts dipped two build weeks running (FAT-03). After a deload, a dip at the end of build week 2
    /// means fatigue outlasted the deload, so no second deload follows this block (FAT-05).
    static func reactiveDeloadDue(_ context: BuildContext) -> Bool {
        let last = context.lastIndex
        func triggered(at weekIndex: Int) -> Bool {
            guard let previous = previousBuildWeek(context, before: weekIndex) else { return false }
            return manyFlagged(weekIndex: weekIndex, context) && manyFlagged(weekIndex: previous, context)
        }
        guard triggered(at: last) else { return false }
        let blockWeeks = context.weekIndexes(inBlock: context.blocks[last])
        guard let first = blockWeeks.first, first > 0, context.weeks[first - 1].kind == .deload else { return true }
        let weekTwo = blockWeeks.first { context.weeks[$0].kind == .build && context.weeks[$0].blockWeek == 2 }
        return !(weekTwo.map { $0 <= last && triggered(at: $0) } ?? false)
    }

    /// Cuts one set from a muscle fatigued two weeks running, once per block (FAT-02).
    /// Returns the muscles fatigued this week, which take no failure set (EFF-04).
    static func cutFatigue(_ context: BuildContext, _ drafts: inout [Draft]) -> Set<Muscle> {
        let last = context.lastIndex
        var fatigued: Set<Muscle> = []
        for muscle in targetMuscles(context) where isFatigued(muscle, weekIndex: last, context) {
            fatigued.insert(muscle)
            guard
                let previous = previousBuildWeek(context, before: last),
                isFatigued(muscle, weekIndex: previous, context),
                !primarySlot(of: muscle, had: .fatigueCut, inBlock: context.blocks[last], context)
            else {
                continue
            }
            let primary = primarySlots(context, muscle)
            // Its slots hold rather than back off this week; the miss streak is kept.
            for index in primary {
                drafts[index].caps.noBackoff = true
            }
            let flagged = primary.filter { index in
                drafts[index].plan == nil
                    && drafts[index].sets > 1
                    && fatigueFlag(context, index, weekIndex: last)?.any == true
            }
            guard
                let pick = removalOrder(context, drafts, flagged, muscle: muscle).first,
                let exposure = context.latestDone(pick)
            else {
                continue
            }
            drafts[pick].sets -= 1
            drafts[pick].plan = BuildSlotPlan(
                sets: drafts[pick].sets,
                reps: exposure.repTarget ?? exposure.repsDone,
                load: context.slots[pick].exercise.repsOnly ? nil : exposure.load,
                rirTarget: 0,
                reason: .fatigueCut(muscle)
            )
        }
        return fatigued
    }
}

//
// Adding and removing sets (L4, FREQ-04)
//
extension BuildEngine {
    /// VOL-02's slot predicate: the last exposure was tapped, made every rep, landed on target and wasn't painful.
    static func canGainSet(_ context: BuildContext, _ index: Int, _ draft: Draft, from exposure: BuildExposure?) -> Bool {
        guard let exposure, exposure.isDone, !context.isCalibration(index, exposure) else { return false }
        let state = context.states[index]
        let reading = context.reading(index, exposure)
        return reading.tapped
            && !exposure.missed
            && reading.kind == .onTarget
            && !state.painHold
            && !state.inPostHold
            && !state.painRose
            && !draft.caps.noRamp
            && draft.sets < BuildRules.maxSetsPerExercise
    }

    /// One more set keeps every muscle it trains under the per-workout cap and its weekly ceiling (FREQ-02, VOL-03).
    static func hasRoom(_ context: BuildContext, _ index: Int, _ drafts: [Draft]) -> Bool {
        let session = plannedCredits(context, drafts, workout: context.slots[index].workout)
        let weekly = plannedCredits(context, drafts)
        return context.slots[index].exercise.credits.allSatisfy { muscle, credit in
            (session[muscle] ?? 0) + credit <= BuildRules.maxCreditsPerSessionPerMuscle
                && (weekly[muscle] ?? 0) + credit <= ceiling(for: muscle, context)
        }
    }

    /// Fewest planned sets first, then fewest credits for the muscle in that workout, then lower fatigue, then program order.
    static func addOrder(_ context: BuildContext, _ drafts: [Draft], _ candidates: [Int], muscle: Muscle) -> [Int] {
        candidates.sorted { rankKey(context, drafts, $0, muscle) < rankKey(context, drafts, $1, muscle) }
    }

    /// The add order reversed.
    static func removalOrder(_ context: BuildContext, _ drafts: [Draft], _ candidates: [Int], muscle: Muscle) -> [Int] {
        addOrder(context, drafts, candidates, muscle: muscle).reversed()
    }

    private static func rankKey(_ context: BuildContext, _ drafts: [Draft], _ index: Int, _ muscle: Muscle) -> RankKey {
        let session = plannedCredits(context, drafts, workout: context.slots[index].workout)
        return RankKey(
            sets: drafts[index].sets,
            sessionCredits: session[muscle] ?? 0,
            fatigue: FatigueLevel.allCases.firstIndex(of: context.slots[index].exercise.fatigueLevel) ?? 0,
            order: index
        )
    }

    private struct RankKey: Comparable {
        var sets: Int
        var sessionCredits: Double
        var fatigue: Int
        var order: Int

        static func < (lhs: RankKey, rhs: RankKey) -> Bool {
            (lhs.sets, lhs.sessionCredits, lhs.fatigue, lhs.order) < (rhs.sets, rhs.sessionCredits, rhs.fatigue, rhs.order)
        }
    }

    /// A muscle planned under 10 weekly credits gains one set a week, at most 2 a block and 1 per slot (VOL-02).
    /// The slot keeps its load and drops a rep (VOL-07).
    static func rampIn(_ context: BuildContext, _ drafts: inout [Draft]) {
        let block = context.blocks[context.lastIndex]
        for muscle in targetMuscles(context) {
            let primary = primarySlots(context, muscle)
            let cut = primary.contains { drafts[$0].plan?.reason.code == .fatigueCut }
                || primarySlot(of: muscle, had: .fatigueCut, inBlock: block, context)
            guard !cut, (plannedCredits(context, drafts)[muscle] ?? 0) < BuildRules.floor else { continue }

            let rampedSlots = primary.filter { index in
                context.slots[index].history.contains { context.blocks[$0.weekIndex] == block && $0.code == .volumeRamp }
            }
            let steppedUp = primary.count(where: { index in
                context.slots[index].history.contains { context.blocks[$0.weekIndex] == block && $0.code == .volumeUp }
            })
            guard rampedSlots.count + steppedUp < BuildRules.rampInMaxPerBlock else { continue }

            let candidates = primary.filter { index in
                drafts[index].plan == nil
                    && !rampedSlots.contains(index)
                    && canGainSet(context, index, drafts[index], from: context.latestDone(index))
                    && hasRoom(context, index, drafts)
            }
            guard
                let pick = addOrder(context, drafts, candidates, muscle: muscle).first,
                let exposure = context.latestDone(pick)
            else {
                continue
            }
            let exercise = context.slots[pick].exercise
            drafts[pick].sets += 1
            drafts[pick].addedSet = true
            drafts[pick].plan = BuildSlotPlan(
                sets: drafts[pick].sets,
                reps: max(exercise.minReps, (exposure.repTarget ?? exposure.repsDone ?? exercise.minReps) - 1),
                load: exercise.repsOnly ? nil : exposure.load,
                rirTarget: 0,
                reason: .volumeRamp(muscle)
            )
        }
    }
}

//
// Block review (VOL-05, STALL-02)
//
extension BuildEngine {
    enum Verdict: Equatable {
        case progressing
        case flat
        case regressed
        /// The slot's first block, or too few rated exposures. Not counted.
        case noData
        /// Flat or down with more reps left than planned, so the effort was the problem. Not counted.
        case effortLow

        var counted: Bool { self == .progressing || self == .flat || self == .regressed }
    }

    /// Compares this block's mean estimated max with an earlier block's, beyond the noise band (STALL-02, STALL-03).
    static func verdict(_ context: BuildContext, _ index: Int, block: Int) -> Verdict {
        let exercise = context.slots[index].exercise
        let history = context.slots[index].history

        // Valid for progress: a rated build-week exposure, not held, not calibrating, not 5+ (STALL-01).
        func value(_ exposure: BuildExposure) -> Double? {
            guard
                context.weeks[exposure.weekIndex].kind == .build,
                exposure.isDone,
                let rir = exposure.tappedRIR,
                rir <= 4,
                !context.wasHeld(index, exposure),
                !context.isCalibration(index, exposure)
            else {
                return nil
            }
            if exercise.repsOnly {
                return exposure.done.last?.reps.map { Double($0 + rir) }
            }
            return exposure.estimatedMax?.tenths
        }
        func window(_ block: Int) -> [(exposure: BuildExposure, value: Double)] {
            Array(
                history
                    .filter { context.blocks[$0.weekIndex] == block }
                    .compactMap { exposure in value(exposure).map { (exposure, $0) } }
                    .suffix(BuildRules.windowExposures)
            )
        }

        let earlierBlocks = Set(
            history
                .filter { context.blocks[$0.weekIndex] < block && context.weeks[$0.weekIndex].kind == .build }
                .map { context.blocks[$0.weekIndex] }
        ).sorted()
        guard !earlierBlocks.isEmpty else { return .noData }
        let referenceBlock = earlierBlocks.count >= BuildRules.trendBlocks
            ? earlierBlocks[earlierBlocks.count - BuildRules.trendBlocks]
            : earlierBlocks[0]
        let current = window(block)
        let reference = window(referenceBlock)
        guard current.count >= BuildRules.minExposures, reference.count >= BuildRules.minExposures else { return .noData }

        let currentMean = current.map(\.value).reduce(0, +) / Double(current.count)
        let referenceMean = reference.map(\.value).reduce(0, +) / Double(reference.count)
        var band = 1.5 * BuildRules.typicalErrorPct(for: exercise.primary) / Double(min(current.count, reference.count)).squareRoot()
        if exercise.repsOnly {
            band = max(band, 100 / referenceMean)
        }
        let change = (currentMean - referenceMean) / referenceMean * 100

        var verdict: Verdict = change >= band ? .progressing : change <= -band ? .regressed : .flat
        // Fewer sets than before explains a lower number, so it isn't a regression.
        let sets = { (window: [(exposure: BuildExposure, value: Double)]) in
            Double(window.map(\.exposure.plannedSets).reduce(0, +)) / Double(window.count)
        }
        if verdict == .regressed, sets(current) != sets(reference) {
            verdict = .flat
        }
        if verdict != .progressing {
            let gap = Double(current.map { context.reading(index, $0.exposure).gap }.reduce(0, +)) / Double(current.count)
            if gap > Double(BuildRules.tolerance) { return .effortLow }
        }
        return verdict
    }

    /// At a block start, steps each muscle's sets up, holds them or steps them down (VOL-05, VOL-06).
    static func stepVolume(_ context: BuildContext, _ drafts: inout [Draft]) {
        let block = context.blocks[context.lastIndex]
        let blockWeeks = context.weekIndexes(inBlock: block)
        let buildWeeks = blockWeeks.filter { context.weeks[$0].kind == .build }
        guard let lastBuild = buildWeeks.last else { return }
        let verdicts = context.slots.indices.map { verdict(context, $0, block: block) }
        let reactive = context.slots.indices.contains {
            context.exposure($0, inWeek: context.lastIndex)?.code == .deloadReactive
        }
        let plannedByWeek = buildWeeks.map { weekCredits(context, weekIndex: $0, logged: false) }
        let loggedByWeek = buildWeeks.map { weekCredits(context, weekIndex: $0, logged: true) }
        let referenceCredits = weekCredits(context, weekIndex: lastBuild, logged: false)

        for muscle in targetMuscles(context) {
            let primary = primarySlots(context, muscle)
            let reference = referenceCredits[muscle] ?? 0
            let step = max(1, min(BuildRules.blockStepSetsMax, Int(BuildRules.blockStepPct * reference)))
            let counted = primary.filter { verdicts[$0].counted }
            let regressed = counted.count(where: { verdicts[$0] == .regressed })
            let flat = counted.count(where: { verdicts[$0] == .flat })
            let fatigueCut = primarySlot(of: muscle, had: .fatigueCut, inBlock: block, context)
            let newlyHeld = primary.filter { index in
                context.states[index].holdStartWeek.map(blockWeeks.contains) == true
            }
            let steppedUpLast = primary.contains { index in
                blockWeeks.first.flatMap { context.exposure(index, inWeek: $0) }?.code == .volumeUp
            }
            let adherenceShort = zip(plannedByWeek, loggedByWeek).count(where: { planned, logged in
                (logged[muscle] ?? 0) < (planned[muscle] ?? 0)
            }) >= 2
            // A focus muscle may rise until its own ceiling; others when half their slots went flat.
            let wantsMore = context.input.focus.contains(muscle)
                ? reference < BuildRules.focusCeiling
                : flat * 2 >= primary.count && reference < BuildRules.ceiling
            let recovering = !reactive
                && !buildWeeks.contains { isFatigued(muscle, weekIndex: $0, context) }
                && regressed == 0
                && !primary.contains { context.states[$0].painHold }
                && !adherenceShort

            if fatigueCut || regressed * 2 > primary.count {
                removeSets(step, muscle: muscle, from: primary, belowFloor: fatigueCut, context, &drafts)
            } else if !newlyHeld.isEmpty {
                removeSets(step, muscle: muscle, from: newlyHeld, belowFloor: true, pain: true, context, &drafts)
            } else if counted.isEmpty || steppedUpLast {
                continue
            } else if reference > ceiling(for: muscle, context), counted.count == primary.count, flat + regressed == counted.count {
                removeSets(step, muscle: muscle, from: primary, belowFloor: false, context, &drafts)
            } else if recovering, wantsMore {
                addSets(step, muscle: muscle, to: primary, context, &drafts)
            }
        }
    }

    private static func addSets(_ count: Int, muscle: Muscle, to slots: [Int], _ context: BuildContext, _ drafts: inout [Draft]) {
        for _ in 0..<count {
            let candidates = slots.filter { index in
                drafts[index].plan?.reason.code == .blockRebase
                    && canGainSet(context, index, drafts[index], from: context.latest(index, in: .build))
                    && hasRoom(context, index, drafts)
            }
            guard let pick = addOrder(context, drafts, candidates, muscle: muscle).first else { return }
            guard var plan = drafts[pick].plan else { return }
            drafts[pick].sets += 1
            drafts[pick].addedSet = true
            plan.sets = drafts[pick].sets
            // A slot that gains a set keeps its build load this week (VOL-07).
            let build = context.latest(pick, in: .build)
            if plan.load != build?.load, !context.slots[pick].exercise.repsOnly {
                plan.load = build?.load
                plan.reps = build?.repTarget ?? plan.reps
            }
            plan.reason = .volumeUp(muscle)
            drafts[pick].plan = plan
        }
    }

    private static func removeSets(
        _ count: Int,
        muscle: Muscle,
        from slots: [Int],
        belowFloor: Bool,
        pain: Bool = false,
        _ context: BuildContext,
        _ drafts: inout [Draft]
    ) {
        for _ in 0..<count {
            guard belowFloor || (plannedCredits(context, drafts)[muscle] ?? 0) - 1 >= BuildRules.floor else { return }
            let candidates = slots.filter { drafts[$0].sets > 1 && (pain || drafts[$0].plan?.reason.code == .blockRebase) }
            guard let pick = removalOrder(context, drafts, candidates, muscle: muscle).first else { return }
            drafts[pick].sets -= 1
            let sets = drafts[pick].sets
            drafts[pick].plan?.sets = sets
            drafts[pick].plan?.reason = .volumeDown(muscle, pain: pain)
        }
    }
}
