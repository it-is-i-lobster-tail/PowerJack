//
//  WorkoutHeaderControls.swift
//  PowerJack
//
//  Created by Brendon on 6/26/26.
//

import SwiftUI
import OSLog

struct WorkoutHeaderControls: View {
    @Bindable var workoutExercise: WorkoutExercise
    @Binding var showOptions: Bool

    private func backButton() {
    }

    var body: some View {
        ZStack {
            HStack {
                Button {
                    Logger.ui.debug("Workout header back button pressed")
                } label: {
                    Image(systemName: "arrow.left")
                }
                .buttonStyle(GlassIconButtonStyle())
                .padding(.leading, SpacingPJ.buttonStandardOffset)
                
                
                Spacer()
                
                VStack {
                    Text("Day 1")
                        .font(.default)
                    Text("Week 1/4")
                        .font(.caption2)
                }
                .frame(width: 60, height: SpacingPJ.buttonStandardSize)
                .padding(.horizontal, 25)
                .glassEffect(
                    .regular
                        .tint(.gray.opacity(OpacityPJ.focusLight)),
                    in: .rect(cornerRadius: 26))
                .clipShape(Capsule())

                Spacer()

                //
                // Menu
                //
                Button {
                    Logger.ui.debug("Workout header menu option pressed")
                    Logger.ui.debug("Current showOptions value: \(showOptions)")

                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        showOptions.toggle()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .buttonStyle(GlassIconButtonStyle())
                .padding(.trailing, SpacingPJ.buttonStandardOffset)
            }
        }
    }
}
