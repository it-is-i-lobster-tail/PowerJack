//
//  GlassOptionsMenu.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
//

import SwiftUI

struct FloatingMenuOverlay<MenuContent: View>: View {
    @Binding var isPresented: Bool
    let xOffset: CGFloat
    let yOffset: CGFloat

    @ViewBuilder let menuContent: () -> MenuContent

    var body: some View {
        ZStack {
            if isPresented {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isPresented = false
                        }

                menuContent()
                    .offset(x: xOffset, y: yOffset)
                    .transition(
                        .scale(scale: 0.85, anchor: .topTrailing)
                        .combined(with: .opacity)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.125), value: isPresented)
    }
}
