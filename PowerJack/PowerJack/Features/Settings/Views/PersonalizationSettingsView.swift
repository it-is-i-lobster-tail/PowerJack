//
//  PersonalizationSettingsView.swift
//  PowerJack
//
//  How PowerJack behaves for you: the rest timer, how long rests last, and hints.
//

import ActivityKit
import SwiftUI
import UserNotifications

struct PersonalizationSettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

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

    @AppStorage(AppSettings.Key.workoutReminders) private var workoutReminders = false
    @AppStorage(AppSettings.Key.workoutReminderEveningMinute)
    private var reminderEveningMinute = WorkoutReminderTiming.defaultEveningMinute
    @State private var notificationsBlocked = false

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
                Toggle(isOn: $workoutReminders) {
                    SettingsRowLabel(
                        systemImage: "bell",
                        title: "Preview Reminders",
                        detail: "Get a preview when PowerJack learns when you usually lift."
                    )
                }
                .onChange(of: workoutReminders) { _, enabled in
                    WorkoutReminders.shared.refresh()
                    guard enabled else { return }
                    Task {
                        await WorkoutReminders.shared.requestAuthorization()
                        await checkNotificationPermission()
                        WorkoutReminders.shared.refresh()
                    }
                }

                if workoutReminders {
                    DatePicker("Evening Reminder", selection: eveningTime, displayedComponents: .hourAndMinute)
                        .onChange(of: reminderEveningMinute) { _, _ in WorkoutReminders.shared.refresh() }
                    if notificationsBlocked {
                        Button("Open Notification Settings") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                openURL(url)
                            }
                        }
                    }
                }
            } header: {
                Text("Workout Reminders")
            } footer: {
                if workoutReminders {
                    Text("For lifts before 9 a.m., send the preview the evening before.")
                }
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
        .task(id: scenePhase) {
            if scenePhase == .active { await checkNotificationPermission() }
        }
        .task {
            for await enabled in ActivityAuthorizationInfo().activityEnablementUpdates {
                liveActivitiesAllowed = enabled
            }
        }
    }

    private var eveningTime: Binding<Date> {
        Binding {
            let calendar = Calendar.current
            return WorkoutReminderTiming.time(on: .now, minute: reminderEveningMinute, calendar: calendar) ?? .now
        } set: { date in
            let calendar = Calendar.current
            reminderEveningMinute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        }
    }

    private func checkNotificationPermission() async {
        notificationsBlocked = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
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
