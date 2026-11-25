//
//  SettingsView.swift
//  PowerJack
//
//  The top of Settings: one row per group, each opening its own page.
//

import SwiftUI

struct SettingsView: View {
    private enum Page: Hashable {
        case personalization, myGym, appearance, yourData, faq, legal, developerTool
    }

    var body: some View {
        Form {
            Section {
                NavigationLink(value: Page.personalization) {
                    SettingsGroupLabel(title: "Personalization", systemImage: "slider.horizontal.3")
                }

                NavigationLink(value: Page.myGym) {
                    SettingsGroupLabel(title: "My Gym", systemImage: "dumbbell")
                }

                NavigationLink(value: Page.appearance) {
                    SettingsGroupLabel(title: "Appearance", systemImage: "circle.lefthalf.filled")
                }

                NavigationLink(value: Page.yourData) {
                    SettingsGroupLabel(title: "Your Data", systemImage: "externaldrive")
                }
            }

            Section {
                NavigationLink(value: Page.faq) {
                    SettingsGroupLabel(title: "FAQ", systemImage: "questionmark.circle")
                }

                NavigationLink(value: Page.legal) {
                    SettingsGroupLabel(title: "Legal", systemImage: "doc.text")
                }
            }

            Section {
                NavigationLink(value: Page.developerTool) {
                    SettingsGroupLabel(title: "Developer Tools", systemImage: "ladybug")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Page.self) { page in
            switch page {
            case .personalization: PersonalizationSettingsView()
            case .myGym: MyGymSettingsView()
            case .appearance: AppearanceSettingsView()
            case .yourData: YourDataSettingsView()
            case .faq: FAQView()
            case .legal: LegalSettingsView()
            case .developerTool: DeveloperToolView()
            }
        }
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
    NavigationStack { SettingsView() }
        .environment(PowerJackStore(inMemory: true))
}
