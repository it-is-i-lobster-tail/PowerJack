//
//  ProgramFocusInfo.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
//

import SwiftData
import SwiftUI

struct ProgramFocusInfo: View {
    let focusMuscles: [Muscle]
    let screenWidth: CGFloat
    
    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Image(systemName: "target")
                    .font(.title)
                    .foregroundStyle(.blue)
                    .padding(.leading, 15)
                
                VStack(alignment: .leading) {
                    Text("Focus")
                        .font(.title3)
                    Text("Primary muscle groups")
                        .font(.caption)
                }
                .padding(.leading, 10)
                
                Spacer()
                
            }

            
            
            HStack {
                ForEach(focusMuscles, id: \.self) {focusMuscle in
                    ZStack {
                        ZStack {
                            Text("\(focusMuscle.rawValue)")
                                .font(.caption)
                            RoundedRectangle(cornerRadius: 26)
                        }
                        .frame(width: 80)
                        .glassEffect(
                            .regular.tint(.white.opacity(OpacityPJ.focusLight)),
                            in: .rect(cornerRadius: 26))
                    }
                    .padding(.horizontal, 5)

                }
                
            }
            .padding(.top, 10)
        }
        .padding(.vertical, 15)
        .glassEffect(
            .regular.tint(.white.opacity(OpacityPJ.focusLight)),
            in: .rect(cornerRadius: 14))
    }
}
