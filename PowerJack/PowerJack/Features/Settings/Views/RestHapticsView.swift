//
//  RestHapticsView.swift
//  PowerJack
//
//  Settings › Rest Timer › Haptics: the heads-up buzz before a rest ends and the buzz when it's time to lift.
//  Tapping a pattern plays it, so it can be felt before it's picked.
//

import SwiftUI

struct RestHapticsView: View {
    @AppStorage(AppSettings.Key.headsUp)
    private var headsUp = AppSettings.Default.headsUp
    @AppStorage(AppSettings.Key.headsUpLead)
    private var headsUpLead = AppSettings.Default.headsUpLead
    @AppStorage(AppSettings.Key.headsUpPattern)
    private var headsUpPattern = AppSettings.Default.headsUpPattern
    @AppStorage(AppSettings.Key.liftPattern)
    private var liftPattern = AppSettings.Default.liftPattern

    var body: some View {
        Form {
            Section {
                Toggle("Heads-Up", isOn: $headsUp.animation())
                if headsUp {
                    Picker("When", selection: $headsUpLead) {
                        ForEach(RestHapticSettings.headsUpLeads, id: \.self) { seconds in
                            Text("\(seconds) sec before").tag(seconds)
                        }
                    }
                }
            } footer: {
                Text("A buzz shortly before your rest ends, so you can get set.")
            }

            if headsUp {
                Section("Heads-Up Pattern") {
                    HapticPatternPicker(selection: $headsUpPattern)
                }
            }

            Section {
                HapticPatternPicker(selection: $liftPattern)
            } header: {
                Text("Time to Lift")
            } footer: {
                Text("Tap a pattern to feel it. Buzzes play while PowerJack is open on your iPhone or Apple Watch.")
            }
        }
        .navigationTitle("Haptics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One row per pattern, with a checkmark on the chosen one. Picking a row plays it.
private struct HapticPatternPicker: View {
    @Binding var selection: HapticPattern

    var body: some View {
        ForEach(HapticPattern.allCases) { pattern in
            Button {
                selection = pattern
                RestHaptics.shared.play(pattern)
            } label: {
                HStack {
                    Text(pattern.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    HapticPatternGlyph(pattern: pattern)
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                        .opacity(pattern == selection ? 1 : 0)
                }
            }
            .accessibilityAddTraits(pattern == selection ? .isSelected : [])
        }
    }
}

/// The rhythm drawn as dashes: short buzzes as dots, long ones as bars.
private struct HapticPatternGlyph: View {
    let pattern: HapticPattern

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(pattern.buzzes.enumerated()), id: \.offset) { _, isLong in
                Capsule()
                    .frame(width: isLong ? 22 : 8, height: 8)
            }
        }
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}

#Preview("Rest Haptics") {
    NavigationStack {
        RestHapticsView()
    }
}
