//
//  PersonalizationSettingsView.swift
//  PowerJack
//
//  How PowerJack behaves for you: the rest timer, how long rests last, and hints.
//

import ActivityKit
import SwiftUI

struct PersonalizationSettingsView: View {
    @Environment(\.openURL) private var openURL

    @AppStorage(AppSettings.Key.inAppRestTimer)
    private var showsInAppRestTimer = AppSettings.Default.inAppRestTimer
    @AppStorage(AppSettings.Key.restLiveActivity)
    private var showsRestLiveActivity = AppSettings.Default.restLiveActivity
    @AppStorage(AppSettings.Key.restVoice)
    private var speaksRestEnd = AppSettings.Default.restVoice
    @AppStorage(AppSettings.Key.hints)
    private var showsHints = AppSettings.Default.hints
    @AppStorage(AppSettings.Key.weightUnit)
    private var weightUnit = WeightUnit.deviceDefault

    @State private var liveActivitiesAllowed = ActivityAuthorizationInfo().areActivitiesEnabled

    var body: some View {
        content.traceScreen("Personalization")
    }

    @ViewBuilder
    private var content: some View {
        Form {
            Section {
                Toggle(isOn: $showsInAppRestTimer) {
                    SettingsRowLabel(
                        systemImage: "timer",
                        title: "In-App Timer",
                        detail: "An island-style countdown at the top of the screen while PowerJack is open."
                    )
                }

                Toggle(isOn: $showsRestLiveActivity) {
                    SettingsRowLabel(
                        systemImage: "iphone.gen3",
                        title: "Dynamic Island & Lock Screen",
                        detail: "Shows your current set and rest countdown when you leave PowerJack. Tap it to jump back to your exercise."
                    )
                }

                if showsRestLiveActivity, !liveActivitiesAllowed {
                    LiveActivitiesOffNote(openSettings: openSystemSettings)
                }

                NavigationLink {
                    RestHapticsView()
                } label: {
                    SettingsRowLabel(
                        systemImage: "iphone.radiowaves.left.and.right",
                        title: "Haptics",
                        detail: "A heads-up buzz before your rest ends, and another when it's time to lift."
                    )
                }

                Toggle(isOn: $speaksRestEnd) {
                    SettingsRowLabel(
                        systemImage: "speaker.wave.2",
                        title: "Voice",
                        detail: "Says your next set when rest ends, like “\(RestPhrase.sample(in: weightUnit).text)”"
                    )
                }
                // Turning it on plays the sample, so there's no separate button to hear it.
                .onChange(of: speaksRestEnd) { _, isOn in
                    if isOn { RestVoice.shared.speak(RestPhrase.sample(in: weightUnit)) }
                }

                NavigationLink {
                    RestBetweenSetsView()
                } label: {
                    SettingsRowLabel(
                        systemImage: "hourglass",
                        title: "Rest Between Sets",
                        detail: "How long the timer counts down after each set, based on the exercise's fatigue level."
                    )
                }
            } header: {
                Text("Rest Timer")
            }

            Section {
                Toggle(isOn: $showsHints) {
                    SettingsRowLabel(
                        systemImage: "lightbulb",
                        title: "Hints",
                        detail: "Short tips during your first workouts."
                    )
                }
                .onChange(of: showsHints) { _, isOn in
                    Hints.isEnabled = isOn
                }
            }
        }
        .navigationTitle("Personalization")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            for await enabled in ActivityAuthorizationInfo().activityEnablementUpdates {
                liveActivitiesAllowed = enabled
            }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

private struct LiveActivitiesOffNote: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            Label("Live Activities are turned off for PowerJack in iOS Settings.", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
            Button("Open iOS Settings", action: openSettings)
                .font(.caption)
        }
    }
}

#Preview("Personalization") {
    NavigationStack { PersonalizationSettingsView() }
}
