//
//  MyGymSettingsView.swift
//  PowerJack
//
//  What your gym's weights look like: the unit they're in and the equipment you have,
//  plus your own exercises and the ones you archived.
//

import SwiftData
import SwiftUI

struct MyGymSettingsView: View {
    @AppStorage(AppSettings.Key.weightUnit)
    private var weightUnit = WeightUnit.deviceDefault
    @Query(filter: #Predicate<Exercise> { $0.archivedAtValue != nil })
    private var archivedExercises: [Exercise]

    var body: some View {
        content.traceScreen("My Gym")
    }

    @ViewBuilder
    private var content: some View {
        Form {
            Section {
                // A trailing menu, so changing the unit takes a deliberate pick, never one stray tap.
                HStack {
                    SettingsRowLabel(
                        systemImage: "scalemass",
                        title: "Weight Unit",
                        detail: "Weights show and are typed in this unit. Logged weights convert."
                    )
                    Picker("Weight Unit", selection: $weightUnit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.name).tag(unit)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }

                NavigationLink {
                    EquipmentList()
                } label: {
                    SettingsRowLabel(systemImage: "dumbbell", title: "Equipment",
                                     detail: "Add equipment and set its load steps.")
                }

                NavigationLink {
                    CustomExerciseList()
                } label: {
                    SettingsRowLabel(systemImage: "figure.strengthtraining.traditional", title: "My Custom Exercises",
                                     detail: "See and edit the exercises you added or imported.")
                }

                // Only once something is archived, so it's there to find when needed.
                if !archivedExercises.isEmpty {
                    NavigationLink {
                        ArchivedExerciseList()
                    } label: {
                        SettingsRowLabel(systemImage: "archivebox", title: "Archived Exercises",
                                         detail: "Hidden from search. Their history stays.")
                    }
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
