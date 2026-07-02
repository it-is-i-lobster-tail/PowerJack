//
//  GlassPressButonStyle.swift
//  PowerJack
//
//  Created by Brendon on 7/1/26.
//

import SwiftUI

struct GlassPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassEffect(
                .regular
                    .tint(.gray.opacity(OpacityPJ.focusLight))
                    .interactive()
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.82 : 1.0)
            .animation(
                .easeInOut(duration: 0.1),
                value: configuration.isPressed
            )
    }
}
