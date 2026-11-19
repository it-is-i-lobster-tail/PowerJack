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

    @Test("The Review page stays one line either way")
    func reviewHeader() async throws {
        let screen = try await HostedView(WorkoutHeader(exercise: nil, isCompact: true))
        defer { screen.close() }

        #expect(screen.contains("Review"))
    }
}
