//
//  ProgramStartWorkout.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
//

import SwiftData
import SwiftUI
import OSLog

struct ProgramStartWorkout: View {
    let screenWidth: CGFloat
    let hight: CGFloat
    
    var body: some View {
        ZStack {
            Button {
                Logger.ui.debug("Program Detail View start workout button pressed")
            } label: {
                Text("Start Workout")
                    .font(.title3)
                    .frame(
                        width: screenWidth * 0.8,
                        height: 48
                    )
            }
            .buttonStyle(GlassPressButtonStyle())
        }
        .frame(
            width: screenWidth,
            height: hight
        )
        .glassEffect(
            .regular.tint(.white.opacity(OpacityPJ.focusLight)),
            in: .rect(cornerRadius: 14))
    }
}
