//
//  ExerciseStripTests.swift
//  PowerJackTests
//
//  The exercise strip under a workout follows the exercise on screen.
//

import SwiftData
import SwiftUI
import Testing
@testable import PowerJack

@MainActor
@Suite(.serialized)
struct ExerciseStripTests {
    private let container = PowerJackSeed.makeInMemoryContainer()
    private let router = ProgramsRouter()
    private static let exerciseCount = 6

    @Test("Resuming a workout mid-way scrolls the strip to the current exercise")
    func resumeScrollsStripToCurrentExercise() async throws {
        let (program, workout) = try makeStartedWorkout()
        // The first four are done, so the lifter resumes on the fifth.
        workout.workoutExercises.prefix(4).forEach { $0.skipRemainingSets() }
        try container.mainContext.save()
        #expect(workout.currentExerciseIndex == 4)

        // Back on the program's page, then Resume pushes the workout again.
        router.showDetailOnly(program)
        let screen = try await HostedView(programScreen())
        // Pop first, so nothing still on the stack reads the program after its container goes away.
        defer {
            router.popToRoot()
            screen.close()
        }
        router.showSession(program)

        let strip = try #require(await stripScrollView(in: screen))
        #expect(await screen.waitUntil { isCardCentered(4, in: strip) }, "offset \(strip.contentOffset.x)")
    }

    @Test("Tapping strip cards quickly leaves the pager and the strip on the last tap")
    func fastChipTapsStayInSync() async throws {
        let (_, workout) = try makeStartedWorkout()
        let names = workout.workoutExercises.map { $0.exercise?.exerciseName ?? "" }
        let screen = try await HostedView(workoutScreen(workout))
        defer { screen.close() }

        // Each tap lands while the last one is still scrolling, back and forth.
        for index in [2, 1, 3, 2] {
            await screen.tap(names[index], settleFor: .milliseconds(40))
        }

        let strip = try #require(await stripScrollView(in: screen))
        let pager = try #require(screen.horizontalScrollViews.first { $0 !== strip })
        #expect(await screen.waitUntil { isCardCentered(2, in: strip) }, "strip offset \(strip.contentOffset.x)")
        #expect(await screen.waitUntil { pagerPage(pager) == 2 }, "pager page \(pagerPage(pager))")
    }

    // MARK: Helpers

    private func workoutScreen(_ workout: Workout) -> some View {
        NavigationStack {
            WorkoutDetailView(workout: workout)
        }
        .modelContainer(container)
    }

    private func programScreen() -> some View {
        ProgramStack(router: router)
            .modelContainer(container)
    }

    /// The strip is the short sideways scroller under the pager.
    private func stripScrollView(in screen: HostedView) async -> UIScrollView? {
        await screen.waitUntil { screen.horizontalScrollViews.count == 2 }
        return screen.horizontalScrollViews.min { $0.bounds.height < $1.bounds.height }
    }

    /// Three equal cards fill the strip between 16-point margins, so a card's center is easy to place.
    private func isCardCentered(_ index: Int, in strip: UIScrollView) -> Bool {
        let spacing = LayoutMetrics.compactSpacing
        let cardWidth = (strip.bounds.width - 32 - spacing * 2) / 3
        let cardMid = 16 + CGFloat(index) * (cardWidth + spacing) + cardWidth / 2
        let visibleMid = strip.contentOffset.x + strip.adjustedContentInset.left + strip.bounds.width / 2
        return abs(cardMid - visibleMid) < (cardWidth + spacing) / 2
    }

    private func pagerPage(_ pager: UIScrollView) -> Int {
        Int((pager.contentOffset.x / pager.bounds.width).rounded())
    }

    private func makeStartedWorkout() throws -> (Program, Workout) {
        let context = container.mainContext
        let template = TemplateProgram(templateName: "Test", workoutsPerWeek: 1, templateMuscleFocus: [.chest])
        let day = template.addTemplateWorkout()
        for number in 1...Self.exerciseCount {
            let exercise = Exercise(
                exerciseName: "Lift \(number)",
                exerciseEquipment: .barbell,
                primaryMuscleFocus: .chest,
                minReps: 6,
                maxReps: 12
            )
            context.insert(exercise)
            day.addTemplateExercise(exercise: exercise)
        }
        context.insert(template)
        let program = Program(programLengthWeeks: 1, templateProgram: template)
        try context.insertAndSave(program)
        program.start()
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        try context.save()
        return (program, workout)
    }
}

private struct ProgramStack: View {
    @Bindable var router: ProgramsRouter

    var body: some View {
        NavigationStack(path: $router.path) {
            Color.clear
                .programRouteDestinations()
        }
        .environment(router)
    }
}
