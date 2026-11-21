import SwiftUI
import Testing
@testable import PowerJack

@MainActor
@Suite(.serialized)
struct WorkoutHeaderTests {
    private let bench = Exercise(exerciseName: "Bench", exerciseEquipment: .barbell, primaryMuscleFocus: .chest)

    @Test("The pill follows navigation visibility, rest and exercise visibility", arguments: [true, false])
    func headerStates(hidden: Bool) async throws {
        let view = WorkoutHeader(pages: [.exercise(bench)], controlsHidden: hidden, pageScroll: ExercisePageScroll())
        let idle = try await HostedView(view)
        let equipment = Equipment.barbell.displayName
        #expect(idle.contains(hidden ? "Bench, \(equipment)" : equipment))
        idle.close()

        for remaining in [45.0, -1.0] {
            let now = Date.now
            let timer = WorkoutHeaderRest(period: RestPeriod(startedAt: now.addingTimeInterval(-60),
                endsAt: now.addingTimeInterval(remaining), exerciseName: "Bench", setNumber: 2, setCount: 3), onTap: {})
            let screen = try await HostedView(view.environment(\.workoutHeaderRest, timer))
            defer { screen.close() }
            let label = try #require(screen.labels.first { $0.contains(remaining > 0 ? "Rest " : "Start set") })
            #expect(label.contains("Bench") == hidden)
            // The timer sits after the equipment rather than replacing it.
            let equipmentAt = try #require(label.range(of: equipment))
            let restAt = try #require(label.range(of: remaining > 0 ? "Rest " : "Start set"))
            #expect(equipmentAt.upperBound <= restAt.lowerBound)
        }
    }

    @Test("The pill grows in place when the cards fade")
    func titleAppearsInPlace() async throws {
        let state = HeaderState()
        let screen = try await HostedView(SwitchingHeader(exercise: bench, state: state))
        defer { screen.close() }
        let equipment = Equipment.barbell.displayName
        let before = try #require(screen.frame(of: equipment))
        state.hidden = true
        await screen.settle(.milliseconds(600))
        let after = try #require(screen.frame(of: "Bench, \(equipment)"))
        #expect(after.height > before.height)
        #expect(abs(before.midX - after.midX) < 1)
    }

    @Test("The pill width follows the swipe between exercise pages")
    func swipeWidthFollowsPages() async throws {
        let row = Exercise(exerciseName: "Row", exerciseEquipment: .dumbbell, primaryMuscleFocus: .back)
        let pages: [WorkoutPageHeader] = [.exercise(bench), .exercise(row)]
        let scroll = ExercisePageScroll()
        let screen = try await HostedView(WorkoutHeader(pages: pages, controlsHidden: false, pageScroll: scroll))
        defer { screen.close() }
        let equipment = Equipment.barbell.displayName
        let start = try #require(screen.frame(of: equipment)).width
        scroll.position = 1
        await screen.settle()
        let end = try #require(screen.frame(of: Equipment.dumbbell.displayName)).width
        scroll.position = 0.5
        await screen.settle()
        let middle = try #require(screen.frame(of: equipment)).width
        #expect(abs(middle - (start + end) / 2) < 2)
    }

    @Test("The idle pill shows the whole name beyond the toolbar slot", arguments: [
        "Chest Supported Dumbbell Row", String(repeating: "W", count: 30)
    ])
    func longExerciseTitle(name: String) async throws {
        let exercise = Exercise(exerciseName: name, exerciseEquipment: .dumbbell, primaryMuscleFocus: .back)
        let textProbe = TextTruncationProbe()
        let screen = try await HostedView(
            WorkoutHeader(pages: [.exercise(exercise)], controlsHidden: true,
                          pageScroll: ExercisePageScroll(), idleWidth: 280)
                .frame(width: 200)
                .textRenderer(textProbe)
        )
        defer { screen.close() }
        let pill = try #require(screen.frame(of: "\(name), Dumbbell"))
        #expect(pill.width > 200 && pill.width <= 281)
        #expect(abs(pill.midX - screen.window.bounds.midX) < 1)
        #expect(!textProbe.truncated.isEmpty)
        #expect(!textProbe.truncated.contains(true))
    }

    @Test("A superset member's pill names its superset before the equipment")
    func supersetLabel() async throws {
        let superset = WorkoutPageSuperset(letter: "A", color: .blue, partners: ["Row"])
        let screen = try await HostedView(
            WorkoutHeader(pages: [.exercise(bench, superset: superset)], controlsHidden: false, pageScroll: ExercisePageScroll())
        )
        defer { screen.close() }
        #expect(screen.contains("Superset with Row, \(Equipment.barbell.displayName)"))
    }

    @Test("Review keeps its own title")
    func reviewHeader() async throws {
        let screen = try await HostedView(WorkoutHeader(pages: [.review], controlsHidden: true, pageScroll: ExercisePageScroll()))
        defer { screen.close() }
        #expect(screen.contains("Review"))
    }
}

@Observable
private final class HeaderState {
    var hidden = false
    let scroll = ExercisePageScroll()
}

private struct SwitchingHeader: View {
    let exercise: Exercise
    let state: HeaderState

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 40, height: 1)
            WorkoutHeader(pages: [.exercise(exercise)], controlsHidden: state.hidden, pageScroll: state.scroll)
            Spacer(minLength: 0)
        }
    }
}
