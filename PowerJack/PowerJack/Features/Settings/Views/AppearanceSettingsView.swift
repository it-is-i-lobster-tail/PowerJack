//
//  AppearanceSettingsView.swift
//  PowerJack
//
//  Light, dark, or following the iPhone.
//

import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage(AppSettings.Key.appearance)
    private var appearance = AppSettings.Default.appearance

    var body: some View {
        content.traceScreen("Appearance")
    }

    @ViewBuilder
    private var content: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { appearance in
                        Text(appearance.name).tag(appearance)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text("System switches between light and dark with your iPhone.")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Appearance") {
    NavigationStack { AppearanceSettingsView() }
}
