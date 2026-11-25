import SwiftUI
import Testing
@testable import PowerJack

@MainActor
@Suite(.serialized)
struct WorkoutHeaderTests {
    private let bench = Exercise(exerciseName: "Bench", exerciseEquipment: .barbell, primaryMuscleFocus: .chest)

    @Test("The pill always shows the name, and a rest timer takes the equipment's place")
    func headerStates() async throws {
        let view = WorkoutHeader(pages: [.exercise(bench)], pageScroll: ExercisePageScroll())
        let idle = try await HostedView(view)
        let equipment = Equipment.barbell.displayName
        #expect(idle.contains("Bench, \(equipment)"))
        idle.close()

        for remaining in [45.0, -1.0] {
            let now = Date.now
            let timer = WorkoutHeaderRest(period: RestPeriod(startedAt: now.addingTimeInterval(-60),
                endsAt: now.addingTimeInterval(remaining), exerciseName: "Bench", setNumber: 2, setCount: 3), onTap: {})
            let screen = try await HostedView(view.environment(\.workoutHeaderRest, timer))
            defer { screen.close() }
            let label = try #require(screen.labels.first { $0.contains(remaining > 0 ? "Rest " : "Start set") })
            #expect(label.contains("Bench"))
            // The timer takes the equipment's place.
            #expect(!label.contains(equipment))
        }
    }

    @Test("The pill width follows the swipe between exercise pages")
    func swipeWidthFollowsPages() async throws {
        let row = Exercise(exerciseName: "Row", exerciseEquipment: .dumbbell, primaryMuscleFocus: .back)
        let pages: [WorkoutPageHeader] = [.exercise(bench), .exercise(row)]
        let scroll = ExercisePageScroll()
        let screen = try await HostedView(WorkoutHeader(pages: pages, pageScroll: scroll))
        defer { screen.close() }
        let first = "Bench, \(Equipment.barbell.displayName)"
        let start = try #require(screen.frame(of: first)).width
        scroll.position = 1
        await screen.settle()
        let end = try #require(screen.frame(of: "Row, \(Equipment.dumbbell.displayName)")).width
        scroll.position = 0.5
        await screen.settle()
        let middle = try #require(screen.frame(of: first)).width
        #expect(abs(middle - (start + end) / 2) < 2)
    }

    @Test("A long name and three-digit heart rate fit in the toolbar slot", arguments: [
        "Chest Supported Dumbbell Row", String(repeating: "W", count: 30)
    ])
    func longExerciseTitle(name: String) async throws {
        let exercise = Exercise(exerciseName: name, exerciseEquipment: .dumbbell, primaryMuscleFocus: .back)
        let textProbe = TextTruncationProbe()
        let heartRate = WorkoutHeartRate.shared
        heartRate.receive([HeartRateSample(id: UUID(), date: .now, bpm: 118)])
        defer { heartRate.clear() }
        let screen = try await HostedView(
            WorkoutHeader(pages: [.exercise(exercise)], pageScroll: ExercisePageScroll(), showsHeartRate: true)
                .frame(width: 200)
                .textRenderer(textProbe)
        )
        defer { screen.close() }
        let pill = try #require(screen.frame(of: "\(name), Dumbbell, Heart rate, 118 beats per minute"))
        #expect(pill.width <= 201)
        #expect(abs(pill.midX - screen.window.bounds.midX) < 1)
        #expect(!textProbe.truncated.isEmpty)
        #expect(!textProbe.truncated.contains(true))
    }

    @Test("A superset member's pill names its superset before the equipment")
    func supersetLabel() async throws {
        let superset = WorkoutPageSuperset(letter: "A", color: .blue, partners: ["Row"])
        let screen = try await HostedView(
            WorkoutHeader(pages: [.exercise(bench, superset: superset)], pageScroll: ExercisePageScroll())
        )
        defer { screen.close() }
        #expect(screen.contains("Bench, Superset with Row, \(Equipment.barbell.displayName)"))
    }

    @Test("Review keeps its own title")
    func reviewHeader() async throws {
        let screen = try await HostedView(WorkoutHeader(pages: [.review], pageScroll: ExercisePageScroll()))
        defer { screen.close() }
        #expect(screen.contains("Review"))
    }
}
