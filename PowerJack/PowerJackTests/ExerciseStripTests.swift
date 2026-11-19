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

    @Test("A new workout opens with the first exercise in the middle of the strip")
    func firstExerciseStartsCentered() async throws {
        let (_, workout) = try makeStartedWorkout()
        let screen = try await HostedView(workoutScreen(workout))
        defer { screen.close() }

        let strip = try #require(await stripScrollView(in: screen))
        #expect(await screen.waitUntil { isCardCentered(0, in: strip, screen: screen) }, "offset \(strip.contentOffset.x)")
    }

    @Test("Review, the last card, comes to the middle of the strip too")
    func reviewCentersWhenSelected() async throws {
        let (_, workout) = try makeStartedWorkout()
        let names = workout.workoutExercises.map { $0.exercise?.exerciseName ?? "" }
        let screen = try await HostedView(workoutScreen(workout))
        defer { screen.close() }

        let strip = try #require(await stripScrollView(in: screen))
        #expect(await screen.waitUntil { isCardCentered(0, in: strip, screen: screen) })
        // Step along the strip the way a lifter would, ending on Review.
        for name in names.dropFirst() + ["Review"] {
            await screen.tap(name)
        }
        #expect(await screen.waitUntil { isCardCentered("Review", in: strip, screen: screen) }, "offset \(strip.contentOffset.x)")
    }

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
        #expect(await screen.waitUntil { isCardCentered(4, in: strip, screen: screen) }, "offset \(strip.contentOffset.x)")
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
        #expect(await screen.waitUntil { isCardCentered(2, in: strip, screen: screen) }, "strip offset \(strip.contentOffset.x)")
        #expect(await screen.waitUntil { pagerPage(pager) == 2 }, "pager page \(pagerPage(pager))")
    }

    @Test("Half a swipe moves the strip half a card")
    func stripFollowsTheSwipe() async throws {
        let (_, workout) = try makeStartedWorkout()
        let screen = try await HostedView(workoutScreen(workout))
        defer { screen.close() }

        let strip = try #require(await stripScrollView(in: screen))
        let pager = try #require(screen.horizontalScrollViews.first { $0 !== strip })
        #expect(await screen.waitUntil { isCardCentered(0, in: strip, screen: screen) })

        // Hold the pages halfway between the first and second exercise, as a finger would.
        pager.setContentOffset(CGPoint(x: pager.bounds.width / 2, y: 0), animated: false)

        #expect(await screen.waitUntil { isMidway(between: "Lift 1", and: "Lift 2", in: strip, screen: screen) }, "offset \(strip.contentOffset.x)")
    }

    @Test("A card looks fully selected on its page, half way between two pages, and plain a page away")
    func cardFocusFollowsThePages() {
        #expect(ExercisePreviewStrip.focus(ofCard: 1, pagePosition: 1) == 1)
        #expect(ExercisePreviewStrip.focus(ofCard: 1, pagePosition: 0.5) == 0.5)
        #expect(ExercisePreviewStrip.focus(ofCard: 1, pagePosition: 1.5) == 0.5)
        #expect(ExercisePreviewStrip.focus(ofCard: 1, pagePosition: 0) == 0)
        #expect(ExercisePreviewStrip.focus(ofCard: 1, pagePosition: 3) == 0)
    }

    @Test("A card's name grows smoothly from caption size a page away to body size on its page")
    func nameSizeFollowsThePages() {
        let resting = ExercisePreviewStrip.textScale(focus: 0, dynamicTypeSize: .large)
        #expect(abs(resting - 12.0 / 17.0) < 0.001)
        #expect(ExercisePreviewStrip.textScale(focus: 1, dynamicTypeSize: .large) == 1)

        // Every small step of a swipe changes the size a little, never a jump.
        let steps = stride(from: 0.0, through: 1.0, by: 0.05).map { ExercisePreviewStrip.textScale(focus: $0, dynamicTypeSize: .large) }
        for (smaller, bigger) in zip(steps, steps.dropFirst()) {
            #expect(bigger > smaller)
            #expect(bigger - smaller < 0.02)
        }

        // Past the strip's Dynamic Type cap, the name stops changing.
        #expect(ExercisePreviewStrip.textScale(focus: 0, dynamicTypeSize: .accessibility5)
            == ExercisePreviewStrip.textScale(focus: 0, dynamicTypeSize: .xxxLarge))
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

    /// The card sits in the middle of the strip, within a few points.
    private func isCardCentered(_ index: Int, in strip: UIScrollView, screen: HostedView) -> Bool {
        isCardCentered("Lift \(index + 1)", in: strip, screen: screen)
    }

    private func isCardCentered(_ name: String, in strip: UIScrollView, screen: HostedView) -> Bool {
        let stripFrame = strip.convert(strip.bounds, to: nil)
        // The page title shows the same name, so take the one inside the strip.
        guard let card = screen.frames(of: name).first(where: { stripFrame.contains(CGPoint(x: $0.midX, y: $0.midY)) }) else {
            return false
        }
        return abs(card.midX - stripFrame.midX) < 2
    }

    /// The strip's middle falls halfway between the two cards.
    private func isMidway(between first: String, and second: String, in strip: UIScrollView, screen: HostedView) -> Bool {
        guard let frames = try? cardFrames([first, second], in: strip, screen: screen) else { return false }
        let stripFrame = strip.convert(strip.bounds, to: nil)
        return abs((frames[0].midX + frames[1].midX) / 2 - stripFrame.midX) < 2
    }

    /// The cards with these names inside the strip, not the page titles with the same names.
    private func cardFrames(_ names: [String], in strip: UIScrollView, screen: HostedView) throws -> [CGRect] {
        let stripFrame = strip.convert(strip.bounds, to: nil)
        return try names.map { name in
            try #require(screen.frames(of: name).first { stripFrame.contains(CGPoint(x: $0.midX, y: $0.midY)) })
        }
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
