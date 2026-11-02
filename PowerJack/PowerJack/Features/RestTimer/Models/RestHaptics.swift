//
//  RestHaptics.swift
//  PowerJack
//
//  Plays haptic patterns on the iPhone: the rest cues while PowerJack is on screen, and previews in Settings.
//  iOS doesn't let apps play their own haptics in the background.
//

import CoreHaptics
import OSLog

final class RestHaptics {
    static let shared = RestHaptics()

    private static let shortBuzz: TimeInterval = 0.12
    private static let longBuzz: TimeInterval = 0.5
    private static let gap: TimeInterval = 0.12

    private var engine: CHHapticEngine?

    func play(_ pattern: HapticPattern) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try engine ?? makeEngine()
            try engine.start()
            try engine.makePlayer(with: Self.hapticPattern(for: pattern)).start(atTime: CHHapticTimeImmediate)
        } catch {
            Logger.restTimer.error("Could not play the rest haptic: \(error.localizedDescription)")
        }
    }

    private func makeEngine() throws -> CHHapticEngine {
        let engine = try CHHapticEngine()
        // Lets the engine sleep between rests; `play` starts it again.
        engine.isAutoShutdownEnabled = true
        self.engine = engine
        return engine
    }

    /// Strong buzzes, back to back, so they're easy to feel through a pocket or on a bench.
    static func hapticPattern(for pattern: HapticPattern) throws -> CHHapticPattern {
        var time: TimeInterval = 0
        let events = pattern.buzzes.map { isLong in
            let duration = isLong ? longBuzz : shortBuzz
            defer { time += duration + gap }
            return CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
                ],
                relativeTime: time,
                duration: duration
            )
        }
        return try CHHapticPattern(events: events, parameters: [])
    }
}
