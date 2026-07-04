//
//  ProgramInfoBanner.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
//

import SwiftData
import SwiftUI

struct ProgramInfoBanner: View {
    let program: Program
    

    var body: some View {
        let programPercentComplete: Double = ((Double(program.workoutsFinished) / Double(program.totalWorkouts)) * 100).rounded()
        
        ZStack {
            VStack {
                Text("\(program.templateProgram.templateName)")
                    .font(.title2)
                Text("\(Int(programPercentComplete))% Finished")
                    .font(.footnote)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
        }
    }
}
