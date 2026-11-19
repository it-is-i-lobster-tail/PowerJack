//
//  SettingsView.swift
//  PowerJack
//
//  The top of Settings: one row per group, each opening its own page.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        PersonalizationSettingsView()
                    } label: {
                        SettingsGroupLabel(title: "Personalization", systemImage: "slider.horizontal.3")
                    }

                    NavigationLink {
                        MyGymSettingsView()
                    } label: {
                        SettingsGroupLabel(title: "My Gym", systemImage: "dumbbell")
                    }

                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        SettingsGroupLabel(title: "Appearance", systemImage: "circle.lefthalf.filled")
                    }

                    NavigationLink {
                        YourDataSettingsView()
                    } label: {
                        SettingsGroupLabel(title: "Your Data", systemImage: "externaldrive")
                    }
                }

                Section {
                    NavigationLink {
                        FAQView()
                    } label: {
                        SettingsGroupLabel(title: "FAQ", systemImage: "questionmark.circle")
                    }

                    NavigationLink {
                        LegalSettingsView()
                    } label: {
                        SettingsGroupLabel(title: "Legal", systemImage: "doc.text")
                    }
                }

                Section {
                    NavigationLink {
                        DeveloperToolView()
                    } label: {
                        SettingsGroupLabel(title: "Developer Tools", systemImage: "ladybug")
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
        .scrollEdgeEffectStyle(.soft, for: .all)
    }
}

/// A row on the top Settings page: just the group's name, so the list reads at a glance.
private struct SettingsGroupLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.blue)
        }
    }
}

/// A setting with a short line underneath saying what it does.
struct SettingsRowLabel: View {
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

#Preview("Settings") {
    SettingsView()
        .environment(PowerJackStore(inMemory: true))
}
