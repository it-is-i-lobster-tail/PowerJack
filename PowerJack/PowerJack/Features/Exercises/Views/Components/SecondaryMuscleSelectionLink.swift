//
//  SecondaryMuscleSelectionLink.swift
//  PowerJack
//
//  Created by Codex on 7/14/26.
//

import SwiftUI

struct SecondaryMuscleSelectionLink: View {
    let boxHeight: CGFloat
    let selectedPrimaryMuscle: Muscle?
    @Binding var selectedSecondaryMuscles: [Muscle]

    var body: some View {
        NavigationLink {
            LimitedMuscleSelectionView(
                navigationTitle: "Secondary Muscles",
                guidance: "Optional, up to \(maxSecondaryMuscles)",
                maximumSelection: maxSecondaryMuscles,
                excludedMuscles: Set([selectedPrimaryMuscle].compactMap { $0 }),
                selectedMuscles: $selectedSecondaryMuscles
            )
        } label: {
            HStack(spacing: 12) {
                FormFieldLabel(
                    systemImage: "target",
                    title: "Secondary Muscles",
                    detail: "Select helper muscles (optional)"
                )

                if !selectedSecondaryMuscles.isEmpty {
                    Text(selectedSecondaryMuscles.count, format: .number)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, LayoutMetrics.sectionSpacing)
        .frame(maxWidth: .infinity, minHeight: boxHeight, maxHeight: boxHeight)
        .powerJackGlassCard(interactive: true)
    }
}
