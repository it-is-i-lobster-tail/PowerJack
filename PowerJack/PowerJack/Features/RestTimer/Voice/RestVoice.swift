//
//  RestVoice.swift
//  PowerJack
//
//  Says the next set out loud when a rest ends, dipping any music underneath and bringing it back after.
//  While a rest counts down it plays silence alongside other audio, so iOS keeps PowerJack running
//  with the phone locked. Speech is made on the device.
//

import AVFAudio
import OSLog

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

    private let synthesizer = AVSpeechSynthesizer()
    private var pending: RestCallout?
    private var countdown: Task<Void, Never>?
    /// Callouts asked for and not yet finished or cut off. The audio session ends when this reaches zero.
    private var unfinished = 0
    /// Plays silence while a callout is waiting.
    private var keepAlive: AVAudioPlayer?

    override private init() {
        super.init()
        synthesizer.delegate = self
        // A phone call pauses the silence. Picks it back up so the callout still plays with the phone locked.
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init)
            guard type == .ended else { return }
            MainActor.assumeIsolated { self?.keepAlive?.play() }
        }
    }

    /// Waits for `callout` and speaks it when its rest ends, replacing any callout still waiting.
    /// `nil` cancels it. A rest that is already over says nothing, so a callout is never late.
    func sync(_ callout: RestCallout?) {
        // Previews render seed data and should never take over audio.
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        guard callout != pending else { return }
        pending = callout
        countdown?.cancel()

        guard let callout, callout.endsAt > .now else {
            stopKeepAlive()
            return
        }
        startKeepAlive()
        countdown = Task {
            try? await Task.sleep(for: .seconds(callout.endsAt.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            // The speech takes over the session, so it isn't ended here.
            keepAlive?.stop()
            keepAlive = nil
            speak(callout.text)
        }
    }

    func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        unfinished += 1
        Task {
            await Self.startSession(options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = Self.voice
            synthesizer.speak(utterance)
        }
    }

    private func startKeepAlive() {
        guard keepAlive == nil else { return }
        guard let url = Bundle.main.url(forResource: "Silence", withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url)
        else {
            Logger.restTimer.error("Could not load the rest voice's silence")
            return
        }
        player.numberOfLoops = -1
        keepAlive = player
        Task {
            // Mixes with music without dipping it or taking over its Lock Screen controls.
            await Self.startSession(options: .mixWithOthers)
            guard keepAlive === player else { return }
            player.play()
        }
    }

    private func stopKeepAlive() {
        guard let keepAlive else { return }
        keepAlive.stop()
        self.keepAlive = nil
        endSessionIfIdle()
    }

    fileprivate func speechEnded() {
        unfinished = max(0, unfinished - 1)
        endSessionIfIdle()
    }

    private func endSessionIfIdle() {
        guard keepAlive == nil, unfinished == 0 else { return }
        // Lets dipped music come back up to full volume.
        Self.audioQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private nonisolated static func startSession(options: AVAudioSession.CategoryOptions) async {
        await withCheckedContinuation { continuation in
            audioQueue.async {
                let session = AVAudioSession.sharedInstance()
                do {
                    // Other audio only dips when the session goes active, so it restarts with the new options.
                    try? session.setActive(false)
                    try session.setCategory(.playback, mode: .voicePrompt, options: options)
                    try session.setActive(true)
                } catch {
                    Logger.restTimer.error("Could not start the rest voice's audio: \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
    }
}

extension RestVoice: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speechEnded() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speechEnded() }
    }
}
