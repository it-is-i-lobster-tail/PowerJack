//
//  PowerJackEngine+Anchors.swift
//  PowerJack
//
//  Each main lift keeps a heavy (H) and a volume (V) series of e1RM values. Its anchor turns into
//  block-start loads (R2.2, R8.2 to R8.4) and a first exposure calibrates it (R8.8).
//

import Foundation

enum PowerJackSeries: Equatable {
    case heavy, volume

    var other: PowerJackSeries { self == .heavy ? .volume : .heavy }
}

extension PowerJackWeekBuilder {
    /// The series a part of a logged exposure feeds, or nil when it isn't main-lift work (R8.3).
    func series(of exposure: PowerJackExposure, part: Int) -> PowerJackSeries? {
        switch exposure.tag {
        case .topAndBack: return part == 0 ? .heavy : .volume
        case .heavy: return .heavy
        case .volume: return .volume
        case nil:
            // Another style's history goes by its planned reps; PowerJack S and A work never counts.
            guard exposure.weekType == nil else { return nil }
            let planned = exposure.entry.sets.last?.plannedReps ?? exposure.entry.sets.last?.reps ?? 0
            return planned <= 6 ? .heavy : .volume
        }
    }

    private func parts(of exercise: PowerJackExercise, in series: PowerJackSeries, before date: Date? = nil)
        -> [(date: Date, exposure: PowerJackExposure, part: PowerJackPart)] {
        context.history(exercise.id).flatMap { exposure in
            exposure.entry.parts.enumerated().compactMap { index, part in
                guard self.series(of: exposure, part: index) == series,
                      date.map({ exposure.date < $0 }) ?? true
                else { return nil }
                return (exposure.date, exposure, part)
            }
        }
    }

    /// The e1RM a past plan was loaded from: its unrounded load at its reps and target.
    func impliedAnchor(_ exercise: PowerJackExercise, _ series: PowerJackSeries, before date: Date? = nil) -> Double? {
        for item in parts(of: exercise, in: series, before: date).reversed() {
            guard item.exposure.weekType == .build,
                  let loadTarget = item.part.loadTarget,
                  let target = item.exposure.entry.target,
                  let reps = item.part.plannedReps,
                  let percent = PowerJackPercent.percent(reps: Double(reps + target))
            else { continue }
            return loadTarget / (percent / 100)
        }
        return nil
    }

    /// R8.4: the median of the newest 3 estimates within 42 days, raised to any floor since,
    /// else the previous anchor raised only by floors.
    func currentE1RM(_ exercise: PowerJackExercise, _ series: PowerJackSeries, previous: Double?) -> Double? {
        let oldest = context.now.addingTimeInterval(-Double(PowerJackRules.anchorMaxAgeDays) * 86_400)
        let values = parts(of: exercise, in: series).compactMap { item -> (date: Date, value: Double, estimate: Bool)? in
            guard item.date >= oldest,
                  item.exposure.weekType != .deload,
                  (item.exposure.entry.pain?.rawValue ?? 0) < LevelOfPain.moderate.rawValue,
                  let value = item.part.value
            else { return nil }
            return (item.date, value.value, value.hasEstimate)
        }
        let estimates = values.filter(\.estimate).suffix(PowerJackRules.anchorWindow)
        let cutoff = estimates.first?.date ?? values.first?.date
        var current = estimates.isEmpty ? previous : median(estimates.map(\.value))
        if let cutoff, let floor = values.filter({ $0.date >= cutoff }).map(\.value).max() {
            current = max(current ?? floor, floor)
        }
        return current
    }

    /// Days since the exercise's last completed working set, anywhere.
    func daysSinceLastSet(_ exercise: PowerJackExercise) -> Double? {
        let last = context.history(exercise.id).compactMap(\.entry.lastCompletedAt).max()
        return last.map { context.now.timeIntervalSince($0) / 86_400 }
    }

    /// The share a break or a lift's own gap cuts, from 14, 28 and 84 days off (R6.7, R8.8).
    func gapCut(_ exercise: PowerJackExercise) -> Double? {
        guard let days = daysSinceLastSet(exercise) else { return nil }
        let band = PowerJackRules.gapBandsDays.lastIndex { days >= Double($0) }
        return band.map { PowerJackRules.gapLoadCutPct[$0] }
    }

    /// The anchor a main-lift series starts a block from, or nil when the lifter loads a
    /// calibrating exposure (R2.2, R8.4, R8.8).
    func blockStartAnchor(_ exercise: PowerJackExercise, _ series: PowerJackSeries) -> (anchor: Double?, calibrating: Bool) {
        let own = impliedAnchor(exercise, series)
        let other = impliedAnchor(exercise, series.other)
        if let cut = gapCut(exercise), let previous = own ?? other {
            return (previous * (1 - cut / 100), true)
        }
        if let own {
            var anchor = min(
                currentE1RM(exercise, series, previous: own) ?? own,
                own * (1 + PowerJackRules.anchorMaxRisePct / 100)
            )
            if painState(exercise).inEpisode { anchor = min(anchor, own) }
            return (anchor, false)
        }
        if let other {
            return (currentE1RM(exercise, series, previous: nil) ?? other, false)
        }
        return (nil, true)
    }

    /// R8.8: a calibrating exposure's value becomes the anchor, uncapped, but never above the
    /// anchor from before a gap.
    func calibratedAnchor(_ part: PowerJackPart, _ exercise: PowerJackExercise, _ series: PowerJackSeries, loggedOn date: Date?) -> Double? {
        guard let value = part.value?.value else { return nil }
        guard let before = impliedAnchor(exercise, series, before: date) else { return value }
        return min(value, before)
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
