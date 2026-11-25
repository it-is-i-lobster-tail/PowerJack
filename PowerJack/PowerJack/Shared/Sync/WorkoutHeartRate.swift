import SwiftUI

struct HeartRateSample: Codable, Sendable {
    let id: UUID
    let date: Date
    let bpm: Double
}

// A separate payload on the mirrored workout channel, independent of program edits.
struct HeartRatePacket: Codable {
    let heartRateSamples: [HeartRateSample]
}

@MainActor @Observable
final class WorkoutHeartRate {
    static let shared = WorkoutHeartRate()

    private(set) var bpm: Int?
    @ObservationIgnored private var samples: [UUID: HeartRateSample] = [:]
    @ObservationIgnored private var refresh: Task<Void, Never>?

    func receive(_ incoming: [HeartRateSample]) {
        let now = Date.now
        for sample in incoming where sample.bpm.isFinite && sample.bpm > 0
            && sample.date <= now && sample.date > now.addingTimeInterval(-10) {
            samples[sample.id] = sample
        }
        guard refresh == nil, !samples.isEmpty else { return }
        refresh = Task {
            while !Task.isCancelled {
                let now = Date.now
                samples = samples.filter { $0.value.date > now.addingTimeInterval(-10) }
                guard let newest = samples.values.map(\.date).max() else {
                    bpm = nil
                    refresh = nil
                    return
                }
                bpm = Int((samples.values.reduce(0) { $0 + $1.bpm } / Double(samples.count)).rounded())
                // Wake early when the last sample expires between two display ticks.
                let delay = min(2, newest.addingTimeInterval(10).timeIntervalSince(now))
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    func clear() {
        refresh?.cancel()
        refresh = nil
        samples.removeAll()
        bpm = nil
    }
}

struct WorkoutHeartRateLabel: View {
    let bpm: Int
    var font: Font = .caption.weight(.medium)
    var showsUnit = true
    var usesZoneStyle = false

    @ScaledMetric(relativeTo: .caption2) private var heartInset: CGFloat = 1

    // Generic display bands use a reference maximum of 190 BPM.
    private var zoneStyle: (numberWeight: Font.Weight, heartScale: CGFloat, heartOpacity: Double) {
        switch bpm {
        case ..<114: (.regular, 0.88, 0.5)
        case ..<133: (.medium, 0.94, 0.625)
        case ..<152: (.semibold, 1, 0.75)
        case ..<171: (.bold, 1.06, 0.875)
        default: (.heavy, 1.12, 1)
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            if usesZoneStyle {
                Image(systemName: "heart")
                    .hidden()
                    // Reserve room for the largest outline in every zone.
                    .padding(heartInset)
                    .overlay {
                        Image(systemName: "heart")
                            .foregroundStyle(.red)
                            .scaleEffect(zoneStyle.heartScale)
                            .opacity(zoneStyle.heartOpacity)
                    }
            } else {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
            }
            Group {
                if showsUnit {
                    Text("\(bpm) BPM")
                } else {
                    Text("888")
                        .fontWeight(usesZoneStyle ? .heavy : nil)
                        .hidden()
                        .overlay(alignment: .trailing) {
                            Text("\(bpm)")
                                .fontWeight(usesZoneStyle ? zoneStyle.numberWeight : nil)
                        }
                }
            }
            .monospacedDigit()
        }
        .font(font)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate, \(bpm) beats per minute")
    }
}
