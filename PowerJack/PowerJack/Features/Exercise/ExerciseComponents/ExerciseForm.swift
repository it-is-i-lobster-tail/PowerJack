//
//  ExerciseForm.swift
//  PowerJack
//
//  Created by Brendon on 7/8/26.
//

import SwiftUI

struct ExerciseForm: View {
    @Binding var draft: ExerciseDraft
    let onSave: (Exercise) -> Void

    private let boxHeight: CGFloat = 85
    @FocusState private var nameIsFocused: Bool
    
    private func ExerciseComponentLabelPicker<Selection>(
        imageName: String,
        selectionName: String,
        selectionDetail: String,
        selection: Binding<Selection?>
    ) -> some View
    where Selection: CaseIterable & Identifiable & Hashable & RawRepresentable,
          Selection.RawValue == String
    {
        Picker(selection: selection) {
            ForEach(Array(Selection.allCases).sorted { $0.rawValue < $1.rawValue }, id: \.self) { option in
                Text(option.rawValue.capitalized)
                    .tag(option as Selection?)
            }
        } label: {
            ExerciseSelctionRow(
                imageName: imageName,
                selectionName: selectionName,
                selectionDetail: selectionDetail,
                doubleImage: false
            )
            .contentShape(Rectangle()) // makes empty spacer area tappable too
        }
        .pickerStyle(.navigationLink)
        .padding(.vertical, 20)
        .padding(.trailing, 20)
        .frame(maxWidth: .infinity, minHeight: boxHeight, maxHeight: boxHeight)
        .glassEffect(
            .regular
                .tint(.white.opacity(OpacityPJ.focusStandard)),
            in: .rect(cornerRadius: 12))
    }
    
    private let muscleColumns = [
        GridItem(.adaptive(minimum: 85), spacing: 8)
    ]
    
    private let equipmentColumns = [
        GridItem(.adaptive(minimum: 85), spacing: 8)
    ]
    
    var body: some View {
        VStack(spacing: 18) {
            
            HStack {
                Image(systemName: "dumbbell")
                    .foregroundStyle(.blue)
                Text("Create a new exercise")
                    .font(.caption)
                Spacer()
            }
            .padding(.leading, 20)
            
            ExerciseName(
                boxHeight: boxHeight,
                exerciseName: $draft.name,
                nameIsFocused: $nameIsFocused
            )
            .padding(.horizontal, 20)
            
            ExerciseComponentLabelPicker(
                imageName: "figure.cross.training",
                selectionName: "Equipment",
                selectionDetail: "Select equipment",
                selection: $draft.equipment
            )
            .padding(.horizontal, 20)
            
            ExerciseComponentLabelPicker(
                imageName: "target",
                selectionName: "Primary Muscle",
                selectionDetail: "Select primary muscle",
                selection: $draft.primaryMuscle
            )
            .padding(.horizontal, 20)
            .onChange(of: draft.primaryMuscle) {
                draft.removePrimaryFromSecondary()
            }
            
            NavigationStack {
                HStack {
                    NavigationLink {
                        ExerciseSelectSecondaryMuscles(
                            selectedPrimaryMuscle: draft.primaryMuscle,
                            selectedSecondaryMuscles: $draft.secondaryMuscles,
                            nameIsFocused: $nameIsFocused
                        )
                    } label: {
                        ExerciseSelctionRow(
                            imageName: "target",
                            selectionName: "Secondary Muscles",
                            selectionDetail: "Select helper muscles (optional)",
                            doubleImage: true
                        )
                        
                        VStack {
                            ForEach(draft.secondaryMuscles, id: \.self) { secondaryMuscle in
                                HStack {
                                    Text("\(secondaryMuscle.rawValue.capitalized)")
                                        .font(.footnote)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .foregroundStyle(.gray)
                                    
                                    Spacer()
                                }
                            }
                        }
                        .frame(width: 80)
                        
                    }
                    .frame(maxWidth: .infinity, minHeight: boxHeight, maxHeight: boxHeight)
                    .glassEffect(
                        .regular
                            .tint(.white.opacity(OpacityPJ.focusStandard)),
                        in: .rect(cornerRadius: 12))
                }
                .padding(.horizontal, 20)
            }
            
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                Text("You can edit these details at any time.")
                    .font(.caption)
                Spacer()
            }
            .padding(.leading, 20)
            
            Spacer()
            
            ExerciseSaveButon(
                draft: draft,
                onSave: onSave
            )
            .padding(.horizontal, 20)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.bottom, 20)
        .background(.white)
        .padding(.vertical, 20)
    }
}
