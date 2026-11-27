import SwiftData
import SwiftUI

/// Snapshot SwiftData on its actor, then index the catalog off the UI thread.
/// Keeping the loader separate avoids rebuilding the index as the user types.
struct ExerciseSearchIndexLoader: View {
    @Query private var exercises: [Exercise]
    @Query private var workouts: [Workout]
    @Query private var imported: [ImportedSet]
    @Binding var index: ExerciseSearch.Index?
    @Binding var familiarity: ExerciseFamiliarity

    var body: some View {
        let documents = exercises.map(ExerciseSearch.Document.init)
        let familiar = ExerciseFamiliarity.from(workouts: workouts, imported: imported)
        Color.clear
            .task(id: documents) {
                let build = Task.detached(priority: .userInitiated) { ExerciseSearch.Index(documents) }
                let updated = await build.value
                if !Task.isCancelled { index = updated }
            }
            .onChange(of: familiar, initial: true) { familiarity = familiar }
    }
}
