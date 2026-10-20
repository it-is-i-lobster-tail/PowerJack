//
//  BuildContext.swift
//  PowerJack
//
//  What the engine derives from the logs before it plans a week: blocks, each slot's state and effort readings.
//  It's a cache of the logs, so the same logs always give the same plan (ENG-04).
//

import Foundation

/// Effort on one exposure measured against its aim (EFF-06).
struct EffortReading: Equatable {
    enum Kind {
        case harder
        case onTarget
        case easier
        /// No tapped rating. Only the smallest step is allowed (ENG-02).
        case unrated
    }

    var kind: Kind
    /// Reps left on the last set: tapped, mapped from an old word, or inferred from the reps.
    var rir: Int
    var target: Int
    /// `rir` minus `target`.
    var gap: Int
    var band: Int
    var tapped: Bool
}

/// A slot's state after replaying its exposures (CLOCK 1).
struct BuildSlotState: Equatable {
    /// Misses in a row, counting 0.5 for a miss soon after a hard session (LOAD-07).
    var missStreak = 0.0
    var painHold = false
    /// Pain at or below this releases a hold (PAIN-03).
    var clearLevel = LevelOfPain.mild
    /// Exposures since a hold was released, or nil if none was.
    var exposuresSinceRelease: Int?
    /// Exposures in a row at Moderate pain or worse (PAIN-02).
    var painStreak = 0
    /// The latest done exposure's pain, nil when it wasn't rated.
    var lastPain: LevelOfPain?
    /// The rated pain before `lastPain`.
    var previousPain: LevelOfPain?
    /// The week the latest hold started.
    var holdStartWeek: Int?
    /// Working sets before a severe pain cut, until they're all back.
    var setsBeforePainCut: Int?
    /// One per history exposure: the slot was held while it was done.
    var heldDuring: [Bool] = []
    /// One per history exposure: it was a calibration exposure (START-05).
    var calibrating: [Bool] = []

    /// LOAD-06 jumps and ramp-in sets stay off for two exposures after a hold ends.
    var inPostHold: Bool {
        guard let exposuresSinceRelease else { return false }
        return exposuresSinceRelease < BuildRules.postHoldExposures
    }
    var painRose: Bool {
        guard let lastPain, let previousPain else { return false }
        return lastPain.rawValue > previousPain.rawValue
    }
}

struct BuildContext {
    let input: BuildInput
    /// The block each week belongs to. Return weeks form their own block.
    let blocks: [Int]
    let states: [BuildSlotState]

    init(_ input: BuildInput) {
        let blocks = Self.blocks(of: input.weeks)
        self.input = input
        self.blocks = blocks
        states = input.slots.map { Self.state(of: $0, weeks: input.weeks, blocks: blocks) }
    }

    var weeks: [BuildWeek] { input.weeks }
    var slots: [BuildSlot] { input.slots }
    var lastIndex: Int { weeks.count - 1 }
    var lastWeek: BuildWeek { weeks[lastIndex] }

    /// The slot's most recent exposure, done or not.
    func latest(_ slot: Int) -> BuildExposure? { slots[slot].history.last }
    func latestDone(_ slot: Int) -> BuildExposure? { slots[slot].history.last(where: \.isDone) }

    /// The slot's latest exposure in a week of `kind`, done or not.
    func latest(_ slot: Int, in kind: WeekKind) -> BuildExposure? {
        slots[slot].history.last { weeks[$0.weekIndex].kind == kind }
    }

    /// The done exposure right before `exposure`.
    func doneExposure(_ slot: Int, before exposure: BuildExposure) -> BuildExposure? {
        slots[slot].history.last { $0.isDone && $0.weekIndex < exposure.weekIndex }
    }

    func exposure(_ slot: Int, inWeek weekIndex: Int) -> BuildExposure? {
        slots[slot].history.first { $0.weekIndex == weekIndex }
    }

    func isCalibration(_ slot: Int, _ exposure: BuildExposure) -> Bool {
        guard let index = slots[slot].history.firstIndex(of: exposure) else { return false }
        return states[slot].calibrating[index]
    }

    func wasHeld(_ slot: Int, _ exposure: BuildExposure) -> Bool {
        guard let index = slots[slot].history.firstIndex(of: exposure) else { return false }
        return states[slot].heldDuring[index]
    }

    /// Week indexes in `block`, oldest first.
    func weekIndexes(inBlock block: Int) -> [Int] {
        blocks.indices.filter { blocks[$0] == block }
    }

    /// Reads an exposure's effort against the aim it was planned with (EFF-06).
    func reading(_ slot: Int, _ exposure: BuildExposure) -> EffortReading {
        let exercise = slots[slot].exercise
        let target = exposure.rirTarget ?? BuildEngine.aim(
            for: weeks[exposure.weekIndex],
            exercise: exercise,
            reps: exposure.repTarget,
            failureBlocked: true
        )
        let band = (exposure.repTarget ?? 0) > BuildRules.highRepThreshold
            ? BuildRules.highRepTolerance
            : BuildRules.tolerance
        let rir: Int
        let tapped: Bool
        switch exposure.effort {
        case .tapped(let value):
            (rir, tapped) = (value, true)
        case .legacy(let value):
            (rir, tapped) = (value, false)
        case .missing:
            // A miss reads as failure; otherwise the aim was reachable, nothing more (RIR-06).
            (rir, tapped) = (exposure.missed ? 0 : target, false)
        }
        let gap = min(rir, 5) - target
        let kind: EffortReading.Kind
        if exposure.missed {
            kind = .harder
        } else if rir == 0 && !BuildRules.failureFatigueLevels.contains(exercise.fatigueLevel) {
            kind = .harder
        } else if gap < -band {
            kind = .harder
        } else if !tapped {
            kind = .unrated
        } else if gap > band {
            kind = .easier
        } else {
            kind = .onTarget
        }
        return EffortReading(kind: kind, rir: rir, target: target, gap: gap, band: band, tapped: tapped)
    }
}

//
// Derivation
//
private extension BuildContext {
    /// A new block starts after a deload, when return weeks start or end, and when a break makes a week block week 1.
    static func blocks(of weeks: [BuildWeek]) -> [Int] {
        var blocks: [Int] = []
        for (index, week) in weeks.enumerated() {
            guard index > 0 else {
                blocks.append(0)
                continue
            }
            let previous = weeks[index - 1]
            let startsBlock = previous.kind == .deload
                || (week.kind == .return) != (previous.kind == .return)
                || (week.kind == .build && week.blockWeek == 1 && previous.kind == .build && previous.blockWeek != 1)
            blocks.append(blocks[index - 1] + (startsBlock ? 1 : 0))
        }
        return blocks
    }

    static func state(of slot: BuildSlot, weeks: [BuildWeek], blocks: [Int]) -> BuildSlotState {
        var state = BuildSlotState()
        var previous: BuildExposure?
        var lastRatedPain: LevelOfPain?
        var seenDone = false

        for exposure in slot.history {
            // Planning a back-off or starting a block cleared the streak before this exposure (LOAD-07, BLK-06).
            if exposure.code == .loadDown { state.missStreak = 0 }
            if let previous, blocks[exposure.weekIndex] != blocks[previous.weekIndex] { state.missStreak = 0 }
            if exposure.code == .painCheckIn, let previous {
                state.setsBeforePainCut = max(state.setsBeforePainCut ?? 0, previous.plannedSets)
            }
            if let target = state.setsBeforePainCut, exposure.plannedSets >= target, exposure.code != .painCheckIn {
                state.setsBeforePainCut = nil
            }
            previous = exposure

            let calibrating = exposure.code == .calibrate
                || (!seenDone && exposure.code == nil && exposure.plannedLoad == nil && exposure.repTarget == nil)
            state.calibrating.append(calibrating)
            state.heldDuring.append(state.painHold)
            guard exposure.isDone else { continue }
            seenDone = true
            let held = state.painHold

            if let pain = exposure.pain {
                if pain.rawValue >= BuildRules.holdAt.rawValue {
                    state.painStreak += 1
                } else if pain.rawValue <= BuildRules.progressMax.rawValue {
                    state.painStreak = 0
                }
                if state.painHold {
                    if pain.rawValue <= state.clearLevel.rawValue {
                        state.painHold = false
                        state.exposuresSinceRelease = 0
                    }
                } else if pain.rawValue >= BuildRules.holdAt.rawValue {
                    // The clear level is the pain before the hold, at least Mild. A restart keeps the first one.
                    if state.holdStartWeek == nil, let before = lastRatedPain, before.rawValue > state.clearLevel.rawValue {
                        state.clearLevel = before
                    }
                    state.painHold = true
                    state.holdStartWeek = exposure.weekIndex
                    state.exposuresSinceRelease = nil
                } else if let count = state.exposuresSinceRelease {
                    state.exposuresSinceRelease = count + 1
                }
                state.previousPain = lastRatedPain
                state.lastPain = pain
                lastRatedPain = pain
            } else {
                if !state.painHold, let count = state.exposuresSinceRelease {
                    state.exposuresSinceRelease = count + 1
                }
                state.previousPain = lastRatedPain
                state.lastPain = nil
            }

            // Held, deload, return and calibration exposures leave the streak alone (CLOCK 1).
            if !held, weeks[exposure.weekIndex].kind == .build, !calibrating {
                if exposure.missed {
                    state.missStreak += exposure.shortGap ? BuildRules.shortGapMissWeight : 1
                } else {
                    state.missStreak = 0
                }
            }
        }
        return state
    }
}
