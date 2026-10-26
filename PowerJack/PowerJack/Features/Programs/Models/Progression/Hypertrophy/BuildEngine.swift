//
//  BuildEngine.swift
//  PowerJack
//
//  Plans a Build (hypertrophy) program's next week from its logs, following the hypertrophy rulebook.
//  Layers run in order and only restrict the ones below (ENG-01): L1 pain, L2 breaks, L3 fatigue and
//  deloads, L4 volume, L5 load and reps, L6 write.
//

import Foundation

enum BuildEngine {
    /// How a new block treats volume at its start.
    enum Review {
        /// Too few build weeks to judge, so volume holds (BLK-05, BLK-08).
        case none
        /// Step each muscle up, hold or down (VOL-05).
        case normal
        /// Every muscle holds, as after a long break (BLK-08).
        case holdAll
    }

    /// Plans the week after `input.weeks.last` once it's finished (CLOCK 2, then CLOCK 3 when a block ends).
    static func plan(_ input: BuildInput) -> BuildPlan {
        let context = BuildContext(input)
        let last = context.lastWeek
        let trained = context.slots.indices.contains { context.exposure($0, inWeek: context.lastIndex)?.isDone == true }

        guard trained else {
            // A skipped build week repeats; a skipped deload still counts as the deload (FREQ-06).
            return last.kind == .deload
                ? newBlock(context, review: reviewAfterDeload(context))
                : repeatWeek(context)
        }
        switch last.kind {
        case .deload:
            return newBlock(context, review: reviewAfterDeload(context))
        case .return:
            if last.returnBand == 3, last.blockWeek < BuildRules.returnWeeks[2] {
                return returnWeek(context, band: last.returnBand, week: last.blockWeek + 1)
            }
            return newBlock(context, review: .holdAll, afterReturn: true)
        case .build:
            if last.blockWeek >= last.buildWeeks {
                return deloadWeek(context, reactive: false)
            }
            if reactiveDeloadDue(context) {
                return deloadWeek(context, reactive: true)
            }
            return buildWeek(context, blockWeek: last.blockWeek + 1)
        }
    }

    /// Replans the rest of a week after a long break (CLOCK 0, BLK-07, BLK-08). `input.weeks.last` is the
    /// last week before the one being replanned; `input.slots` are the workouts not started yet.
    /// Band 1 starts a new block, and the break counts as its deload after 2 build weeks.
    /// Bands 2 and 3 start return weeks.
    static func planAfterBreak(_ input: BuildInput, band: Int) -> BuildPlan {
        let context = BuildContext(input)
        // A break that cuts return weeks short starts again from the return weeks, never the loads before the first break.
        let inReturn = context.lastWeek.kind == .return
        guard band < 2 else { return returnWeek(context, band: band, week: 1, fromReturn: inReturn) }
        guard !inReturn else { return newBlock(context, review: .holdAll, afterReturn: true, breakEnded: true) }
        return newBlock(context, review: reviewAfterDeload(context), breakEnded: true)
    }

    /// Reps to leave on the last set (EFF-01). `reps` is the planned rep target.
    static func aim(
        for week: BuildWeek,
        exercise: BuildExercise,
        reps: Int?,
        failureBlocked: Bool,
        calibrating: Bool = false
    ) -> Int {
        guard week.kind == .build else { return BuildRules.deloadRIR }
        if calibrating { return BuildRules.startRIR }
        let base = BuildRules.rir(blockWeek: week.blockWeek, of: week.buildWeeks)
        // The final build week may take the last set to failure, but never on the heaviest lifts (EFF-04).
        if base <= 1, !failureBlocked, BuildRules.failureFatigueLevels.contains(exercise.fatigueLevel) {
            return 0
        }
        // Long and bodyweight sets aim one rep closer to failure (EFF-05).
        if exercise.repsOnly || (reps ?? 0) > BuildRules.highRepThreshold {
            return max(1, base - 1)
        }
        return base
    }

    /// The most reps a slot's target can reach before it must add load (ENG-01).
    static func repCeiling(_ exercise: BuildExercise, repTarget: Int?) -> Int {
        if exercise.repsOnly { return BuildRules.bodyweightRepCap }
        if let repTarget, repTarget > exercise.maxReps { return extendedCeiling(exercise) }
        return exercise.maxReps
    }

    /// LOAD-04's longest rep range for a light lift.
    static func extendedCeiling(_ exercise: BuildExercise) -> Int {
        min(exercise.maxReps + BuildRules.repRangeExtensionMax, BuildRules.maxReps)
    }
}

//
// Weeks
//
extension BuildEngine {
    /// A slot's plan while the week's layers narrow it.
    struct Draft {
        var plan: BuildSlotPlan?
        /// Working sets so far, for the volume math.
        var sets: Int
        var caps = Caps()
        /// No failure set this week (EFF-04).
        var failureBlocked = false
        /// Gained a set this week, its one change (VOL-07).
        var addedSet = false
    }

    /// Limits a higher layer puts on L4 and L5 (PAIN-01, PAIN-03, BLK-07).
    struct Caps {
        /// Pain rose: no increase of any kind.
        var noIncrease = false
        /// No pain tap: one rep or one load step at most.
        var smallStep = false
        /// No LOAD-06 jump.
        var noJump = false
        /// No ramp-in set.
        var noRamp = false
        /// No load above this, the first block after a return.
        var loadCap: Int?
        /// The muscle's fatigue cut this week replaces a back-off with a hold (FAT-02).
        var noBackoff = false
    }

    static func buildWeek(_ context: BuildContext, blockWeek: Int) -> BuildPlan {
        let week = context.nextBuildWeek(blockWeek: blockWeek)
        var drafts = context.slots.indices.map { startDraft(context, $0) }

        for index in drafts.indices where drafts[index].plan == nil {
            painLayer(context, index, &drafts[index])
            drafts[index].caps.loadCap = returnLoadCap(context, index)
        }
        let fatigued = cutFatigue(context, &drafts)
        rampIn(context, &drafts)
        for index in drafts.indices where drafts[index].plan == nil {
            if fatigued.contains(context.slots[index].exercise.primary) {
                drafts[index].failureBlocked = true
            }
            drafts[index].plan = progress(context, index, drafts[index], week: week)
        }
        return finish(context, drafts, week: week)
    }

    static func deloadWeek(_ context: BuildContext, reactive: Bool) -> BuildPlan {
        let week = BuildWeek(kind: .deload, blockWeek: context.lastWeek.blockWeek + 1)
        var drafts = context.slots.indices.map { startDraft(context, $0) }
        for index in drafts.indices {
            let held = drafts[index].plan ?? painPlan(context, index)
            let deload = deloadPlan(context, index, reactive: reactive)
            drafts[index].plan = held.map { lower($0, deload) } ?? deload
        }
        return finish(context, drafts, week: week)
    }

    static func returnWeek(_ context: BuildContext, band: Int, week number: Int, fromReturn: Bool = false) -> BuildPlan {
        let week = BuildWeek(kind: .return, blockWeek: number, returnBand: band)
        var drafts = context.slots.indices.map { Draft(plan: nil, sets: context.latest($0)?.plannedSets ?? 0) }
        for index in drafts.indices {
            let held = painPlan(context, index)
            let back = returnPlan(context, index, band: band, week: number, fromReturn: fromReturn)
            drafts[index].plan = held.map { lower($0, back) } ?? back
        }
        return finish(context, drafts, week: week)
    }

    static func newBlock(
        _ context: BuildContext,
        review: Review,
        afterReturn: Bool = false,
        breakEnded: Bool = false
    ) -> BuildPlan {
        let week = context.nextBuildWeek(blockWeek: 1)
        var drafts = context.slots.indices.map { Draft(plan: nil, sets: context.latest($0)?.plannedSets ?? 0) }
        for index in drafts.indices {
            painLayer(context, index, &drafts[index])
            if drafts[index].plan == nil {
                let rebased = rebaseline(context, index, afterReturn: afterReturn, caps: drafts[index].caps)
                drafts[index].plan = breakEnded && rebased.reason.code == .blockRebase
                    ? BuildSlotPlan(
                        sets: rebased.sets, reps: rebased.reps, load: rebased.load,
                        rirTarget: rebased.rirTarget, reason: .breakRebase
                    )
                    : rebased
            }
            drafts[index].sets = drafts[index].plan?.sets ?? drafts[index].sets
        }
        if review == .normal {
            stepVolume(context, &drafts)
        }
        return finish(context, drafts, week: week)
    }

    /// Every slot repeats what it was given, in the same place in the block (FREQ-06).
    static func repeatWeek(_ context: BuildContext) -> BuildPlan {
        let drafts = context.slots.indices.map { index in
            Draft(plan: repeatPlan(context, index), sets: context.latest(index)?.plannedSets ?? 0)
        }
        var week = context.lastWeek
        // A break handled in the skipped week doesn't carry over, so the repeat can catch the next one.
        if week.kind == .build {
            week = context.nextBuildWeek(blockWeek: week.blockWeek)
        }
        return finish(context, drafts, week: week)
    }

    /// Reviews volume after a deload only when the block had enough build weeks to judge (BLK-05).
    static func reviewAfterDeload(_ context: BuildContext) -> Review {
        buildWeeksDone(context, inBlock: context.blocks[context.lastIndex]) >= BuildRules.minBuildWeeksForReview
            ? .normal
            : .none
    }

    /// Build weeks in `block` where at least one exercise was trained.
    static func buildWeeksDone(_ context: BuildContext, inBlock block: Int) -> Int {
        context.weekIndexes(inBlock: block).count(where: { weekIndex in
            context.weeks[weekIndex].kind == .build
                && context.slots.indices.contains { context.exposure($0, inWeek: weekIndex)?.isDone == true }
        })
    }

    /// Starts a slot's draft, settling it at once when it wasn't trained (FREQ-06).
    static func startDraft(_ context: BuildContext, _ index: Int) -> Draft {
        let latest = context.latest(index)
        var draft = Draft(plan: nil, sets: latest?.plannedSets ?? 0)
        if latest?.isDone != true {
            draft.plan = repeatPlan(context, index)
        }
        return draft
    }

    /// The same plan again, check-in included, as when an exercise was skipped.
    static func repeatPlan(_ context: BuildContext, _ index: Int) -> BuildSlotPlan {
        let latest = context.latest(index)
        let carriedPain = latest.flatMap { $0.checkIn == .none ? nil : $0.checkInSourcePain }
        return BuildSlotPlan(
            sets: max(1, latest?.plannedSets ?? BuildRules.minSetsPerExercise),
            reps: latest?.repTarget,
            load: latest?.plannedLoad,
            rirTarget: 0,
            reason: latest?.code == .calibrate ? .calibrate(repsOnly: context.slots[index].exercise.repsOnly) : .repeatNotDone,
            checkInPain: carriedPain
        )
    }

    /// In a conflict, the lower load wins, then fewer sets (ENG-01). `held`'s reason stays only with its check-in.
    static func lower(_ held: BuildSlotPlan, _ other: BuildSlotPlan) -> BuildSlotPlan {
        var plan = held
        plan.sets = min(held.sets, other.sets)
        if let otherLoad = other.load {
            plan.load = held.load.map { min($0, otherLoad) } ?? otherLoad
        }
        if let otherReps = other.reps {
            plan.reps = held.reps.map { min($0, otherReps) } ?? otherReps
        }
        if held.checkInPain == nil {
            plan.reason = other.reason
        }
        return plan
    }

    /// Clamps sets and reps and sets each slot's aim (L6).
    static func finish(_ context: BuildContext, _ drafts: [Draft], week: BuildWeek) -> BuildPlan {
        let slots = drafts.enumerated().map { index, draft in
            let exercise = context.slots[index].exercise
            var plan = draft.plan ?? repeatPlan(context, index)
            plan.sets = min(max(plan.sets, 1), BuildRules.maxSetsPerExercise)
            plan.load = plan.load.map { min($0, BuildRules.maxLoad) }
            if let reps = plan.reps, week.kind == .build {
                plan.reps = min(max(reps, exercise.minReps), repCeiling(exercise, repTarget: reps))
            }
            let calibrating = plan.reason.code == .calibrate
            let held = context.states[index].painHold || plan.checkInPain != nil
            plan.rirTarget = aim(
                for: week,
                exercise: exercise,
                reps: plan.reps,
                failureBlocked: draft.failureBlocked || held || draft.addedSet,
                calibrating: calibrating
            )
            return plan
        }
        return BuildPlan(week: week, slots: slots)
    }
}
