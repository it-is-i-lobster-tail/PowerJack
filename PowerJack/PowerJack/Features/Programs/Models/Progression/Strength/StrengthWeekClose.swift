//
//  StrengthWeekClose.swift
//  PowerJack
//
//  Runs when a strength week ends: folds its sessions into the lift records (e1RM, flags,
//  plateaus, pain, the break clock) and decides what the next week is (the weekly loop, steps 1-4).
//

import Foundation

/// A finished week, as the rules read it.
struct StrengthClosedWeek {
    struct Entry {
        var key: String
        var role: StrengthRole
        var zone: StrengthZone?
        var curve: StrengthCurve
        var session: StrengthSession
    }

    var entries: [Entry]
    var priorityKeys: [String]
    var kind: WeekKind
    var closedAt: Date
}

enum StrengthWeekClose {
    static func close(_ state: inout StrengthState, week: StrengthClosedWeek) {
        let entries = week.entries.sorted { ($0.session.date ?? .distantFuture) < ($1.session.date ?? .distantFuture) }

        // Every session moves the lift's pain and break clock, accessories included.
        for entry in entries {
            StrengthPain.record(&state[entry.key].pain, session: entry.session)
            if entry.session.trained, let date = entry.session.date {
                state[entry.key].lastTrained = max(state[entry.key].lastTrained ?? .distantPast, date)
            }
        }

        let loaded = Dictionary(grouping: entries.filter { $0.role != .accessory }, by: \.key)
        for (key, liftEntries) in loaded {
            closeLift(&state[key], entries: liftEntries, at: week.closedAt)
        }
        closeClock(&state, week: week, loadedKeys: Array(loaded.keys))
    }

    // MARK: Lifts

    private static func closeLift(
        _ record: inout StrengthLiftRecord,
        entries: [StrengthClosedWeek.Entry],
        at now: Date
    ) {
        let trained = entries.map(\.session).filter(\.trained)
        guard let curve = entries.first?.curve, !trained.isEmpty else { return }
        record.stepThisWeek = nil

        let calibrating = trained.contains { $0.plan.kind == .calibration }
        let returnBand = trained.filter { $0.plan.kind == .returnWeek1 }.map(\.plan.returnBand).max()
        let returned = trained.contains { $0.plan.kind.isReturn }
        if let returnBand {
            // Back from a break: two fast updates, and over 90 days off starts from 75% of the old e1RM (12.2, 12.4).
            record.fastUpdatesLeft = StrengthRules.fastWeeks
            if returnBand >= 4 {
                record.e1rmKg = record.e1rmKg.map { $0 * 0.75 }
                record.calibrationWeeksLeft = StrengthRules.calibrationWeeks
            }
        }

        let before = record.e1rmKg
        let weekly = StrengthEstimate.update(
            &record,
            with: trained,
            curve: curve,
            calibrating: calibrating || record.isCalibrating
        )
        if calibrating || returnBand == 4 {
            record.calibrationWeeksLeft = max(0, record.calibrationWeeksLeft - 1)
        }

        // 10.1-10.2: only normal sessions after the last deload, return or pain hold count.
        let painActive = record.pain.isRamping || record.pain.holds || record.pain.pending != nil
        let normal = trained.filter { $0.plan.kind == .normal && !$0.isPainful }
        if returned || trained.contains(where: { $0.plan.kind.isLight }) || painActive {
            record.marks = []
            record.dropReferenceKg = nil
            record.dropWeeks = 0
            record.flagged = false
        } else if !calibrating {
            flag(&record, sessions: normal, weekly: weekly, before: before, at: now)
        }

        // 11: plateau windows hold normal weeks only, and restart after calibration, a return or pain,
        // so a stall is never called on loss that pain caps caused (adopted fix 2).
        let painEased = trained.contains { $0.plan.kind == .painCut || $0.plan.kind == .painLighter }
        if calibrating || returned || painEased {
            record.stallPoints = []
        } else if !normal.isEmpty, !trained.contains(where: { $0.plan.kind.isLight }), let e1rm = record.e1rmKg {
            let heavy = entries.filter { $0.session.plan.kind == .normal }
                .min { $0.session.plan.repsToFailure < $1.session.plan.repsToFailure }?.session
            let planE1rm = heavy.flatMap { session in
                session.plan.intendedKg.map { $0 / curve.share(repsToFailure: session.plan.repsToFailure) }
            }
            let point = StallPoint(
                e1rmKg: e1rm,
                planE1rmKg: planE1rm,
                plannedSets: entries.reduce(0) { $0 + $1.session.plan.sets.count },
                completedSets: trained.reduce(0) { $0 + $1.completedSets.count },
                flagged: record.flagged
            )
            record.stallPoints = Array((record.stallPoints + [point]).suffix(StrengthRules.stallWindowAdvanced))
            if record.rebuildWeeksLeft > 0 { record.rebuildWeeksLeft -= 1 }
        }
    }

    /// 10.2: (a) 2 of the last 3 counted sessions within 14 days fell 2+ reps short or missed a rep,
    /// or (b) two weekly e1RMs in a row sat 5% under the e1RM before the drop.
    private static func flag(
        _ record: inout StrengthLiftRecord,
        sessions: [StrengthSession],
        weekly: Double?,
        before: Double?,
        at now: Date
    ) {
        let windowStart = now.addingTimeInterval(-Double(StrengthRules.flagWindowDays) * 86_400)
        let marks = sessions.map { session in
            SessionMark(
                date: session.date ?? now,
                bad: (session.delta ?? 0) <= StrengthRules.flagDelta || !session.missedSets.isEmpty
            )
        }
        record.marks = Array((record.marks + marks).suffix(StrengthRules.flagLastSessions)).filter { $0.date > windowStart }
        let sessionFlag = record.marks.count(where: \.bad) >= StrengthRules.flagBadSessions

        var dropFlag = false
        if record.confidence(at: now) >= StrengthRules.confidenceMin, let weekly, let before {
            let reference = record.dropReferenceKg ?? before
            if weekly <= reference * (1 - StrengthRules.mdcShare) {
                record.dropReferenceKg = reference
                record.dropWeeks += 1
            } else {
                record.dropReferenceKg = nil
                record.dropWeeks = 0
            }
            dropFlag = record.dropWeeks >= 2
        }
        record.flagged = sessionFlag || dropFlag
    }

    // MARK: Block clock

    private static func closeClock(_ state: inout StrengthState, week: StrengthClosedWeek, loadedKeys: [String]) {
        let sessions = week.entries.map(\.session)
        let anyTrained = sessions.contains(where: \.trained)
        // 12.5: a return week is one where every priority lift trained came back from a break. One lift back from
        // a missed session is not, so it neither skips the planned deload nor restarts the count.
        let primaries = week.entries.filter { $0.role == .primary && $0.session.trained }
        let returnWeek = !primaries.isEmpty && primaries.allSatisfy { $0.session.plan.kind == .returnWeek1 }
        var clock = state.clock
        if anyTrained { clock.trainedWeeks += 1 }
        clock.recentWeeks = Array((clock.recentWeeks + [StrengthClock.WeekMark(
            deload: week.kind == .deload,
            returned: returnWeek,
            missed: !anyTrained
        )]).suffix(StrengthRules.deloadSkipWeeks))

        // 10.4b: half the rated lifts hit RIR 0 two normal weeks running.
        let rated = week.entries.filter {
            $0.role != .accessory && $0.session.plan.kind == .normal && $0.session.trained && $0.session.rir != nil
        }
        if week.kind == .build, !rated.isEmpty {
            let share = Double(rated.count { $0.session.rir == 0 }) / Double(rated.count)
            clock.rir0Weeks = share >= StrengthRules.globalRIR0Share ? clock.rir0Weeks + 1 : 0
        }

        if week.kind == .deload {
            clock.weeksSinceDeload = 0
            // Fatigue counts only weeks after the last deload, so RIR 0 weeks must run in a row again (10.1, 10.4).
            clock.rir0Weeks = 0
            startBlock(&clock, flip: clock.lastDeloadPlanned, state: &state, keys: loadedKeys)
            state.clock = clock
            return
        }

        clock.weeksSinceDeload = returnWeek ? 0 : clock.weeksSinceDeload + 1
        let calibrating = week.entries.contains { $0.role == .primary && $0.session.plan.kind == .calibration }
        let flaggedLifts = week.priorityKeys.filter { state[$0].flagged }.count
        let anyFlag = loadedKeys.contains { state[$0].flagged }
        let reactive = flaggedLifts >= StrengthRules.globalFlagLifts || clock.rir0Weeks >= StrengthRules.globalRIR0Weeks
        let blockEnd = !calibrating && clock.blockWeek >= clock.trainWeeks
        // A flag brings the deload a week forward, but never makes a block shorter than 3 training weeks (10.4a).
        let broughtForward = !calibrating
            && clock.blockWeek >= max(clock.trainWeeks - 1, ProgramBlocks.minBuildWeeks)
            && anyFlag
        let backstop = clock.weeksSinceDeload >= StrengthRules.deloadMaxGapWeeks
        // A deload, return or missed week in the last 3 skips the planned deload (10.5).
        let recentBreak = clock.recentWeeks.contains { $0.deload || $0.returned || $0.missed }

        if blockEnd || broughtForward || reactive {
            checkPlateaus(&state, keys: loadedKeys, at: week.closedAt)
        }

        if reactive || backstop || ((blockEnd || broughtForward) && !recentBreak) {
            clock.upcoming = .deload
            clock.startsBlock = false
            clock.lastDeloadPlanned = !reactive
            // A deload week replaces any micro-deload due (module 10 edge cases).
            for key in loadedKeys {
                state[key].flagged = false
                state[key].marks = []
            }
        } else if blockEnd {
            // The skipped deload's block still ends; the next one starts now.
            startBlock(&clock, flip: true, state: &state, keys: loadedKeys)
        } else {
            clock.upcoming = .build
            clock.startsBlock = false
            if !calibrating { clock.blockWeek += 1 }
        }
        state.clock = clock
    }

    /// Next week is block week 1. Stall steps found at the last block's end take effect now.
    private static func startBlock(_ clock: inout StrengthClock, flip: Bool, state: inout StrengthState, keys: [String]) {
        clock.upcoming = .build
        clock.startsBlock = true
        clock.blockWeek = 1
        clock.blockType = flip ? (clock.blockType == .a ? .b : .a) : .a
        for key in state.lifts.keys {
            var record = state[key]
            record.repShiftActive = record.pendingStep == .repZone
            record.stepThisWeek = record.pendingStep
            switch record.pendingStep {
            case .repZone: record.plateauStage = 1
            case .sets: record.plateauStage = 2
            case .reset:
                record.plateauStage = 0
                record.rebuildWeeksLeft = StrengthRules.resetRebuildWeeks
            case .fewerSets, nil: break
            }
            record.pendingStep = nil
            state[key] = record
        }
    }

    // MARK: Plateaus

    /// 11.1-11.5, at a block's last training week: no real gain in 8 (intermediate) or 12 (advanced)
    /// normal weeks picks one change for the next block, cheapest first.
    private static func checkPlateaus(_ state: inout StrengthState, keys: [String], at now: Date) {
        let experience = state.clock.experience
        let window = experience == .advanced ? StrengthRules.stallWindowAdvanced : StrengthRules.stallWindowIntermediate
        for key in keys {
            var record = state[key]
            defer { state[key] = record }
            guard
                record.pendingStep == nil,
                !record.flagged,
                !record.pain.isRamping, !record.pain.holds,
                record.confidence(at: now) >= StrengthRules.confidenceMin,
                record.stallPoints.count >= window
            else { continue }

            let points = Array(record.stallPoints.suffix(window))
            let planned = points.reduce(0) { $0 + $1.plannedSets }
            let completed = points.reduce(0) { $0 + $1.completedSets }
            // 11.2: adherence first. Too many missed sets is not a plateau.
            guard planned > 0, Double(completed) / Double(planned) >= StrengthRules.stallMinAdherence,
                  let first = points.first, let last = points.last
            else { continue }

            let e1rmGain = last.e1rmKg / first.e1rmKg - 1
            let planGain = if let start = first.planE1rmKg, let end = last.planE1rmKg { end / start - 1 } else { 0.0 }
            guard e1rmGain < StrengthRules.stallMinGain, planGain < StrengthRules.stallMinGain else { continue }

            record.stallPoints = []
            if points.contains(where: \.flagged) {
                record.pendingStep = .fewerSets
                continue
            }
            // Steps 3 and 4 (a session, a variant) are not built, so they always count as failed (Decisions).
            // Advanced heavy slots already run 3 reps, so step 1 has nothing to shift (11.5).
            let canShiftReps = record.plateauStage == 0 && experience == .intermediate
            let canAddSets = record.plateauStage <= 1 && last.completedSets < StrengthRules.stallSetLimit
            record.pendingStep = canShiftReps ? .repZone : canAddSets ? .sets : .reset
        }
    }
}
