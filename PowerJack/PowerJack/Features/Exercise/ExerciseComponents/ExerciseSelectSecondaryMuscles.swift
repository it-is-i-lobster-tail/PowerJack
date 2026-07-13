//
//  SelectSecondaryMuscles.swift
//  PowerJack
//
//  Created by Brendon on 7/6/26.
//

import SwiftUI

struct ExerciseSelectSecondaryMuscles: View {
    let selectedPrimaryMuscle: Muscle?
    @Binding var selectedSecondaryMuscles: [Muscle]
    @FocusState.Binding var nameIsFocused: Bool
    
    var body: some View {
        VStack {
            VStack(spacing: 6) {
                Text("(Optional) up to 4")
                    .font(.default)
                Text("\(selectedSecondaryMuscles.count) of 4")
                    .font(.footnote)
            }
            .padding(.vertical, 20)
            
            let muscleArryy = Array(Muscle.allCases.sorted { $0.rawValue < $1.rawValue })

            LazyVStack(spacing: 0) {
                ForEach(muscleArryy.enumerated(), id: \.element) { index, muscle in
                    let selectedIndex = selectedSecondaryMuscles.firstIndex(of: muscle)
                    let isSelected = selectedIndex != nil
                    let canSelectMore = selectedSecondaryMuscles.count < maxSecondaryMuscles
                    let isPrimary = muscle == selectedPrimaryMuscle

                    Button {
                        if let selectedIndex {
                            selectedSecondaryMuscles.remove(at: selectedIndex)
                        } else if canSelectMore && !isPrimary {
                            selectedSecondaryMuscles.append(muscle)
                        }
                        nameIsFocused = false
                    } label: {
                        HStack {
                            Text(muscle.rawValue.capitalized)
                                .font(.default)
                                .padding(.leading, 23)
                                .frame(minHeight: 50)
                            if isPrimary {
                                Text("(Primary)")
                                    .font(.caption)
                            }
                            Spacer()
                        }
                        .background(
                            isSelected
                            ? Color.gray.opacity(OpacityPJ.focusThin)
                            : Color.white
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled((!isSelected && !canSelectMore) || isPrimary)
                    .opacity((!isSelected && !canSelectMore) || isPrimary ? 0.45 : 1)
                    
                    if index < Array(Muscle.allCases).count - 1 {
                        Divider()
                            .background(Color.gray.opacity(OpacityPJ.focusStandard))
                            .padding(.horizontal, 20)
                    }
                }
                .animation(.easeOut(duration: 0.20), value: selectedSecondaryMuscles)
                .animation(.easeOut(duration: 0.20), value: selectedPrimaryMuscle)
            }
            .glassEffect(
                .regular
                    .tint(.gray.opacity(OpacityPJ.focusThin)),
                in: .rect(cornerRadius: 12))

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .background(.white)
        .padding(.vertical, 20)
        .navigationTitle("Secondary Muscles")
        .navigationBarTitleDisplayMode(.inline)
    }
}
