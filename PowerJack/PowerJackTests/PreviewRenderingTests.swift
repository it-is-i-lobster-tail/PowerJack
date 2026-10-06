import SwiftData
import SwiftUI
import XCTest
@testable import PowerJack

/// Exercises the same screens and data used by Canvas on a real simulator runtime.
/// These checks catch runtime/model failures; Canvas's JIT pipeline is separate.
@MainActor
final class PreviewRenderingTests: XCTestCase {
    func testPreviewScreensRender() async throws {
        let scenario = PowerJackSeed.weekOneProgress()
        let empty = PowerJackSeed.makeInMemoryContainer()
        let emptyWorkout = PowerJackSeed.emptyWorkout()
        let progression = PowerJackSeed.weekTwoProgression()

        func navigation<V: View>(_ view: V, emptyData: Bool = false) -> AnyView {
            AnyView(NavigationPreviewHost(modelContainer: emptyData ? empty : scenario.container) { view })
        }

        let screens: [(String, AnyView)] = [
            ("Root - Active", AnyView(PowerJackRootView().modelContainer(scenario.container))),
            ("Root - Empty", AnyView(PowerJackRootView().modelContainer(empty))),
            ("Programs - Loaded", navigation(ProgramListView())),
            ("Programs - Empty", navigation(ProgramListView(), emptyData: true)),
            ("Program Detail", navigation(ProgramDetailView(program: scenario.program))),
            ("New Program - Loaded", navigation(ProgramNew())),
            ("New Program - Empty", navigation(ProgramNew(), emptyData: true)),
            ("Templates - Loaded", AnyView(TemplateProgramListView().modelContainer(scenario.container))),
            ("Templates - Empty", AnyView(TemplateProgramListView().modelContainer(empty))),
            ("Template Detail", navigation(TemplateProgramDetailView(templateProgram: scenario.templateProgram))),
            ("New Template", navigation(TemplateProgramNew(onSave: { _ in }))),
            ("Template Builder", navigation(BuilderHost())),
            ("Exercises - Change", AnyView(ExerciseSelectionView(navigationTitle: "Change Exercise", onSelect: { _ in }).modelContainer(scenario.container))),
            ("Exercises - Browse", AnyView(ExerciseSelectionView(navigationTitle: "Select Exercise").modelContainer(scenario.container))),
            ("Exercises - Empty", AnyView(ExerciseSelectionView(navigationTitle: "Select Exercise").modelContainer(empty))),
            ("Exercise - Barbell", navigation(ExerciseDetailView(exercise: scenario.exercises[0]))),
            ("Exercise - Bodyweight", navigation(ExerciseDetailView(exercise: scenario.exercises[2]))),
            ("Exercise - Leg Press", navigation(ExerciseDetailView(exercise: scenario.exercises[5]))),
            ("New Exercise", navigation(ExerciseNewView(onSave: { _ in }), emptyData: true)),
            ("Workout - Loaded", navigation(WorkoutDetailView(workout: scenario.weekOneWorkouts[2]))),
            ("Workout - Empty", AnyView(NavigationPreviewHost(modelContainer: emptyWorkout.container) {
                WorkoutDetailView(workout: emptyWorkout.workout)
            })),
            ("Workout - Week 2", AnyView(NavigationPreviewHost(modelContainer: progression.container) {
                WorkoutDetailView(workout: progression.weekTwoWorkouts[0], weekNumber: 2, weekCount: 4)
            })),
            ("Session - Week 1", navigation(ProgramSessionView(program: scenario.program))),
            ("Session - Week 2", AnyView(NavigationPreviewHost(modelContainer: progression.container) {
                ProgramSessionView(program: progression.program)
            })),
            ("Feedback", AnyView(Feedback(
                workoutExercise: scenario.weekOneWorkouts[1].workoutExercises[0],
                onFinished: {}
            ).modelContainer(scenario.container))),
            ("Manual Check-In", AnyView(ManualCheckInSheet(
                workoutExercise: progression.checkInExercise,
                onResolved: {}
            ).modelContainer(progression.container))),
            ("Settings", AnyView(SettingsView().environment(PowerJackStore(inMemory: true)))),
            ("Rest Between Sets", AnyView(NavigationStack { RestBetweenSetsView() })),
            ("Workout Summary", AnyView(ExerciseSummaryView(
                setCounts: scenario.weekOneWorkouts[0].completedSetsByMuscle,
                onContinue: {}
            ))),
            ("Rest Island", AnyView(RestIslandHost(
                rest: try XCTUnwrap(scenario.weekOneWorkouts[1].currentRest)
            ))),
        ]

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        for (name, screen) in screens {
            let host = UIHostingController(rootView: screen)
            window.rootViewController = host
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertGreaterThan(host.view.bounds.width, 0, name)
            let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
            let image = renderer.image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testSeedScenarioPersistsExpectedProgress() throws {
        let scenario = PowerJackSeed.weekOneProgress()
        XCTAssertEqual(try scenario.container.mainContext.fetch(FetchDescriptor<Exercise>()).count, 6)
        XCTAssertEqual(scenario.program.programWeeks.count, 8)
        XCTAssertEqual(scenario.program.workoutsFinished, 1)
        XCTAssertTrue(scenario.program.nextWorkout === scenario.weekOneWorkouts[1])
        XCTAssertEqual(scenario.weekOneWorkouts.map(\.totalSets), [6, 6, 6])
        XCTAssertEqual(scenario.weekOneWorkouts[0].getCountCompletedSets(), 6)
        XCTAssertEqual(scenario.weekOneWorkouts[1].getCountSkippedSets(), 2)
        XCTAssertEqual(scenario.weekOneWorkouts[0].workoutExercises[0].workoutSets[0].reps, 8)
        XCTAssertTrue(scenario.weekOneWorkouts[0].workoutExercises.allSatisfy { $0.feedback != nil })
    }

    func testProgressionSeedScenarioBuildsWeekTwo() throws {
        let scenario = PowerJackSeed.weekTwoProgression()
        XCTAssertEqual(scenario.program.programWeeks.count, 4)
        XCTAssertEqual(scenario.program.workoutsFinished, 3)
        XCTAssertEqual(scenario.weekTwoWorkouts.count, 3)
        XCTAssertTrue(scenario.program.nextWorkout === scenario.weekTwoWorkouts[0])
        XCTAssertTrue(scenario.checkInExercise.checkInPending)
        XCTAssertEqual(scenario.program.weekNumber(containing: scenario.weekTwoWorkouts[0]), 2)
    }
}

private struct BuilderHost: View {
    @State private var draft = TemplateProgramDraft()

    var body: some View {
        TemplateBuilder(draft: $draft)
    }
}

private struct RestIslandHost: View {
    let rest: RestPeriod
    @State private var isExpanded = true

    var body: some View {
        RestIsland(rest: rest, isExpanded: $isExpanded, onOpenExercise: {})
            .frame(maxHeight: .infinity, alignment: .top)
    }
}
