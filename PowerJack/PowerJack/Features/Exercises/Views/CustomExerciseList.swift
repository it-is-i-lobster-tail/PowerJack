//
//  CustomExerciseList.swift
//  PowerJack
//
//  The lifter's own exercises, searched like the exercise picker and filtered by where they came from.
//

import SwiftData
import SwiftUI

/// Where a custom exercise came from: an import (it has imported sets) or made in PowerJack.
enum CustomExerciseOrigin: String, CaseIterable, Identifiable {
    case all = "All"
    case imported = "Imported"
    case madeHere = "Made Here"

    var id: Self { self }

    /// The lifter's own exercises with this origin, best search match first, or by name with nothing typed.
    static func shown(_ exercises: [Exercise], origin: CustomExerciseOrigin, importedKeys: Set<String>, query: String,
                      index: ExerciseSearch.Index?, familiarity: ExerciseFamiliarity = .none) -> [Exercise] {
        let own = exercises.filter { exercise in
            guard exercise.userCreated else { return false }
            switch origin {
            case .all: return true
            case .imported: return isImported(exercise, importedKeys: importedKeys)
            case .madeHere: return !isImported(exercise, importedKeys: importedKeys)
            }
        }
        guard !ExerciseQuery(query).isEmpty else {
            return own.sorted { $0.exerciseName.localizedStandardCompare($1.exerciseName) == .orderedAscending }
        }
        return ExercisePickerResults(exercises: own, index: index, familiarity: familiarity,
                                     query: query, muscles: [], mode: .add).matches
    }

    static func isImported(_ exercise: Exercise, importedKeys: Set<String>) -> Bool {
        exercise.syncKey.map(importedKeys.contains) ?? false
    }

    /// The exercises imported sets belong to. Reads one column, so a big import stays quick.
    static func importedKeys(in context: ModelContext) -> Set<String> {
        var descriptor = FetchDescriptor<ImportedSet>()
        descriptor.propertiesToFetch = [\.exerciseKey]
        return Set(((try? context.fetch(descriptor)) ?? []).map(\.exerciseKey))
    }
}

struct CustomExerciseList: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Exercise> { $0.userCreatedValue }, sort: \Exercise.exerciseName)
    private var exercises: [Exercise]

    @State private var index: ExerciseSearch.Index?
    @State private var familiarity = ExerciseFamiliarity.none
    @State private var importedKeys: Set<String> = []
    @State private var search = ""
    @State private var origin = CustomExerciseOrigin.all
    @State private var editing: Exercise?

    var body: some View {
        // A misspelt search retries with the closest exercise names, like the exercise picker.
        let (shown, correction) = SpellingCorrection.results(
            for: search, vocabulary: { exercises.map(\.exerciseName) }, isEmpty: \.isEmpty
        ) { text in
            CustomExerciseOrigin.shown(exercises, origin: origin, importedKeys: importedKeys, query: text,
                                       index: index, familiarity: familiarity)
        }
        List {
            if let correction { SpellingCorrectionNote(correction: correction) }
            ForEach(shown) { exercise in
                ExerciseSelectionRow(
                    exercise: exercise,
                    note: origin == .all && CustomExerciseOrigin.isImported(exercise, importedKeys: importedKeys)
                        ? "Imported" : nil
                ) { editing = exercise }
                .buttonStyle(.plain)
            }
        }
        .overlay { emptyState(isEmpty: shown.isEmpty) }
        .safeAreaBar(edge: .top, spacing: 0) {
            if !exercises.isEmpty {
                Picker("Show", selection: $origin) {
                    ForEach(CustomExerciseOrigin.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, LayoutMetrics.compactSpacing)
            }
        }
        // Always shown: the filter bar below would otherwise tuck the search field away.
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .searchAutocorrects()
        .navigationTitle("My Custom Exercises")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editing) { exercise in
            ExerciseDetailView(exercise: exercise)
        }
        .background { ExerciseSearchIndexLoader(index: $index, familiarity: $familiarity) }
        .task(id: exercises.count) { importedKeys = CustomExerciseOrigin.importedKeys(in: context) }
        .traceScreen("My Custom Exercises")
    }

    @ViewBuilder
    private func emptyState(isEmpty: Bool) -> some View {
        if exercises.isEmpty {
            EmptyStateView(title: "No Custom Exercises", systemImage: "figure.strengthtraining.traditional",
                           description: "Exercises you add, or create while importing, show here.")
        } else if isEmpty && index == nil && !search.isEmpty {
            ProgressView("Preparing search")
        } else if isEmpty && !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else if isEmpty {
            EmptyStateView(title: origin == .imported ? "No Imported Exercises" : "No Exercises Made Here",
                           systemImage: "line.3.horizontal.decrease")
        }
    }
}

#Preview("My Custom Exercises") {
    let scenario = PowerJackSeed.weekOneProgress()
    NavigationStack { CustomExerciseList() }
        .modelContainer(scenario.container)
}
