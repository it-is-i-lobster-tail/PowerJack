//
//  SettingsView.swift
//  PowerJack
//

import ActivityKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage(AppSettings.Key.inAppRestTimer)
    private var showsInAppRestTimer = AppSettings.Default.inAppRestTimer
    @AppStorage(AppSettings.Key.restLiveActivity)
    private var showsRestLiveActivity = AppSettings.Default.restLiveActivity

    @State private var liveActivitiesAllowed = ActivityAuthorizationInfo().areActivitiesEnabled

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $showsInAppRestTimer) {
                        SettingsToggleLabel(
                            systemImage: "timer",
                            title: "In-App Timer",
                            detail: "An island-style countdown at the top of the screen while PowerJack is open."
                        )
                    }

                    Toggle(isOn: $showsRestLiveActivity) {
                        SettingsToggleLabel(
                            systemImage: "iphone.gen3",
                            title: "Dynamic Island & Lock Screen",
                            detail: "Keeps the countdown visible when you leave PowerJack. Tap it to jump back to your exercise."
                        )
                    }

                    if showsRestLiveActivity, !liveActivitiesAllowed {
                        LiveActivitiesOffNote(openSettings: openSystemSettings)
                    }
                } header: {
                    Text("Rest Timer")
                } footer: {
                    Text("iOS shows a Live Activity in the Dynamic Island and on the Lock Screen together, so they share one switch.")
                }

                Section("Rest Between Sets") {
                    ForEach(Fatigue.allCases) { fatigue in
                        LabeledContent(
                            fatigue.rawValue.capitalized,
                            value: fatigue.restDuration.minuteSecondText
                        )
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
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

private struct SettingsToggleLabel: View {
    let systemImage: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.blue)
        }
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

#Preview("Settings") {
    SettingsView()
}
