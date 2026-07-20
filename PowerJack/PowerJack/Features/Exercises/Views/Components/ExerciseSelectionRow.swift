//
//  ExerciseSelectionRow.swift
//  PowerJack
//
//  Created by Codex on 7/14/26.
//

import SwiftUI

struct ExerciseSelectionRow: View {
    let exercise: Exercise
    let isEnabled: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading) {
                    Text(exercise.exerciseName)

                    HStack {
                        Text(exercise.exerciseEquipment.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("|")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(exercise.primaryMuscleFocus.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : VisualOpacity.standard)
    }
}
