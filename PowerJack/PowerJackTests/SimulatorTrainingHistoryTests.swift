#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct SimulatorTrainingHistoryTests {
    @Test("Reopening the local sample database keeps edits and seeds each workout once")
    func persistsHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let store = try SimulatorTrainingHistory.openStore(in: directory)
            let context = store.container.mainContext
            let exercises = try context.fetch(FetchDescriptor<Exercise>())
            let lunge = try #require(exercises.first { $0.exerciseName == "Barbell Reverse Lunge (reps per leg)" })
            lunge.exerciseName = "My barbell reverse lunge"
            try context.save()
        }

        let reopened = try SimulatorTrainingHistory.openStore(in: directory)
        let context = reopened.container.mainContext
        #expect(try context.fetchCount(FetchDescriptor<Program>()) == 4)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutLog>()) == 141)
        #expect(try context.fetch(FetchDescriptor<Exercise>()).contains { $0.exerciseName == "My barbell reverse lunge" })
        reopened.turnOnICloudBackup()
        #expect(!reopened.syncsWithICloud)
        #expect(!reopened.allowsExternalSync)
    }
}
#endif
