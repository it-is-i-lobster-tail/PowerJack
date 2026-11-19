//
//  WorkoutHeaderTests.swift
//  PowerJackTests
//
//  The workout's header bubble: the name with its equipment while the bars show,
//  and the name alone in a smaller bubble while they're faded.
//

import SwiftUI
import Testing
@testable import PowerJack

@MainActor
@Suite(.serialized)
struct WorkoutHeaderTests {
    private let exercise = Exercise(
        exerciseName: "Bench",
        exerciseEquipment: .barbell,
        primaryMuscleFocus: .chest
    )

    @Test("The full header shows the equipment under the name")
    func fullHeaderShowsEquipment() async throws {
        let screen = try await HostedView(WorkoutHeader(exercise: exercise))
        defer { screen.close() }

        #expect(screen.contains("Bench, \(Equipment.barbell.displayName)"))
    }

    @Test("The compact header shows the name alone")
    func compactHeaderShowsNameOnly() async throws {
        let screen = try await HostedView(WorkoutHeader(exercise: exercise, isCompact: true))
        defer { screen.close() }

        #expect(screen.contains("Bench"))
        #expect(screen.label(startingWith: "Bench,") == nil)
    }

    @Test("The compact header is shorter and narrower than the full one")
    func compactHeaderIsSmaller() async throws {
        let full = try await HostedView(WorkoutHeader(exercise: exercise))
        let fullFrame = try #require(full.frame(of: "Bench, \(Equipment.barbell.displayName)"))
        full.close()

        let compact = try await HostedView(WorkoutHeader(exercise: exercise, isCompact: true))
        defer { compact.close() }
        let compactFrame = try #require(compact.frame(of: "Bench"))

        #expect(compactFrame.height < fullFrame.height)
        #expect(compactFrame.width < fullFrame.width)
        // Centered on the same spot, so the name doesn't drift as it shrinks.
        #expect(abs(compactFrame.midX - fullFrame.midX) < 1)
    }

    @Test("Going compact shrinks the bubble in place, without moving it sideways")
    func compactShrinksInPlace() async throws {
        let state = CompactState()
        let screen = try await HostedView(SwitchingHeader(exercise: exercise, state: state))
        defer { screen.close() }
        let fullFrame = try #require(screen.frame(of: "Bench, \(Equipment.barbell.displayName)"))

        state.isCompact = true
        await screen.settle(.milliseconds(600))
        let compactFrame = try #require(screen.frame(of: "Bench"))

        #expect(compactFrame.width < fullFrame.width)
        // The accessibility frame takes in the folded equipment line, so only the sideways
        // position is checked here. The navigation bar re-centering it is what made it jiggle.
        #expect(abs(compactFrame.midX - fullFrame.midX) < 1)
    }

    @Test("A short name's compact bubble isn't held wide by its equipment")
    func shortNameCompactWidth() async throws {
        let dip = Exercise(exerciseName: "Dip", exerciseEquipment: .bodyweight, primaryMuscleFocus: .chest)
        let compact = try await HostedView(WorkoutHeader(exercise: dip, isCompact: true))
        defer { compact.close() }
        let compactFrame = try #require(compact.frame(of: "Dip"))
        let review = try await HostedView(WorkoutHeader(exercise: nil, isCompact: true))
        defer { review.close() }
        let reviewFrame = try #require(review.frame(of: "Review"))

        // "Dip" is shorter than "Review", so its bubble must be too, whatever its equipment.
        #expect(compactFrame.width < reviewFrame.width)
    }

    @Test("Mid-swipe the bubble's width sits between the two pages' widths")
    func swipeWidthFollowsPages() async throws {
        let dip = Exercise(exerciseName: "Dip", exerciseEquipment: .bodyweight, primaryMuscleFocus: .chest)
        let long = Exercise(exerciseName: "Chest Supported Dumbbell Row", exerciseEquipment: .dumbbell, primaryMuscleFocus: .chest)
        let pages: [Exercise?] = [dip, long]

        let short = try await HostedView(WorkoutHeader(exercise: dip))
        let shortWidth = try #require(short.frame(of: "Dip, \(Equipment.bodyweight.displayName)")).width
        short.close()
        let wide = try await HostedView(WorkoutHeader(exercise: long))
        let wideWidth = try #require(wide.frame(of: "Chest Supported Dumbbell Row, \(Equipment.dumbbell.displayName)")).width
        wide.close()

        let scroll = ExercisePageScroll()
        scroll.position = 0.5
        let screen = try await HostedView(WorkoutHeader(exercise: dip, pages: pages, pageScroll: scroll))
        defer { screen.close() }
        let midWidth = try #require(screen.frame(of: "Dip, \(Equipment.bodyweight.displayName)")).width

        #expect(abs(midWidth - (shortWidth + wideWidth) / 2) < 2)
    }

    @Test("Rest, ready and equipment occupy equal-height lines even for a long title")
    func subtitleHeight() async throws {
        let long = Exercise(exerciseName: "Cable Overhead Extension", exerciseEquipment: .cable, primaryMuscleFocus: .chest)
        let reference = try await HostedView(WorkoutHeader(exercise: exercise).frame(width: 170))
        let height = try #require(reference.frame(of: "Bench, \(Equipment.barbell.displayName)")).height
        reference.close()

        for remaining in [nil, 30.0, -1.0] as [Double?] {
            let now = Date.now
            let timer = remaining.map {
                WorkoutHeaderRest(period: RestPeriod(startedAt: now.addingTimeInterval(-60),
                    endsAt: now.addingTimeInterval($0), exerciseName: long.exerciseName,
                    setNumber: 2, setCount: 3), onTap: {})
            }
            let screen = try await HostedView(WorkoutHeader(exercise: long)
                .environment(\.workoutHeaderRest, timer)
                .frame(width: 170))
            defer { screen.close() }
            let label = try #require(screen.label(startingWith: long.exerciseName))
            if let remaining {
                #expect(label.contains(remaining > 0 ? "Rest" : "Start set"))
            }
            let frame = try #require(screen.frame(of: label))
            #expect(abs(frame.height - height) < 1)
        }
    }

    @Test("The Review page stays one line either way")
    func reviewHeader() async throws {
        let screen = try await HostedView(WorkoutHeader(exercise: nil, isCompact: true))
        defer { screen.close() }

        #expect(screen.contains("Review"))
    }
}

@Observable
private final class CompactState {
    var isCompact = false
}

/// A header beside a spacer that flips to compact, like the workout's when the bars fade.
private struct SwitchingHeader: View {
    let exercise: Exercise
    let state: CompactState

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 40, height: 1)
            WorkoutHeader(exercise: exercise, isCompact: state.isCompact)
            Spacer(minLength: 0)
        }
    }
}
