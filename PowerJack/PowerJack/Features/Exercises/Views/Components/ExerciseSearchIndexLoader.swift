import SwiftData
import SwiftUI

/// Snapshot SwiftData on its actor, then index the catalog off the UI thread.
/// Keeping the loader separate avoids rebuilding the index as the user types.
struct ExerciseSearchIndexLoader: View {
    @Environment(\.modelContext) private var context
    @Query private var exercises: [Exercise]
    @Binding var index: ExerciseSearch.Index?
    @Binding var familiarity: ExerciseFamiliarity

    private static let familiarityCache = HistoryCache<ExerciseFamiliarity>()

    var body: some View {
        let documents = exercises.map(ExerciseSearch.Document.init)
        // Walking every workout is slow with years of history, so it runs once per saved change.
        let familiar = Self.familiarityCache.value(in: context) {
            ExerciseFamiliarity.from(workouts: (try? context.fetch(FetchDescriptor<Workout>())) ?? [],
                                     imported: (try? context.fetch(FetchDescriptor<ImportedSet>())) ?? [])
        }
        Color.clear
            .task(id: documents) {
                let build = Task.detached(priority: .userInitiated) { ExerciseSearch.Index(documents) }
                let updated = await build.value
                if !Task.isCancelled { index = updated }
            }
            .onChange(of: familiar, initial: true) { familiarity = familiar }
    }
}
