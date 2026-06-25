//
//  ContentView.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import SwiftUI
import SwiftData

struct WorkoutSetView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var workoutSets: [WorkoutSet]

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(workoutSets) { workoutSet in
                    WorkoutSetRowView(workoutSet: workoutSet)
                }
                .onDelete(perform: deleteItems)
            }
            .listStyle(.insetGrouped)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        } detail: {
            Text("Select an item")
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = WorkoutSet(
                order: workoutSets.count,
                reps: 15,
                weightTenthsPounds: 15
            )
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(workoutSets[index])
            }
        }
    }
}

#Preview("WorkoutSetView") {
    WorkoutSetView()
        .modelContainer(makeWorkoutSetPreviewContainer())
}
