//
//  MuscleSelectionViewTests.swift
//  PowerJackTests
//

import SwiftUI
import Testing
@testable import PowerJack

@MainActor
@Suite(.serialized)
struct MuscleSelectionViewTests {
    @Test("Tapping muscles selects up to the limit and never the excluded one")
    func selectsUpToLimit() async throws {
        let selection = SelectionBox()
        let screen = try await HostedView(
            NavigationStack {
                MuscleSelectionHost(selection: selection, maximum: 2, excluded: [.chest])
            }
        )
        defer { screen.close() }

        await screen.tap("Back")
        await screen.tap("Biceps")
        await screen.tap("Abs")
        await screen.tap("Chest")
        #expect(selection.muscles == [.back, .biceps])

        // Tapping a selected muscle frees a slot.
        await screen.tap("Back")
        await screen.tap("Abs")
        #expect(selection.muscles == [.biceps, .abs])
    }
}

@MainActor
@Observable
final class SelectionBox {
    var muscles: [Muscle] = []
}

private struct MuscleSelectionHost: View {
    @Bindable var selection: SelectionBox
    let maximum: Int
    let excluded: Set<Muscle>

    var body: some View {
        LimitedMuscleSelectionView(
            navigationTitle: "Muscles",
            guidance: "Pick some",
            maximumSelection: maximum,
            excludedMuscles: excluded,
            selectedMuscles: $selection.muscles
        )
    }
}
