//
//  ExerciseSaveButon.swift
//  PowerJack
//
//  Created by Brendon on 7/7/26.
//

import SwiftUI
import SwiftData
import OSLog

struct ExerciseSaveButon: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
  
    var draft: ExerciseDraft
    let onSave: (Exercise) -> Void
    
    var body: some View {
        Button {
            guard let equipment = draft.equipment,
                  let primaryMuscle = draft.primaryMuscle
            else {
                return
            }
    
            let newExercise = Exercise(
                exerciseName: draft.name,
                exerciseEquipment: equipment,
                primaryMuscleFocus: primaryMuscle,
                secondaryMuscles: draft.secondaryMuscles
            )
            onSave(newExercise)
            dismiss()

        } label: {
            Text("Save")
                .font(.default)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    draft.canSave
                    ? Color.blue
                    : Color.gray
                )
                .foregroundStyle(.white)
                .clipShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(!draft.canSave)
    }
}
