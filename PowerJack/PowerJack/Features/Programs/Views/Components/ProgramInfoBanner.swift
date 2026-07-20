//
//  ProgramInfoBanner.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
//

import SwiftUI

struct ProgramInfoBanner: View {
    let program: Program

    var body: some View {
        VStack {
            Text(program.templateProgram.templateName)
                .font(.title2)
            Text("\(program.percentFinished)% Finished")
                .font(.footnote)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, LayoutMetrics.compactSpacing)
    }
}
