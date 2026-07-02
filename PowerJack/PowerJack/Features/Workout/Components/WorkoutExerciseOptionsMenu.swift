//
//  WorkoutExerciseOptionsMenu.swift
//  PowerJack
//
//  Created by Brendon on 6/26/26.
//

import SwiftUI

struct WorkoutExerciseOptionsMenu: View {
    let screenWidth: CGFloat
    @Bindable var workoutExercise: WorkoutExercise
    @Binding var showOptions: Bool

    private func optionRow(
        systemImage: String,
        title: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 28)
                    .font(.footnote)

                Text(title)
                    .font(.footnote)

                Spacer()
            }
            .foregroundStyle(isDestructive ? .red : .primary)
            .padding(.horizontal, 15)
            .frame(
                width: ((screenWidth - SpacingPJ.buttonStandardOffset) / 2),
                height: SpacingPJ.buttonStandardSize
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                optionRow(
                    systemImage: "plus",
                    title: "Add New Set"
                ) {
                    workoutExercise.addSet()
                    showOptions = false
                }

                Divider()
                
                optionRow(
                    systemImage: "minus",
                    title: "Remove Last Set",
                    isDestructive: true
                ) {
                    _ = workoutExercise.removeLastSet()
                    showOptions = false
                }
            }
        }
        .frame(
            width: ((screenWidth - SpacingPJ.buttonStandardOffset) / 2),
            height: 80
        )
        .glassEffect(
        .regular.tint(.gray.opacity(OpacityPJ.focusHeavy)), in: .rect(cornerRadius: 26))
    }
}
