//
//  SettingsView.swift
//  PowerJack
//

import ActivityKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(PowerJackStore.self) private var store

    @AppStorage(AppSettings.Key.inAppRestTimer)
    private var showsInAppRestTimer = AppSettings.Default.inAppRestTimer
    @AppStorage(AppSettings.Key.restLiveActivity)
    private var showsRestLiveActivity = AppSettings.Default.restLiveActivity

    @State private var liveActivitiesAllowed = ActivityAuthorizationInfo().areActivitiesEnabled
    @State private var iCloudAvailable = true
    @State private var isConfirmingICloudOff = false
    @State private var isDeletingICloudCopy = false
    @State private var showsICloudOffError = false

    var body: some View {
        NavigationStack {
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
                } header: {
                    Text("Rest Timer")
                }

                Section {
                    NavigationLink {
                        RestBetweenSetsView()
                    } label: {
                        SettingsRowLabel(
                            systemImage: "hourglass",
                            title: "Rest Between Sets",
                            detail: "How long the timer counts down after each set, based on the exercise's fatigue level."
                        )
                    }
                }

                Section {
                    Toggle(isOn: iCloudBackup) {
                        SettingsRowLabel(
                            systemImage: "icloud",
                            title: "iCloud Backup",
                            detail: "Keeps your programs, templates and workout history in your private iCloud, so a new iPhone or a reinstall picks up where you left off. Only you can see it."
                        )
                    }
                    .disabled(isDeletingICloudCopy)
                } header: {
                    Text("Your Data")
                } footer: {
                    if isDeletingICloudCopy {
                        Text("Deleting your iCloud copy…")
                    } else if store.syncsWithICloud, !iCloudAvailable {
                        Text("Sign in to iCloud in iOS Settings to start backing up.")
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
        .alert("Turn Off iCloud Backup?", isPresented: $isConfirmingICloudOff) {
            Button("Yes, Turn Off", role: .destructive, action: turnOffICloudBackup)
            Button("No", role: .cancel) {}
        } message: {
            Text("Your workouts stay on this iPhone, but the copy in iCloud will be deleted. A new iPhone or a reinstall won't get them back.")
        }
        .alert("Couldn't Turn Off iCloud Backup", isPresented: $showsICloudOffError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("iCloud couldn't be reached, so nothing was deleted. Check your connection and try again.")
        }
        .task {
            iCloudAvailable = await store.iCloudAccountAvailable()
        }
        .task {
            for await enabled in ActivityAuthorizationInfo().activityEnablementUpdates {
                liveActivitiesAllowed = enabled
            }
        }
    }

    // Turning backup off asks first, because it deletes the iCloud copy.
    private var iCloudBackup: Binding<Bool> {
        Binding(
            get: { store.syncsWithICloud },
            set: { isOn in
                if isOn {
                    store.turnOnICloudBackup()
                } else {
                    isConfirmingICloudOff = true
                }
            }
        )
    }

    private func turnOffICloudBackup() {
        isDeletingICloudCopy = true
        Task {
            do {
                try await store.turnOffICloudBackup()
            } catch {
                showsICloudOffError = true
            }
            isDeletingICloudCopy = false
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

private struct SettingsRowLabel: View {
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
        .environment(PowerJackStore(inMemory: true))
}
