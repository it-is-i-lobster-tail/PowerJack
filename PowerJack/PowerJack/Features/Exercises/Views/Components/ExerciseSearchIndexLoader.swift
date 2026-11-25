import SwiftData
import SwiftUI

/// Snapshot SwiftData on its actor, then index the catalog off the UI thread.
/// Keeping the loader separate avoids rebuilding the index as the user types.
struct ExerciseSearchIndexLoader: View {
    @Query private var exercises: [Exercise]
    @Binding var index: ExerciseChartSearch.Index?

    var body: some View {
        let documents = exercises.map(ExerciseChartSearch.Document.init)
        Color.clear.task(id: documents) {
            let build = Task.detached(priority: .userInitiated) { ExerciseChartSearch.Index(documents) }
            let updated = await build.value
            if !Task.isCancelled { index = updated }
        }
    }
}
