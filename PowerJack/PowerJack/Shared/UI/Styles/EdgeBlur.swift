//
//  EdgeBlur.swift
//  PowerJack
//
//  Softens content that scrolls under a floating bar.
//

import SwiftUI

/// Softens content that scrolls under a floating bar, like the scroll edge effect under a title:
/// clear where content first meets the bar, blurring and fading into the page toward the screen's edge.
/// At rest, content ends before it.
struct EdgeBlur: View {
    /// The screen edge the bar sits on.
    let edge: VerticalEdge
    /// How far the fade reaches from the bar's inner side before the blur is solid.
    var fadeLength: CGFloat = 22

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            // The material alone is lighter than a dark page, so fade it toward the page color.
            .overlay(Color(uiColor: .systemBackground).opacity(0.7))
            .mask { mask }
            .ignoresSafeArea(edges: edge == .top ? .top : .bottom)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Clear at the bar's inner side, solid after `fadeLength`.
    private var mask: some View {
        VStack(spacing: 0) {
            if edge == .top {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: fadeLength)
            } else {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: fadeLength)
                Color.black
            }
        }
    }
}
