import Foundation
import Testing
@testable import PowerJack

@MainActor
struct WorkoutHeartRateTests {
    @Test func rollingAverageAndExpiry() async throws {
        let rate = WorkoutHeartRate()
        defer { rate.clear() }
        let now = Date.now
        let older = HeartRateSample(id: UUID(), date: now.addingTimeInterval(-9), bpm: 100)
        let newest = HeartRateSample(id: UUID(), date: now.addingTimeInterval(-6.5), bpm: 120)
        let stale = HeartRateSample(id: UUID(), date: now.addingTimeInterval(-10), bpm: 180)
        rate.receive([newest, older, older, stale])
        try await Task.sleep(for: .milliseconds(100))
        #expect(rate.bpm == 110)
        try await Task.sleep(for: .seconds(2))
        #expect(rate.bpm == 120)
        try await Task.sleep(for: .seconds(1.6))
        #expect(rate.bpm == nil)
        rate.receive([stale])
        await Task.yield()
        #expect(rate.bpm == nil)
    }
}
