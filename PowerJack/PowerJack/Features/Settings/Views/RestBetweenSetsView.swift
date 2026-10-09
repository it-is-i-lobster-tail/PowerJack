//
//  RestBetweenSetsView.swift
//  PowerJack
//
//  Edits each rest length with a minutes and seconds wheel.
//

import SwiftUI

struct RestBetweenSetsView: View {
    /// The level whose wheel is open. Only one is open at a time.
    @State var expanded: RestLength?

    var body: some View {
        Form {
            Section {
                ForEach(RestLength.allCases) { length in
                    RestLengthRow(
                        length: length,
                        isExpanded: Binding(
                            get: { expanded == length },
                            set: { expanded = $0 ? length : nil }
                        )
                    )
                }
            } footer: {
                Text("Each exercise's fatigue level picks its rest. The last set of an exercise starts no rest, so the next exercise begins right away.")
            }
        }
        .navigationTitle("Rest Between Sets")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RestLengthRow: View {
    let length: RestLength
    @Binding var isExpanded: Bool

    @AppStorage private var seconds: Int

    private var fatigueLevel: FatigueLevel {
        FatigueLevel.allCases.first { $0.restLength == length } ?? .moderate
    }

    init(length: RestLength, isExpanded: Binding<Bool>) {
        self.length = length
        _isExpanded = isExpanded
        _seconds = AppStorage(
            wrappedValue: Int(length.defaultDuration.components.seconds),
            length.secondsKey
        )
    }

    var body: some View {
        Button {
            withAnimation(.snappy) { isExpanded.toggle() }
        } label: {
            LabeledContent {
                Text(Duration.seconds(seconds).minuteSecondText)
                    .monospacedDigit()
                    .foregroundStyle(isExpanded ? Color.accentColor : .secondary)
            } label: {
                Text(length.name)
                Text("\(fatigueLevel.name) fatigue exercises")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)

        if isExpanded {
            MinuteSecondWheel(seconds: $seconds)
        }
    }
}

/// Minutes in steps of 1 and seconds in steps of 5, held inside `RestLength.range`.
/// Also used for an exercise's custom rest.
struct MinuteSecondWheel: View {
    @Binding var seconds: Int

    private static let range = Int(RestLength.range.lowerBound.components.seconds)
        ... Int(RestLength.range.upperBound.components.seconds)
    private static let step = Int(RestLength.step.components.seconds)

    private var minutes: Binding<Int> {
        Binding(
            get: { seconds / 60 },
            set: { setTotal($0 * 60 + seconds % 60) }
        )
    }

    private var secondsPart: Binding<Int> {
        Binding(
            get: { seconds % 60 },
            set: { setTotal(seconds / 60 * 60 + $0) }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            Picker("Minutes", selection: minutes) {
                ForEach(Self.range.lowerBound / 60 ... Self.range.upperBound / 60, id: \.self) { minute in
                    Text("\(minute) min").tag(minute)
                }
            }
            Picker("Seconds", selection: secondsPart) {
                ForEach(Array(stride(from: 0, to: 60, by: Self.step)), id: \.self) { second in
                    Text("\(second) sec").tag(second)
                }
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
    }

    /// Out-of-range picks (like 0 min 10 sec) snap back to the nearest allowed time.
    private func setTotal(_ total: Int) {
        let clamped = min(max(total, Self.range.lowerBound), Self.range.upperBound)
        withAnimation { seconds = clamped }
    }
}

#Preview("Rest Between Sets") {
    NavigationStack {
        RestBetweenSetsView(expanded: .standard)
    }
}
