//
//  ImportedDataView.swift
//  PowerJack
//
//  Every set brought in from another app, by day. Search, select and delete them.
//

import SwiftData
import SwiftUI

struct ImportedDataView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\ImportedSet.trainingDay, order: .reverse), SortDescriptor(\ImportedSet.sourceOrder)])
    private var sets: [ImportedSet]
    @Query private var exercises: [Exercise]

    @State private var search = ""
    @State private var index: ExerciseSearch.Index?
    @State private var selection: Set<PersistentIdentifier> = []
    @State private var editMode: EditMode = .inactive
    @State private var isConfirmingDelete = false
    @State private var showsDeleteError = false

    private var shown: [ImportedSet] { ImportedData.matching(search, in: sets, index: index) }
    private var isSelecting: Bool { editMode.isEditing }

    /// Only sets the lifter can see are deleted, so a search never deletes rows it hides.
    private var selected: [ImportedSet] { shown.filter { selection.contains($0.persistentModelID) } }

    var body: some View {
        let shown = shown
        let selected = selected
        List(selection: $selection) {
            ForEach(ImportedData.days(shown)) { day in
                Section(day.title) {
                    ForEach(day.sets) { set in row(set) }
                }
            }
        }
        .overlay {
            if sets.isEmpty {
                ContentUnavailableView("No Imported Sets", systemImage: "square.and.arrow.down",
                                       description: Text("Sets you import from another app, such as FitNotes, show here."))
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .environment(\.editMode, $editMode)
        .searchable(text: $search, prompt: "Search exercises")
        // Keep Select and Select All in reach while searching, so a search can be selected and deleted.
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .navigationTitle(isSelecting ? selectedTitle(selected.count) : "Imported Data")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSelecting)
        .toolbar(isSelecting ? .hidden : .visible, for: .tabBar)
        .toolbar {
            if !sets.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSelecting ? "Done" : "Select", action: toggleSelecting)
                }
            }
            if isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    let allSelected = !shown.isEmpty && selected.count == shown.count
                    Button(allSelected ? "Deselect All" : "Select All") {
                        let ids = shown.map(\.persistentModelID)
                        if allSelected { selection.subtract(ids) } else { selection.formUnion(ids) }
                    }
                    .disabled(shown.isEmpty)
                }
                ToolbarSpacer(placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button("Delete", role: .destructive) { isConfirmingDelete = true }
                        .tint(.red)
                        .disabled(selected.isEmpty)
                        .accessibilityIdentifier("importedData.delete")
                }
            }
        }
        .alert(deleteTitle(selected.count), isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) { delete(selected) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They'll be removed from this iPhone, iCloud and your Data charts. This can't be undone.")
        }
        .alert("Couldn't Delete", isPresented: $showsDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing was deleted. Try again.")
        }
        .task(id: sets.count) {
            let documents = ImportedData.documents(for: sets, exercises: exercises)
            let build = Task.detached(priority: .userInitiated) { ExerciseSearch.Index(documents) }
            let built = await build.value
            if !Task.isCancelled { index = built }
        }
        .traceScreen("Imported Data")
    }

    private func row(_ set: ImportedSet) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(set.exerciseName)
            Text(ImportedData.detail(set, unit: .current))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !set.sourceExercise.isEmpty, set.sourceExercise != set.exerciseName {
                Text("Imported as “\(set.sourceExercise)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func selectedTitle(_ count: Int) -> String {
        switch count {
        case 0: "Select Sets"
        case 1: "1 Set Selected"
        default: "\(count) Sets Selected"
        }
    }

    private func deleteTitle(_ count: Int) -> String {
        count == 1 ? "Delete 1 Set?" : "Delete \(count) Sets?"
    }

    private func toggleSelecting() {
        withAnimation {
            if isSelecting {
                editMode = .inactive
                selection = []
            } else {
                editMode = .active
            }
        }
    }

    private func delete(_ doomed: [ImportedSet]) {
        let deletesEverything = doomed.count == sets.count
        let ids = doomed.map(\.persistentModelID)
        do {
            try ImportedData.delete(doomed, in: context)
            selection.subtract(ids)
            if deletesEverything { editMode = .inactive }
        } catch {
            showsDeleteError = true
        }
    }
}

#Preview("Imported Data") {
    NavigationStack { ImportedDataView() }
        .environment(PowerJackStore(inMemory: true))
}
