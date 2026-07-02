//
//  Button.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
//

import SwiftData
import SwiftUI

struct GlassIconButtonStyle: ButtonStyle {
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2)
            .frame(
                width: SpacingPJ.buttonStandardSize,
                height: SpacingPJ.buttonStandardSize
            )
            .glassEffect(
                .regular
                    .tint(.gray.opacity(OpacityPJ.focusLight))
                    .interactive(),
                in: .circle
            )
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .opacity(configuration.isPressed ? 0.80 : 1.0)
            .animation(
                .easeInOut(duration: 0.125),
                value: configuration.isPressed
            )
    }
}
