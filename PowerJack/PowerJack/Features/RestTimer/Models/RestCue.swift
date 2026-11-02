//
//  RestCue.swift
//  PowerJack
//
//  The buzzes that mark the end of a rest: an optional heads-up shortly before it ends,
//  then one when it's time to lift. Each plays a pattern picked in Settings. Shared with the watch app.
//

import Foundation

nonisolated enum RestCue: Hashable {
    /// Shortly before the rest ends, so there's time to get set.
    case headsUp
    /// The rest is over.
    case lift
}

/// A rhythm of short and long buzzes.
nonisolated enum HapticPattern: String, CaseIterable, Identifiable {
    case oneShort
    case twoShort
    case threeShort
    case oneLong
    case shortShortLong

    var id: Self { self }

    var name: String {
        switch self {
        case .oneShort: "One Short"
        case .twoShort: "Two Short"
        case .threeShort: "Three Short"
        case .oneLong: "One Long"
        case .shortShortLong: "Short, Short, Long"
        }
    }

    /// Each buzz in order, `true` for a long one.
    var buzzes: [Bool] {
        switch self {
        case .oneShort: [false]
        case .twoShort: [false, false]
        case .threeShort: [false, false, false]
        case .oneLong: [true]
        case .shortShortLong: [false, false, true]
        }
    }
}

/// The haptics part of Settings › Rest Timer.
nonisolated struct RestHapticSettings: Equatable {
    /// The choices for how long before the rest ends the heads-up plays, in seconds.
    static let headsUpLeads = [5, 10, 15, 20, 30]

    var headsUp = AppSettings.Default.headsUp
    var headsUpLead = AppSettings.Default.headsUpLead
    var headsUpPattern = AppSettings.Default.headsUpPattern
    var liftPattern = AppSettings.Default.liftPattern

    static var current: Self {
        let defaults = UserDefaults.standard
        var settings = Self()
        if defaults.object(forKey: AppSettings.Key.headsUp) != nil {
            settings.headsUp = defaults.bool(forKey: AppSettings.Key.headsUp)
        }
        if defaults.object(forKey: AppSettings.Key.headsUpLead) != nil {
            settings.headsUpLead = defaults.integer(forKey: AppSettings.Key.headsUpLead)
        }
        if let pattern = defaults.string(forKey: AppSettings.Key.headsUpPattern).flatMap(HapticPattern.init) {
            settings.headsUpPattern = pattern
        }
        if let pattern = defaults.string(forKey: AppSettings.Key.liftPattern).flatMap(HapticPattern.init) {
            settings.liftPattern = pattern
        }
        return settings
    }

    func pattern(for cue: RestCue) -> HapticPattern {
        switch cue {
        case .headsUp: headsUpPattern
        case .lift: liftPattern
        }
    }
}

extension RestPeriod {
    /// The cues still to come after `date`, with when each plays.
    /// A rest no longer than the heads-up lead only gets the lift cue.
    func cues(after date: Date, settings: RestHapticSettings) -> [(cue: RestCue, at: Date)] {
        var all: [(cue: RestCue, at: Date)] = [(.lift, endsAt)]
        if settings.headsUp {
            all.insert((.headsUp, endsAt.addingTimeInterval(-TimeInterval(settings.headsUpLead))), at: 0)
        }
        return all.filter { $0.at > startedAt && $0.at >= date }
    }

    /// Waits for each cue and hands its pattern to `play`. Stop it by cancelling the task.
    /// A cue that comes due while the app is suspended is skipped rather than played late.
    func playCues(_ play: (HapticPattern) async -> Void) async {
        let settings = RestHapticSettings.current
        for (cue, date) in cues(after: .now, settings: settings) {
            try? await Task.sleep(for: .seconds(date.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            guard Date.now.timeIntervalSince(date) < 2 else { continue }
            await play(settings.pattern(for: cue))
        }
    }
}
