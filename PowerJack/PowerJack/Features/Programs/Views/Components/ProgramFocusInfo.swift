//
//  ProgramFocusInfo.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
//

import SwiftUI

struct ProgramFocusInfo: View {
    let focusMuscles: [Muscle]
    let screenWidth: CGFloat

    var body: some View {
        GlassEffectContainer(spacing: 5) {
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

                // Chips share the row evenly and stay inset from the card edge on every iPhone.
                HStack(spacing: LayoutMetrics.compactSpacing) {
                    ForEach(focusMuscles, id: \.self) { focusMuscle in
                        Text(focusMuscle.rawValue)
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .glassEffect(
                                .regular.tint(.glassSurface.opacity(VisualOpacity.subtle)),
                                in: .rect(cornerRadius: 26)
                            )
                    }
                }
                .padding(.horizontal, LayoutMetrics.sectionSpacing)
                .padding(.top, 10)
            }
            .padding(.vertical, 15)
            .frame(width: screenWidth)
            .powerJackGlassPanel()
        }
    }
}
