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

    @Test("Start set returns to the group that owns the timer even with earlier exercises unfinished",
          arguments: [false, true])
    func timerReturnsToLoggedGroup(superset: Bool) async throws {
        let (program, workout) = try makeStartedWorkout()
        let exercises = workout.workoutExercises
        let a = UUID()
        for member in exercises.prefix(2) { member.setSuperset(a) }
        let members = superset ? Array(exercises[3...4]) : [exercises[3]]
        if superset {
            let b = UUID()
            for member in members { member.setSuperset(b) }
        }
        for member in members {
            member.completeSet(try #require(member.warmupSets.first))
        }
        #expect(workout.currentRest != nil)
        #expect(workout.currentSet?.workoutExercise === members[0])
        #expect(workout.currentExerciseIndex == 0)
        let card = superset ? "Superset B, 2 exercises" : "Lift 4"

        // Opening the workout via the timer and tapping again from another page use the same destination.
        router.showDetailOnly(program)
        let screen = try await HostedView(programScreen())
        defer { router.popToRoot(); screen.close() }
        router.showCurrentExercise(of: program)
        let strip = try #require(await stripScrollView(in: screen))
        #expect(await screen.waitUntil { isCardCentered(card, in: strip, screen: screen) })
        #expect(await screen.tap("Superset A, 2 exercises"))
        #expect(await screen.waitUntil { isCardCentered("Superset A, 2 exercises", in: strip, screen: screen) })
        router.showCurrentExercise(of: program)
        #expect(await screen.waitUntil { isCardCentered(card, in: strip, screen: screen) })
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

    @Test("Scrubbing halfway moves the workout before the strip settles")
    func stripScrubsThePager() async throws {
        let (_, workout) = try makeStartedWorkout()
        let scroll = ExercisePageScroll()
        let screen = try await HostedView(ScrubScreen(workout: workout, scroll: scroll).modelContainer(container))
        defer { screen.close() }
        let strip = try #require(await stripScrollView(in: screen))
        let pager = try #require(screen.horizontalScrollViews.first { $0 !== strip })
        #expect(await screen.waitUntil { isCardCentered(0, in: strip, screen: screen) })
        let cards = try cardFrames(["Lift 1", "Lift 2"], in: strip, screen: screen)
        let halfCard = (cards[1].midX - cards[0].midX) / 2

        // Hold the strip between snap targets, before any change to the selected index.
        scroll.isDrivenByStrip = true
        scroll.stripPhase = .interacting
        await screen.settle()
        strip.setContentOffset(CGPoint(x: strip.contentOffset.x + halfCard, y: 0), animated: false)
        #expect(await screen.waitUntil {
            abs(pager.contentOffset.x - pager.bounds.width / 2) < 2 && abs(scroll.position - 0.5) < 0.01
        })
    }

    @Test("A card's name grows smoothly from caption size a page away to callout size on its page")
    func nameSizeFollowsThePages() {
        let resting = ExercisePreviewStrip.textScale(focus: 0, dynamicTypeSize: .large)
        #expect(abs(resting - 12.0 / 16.0) < 0.001)
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

    @Test("Long names fit in focused and neighboring cards", arguments: [DynamicTypeSize.large, .xxxLarge])
    func fullPreviewNames(size: DynamicTypeSize) async throws {
        HostedView.keep(container)
        let (_, workout) = try makeStartedWorkout()
        let exercises = workout.workoutExercises
        exercises[0].exercise?.exerciseName = "Chest Supported Dumbbell Row"
        exercises[1].exercise?.exerciseName = String(repeating: "W", count: 30)
        exercises[1].skipRemainingSets()
        let scroll = ExercisePageScroll()
        var truncated: [Bool] = []
        let screen = try await HostedView(
            ExercisePreviewStrip(pages: Array(WorkoutPage.pages(for: workout).prefix(3)),
                                 screenWidth: 320, pageScroll: scroll, selectedPageIndex: .constant(0))
                .frame(width: 320)
                .environment(\.dynamicTypeSize, size)
                .onPreferenceChange(Text.LayoutKey.self) { layouts in
                    truncated = layouts.map { $0.layout.isTruncated }
                }
        )
        defer { screen.close() }
        for position in [0.0, 0.5, 1, 2] {
            scroll.position = position
            await screen.settle()
            #expect(truncated.count >= 2)
            #expect(!truncated.contains(true))
        }
    }

    @Test("Three- and two-exercise supersets each share a single page and preview card")
    func groupedPages() async throws {
        let (_, workout) = try makeStartedWorkout()
        let exercises = workout.workoutExercises
        let a = UUID(), b = UUID()
        for member in exercises[1...3] { member.setSuperset(a) }
        for member in exercises[4...5] { member.setSuperset(b) }
        let pages = WorkoutPage.pages(for: workout)
        #expect(pages.map(\.indices) == [0..<1, 1..<4, 4..<6])
        #expect(pages.map { $0.header.title } == ["Lift 1", "Superset A", "Superset B"])

        let screen = try await HostedView(workoutScreen(workout))
        defer { screen.close() }
        let strip = try #require(await stripScrollView(in: screen))
        let pager = try #require(screen.horizontalScrollViews.first { $0 !== strip })
        for (index, count, letter) in [(1, 3, "A"), (2, 2, "B")] {
            let label = "Superset \(letter), \(count) exercises"
            #expect(await screen.tap(label))
            #expect(await screen.waitUntil { isCardCentered(label, in: strip, screen: screen) && pagerPage(pager) == index })
            for member in 1...count {
                #expect(screen.label(startingWith: "\(letter)\(member), Lift") != nil)
            }
        }
        #expect(await screen.tap("Review"))
        #expect(await screen.waitUntil { pagerPage(pager) == 3 })
    }

    @Test("Checking a set follows the next superset member vertically on the same page")
    func followsNextMember() async throws {
        let (_, workout) = try makeStartedWorkout()
        let pair = Array(workout.workoutExercises.prefix(2))
        let groupID = UUID()
        for exercise in pair { exercise.setSuperset(groupID) }
        let screen = try await HostedView(workoutScreen(workout))
        defer { screen.close() }
        let strip = try #require(await stripScrollView(in: screen))
        let pager = try #require(screen.horizontalScrollViews.first { $0 !== strip })
        let heading = try #require(screen.label(startingWith: "A2, Lift 2"))
        let before = try #require(screen.frame(of: heading)).minY
        let current = try #require(workout.currentSet)
        current.workoutExercise.completeSet(current.workoutSet)
        #expect(workout.currentSet?.workoutExercise === pair[1])
        #expect(WorkoutPage.pages(for: workout)[0].entryIndex == 1)
        #expect(await screen.waitUntil {
            guard let frame = screen.frame(of: heading) else { return false }
            return frame.minY < before - 30 && pagerPage(pager) == 0
        })
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

private struct ScrubScreen: View {
    let workout: Workout
    let scroll: ExercisePageScroll
    @FocusState private var field: FocusedSetField?

    var body: some View {
        GeometryReader { geometry in
            WorkoutDetailContent(screenWidth: geometry.size.width, topInset: 0,
                                 pages: WorkoutPage.pages(for: workout), selectedExerciseIndex: .constant(0),
                                 focusedSetField: $field, onExerciseSetsDone: { _ in }, pageScroll: scroll)
        }
    }
}
