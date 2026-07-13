//
//  ExerciseName.swift
//  PowerJack
//
//  Created by Brendon on 7/6/26.
//

import SwiftUI

struct ExerciseName: View {
    let boxHeight: CGFloat
    @Binding var exerciseName: String
    @FocusState.Binding var nameIsFocused: Bool
    
    private func exerciseNameLengthExceeded() -> Bool {
        return exerciseName.count > maxExerciseNameLengthInput
    }
    
    var body: some View {
        HStack{
            
            Image(systemName: "pencil")
                .font(.title)
                .foregroundStyle(.blue)
                .padding(.leading, 10)
            
            VStack {
                HStack {
                    Text("Name")

                    if exerciseName.count > Int((Double(maxExerciseNameLengthInput) * 0.8).rounded()) {
                        Text("\(exerciseName.count)/\(maxExerciseNameLengthInput)")
                            .foregroundStyle(
                                exerciseNameLengthExceeded() ?
                                .red :
                                .primary)
                    }
                    
                    Spacer()
                }
                HStack {
                    TextField("exercise name", text: $exerciseName)
                        .focused($nameIsFocused)
                        .padding(.leading, 13)
                        .padding(.vertical, 8)
                        .glassEffect(
                            .regular.tint(
                                exerciseNameLengthExceeded()
                                ? .red.opacity(OpacityPJ.focusLight)
                                : nameIsFocused
                                    ? .gray.opacity(OpacityPJ.focusLight)
                                    : .white.opacity(OpacityPJ.focusThin)
                            ),
                            in: .rect(cornerRadius: 8)
                        )
                        .animation(.easeOut(duration: 0.10), value: nameIsFocused)
                        .animation(.easeOut(duration: 0.25), value: exerciseName)
                }
                .padding(.trailing, 20)
            }
            .padding(.vertical, 20)
            .padding(.leading, 20)

        }
        .frame(maxWidth: .infinity, minHeight: boxHeight, maxHeight: boxHeight)
        .glassEffect(
            .regular
                .tint(.white.opacity(OpacityPJ.focusStandard)),
            in: .rect(cornerRadius: 12))
    }
}
