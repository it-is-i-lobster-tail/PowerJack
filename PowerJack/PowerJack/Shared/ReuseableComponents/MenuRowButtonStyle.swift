//
//  GlassMenuButton.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
//

import SwiftData
import SwiftUI

struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Rectangle()
                    .fill(configuration.isPressed ? Color.gray.opacity(0.12) : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.10), value: configuration.isPressed)
    }
}
