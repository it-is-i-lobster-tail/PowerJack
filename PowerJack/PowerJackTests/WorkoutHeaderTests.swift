import SwiftUI
import Testing
@testable import PowerJack

@MainActor
@Suite(.serialized)
struct WorkoutHeaderTests {
    private let bench = Exercise(exerciseName: "Bench", exerciseEquipment: .barbell, primaryMuscleFocus: .chest)

    @Test("The pill follows navigation visibility, page type and rest", arguments: [true, false], [true, false])
    func headerStates(superset: Bool, hidden: Bool) async throws {
        let page: WorkoutPageHeader = superset ? .superset("B") : .exercise(bench)
        let view = WorkoutHeader(pages: [page], controlsHidden: hidden, pageScroll: ExercisePageScroll())
        let idle = try await HostedView(view)
        let equipment = Equipment.barbell.displayName
        #expect(idle.contains(superset ? "Superset B" : hidden ? "Bench, \(equipment)" : equipment))
        idle.close()

        for remaining in [45.0, -1.0] {
            let now = Date.now
            let timer = WorkoutHeaderRest(period: RestPeriod(startedAt: now.addingTimeInterval(-60),
                endsAt: now.addingTimeInterval(remaining), exerciseName: "Bench", setNumber: 2, setCount: 3), onTap: {})
            let screen = try await HostedView(view.environment(\.workoutHeaderRest, timer))
            defer { screen.close() }
            let title = superset ? "Superset B" : "Bench"
            let label = try #require(screen.labels.first { $0.contains(remaining > 0 ? "Rest " : "Start set") })
            #expect(label.contains(title) == hidden)
            #expect(!label.contains(equipment))
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

    @Test("The pill width follows the swipe across an exercise and a superset")
    func swipeWidthFollowsPages() async throws {
        let pages: [WorkoutPageHeader] = [.exercise(bench), .superset("B")]
        let scroll = ExercisePageScroll()
        let screen = try await HostedView(WorkoutHeader(pages: pages, controlsHidden: false, pageScroll: scroll))
        defer { screen.close() }
        let equipment = Equipment.barbell.displayName
        let start = try #require(screen.frame(of: equipment)).width
        scroll.position = 1
        await screen.settle()
        let end = try #require(screen.frame(of: "Superset B")).width
        scroll.position = 0.5
        await screen.settle()
        let middle = try #require(screen.frame(of: equipment)).width
        #expect(abs(middle - (start + end) / 2) < 2)
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
