//
//  RestVoiceClips.swift
//  PowerJack
//
//  The recorded voice: every phrase a callout can use, packed one after another into Voice.m4a.
//  Voice.json maps each clip's name (e.g. "lb-225") to where it starts in the file and how long it is, in frames.
//

import AVFAudio
import OSLog

nonisolated struct RestVoiceClips {
    /// The pause between phrases, like the comma in "225 pounds, 10 reps".
    static let gap: TimeInterval = 0.2

    private let url: URL
    private let ranges: [String: [AVAudioFramePosition]]

    init?(bundle: Bundle = .main) {
        guard
            let url = bundle.url(forResource: "Voice", withExtension: "m4a"),
            let indexURL = bundle.url(forResource: "Voice", withExtension: "json"),
            let data = try? Data(contentsOf: indexURL),
            let ranges = try? JSONDecoder().decode([String: [AVAudioFramePosition]].self, from: data)
        else {
            return nil
        }
        self.url = url
        self.ranges = ranges
    }

    func contains(_ phrase: RestPhrase) -> Bool {
        phrase.clips.allSatisfy { ranges[$0] != nil }
    }

    /// The phrase's clips in one buffer, with a short pause between them. `nil` when a clip wasn't recorded.
    func buffer(for phrase: RestPhrase) -> AVAudioPCMBuffer? {
        let clips = phrase.clips.compactMap { ranges[$0] }
        guard !clips.isEmpty, clips.count == phrase.clips.count else { return nil }
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let gapFrames = AVAudioFrameCount(format.sampleRate * Self.gap)
            let length = clips.reduce(0) { $0 + AVAudioFrameCount($1[1]) } + gapFrames * AVAudioFrameCount(clips.count - 1)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: length) else { return nil }

            for (index, clip) in clips.enumerated() {
                if index > 0 {
                    try append(silence: gapFrames, to: buffer)
                }
                let frames = AVAudioFrameCount(clip[1])
                guard let part = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
                file.framePosition = clip[0]
                try file.read(into: part, frameCount: frames)
                try append(part, to: buffer)
            }
            return buffer
        } catch {
            Logger.restTimer.error("Could not read the rest voice's clips: \(error.localizedDescription)")
            return nil
        }
    }

    private func append(_ part: AVAudioPCMBuffer, to buffer: AVAudioPCMBuffer) throws {
        guard let source = part.floatChannelData?[0], let target = buffer.floatChannelData?[0] else {
            throw CocoaError(.featureUnsupported)
        }
        (target + Int(buffer.frameLength)).update(from: source, count: Int(part.frameLength))
        buffer.frameLength += part.frameLength
    }

    private func append(silence frames: AVAudioFrameCount, to buffer: AVAudioPCMBuffer) throws {
        guard let target = buffer.floatChannelData?[0] else { throw CocoaError(.featureUnsupported) }
        (target + Int(buffer.frameLength)).update(repeating: 0, count: Int(frames))
        buffer.frameLength += frames
    }
}
