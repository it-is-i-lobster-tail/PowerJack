import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import PowerJack

@MainActor
struct StudyQuestionTests {
    #if DEBUG && targetEnvironment(simulator)
    @Test("The chart search explains a missing measurement on screen")
    func missingMeasurement() async throws {
        let store = PowerJackStore(inMemory: true)
        HostedView.keep(store.container)
        let screen = try await HostedView(ProgramDataView().modelContainer(store.container))
        defer { screen.close() }
        try #require(await screen.typeIntoFirstField("Did sleep help my bench press?"))
        #expect(await screen.waitUntil {
            screen.labels.contains { $0.contains("Not enough data") && $0.contains("sleep records") }
        })
    }

    @Test("Direct answers use the requested workout denominator, movement and dates")
    func scopedCalculations() throws {
        let context = PowerJackStore(inMemory: true)
        let db = context.container.mainContext
        let calendar = Calendar(identifier: .gregorian)
        let today = try #require(calendar.date(from: .init(year: 2026, month: 11, day: 25, hour: 10)))
        try SimulatorTrainingHistory.populate(in: db, now: today)
        let history = StudyHistory(programs: try db.fetch(FetchDescriptor<Program>()), archive: try HistoryArchive.records(in: db),
                                   logs: try db.fetch(FetchDescriptor<WorkoutLog>()), unit: .pounds, today: today, calendar: calendar)
        let volume = StudyQuestion("How much bench volume did I do in October?", history: history)
        let october = history.sessions.filter {
            $0.key == StudyHistory.bench && calendar.component(.month, from: $0.date) == 10
                && calendar.component(.year, from: $0.date) == 2026
        }
        let expected = october.flatMap(\.done).reduce(0.0) { total, set in
            total + history.weight(set.load ?? 0) * Double(set.reps ?? 0)
        }
        let chart = try #require(volume.result(history))
        #expect(expected > 0)
        #expect(chart.summary.contains(expected.studyNumber))
        let attendance = StudyQuestion("How many workouts did I finish last week?", history: history)
        let completed = history.workouts.filter { $0.status == .complete && $0.date.map(attendance.includes) == true }
        #expect(attendance.result(history)?.plottedValues?.rows.count == completed.count)
        let consecutive = StudyQuestion("How often do I train chest on back-to-back days?", history: history)
        #expect(consecutive.muscles == [.chest])
        let exact = StudyQuestion("compare squat versus deadlift strength", history: history)
        #expect(exact.liftNames.count == 2)
        #expect(!exact.sessions(history).contains { $0.name.localizedCaseInsensitiveContains("Romanian") })
        let rows = try #require(exact.result(history)?.plottedValues?.rows)
        #expect(rows.count == 2)
        let unsupported = try #require(StudyQuestion("bench strength relative to bodyweight", history: history).result(history))
        #expect(unsupported.summary.contains("no dated bodyweight"))
        #expect(unsupported.plottedValues?.rows.first?.last == "Unrecorded")
        let knee = try #require(StudyQuestion("Did my knee pain affect my squat this month?", history: history).result(history))
        #expect(knee.galleryCaption == "Not enough data")
        #expect(knee.figure == nil)
        let unmatched = try #require(StudyQuestion("What did I listen to in the gym?", history: history).result(history))
        #expect(unmatched.galleryCaption == "Not enough data")
        let midSentence = StudyQuestion("How many October sessions did I finish?", history: history)
        #expect(midSentence.interval == volume.interval)
        let empty = StudyHistory(programs: [], archive: [], logs: [], unit: .pounds, today: today)
        let partialTotal = try #require(StudyQuestion("What is my powerlifting total?", history: empty).result(empty))
        #expect(partialTotal.galleryCaption == "Not enough data")
        let twoMonths = try #require(StudyQuestion("Did I do more workouts in October than in September?", history: history).result(history))
        #expect(twoMonths.plottedValues?.rows.count == 2)
        for browse in ["arms", "legs strength", "upper body volume Oct", "press"] {
            #expect(StudyQuestion(browse, history: history).result(history) == nil)
        }
    }
    #endif
}
