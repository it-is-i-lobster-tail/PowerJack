//
//  LimitedMuscleSelectionView.swift
//  PowerJack
//
//  Created by Codex on 7/20/26.
//

import SwiftUI

struct LimitedMuscleSelectionView: View {
    let navigationTitle: LocalizedStringKey
    let guidance: LocalizedStringKey
    let maximumSelection: Int
    let excludedMuscles: Set<Muscle>

    @Binding var selectedMuscles: [Muscle]

    private var muscles: [Muscle] {
        Muscle.allCases.sorted { $0.rawValue < $1.rawValue }
    }

    init(
        navigationTitle: LocalizedStringKey,
        guidance: LocalizedStringKey,
        maximumSelection: Int,
        excludedMuscles: Set<Muscle> = [],
        selectedMuscles: Binding<[Muscle]>
    ) {
        self.navigationTitle = navigationTitle
        self.guidance = guidance
        self.maximumSelection = maximumSelection
        self.excludedMuscles = excludedMuscles
        _selectedMuscles = selectedMuscles
    }

    var body: some View {
        VStack(spacing: LayoutMetrics.compactSpacing) {
            VStack(spacing: 6) {
                Text(guidance)
                Text("\(selectedMuscles.count) of \(maximumSelection)")
                    .font(.footnote)
            }
            .padding(.vertical, LayoutMetrics.sectionSpacing)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(muscles, id: \.self) { muscle in
                        MuscleSelectionRow(
                            muscle: muscle,
                            isSelected: selectedMuscles.contains(muscle),
                            isExcluded: excludedMuscles.contains(muscle),
                            canSelectMore: selectedMuscles.count < maximumSelection,
                            action: { toggle(muscle) }
                        )

                        if muscle != muscles.last {
                            Divider()
                                .padding(.horizontal, LayoutMetrics.sectionSpacing)
                        }
                    }
                }
                .powerJackGlassCard(interactive: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, LayoutMetrics.sectionSpacing)
        .padding(.bottom, LayoutMetrics.sectionSpacing)
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ muscle: Muscle) {
        if let selectedIndex = selectedMuscles.firstIndex(of: muscle) {
            selectedMuscles.remove(at: selectedIndex)
        } else if selectedMuscles.count < maximumSelection,
                  !excludedMuscles.contains(muscle) {
            selectedMuscles.append(muscle)
        }
    }
}

private struct MuscleSelectionRow: View {
    let muscle: Muscle
    let isSelected: Bool
    let isExcluded: Bool
    let canSelectMore: Bool
    let action: () -> Void

    private var isDisabled: Bool {
        isExcluded || (!isSelected && !canSelectMore)
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(muscle.rawValue.capitalized)
                if isExcluded {
                    Text("(Primary)")
                        .font(.caption)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
            .frame(minHeight: 50)
            .padding(.horizontal, LayoutMetrics.sectionSpacing)
            .background(
                isSelected
                ? Color.gray.opacity(VisualOpacity.subtle)
                : Color.clear
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? VisualOpacity.standard : 1)
    }
}
