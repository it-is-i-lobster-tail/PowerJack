//
//  ArchivedExerciseList.swift
//  PowerJack
//
//  The lifter's archived exercises: hidden from search and pickers, history kept. Swipe one to bring it back.
//

import SwiftData
import SwiftUI

struct ArchivedExerciseList: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Exercise> { $0.archivedAtValue != nil }, sort: \Exercise.exerciseName)
    private var exercises: [Exercise]

    @State private var editing: Exercise?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(exercises) { exercise in
                    ExerciseSelectionRow(exercise: exercise) { editing = exercise }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Unarchive", systemImage: "tray.and.arrow.up") { unarchive(exercise) }
                                .tint(.blue)
                        }
                }
            } footer: {
                if !exercises.isEmpty {
                    Text("Archived exercises don't show in search. Their history stays in your charts and exports.")
                }
            }
        }
        .overlay {
            if exercises.isEmpty {
                EmptyStateView(title: "No Archived Exercises", systemImage: "archivebox",
                               description: "Exercises you archive show here.")
            }
        }
        .navigationTitle("Archived Exercises")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            if let editing { ExerciseDetailView(exercise: editing) }
        }
        .saveErrorAlert($errorMessage)
        .traceScreen("Archived Exercises")
    }

    private func unarchive(_ exercise: Exercise) {
        do {
            try ExerciseRemoval.unarchive(exercise, in: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("Archived Exercises") {
    let scenario = PowerJackSeed.weekOneProgress()
    NavigationStack { ArchivedExerciseList() }
        .modelContainer(scenario.container)
}
