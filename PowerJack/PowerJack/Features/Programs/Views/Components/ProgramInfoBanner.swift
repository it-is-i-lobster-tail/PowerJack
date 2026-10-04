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
            Text(program.templateName)
                .font(.title2)
            HStack {
                Text("\(program.percentFinished)% Finished")
                    .font(.footnote)
                if program.status != .active {
                    Text(" | \(program.status.rawValue.localizedCapitalized)")
                        .font(.footnote)
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, LayoutMetrics.compactSpacing)
    }
}
