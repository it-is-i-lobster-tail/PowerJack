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
    /// A short tag after the muscle, such as "Imported".
    var note: String? = nil
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading) {
                    Text(exercise.exerciseName)

                    HStack {
                        Text(exercise.equipmentDisplayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("|")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(exercise.primaryMuscleFocus.rawValue.localizedCapitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let note {
                            Text("|")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
