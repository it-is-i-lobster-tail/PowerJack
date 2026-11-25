//
//  ExerciseSelectionRow.swift
//  PowerJack
//
//  Created by Codex on 7/14/26.
//

import SwiftUI

struct ExerciseSelectionRow: View {
    let exercise: Exercise
    var isSelected = false
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading) {
                    Text(exercise.exerciseName)

                    HStack {
                        Text(exercise.equipment.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("|")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(exercise.primaryMuscleFocus.rawValue.localizedCapitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
