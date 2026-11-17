//
//  MyGymSettingsView.swift
//  PowerJack
//
//  What your gym's weights look like: the unit they're in and the smallest jumps you can make.
//

import SwiftUI

struct MyGymSettingsView: View {
    @AppStorage(AppSettings.Key.weightUnit)
    private var weightUnit = WeightUnit.deviceDefault

    var body: some View {
        content.traceScreen("My Gym")
    }

    @ViewBuilder
    private var content: some View {
        Form {
            Section {
                // A trailing control, like the toggles: lb or kg.
                HStack {
                    SettingsRowLabel(
                        systemImage: "scalemass",
                        title: "Weight Unit",
                        detail: "Weights show and are typed in this unit. Logged weights convert."
                    )
                    Picker("Weight Unit", selection: $weightUnit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                NavigationLink {
                    LoadStepsView()
                } label: {
                    SettingsRowLabel(
                        systemImage: "plusminus",
                        title: "Load Steps",
                        detail: "The smallest weight jump for each kind of equipment in Strength programs."
                    )
                }
            }
        }
        .navigationTitle("My Gym")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("My Gym") {
    NavigationStack { MyGymSettingsView() }
}
