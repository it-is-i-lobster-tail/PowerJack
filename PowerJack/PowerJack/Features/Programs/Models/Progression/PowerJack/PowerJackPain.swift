//
//  PowerJackPain.swift
//  PowerJack
//
//  Each exercise's pain state, replayed from its pain taps (R10.2 to R10.5). Pain acts before any
//  progression. It changes only training: load, sets and effort, never advice.
//

import Foundation

enum PowerJackPainAction: Equatable {
    /// R2 to R5 decide.
    case progress
    /// Same load and reps; `floor` keeps at least 2 reps in reserve (an episode).
    case hold(floor: Bool)
    /// Moderate or worse twice in a row: cut 10%, never more than 30% under the pre-pain load.
    case reduce
    /// Severe or Extreme: the check-in opens before the next exposure.
    case checkIn(LevelOfPain)
    /// The episode cleared: climb back toward the pre-pain load, at most 5% an exposure.
    case returning
}

struct PowerJackPainState: Equatable {
    var action: PowerJackPainAction = .progress
    /// The latest exposure was pain-affected, so it carries no progression signal (R10.6).
    var lastExposureAffected = false
    /// When the current or latest episode opened.
    var episodeStart: Date?

    var inEpisode: Bool {
        switch action {
        case .hold(floor: true), .reduce, .checkIn: true
        default: false
        }
    }

    /// Replays an exercise's rated exposures, oldest first.
    static func replay(_ exposures: [PowerJackExposure]) -> PowerJackPainState {
        enum Mode { case normal, episode }
        var mode = Mode.normal
        var lastPain = 0
        var baseline = 0
        var painStreak = 0
        var cleanStreak = 0
        var sinceCleared: Int?
        var rising = false
        var affected = false
        var episodeStart: Date?

        for exposure in exposures {
            guard let pain = exposure.entry.pain?.rawValue else { continue }
            let wasInEpisode = mode == .episode
            rising = pain >= LevelOfPain.noticeable.rawValue && pain > lastPain
            painStreak = pain >= LevelOfPain.moderate.rawValue ? painStreak + 1 : 0
            sinceCleared = sinceCleared.map { $0 + 1 }

            if pain >= LevelOfPain.moderate.rawValue {
                if mode == .normal {
                    mode = .episode
                    baseline = lastPain
                    // A rating this bad while returning reopens the same episode.
                    let returning = sinceCleared.map { $0 < Self.returnExposures } ?? false
                    if !returning || episodeStart == nil { episodeStart = exposure.date }
                }
                cleanStreak = 0
                sinceCleared = nil
            } else if mode == .episode {
                let days = episodeStart.map { exposure.date.timeIntervalSince($0) / 86_400 } ?? 0
                let clearMax = days > 28 ? LevelOfPain.noticeable.rawValue : max(1, baseline)
                let clean = pain <= clearMax && !rising && exposure.weekType != .deload
                cleanStreak = clean ? cleanStreak + 1 : 0
                if cleanStreak >= PowerJackRules.painClearAfterExposures {
                    mode = .normal
                    sinceCleared = 0
                }
            }
            affected = pain >= LevelOfPain.moderate.rawValue || wasInEpisode
            lastPain = pain
        }

        var state = PowerJackPainState(lastExposureAffected: affected, episodeStart: episodeStart)
        if lastPain >= LevelOfPain.severe.rawValue {
            state.action = .checkIn(LevelOfPain(rawValue: lastPain) ?? .severe)
        } else if mode == .episode {
            state.action = painStreak >= 2 && painStreak % 2 == 0 ? .reduce : .hold(floor: true)
        } else if rising {
            state.action = .hold(floor: false)
        } else if let sinceCleared, sinceCleared < Self.returnExposures {
            state.action = .returning
        }
        return state
    }

    /// Exposures after an episode clears that may still climb back. Each slot stops climbing
    /// sooner, once it is back at its pre-pain load.
    private static let returnExposures = 6
}
