//
//  RestVoice.swift
//  PowerJack
//
//  Says the next set out loud when a rest ends, dipping any music underneath and bringing it back after.
//  While a rest counts down it plays silence alongside other audio, so iOS keeps PowerJack running
//  with the phone locked. The voice is recorded (see `RestVoiceClips`); a phrase with no recording,
//  such as an unusual weight, is spoken by the device instead.
//

import AVFAudio
import OSLog
import UIKit

final class RestVoice: NSObject {
    static let shared = RestVoice()

    /// Starting and ending the audio session can block while other apps' audio adjusts,
    /// so it happens here, in order, instead of on the main thread.
    private nonisolated static let audioQueue = DispatchQueue(label: "PowerJack.RestVoice.audio")

    /// The phrases are English, so a non-English system voice would garble them.
    private static let voice: AVSpeechSynthesisVoice? = {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        return AVSpeechSynthesisVoice(language: language.hasPrefix("en") ? language : "en-US")
    }()

    private let clips = RestVoiceClips()
    private let synthesizer = AVSpeechSynthesizer()
    /// The callout waiting for its rest to end, or the last one, once said.
    private(set) var pending: RestCallout?
    private var countdown: Task<Void, Never>?
    /// Plays silence while a callout is waiting.
    private var keepAlive: AVAudioPlayer?
    /// Holds on while an interruption pauses the silence. See `interrupted(_:)`.
    private var interruptionTime: BackgroundTime?

    /// Counts up with each phrase, so one that was cut off can't end the one that cut it off.
    private var speechID = 0
    private var isSpeaking = false
    /// What's saying the phrase: an engine playing its recording, or the device voice.
    private var speech: AVAudioEngine?
    private var utterance: AVSpeechUtterance?
    /// Keeps PowerJack running from the moment the silence stops until the phrase is said.
    private var speechTime: BackgroundTime?

    override private init() {
        super.init()
        synthesizer.delegate = self
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init)
            MainActor.assumeIsolated { self?.interrupted(type) }
        }
        // Back on screen after something stopped the silence, it starts again, ready for the phone to lock.
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumeKeepAlive() }
        }
    }

    /// Waits for `callout` and speaks it when its rest ends, replacing any callout still waiting.
    /// `nil` cancels it. A rest that is already over says nothing, so a callout is never late.
    func sync(_ callout: RestCallout?) {
        // Previews render seed data and should never take over audio.
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        guard callout != pending else {
            // The same rest again: picks the silence back up if something stopped it.
            resumeKeepAlive()
            return
        }
        pending = callout
        countdown?.cancel()

        guard let callout, callout.endsAt > .now else {
            stopKeepAlive()
            return
        }
        startKeepAlive()
        countdown = Task {
            // Without a tolerance, iOS can run the timer late by up to a tenth of the rest with the phone locked.
            try? await Task.sleep(for: .seconds(callout.endsAt.timeIntervalSinceNow), tolerance: .milliseconds(100))
            guard !Task.isCancelled else { return }
            // iOS kept PowerJack suspended past the end of the rest, as through a phone call.
            // Said now, it would only confuse.
            guard !callout.isLate(at: .now) else {
                stopKeepAlive()
                return
            }
            speak(callout.phrase)
            // The voice takes over the session, so the silence stops without ending it.
            keepAlive?.stop()
            keepAlive = nil
        }
    }

    /// Says `phrase` now, cutting off anything still being said.
    func speak(_ phrase: RestPhrase) {
        stopSpeaking()
        speechID += 1
        let id = speechID
        isSpeaking = true
        // iOS suspends a backgrounded app as soon as its audio stops, and nothing plays for a moment
        // while the session restarts to dip other audio.
        let cutOff = speechTime
        speechTime = BackgroundTime()
        cutOff?.end()

        let recording = clips?.buffer(for: phrase)
        Task {
            guard await Self.startSession(options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]),
                  id == speechID
            else {
                finishSpeaking(id)
                return
            }
            if let recording, play(recording, id: id) { return }
            let utterance = AVSpeechUtterance(string: phrase.text)
            utterance.voice = Self.voice
            self.utterance = utterance
            synthesizer.speak(utterance)
        }
    }

    /// Plays `recording` on an engine made for whatever the audio plays through now, so headphones
    /// that came or went since the last callout can't leave it set up for the old route.
    /// Returns false when the engine can't start.
    private func play(_ recording: AVAudioPCMBuffer, id: Int) -> Bool {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: recording.format)
        do {
            try engine.start()
        } catch {
            Logger.restTimer.error("Could not play the rest voice: \(error.localizedDescription)")
            return false
        }
        player.scheduleBuffer(recording, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.finishSpeaking(id) }
        }
        player.play()
        speech = engine

        // Headphones coming or going stop the engine partway, so the phrase also ends once it's had time to play.
        let length = Double(recording.frameLength) / recording.format.sampleRate
        Task {
            try? await Task.sleep(for: .seconds(length + 3))
            finishSpeaking(id)
        }
        return true
    }

    private func stopSpeaking() {
        speech?.stop()
        speech = nil
        utterance = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    /// Ends phrase `id` and lets go of the audio, unless a newer phrase cut it off.
    private func finishSpeaking(_ id: Int) {
        guard id == speechID, isSpeaking else { return }
        isSpeaking = false
        stopSpeaking()
        speechTime?.end()
        speechTime = nil
        endSessionIfIdle()
    }

    /// The device voice finished or was cut off.
    fileprivate func finished(_ utterance: AVSpeechUtterance) {
        guard utterance === self.utterance else { return }
        finishSpeaking(speechID)
    }

    private func startKeepAlive() {
        if keepAlive == nil {
            guard let url = Bundle.main.url(forResource: "Silence", withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url)
            else {
                Logger.restTimer.error("Could not load the rest voice's silence")
                return
            }
            player.numberOfLoops = -1
            keepAlive = player
        }
        resumeKeepAlive()
    }

    /// Starts the session and plays the silence: when a callout starts waiting, and again after
    /// an interruption or anything else stopped it.
    private func resumeKeepAlive() {
        guard let player = keepAlive, !player.isPlaying else { return }
        // The Live Activity's check button and the watch start rests with PowerJack in the background,
        // where iOS would suspend it before the silence gets going.
        let time = BackgroundTime()
        Task {
            // Mixes with music without dipping it or taking over its Lock Screen controls.
            await Self.startSession(options: .mixWithOthers)
            if keepAlive === player {
                if !player.isPlaying { player.play() }
            } else {
                // The callout went while the session started, so the session goes too.
                endSessionIfIdle()
            }
            time.end()
        }
    }

    private func stopKeepAlive() {
        interruptionTime?.end()
        interruptionTime = nil
        guard let keepAlive else { return }
        keepAlive.stop()
        self.keepAlive = nil
        endSessionIfIdle()
    }

    /// A call, Siri or an alarm pauses the silence. With the phone locked, iOS then soon suspends PowerJack,
    /// which misses both the interruption's end and the callout.
    private func interrupted(_ type: AVAudioSession.InterruptionType?) {
        switch type {
        case .began:
            // Holds on through a short one, like Siri. A phone call can outlast the time iOS gives.
            if keepAlive != nil, interruptionTime == nil {
                interruptionTime = BackgroundTime()
            }
        case .ended:
            // The interruption ended the session too, so the silence starts it again.
            resumeKeepAlive()
            interruptionTime?.end()
            interruptionTime = nil
        default:
            break
        }
    }

    private func endSessionIfIdle() {
        guard keepAlive == nil, !isSpeaking else { return }
        // Lets dipped music come back up to full volume.
        Self.audioQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// Starts the session with `options`. False when it can't start, as during a phone call.
    @discardableResult
    private nonisolated static func startSession(options: AVAudioSession.CategoryOptions) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            audioQueue.async {
                let session = AVAudioSession.sharedInstance()
                do {
                    // Other audio only dips when the session goes active, so it restarts with the new options.
                    try? session.setActive(false)
                    try session.setCategory(.playback, mode: .voicePrompt, options: options)
                    try session.setActive(true)
                    continuation.resume(returning: true)
                } catch {
                    Logger.restTimer.error("Could not start the rest voice's audio: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                }
            }
        }
    }
}

extension RestVoice {
    /// Says the active workout's rest when it ends, for rests started where PowerJack's screens may not be
    /// running to notice: from the Live Activity's check button, or by a set logged on the watch.
    func follow(_ workout: Workout?) {
        let isOn = UserDefaults.standard.object(forKey: AppSettings.Key.restVoice) as? Bool ?? AppSettings.Default.restVoice
        sync(isOn ? workout?.restCallout : nil)
    }
}

extension RestVoice: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        nonisolated(unsafe) let utterance = utterance
        Task { @MainActor in self.finished(utterance) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        nonisolated(unsafe) let utterance = utterance
        Task { @MainActor in self.finished(utterance) }
    }
}

/// Keeps PowerJack running in the background until `end()`. iOS suspends a backgrounded app soon after
/// its audio stops, so this bridges the moments the audio changes hands.
private final class BackgroundTime {
    private var task = UIBackgroundTaskIdentifier.invalid

    init() {
        task = UIApplication.shared.beginBackgroundTask(withName: "Rest voice") { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}
